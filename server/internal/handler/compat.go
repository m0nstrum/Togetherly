package handler

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"regexp"
	"strings"

	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
	"github.com/m0nstrum/togetherly/server/internal/usecase/records"
)

// Compat — внутренний API, который JS-хуки апстрима зовут по
// http://127.0.0.1:8120/internal/* (у апстрима его держал hotpath поверх
// Postgres). Форк отвечает на те же пути поверх PocketBase, поэтому хуки
// остаются нетронутыми. Слушает только петлю; запросы не с петли — 404, как в
// hotpath.
//
// Перенесено всё, что зовут хуки из server/hooks.allow. Остальные пути
// hotpath отвечают 501 с записью в журнал — так видно, если новый хук
// апстрима потянул ещё один.
func Compat(svc *pairs.Service, recs *records.Service, pub Publisher, log *slog.Logger) http.Handler {
	mux := http.NewServeMux()
	h := compat{svc: svc, recs: recs, pub: pub, log: log}
	mux.HandleFunc("POST /internal/pair-accept", h.pairAccept)
	mux.HandleFunc("GET /internal/group-read", h.groupRead)
	mux.HandleFunc("POST /internal/group-write", h.groupWrite)
	mux.HandleFunc("GET /internal/groups-of", h.groupsOf)
	mux.HandleFunc("POST /internal/waiting-create", h.waitingCreate)
	mux.HandleFunc("POST /internal/waiting-reset", h.waitingReset)
	mux.HandleFunc("POST /internal/pair-claim-approve", h.claimApprove)
	mux.HandleFunc("POST /internal/record", h.record)
	// Своё, не hotpath: пуши хуков (зов в ленту, порисовать) вместо
	// APNs/FCM — server/hooks/apns_push.js.
	mux.HandleFunc("POST /internal/notify", h.notify)
	// Страна по IP — для правил рекламы сундука. Рекламы нет, страна не нужна.
	mux.HandleFunc("GET /internal/geo", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{})
	})
	mux.HandleFunc("/internal/", h.notPorted)
	return loopbackOnly(mux)
}

type compat struct {
	svc  *pairs.Service
	recs *records.Service
	pub  Publisher
	log  *slog.Logger
}

// Publisher — публикация в канал Centrifugo (infrastructure/centrifugo).
type Publisher interface {
	Publish(ctx context.Context, channel string, data any) error
}

// notify — уведомление человеку в его канал `user:<uid>`. Клиент
// (lib/fork/push_relay.dart) рисует из него локальное уведомление: и в
// приложении, и из фонового сервиса, который держит сокет.
func (h compat) notify(w http.ResponseWriter, r *http.Request) {
	var body struct {
		UID    string            `json:"uid"`
		Thread string            `json:"thread"`
		Title  string            `json:"title"`
		Body   string            `json:"body"`
		Data   map[string]string `json:"data"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.UID == "" || body.Thread == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false})
		return
	}
	body.Title, body.Body = dropSealed(body.Title), dropSealed(body.Body)
	id := make([]byte, 8)
	_, _ = rand.Read(id)
	err := h.pub.Publish(r.Context(), "user:"+body.UID, map[string]any{
		"event": "create", "collection": "fork_notify",
		"record": map[string]any{
			"id": hex.EncodeToString(id), "collectionName": "fork_notify",
			"thread": body.Thread, "title": body.Title, "body": body.Body, "data": body.Data,
		},
	})
	if err != nil {
		h.fail(w, r, "notify", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

// sealedToken — шифртекст поля E2E (`e2e1.<keyId>.<nonce>.<ct>`).
var sealedToken = regexp.MustCompile(`e2e1\.[A-Za-z0-9_:.+/=\-]+`)

// dropSealed убирает шифртекст из текста уведомления: хуки апстрима берут
// имя из профиля, а там теперь шифр личного ключа (docs/E2E.md).
func dropSealed(s string) string {
	if !strings.Contains(s, "e2e1.") {
		return s
	}
	return strings.Join(strings.Fields(sealedToken.ReplaceAllString(s, "")), " ")
}

func (h compat) waitingCreate(w http.ResponseWriter, r *http.Request) {
	var in pairs.WaitingCreateInput
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "bad body"})
		return
	}
	h.result(w, r, "waiting-create")(h.svc.WaitingCreate(r.Context(), in))
}

func (h compat) waitingReset(w http.ResponseWriter, r *http.Request) {
	var in struct {
		GroupID string `json:"group_id"`
		UID     string `json:"uid"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "bad body"})
		return
	}
	h.result(w, r, "waiting-reset")(h.svc.WaitingReset(r.Context(), in.GroupID, in.UID))
}

