package handler

import (
	"errors"
	"log/slog"
	"net/http"
	"slices"
	"strings"
	"time"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
	"github.com/spf13/cast"

	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
)

// Waiting — пара с пустым местом («он в армии», бывший waiting.pb.js).
// Пара заводится на одного, второе место держит заглушка (имя, фото, дата
// возвращения), записи пишутся с первого дня. Вернувшийся вводит код второго
// места, хозяйка подтверждает — и вся история уже его.
//
//	POST /api/waiting/create  {name, avatar?, returnDate?}
//	POST /api/waiting/update  {groupId, name?, avatar?, returnDate?}
//	POST /api/waiting/claim   {code}             — заявка на второе место
//	POST /api/waiting/approve {groupId, approve} — хозяйка решает
//	POST /api/waiting/reset   {groupId}          — новый код
//	POST /api/waiting/cancel  {groupId}          — передумала ждать
//	GET  /api/waiting/state?code=…              — статус заявки для ждущего
//
// Код не протухает: срок возвращения плавает, и таймер означал бы «пара
// развалилась сама». Привязку подтверждает хозяйка: код может засветиться в
// сторис. Своей живой пары у заявителя быть не должно.
func Waiting(r *router.Router[*core.RequestEvent], svc *pairs.Service, now func() time.Time, log *slog.Logger) {
	fail := func(e *core.RequestEvent, status int, msg string) error {
		return e.JSON(status, map[string]any{"success": false, "message": msg})
	}
	body := func(e *core.RequestEvent) map[string]any {
		b := map[string]any{}
		_ = e.BindBody(&b)
		return b
	}
	result := func(e *core.RequestEvent, op string, res pairs.Result, err error) error {
		if err != nil {
			log.Error("waiting "+op, "uid", e.Auth.Id, "err", err)
			return fail(e, http.StatusInternalServerError, "Не сохранилось")
		}
		return e.JSON(res.Status, res.Body)
	}
	profile := func(e *core.RequestEvent, uid string) (string, string) {
		u, err := e.App.FindRecordById("users", uid)
		if err != nil {
			return "", ""
		}
		return u.GetString("display_name"), u.GetString("avatar_url")
	}
	// ownGroup — пара, где вошедший участник; иначе ответ с отказом.
	ownGroup := func(e *core.RequestEvent, gid string) (*core.Record, error) {
		if gid == "" {
			return nil, fail(e, http.StatusBadRequest, "Не указана пара")
		}
		g, err := svc.Group(e.Request.Context(), gid)
		if err != nil {
			return nil, fail(e, http.StatusNotFound, "Пара не найдена")
		}
		if !slices.Contains(pairs.Members(g), e.Auth.Id) {
			return nil, fail(e, http.StatusForbidden, "Это не ваша пара")
		}
		return g, nil
	}
	write := func(e *core.RequestEvent, gid string, set map[string]any) error {
		_, err := svc.Write(e.Request.Context(), pairs.WriteInput{GroupID: gid, Set: set})
		return err
	}

	r.POST("/api/waiting/create", func(e *core.RequestEvent) error {
		b := body(e)
		myName, myAvatar := profile(e, e.Auth.Id)
		res, err := svc.WaitingCreate(e.Request.Context(), pairs.WaitingCreateInput{
			UID:               e.Auth.Id,
			PlaceholderName:   cast.ToString(b["name"]),
			PlaceholderAvatar: strings.TrimSpace(cast.ToString(b["avatar"])),
			ReturnDate:        strings.TrimSpace(cast.ToString(b["returnDate"])),
			MyName:            myName,
			MyAvatar:          myAvatar,
		})
		return result(e, "create", res, err)
	}).Bind(apis.RequireAuth())

	r.POST("/api/waiting/update", func(e *core.RequestEvent) error {
		b := body(e)
		g, deny := ownGroup(e, cast.ToString(b["groupId"]))
		if g == nil {
			return deny
		}
		if !g.GetBool("waiting_mode") {
			return fail(e, http.StatusBadRequest, "Место уже занято")
		}
		set := map[string]any{}
		if v, ok := b["name"]; ok {
			if n := []rune(strings.TrimSpace(cast.ToString(v))); len(n) > 0 {
				set["placeholder_name"] = string(n[:min(len(n), 60)])
			}
		}
		if v, ok := b["avatar"]; ok {
			set["placeholder_avatar"] = cast.ToString(v)
		}
		if v, ok := b["returnDate"]; ok {
			set["return_date"] = strings.TrimSpace(cast.ToString(v))
		}
		if len(set) > 0 {
			if err := write(e, g.Id, set); err != nil {
				log.Warn("waiting update: запись не прошла", "err", err)
				return fail(e, http.StatusInternalServerError, "Не сохранилось")
			}
		}
		return e.JSON(http.StatusOK, map[string]any{"success": true})
	}).Bind(apis.RequireAuth())

	r.POST("/api/waiting/claim", func(e *core.RequestEvent) error {
		uid := e.Auth.Id
		code := strings.ToUpper(strings.TrimSpace(cast.ToString(body(e)["code"])))
		deny := func(status int, msg, why string) error {
			log.Warn("waiting claim: отказ", "why", why, "code", code, "uid", uid)
			return fail(e, status, msg)
		}
		if code == "" {
			return deny(http.StatusBadRequest, "Код не указан", "пустой код")
		}
		g, err := svc.GroupByClaimToken(e.Request.Context(), code)
		if err != nil {
			return deny(http.StatusNotFound, "Код не найден", "нет такого claim_token")
		}
		if !g.GetBool("waiting_mode") {
			return deny(http.StatusBadRequest, "Место уже занято", "waiting_mode выключен")
		}
		members := pairs.Members(g)
		if slices.Contains(members, uid) {
			return e.JSON(http.StatusOK, map[string]any{"success": true, "status": "member", "pairId": g.Id})
		}
		mine, err := svc.GroupsOfUser(uid, true)
		if err != nil {
			return deny(http.StatusInternalServerError, "Не удалось отправить заявку", err.Error())
		}
		for _, m := range mine {
			if m.Id != g.Id {
				return deny(http.StatusBadRequest, "У вас уже есть пара — выйдите из неё", "заявитель уже в паре")
			}
		}
		myName, _ := profile(e, uid)
		if err := write(e, g.Id, map[string]any{"claim_uid": uid, "claim_name": myName, "claim_at": now().UnixMilli()}); err != nil {
			return deny(http.StatusInternalServerError, "Не удалось отправить заявку", err.Error())
		}
		names := map[string]any{}
		_ = g.UnmarshalJSONField("member_names", &names)
		owner := ""
		if len(members) > 0 {
			owner = cast.ToString(names[members[0]])
		}
		return e.JSON(http.StatusOK, map[string]any{"success": true, "status": "pending", "pairId": g.Id, "ownerName": owner})
	}).Bind(apis.RequireAuth())

	r.POST("/api/waiting/approve", func(e *core.RequestEvent) error {
		b := body(e)
		g, deny := ownGroup(e, cast.ToString(b["groupId"]))
		if g == nil {
			return deny
		}
		claim := g.GetString("claim_uid")
		if claim == "" {
			return fail(e, http.StatusBadRequest, "Заявки нет")
		}
		if v, ok := b["approve"].(bool); ok && !v {
			if err := write(e, g.Id, map[string]any{"claim_uid": "", "claim_name": "", "claim_at": 0}); err != nil {
				return fail(e, http.StatusInternalServerError, "Не сохранилось")
			}
			return e.JSON(http.StatusOK, map[string]any{"success": true, "approved": false})
		}
		name, avatar := profile(e, claim)
		if name == "" {
			name = g.GetString("placeholder_name")
		}
		res, err := svc.ClaimApprove(e.Request.Context(), pairs.ClaimApproveInput{
			GroupID: g.Id, ClaimUID: claim, ClaimName: name, ClaimAvatar: avatar,
		})
		if err != nil || res.Body["ok"] != true {
			if res.Body["error"] == "full" {
				return fail(e, http.StatusBadRequest, "Место уже занято")
			}
			log.Warn("waiting approve: запись не прошла", "err", err)
			return fail(e, http.StatusInternalServerError, "Не сохранилось")
		}
		return e.JSON(http.StatusOK, map[string]any{"success": true, "approved": true, "pairId": g.Id})
	}).Bind(apis.RequireAuth())

	r.POST("/api/waiting/reset", func(e *core.RequestEvent) error {
		gid := cast.ToString(body(e)["groupId"])
		if gid == "" {
			return fail(e, http.StatusBadRequest, "Не указана пара")
		}
		res, err := svc.WaitingReset(e.Request.Context(), gid, e.Auth.Id)
		return result(e, "reset", res, err)
	}).Bind(apis.RequireAuth())

	// Отмена распускает пару мягко и ГАСИТ код: иначе он уводил бы
	// вернувшегося в распущенную группу без участников. Клиенту эти поля
	// закрыты стражем пары.
	r.POST("/api/waiting/cancel", func(e *core.RequestEvent) error {
		gid := cast.ToString(body(e)["groupId"])
		g, deny := ownGroup(e, gid)
		if g == nil {
			return deny
		}
		// Место занято — это обычная пара, расходятся из неё выходом.
		if !g.GetBool("waiting_mode") {
			return fail(e, http.StatusBadRequest, "Место уже занято")
		}
		if g.GetBool("disbanded") {
			return e.JSON(http.StatusOK, map[string]any{"success": true, "already": true})
		}
		if err := write(e, g.Id, map[string]any{
			"disbanded": true, "disbanded_at": now().UTC(),
			"claim_token": "", "claim_uid": "", "claim_name": "", "claim_at": 0,
		}); err != nil {
			log.Warn("waiting cancel: запись не прошла", "group", gid, "err", err)
			return fail(e, http.StatusInternalServerError, "Не получилось")
		}
		return e.JSON(http.StatusOK, map[string]any{"success": true})
	}).Bind(apis.RequireAuth())

	// Пока хозяйка не подтвердила, заявитель не участник и правила пару ему
	// не отдают: этот роут — единственное, что ему видно.
	r.GET("/api/waiting/state", func(e *core.RequestEvent) error {
		uid := e.Auth.Id
		state := func(status, pair string) error {
			out := map[string]any{"success": true, "status": status}
			if pair != "" {
				out["pairId"] = pair
			}
			return e.JSON(http.StatusOK, out)
		}
		// Приняли — пара уже своя (код к тому времени погашен).
		if mine, err := svc.GroupsOfUser(uid, true); err == nil && len(mine) > 0 {
			return state("approved", mine[0].Id)
		}
		code := strings.ToUpper(strings.TrimSpace(e.Request.URL.Query().Get("code")))
		if code == "" {
			return state("none", "")
		}
		g, err := svc.GroupByClaimToken(e.Request.Context(), code)
		if errors.Is(err, pairs.ErrNotFound) || g == nil {
			return state("gone", "")
		}
		if slices.Contains(pairs.Members(g), uid) {
			return state("approved", g.Id)
		}
		if g.GetString("claim_uid") == uid {
			return state("pending", "")
		}
		// Заявку сняли или заменили чужой — повторить.
		return state("rejected", "")
	}).Bind(apis.RequireAuth())
}
