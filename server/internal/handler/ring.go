package handler

import (
	"context"
	"errors"
	"log/slog"
	"net/http"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"

	"github.com/m0nstrum/togetherly/server/internal/usecase/ring"
)

// Ringer — зов звонка партнёру.
type Ringer interface {
	Ring(ctx context.Context, uid, groupID string, kind ring.Kind) error
}

// Ring — POST /api/fork/ring {group_id, kind}: разбудить партнёра, которому
// звонят (kind=call, по умолчанию; UX_AUDIT L6, lib/fork/watch/pair_call.dart)
// или которого зовут в комнату просмотра (kind=watch; lib/fork/watch/room_shell.dart).
func Ring(r *router.Router[*core.RequestEvent], svc Ringer, log *slog.Logger) {
	r.POST("/api/fork/ring", func(e *core.RequestEvent) error {
		var body struct {
			GroupID string `json:"group_id"`
			Kind    string `json:"kind"`
		}
		if err := e.BindBody(&body); err != nil || body.GroupID == "" {
			return e.BadRequestError("Нужен group_id.", nil)
		}
		kind := ring.Kind(body.Kind)
		if kind == "" {
			kind = ring.KindCall
		}
		err := svc.Ring(e.Request.Context(), e.Auth.Id, body.GroupID, kind)
		switch {
		case errors.Is(err, ring.ErrBadKind):
			return e.BadRequestError("Неизвестный kind.", nil)
		case errors.Is(err, ring.ErrNotMember):
			return e.ForbiddenError("Не ваша пара.", nil)
		case errors.Is(err, ring.ErrTooOften):
			return e.TooManyRequestsError("Слишком часто.", nil)
		case err != nil:
			log.ErrorContext(e.Request.Context(), "ring", "err", err)
			return router.NewApiError(http.StatusBadGateway, "Партнёра не разбудили.", nil)
		}
		return e.JSON(http.StatusOK, map[string]any{"ok": true})
	}).Bind(apis.RequireAuth("users"))
}
