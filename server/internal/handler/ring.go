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
	Ring(ctx context.Context, uid, groupID string) error
}

// Ring — POST /api/fork/ring {group_id}: разбудить партнёра, которому
// звонят (UX_AUDIT L6, lib/fork/watch/pair_call.dart).
func Ring(r *router.Router[*core.RequestEvent], svc Ringer, log *slog.Logger) {
	r.POST("/api/fork/ring", func(e *core.RequestEvent) error {
		var body struct {
			GroupID string `json:"group_id"`
		}
		if err := e.BindBody(&body); err != nil || body.GroupID == "" {
			return e.BadRequestError("Нужен group_id.", nil)
		}
		err := svc.Ring(e.Request.Context(), e.Auth.Id, body.GroupID)
		switch {
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