func (h compat) claimApprove(w http.ResponseWriter, r *http.Request) {
	var in pairs.ClaimApproveInput
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "error": "bad body"})
		return
	}
	h.result(w, r, "pair-claim-approve")(h.svc.ClaimApprove(r.Context(), in))
}

func (h compat) record(w http.ResponseWriter, r *http.Request) {
	var body map[string]any
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "Failed to create record."})
		return
	}
	col, _ := body["collection"].(string)
	delete(body, "collection")
	rec, err := h.recs.Create(r.Context(), col, body)
	if errors.Is(err, records.ErrForbidden) {
		writeJSON(w, http.StatusBadRequest, map[string]any{"message": "Failed to create record."})
		return
	}
	if err != nil {
		h.fail(w, r, "record", err)
		return
	}
	writeJSON(w, http.StatusOK, rec)
}

// result отдаёт ответ usecase как есть: код и тело hotpath.
func (h compat) result(w http.ResponseWriter, r *http.Request, op string) func(pairs.Result, error) {
	return func(res pairs.Result, err error) {
		if err != nil {
			h.fail(w, r, op, err)
			return
		}
		writeJSON(w, res.Status, res.Body)
	}
}

func (h compat) pairAccept(w http.ResponseWriter, r *http.Request) {
	var in pairs.AcceptInput
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"success": false, "message": "bad body"})
		return
	}
	res, err := h.svc.Accept(r.Context(), in)
	if err != nil {
		h.log.ErrorContext(r.Context(), "pair-accept", "err", err)
		writeJSON(w, http.StatusInternalServerError, map[string]any{"success": false, "message": "internal error"})
		return
	}
	status := http.StatusOK
	if !res.Success && res.Message == "bad params" {
		status = http.StatusBadRequest
	}
	writeJSON(w, status, res)
}

func (h compat) groupRead(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	var (
		rec any
		err error
	)
	switch {
	case q.Get("id") != "":
		rec, err = h.svc.Group(r.Context(), q.Get("id"))
	case q.Get("claim_token") != "":
		rec, err = h.svc.GroupByClaimToken(r.Context(), q.Get("claim_token"))
	default:
		writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "error": "bad params"})
		return
	}
	if errors.Is(err, pairs.ErrNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]any{"ok": false, "error": "no group"})
		return
	}
	if err != nil {
		h.fail(w, r, "group-read", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "record": rec})
}

func (h compat) groupWrite(w http.ResponseWriter, r *http.Request) {
	var in pairs.WriteInput
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || in.GroupID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "error": "bad params"})
		return
	}
	rec, err := h.svc.Write(r.Context(), in)
	if errors.Is(err, pairs.ErrNotFound) {
		writeJSON(w, http.StatusNotFound, map[string]any{"ok": false, "error": "no group"})
		return
	}
	if err != nil {
		h.fail(w, r, "group-write", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "record": rec})
}

func (h compat) groupsOf(w http.ResponseWriter, r *http.Request) {
	uid := r.URL.Query().Get("uid")
	if uid == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "error": "bad params"})
		return
	}
	recs, err := h.svc.GroupsOf(r.Context(), uid, r.URL.Query().Get("live") != "0")
	if err != nil {
		h.fail(w, r, "groups-of", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "items": recs})
}

func (h compat) notPorted(w http.ResponseWriter, r *http.Request) {
	h.log.WarnContext(r.Context(), "internal: путь hotpath ещё не перенесён", "path", r.URL.Path)
	writeJSON(w, http.StatusNotImplemented, map[string]any{"ok": false, "success": false, "error": "not ported"})
}

func (h compat) fail(w http.ResponseWriter, r *http.Request, op string, err error) {
	h.log.ErrorContext(r.Context(), op, "err", err)
	writeJSON(w, http.StatusInternalServerError, map[string]any{"ok": false, "error": "internal error"})
}

func loopbackOnly(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host, _, err := net.SplitHostPort(r.RemoteAddr)
		if ip := net.ParseIP(host); err != nil || ip == nil || !ip.IsLoopback() {
			http.NotFound(w, r)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
