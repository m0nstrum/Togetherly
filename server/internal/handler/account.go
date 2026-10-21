package handler

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"

	"github.com/m0nstrum/togetherly/server/internal/usecase/account"
)

// ScheduleDelete — POST /api/account/schedule-delete (lib/models/user_data.dart,
// deleteAccount): аккаунт стирается через неделю, вход паролем отменяет.
func ScheduleDelete(r *router.Router[*core.RequestEvent], svc *account.Service, now func() time.Time, log *slog.Logger) {
	r.POST("/api/account/schedule-delete", func(e *core.RequestEvent) error {
		at, err := svc.Schedule(e.Request.Context(), e.Auth, now())
		if err != nil {
			log.ErrorContext(e.Request.Context(), "schedule-delete", "err", err)
			return e.InternalServerError("Не удалось пометить аккаунт.", nil)
		}
		return e.JSON(http.StatusOK, map[string]any{"success": true, "deleteAfter": at})
	}).Bind(apis.RequireAuth("users"))
}
