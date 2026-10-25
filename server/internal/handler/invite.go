package handler

import (
	"log/slog"
	"net/http"
	"strings"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"

	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
)

// NormalizeInviteCode чистит то, что человек принёс в поле кода: ссылку
// целиком («…/invite/HQ792S»), русскую раскладку (А, В, Е… от латинских не
// отличить), кавычки автозамены. Чистим на сервере: выпущенные сборки
// получают правку без обновления.
func NormalizeInviteCode(raw string) string {
	s := strings.ToUpper(strings.TrimSpace(raw))
	if i := strings.LastIndex(s, "/INVITE/"); i >= 0 {
		s = s[i+len("/INVITE/"):]
	}
	s, _, _ = strings.Cut(s, "?")
	s, _, _ = strings.Cut(s, "#")
	cyr := map[rune]rune{'А': 'A', 'В': 'B', 'Е': 'E', 'К': 'K', 'М': 'M', 'Н': 'H',
		'О': 'O', 'Р': 'P', 'С': 'C', 'Т': 'T', 'У': 'Y', 'Х': 'X'}
	var b strings.Builder
	for _, r := range s {
		if l, ok := cyr[r]; ok {
			r = l
		}
		if (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// InviteAccept — POST /api/invite/accept {code} (бывший invite.pb.js).
// Чужие коды клиенту не видны (правило invite_codes — только владелец), а
// вписать себя в чужую пару правило не даст, поэтому приём — только здесь.
//
// Кодов два вида при одном поле ввода: приглашение и постоянный код второго
// места пары «в ожидании» (`groups.claim_token`). Не нашли приглашение —
// пробуем второе место и отдаём заявку на подтверждение.
//
// Код после приёма не удаляется, а привязывается к паре: повторный приём
// (двойной тап, диплинк дважды) попадает во «вход в свою пару» и отвечает
// успехом, а третьего не пустит заполненная пара.
func InviteAccept(r *router.Router[*core.RequestEvent], svc *pairs.Service, log *slog.Logger) {
	r.POST("/api/invite/accept", func(e *core.RequestEvent) error {
		var body struct {
			Code string `json:"code"`
		}
		_ = e.BindBody(&body)
		me := e.Auth.Id
		code := NormalizeInviteCode(body.Code)
		// Отказы пишем сами: иначе жалоба «код не работает» разбирается вслепую.
		deny := func(status int, message, why string) error {
			args := []any{"why", why, "code", code, "uid", me}
			if strings.ToUpper(strings.TrimSpace(body.Code)) != code {
				args = append(args, "raw", body.Code)
			}
			log.Warn("invite accept: отказ", args...)
			return e.JSON(status, map[string]any{"success": false, "message": message})
		}
		if code == "" {
			return deny(http.StatusBadRequest, "Код не указан", "пустой код")
		}

		rec, err := e.App.FindFirstRecordByFilter("invite_codes", "code = {:c}", dbx.Params{"c": code})
		if err != nil {
			// У распущенной пары код формально жив — такой не берём.
			waiting, err := e.App.FindFirstRecordByFilter("groups", "claim_token = {:t} && disbanded = false", dbx.Params{"t": code})
			if err == nil {
				return e.JSON(http.StatusOK, map[string]any{"success": true, "waiting": true, "pairId": waiting.Id, "code": code})
			}
			// Чаще всего код фантомный: старые сборки рисовали его на телефоне
			// без сервера. Перевыпуск — единственное, что человек сделает сам.
			return deny(http.StatusNotFound, "Код не найден. Пусть партнёр нажмёт «Новый код» и продиктует заново",
				"кода нет ни в invite_codes, ни в claim_token")
		}
		owner := rec.GetString("owner_uid")
		if owner == "" {
			return deny(http.StatusBadRequest, "Код повреждён", "у кода пустой owner_uid")
		}
		if owner == me {
			return deny(http.StatusBadRequest, "Это ваш собственный код!", "свой же код")
		}
		profile := func(uid, fallback string) (string, string) {
			u, err := e.App.FindRecordById("users", uid)
			if err != nil {
				return fallback, ""
			}
			name := u.GetString("display_name")
			if name == "" {
				name = fallback
			}
			return name, u.GetString("avatar_url")
		}
		ownerName, ownerAvatar := profile(owner, "Partner")
		myName, myAvatar := profile(me, "")
		res, err := svc.Accept(e.Request.Context(), pairs.AcceptInput{
			OwnerUID: owner, MyUID: me, CodeGroupID: rec.GetString("group_id"),
			OwnerName: ownerName, OwnerAvatar: ownerAvatar, MyName: myName, MyAvatar: myAvatar,
		})
		if err != nil {
			log.Error("invite accept", "uid", me, "err", err)
			return deny(http.StatusInternalServerError, "Не удалось принять код", "сбой приёма")
		}
		if !res.Success {
			msg := res.Message
			if msg == "" {
				msg = "Не удалось принять код"
			}
			return deny(http.StatusBadRequest, msg, msg)
		}
		if rec.GetString("group_id") != res.PairID {
			rec.Set("group_id", res.PairID)
			if err := e.App.Save(rec); err != nil {
				log.Warn("invite accept: код не привязан к паре", "code", code, "err", err)
			}
		}
		return e.JSON(http.StatusOK, res)
	}).Bind(apis.RequireAuth())
}
