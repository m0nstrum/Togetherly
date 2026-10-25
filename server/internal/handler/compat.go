package handler

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"net/http"

	"github.com/m0nstrum/togetherly/server/internal/usecase/notify"
	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
	"github.com/m0nstrum/togetherly/server/internal/usecase/records"
)

// Compat — внутренний API, который JS-хуки апстрима зовут по
// http://127.0.0.1:8120/internal/* (у апстрима его держал hotpath поверх
// Postgres). Форк отвечает на те же пути поверх PocketBase, поэтому хуки
// остаются нетронутыми. Слушает только петлю; запросы не с петли — 404, как в
// hotpath.
//
// Остались пути, которые зовут ещё не перенесённые в Go хуки
// (server/pb_hooks); перенесённые убраны вместе с хуками. Остальные пути
// hotpath отвечают 501 с записью в журнал.
func Compat(svc *pairs.Service, recs *records.Service, notif *notify.Service, log *slog.Logger) http.Handler {
	mux := http.NewServeMux()
	h := compat{svc: svc, recs: recs, notif: notif, log: log}
	mux.HandleFunc("GET /internal/group-read", h.groupRead)
	mux.HandleFunc("POST /internal/group-write", h.groupWrite)
	mux.HandleFunc("GET /internal/groups-of", h.groupsOf)
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

// Publisher — публикация в канал Centrifugo.
type Publisher = notify.Publisher

type compat struct {
	svc   *pairs.Service
	recs  *records.Service
	notif *notify.Service
	log   *slog.Logger
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
	// Кому слать, хук уже решил сам (apns_push.js).
	err := h.notif.Deliver(r.Context(), body.UID, notify.Message{
		Thread: body.Thread, Title: body.Title, Body: body.Body, Data: body.Data,
	})
	if err != nil {
		h.fail(w, r, "notify", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
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
