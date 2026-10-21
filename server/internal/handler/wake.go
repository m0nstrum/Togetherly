package handler

import (
	"context"
	"log/slog"
	"net/http"
	"strings"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"

	"github.com/m0nstrum/togetherly/server/internal/usecase/wake"
)

// PushTokens — токены FCM устройств человека.
type PushTokens interface {
	Register(ctx context.Context, uid, token string) error
	Unregister(ctx context.Context, uid, token string) error
}

// WakeInbox — ящик событий будильника.
type WakeInbox interface {
	Fetch(uid, id string) (wake.Entry, bool)
	// Enabled — шлёт ли сервер FCM: без этого телефон держит свой сокет.
	Enabled() bool
}

// Wake — маршруты будильника FCM (PLAN S12, lib/fork/push/fcm_wake.dart):
//
//	POST   /api/fork/push-token {token} — токен устройства за собой;
//	DELETE /api/fork/push-token {token} — забыть при выходе;
//	POST   /api/fork/wake {event}       — событие, о котором пришёл пуш.
func Wake(r *router.Router[*core.RequestEvent], tokens PushTokens, inbox WakeInbox, log *slog.Logger) {
	token := func(e *core.RequestEvent) (string, bool) {
		var body struct {
			Token string `json:"token"`
		}
		if err := e.BindBody(&body); err != nil {
			return "", false
		}
		t := strings.TrimSpace(body.Token)
		return t, t != "" && len(t) <= 4096
	}
	r.POST("/api/fork/push-token", func(e *core.RequestEvent) error {
		t, ok := token(e)
		if !ok {
			return e.BadRequestError("Нужен token.", nil)
		}
		if err := tokens.Register(e.Request.Context(), e.Auth.Id, t); err != nil {
			log.ErrorContext(e.Request.Context(), "push-token", "err", err)
			return e.InternalServerError("Токен не сохранён.", nil)
		}
		return e.JSON(http.StatusOK, map[string]any{"ok": true, "enabled": inbox.Enabled()})
	}).Bind(apis.RequireAuth("users"))
	r.DELETE("/api/fork/push-token", func(e *core.RequestEvent) error {
		t, ok := token(e)
		if !ok {
			return e.BadRequestError("Нужен token.", nil)
		}
		if err := tokens.Unregister(e.Request.Context(), e.Auth.Id, t); err != nil {
			log.ErrorContext(e.Request.Context(), "push-token", "err", err)
			return e.InternalServerError("Токен не удалён.", nil)
		}
		return e.JSON(http.StatusOK, map[string]any{"ok": true})
	}).Bind(apis.RequireAuth("users"))
	r.POST("/api/fork/wake", func(e *core.RequestEvent) error {
		var body struct {
			Event string `json:"event"`
		}
		if err := e.BindBody(&body); err != nil || body.Event == "" {
			return e.BadRequestError("Нужен event.", nil)
		}
		ev, ok := inbox.Fetch(e.Auth.Id, body.Event)
		if !ok {
			return e.NotFoundError("Событие ушло.", nil)
		}
		return e.JSON(http.StatusOK, ev)
	}).Bind(apis.RequireAuth("users"))
}
