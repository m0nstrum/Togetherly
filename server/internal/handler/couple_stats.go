package handler

import (
	"log/slog"
	"net/http"
	"slices"
	"time"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"

	"github.com/m0nstrum/togetherly/server/internal/usecase/stats"
)

// CoupleStats — GET /api/couple/stats?groupId=… (бывший couple_stats.pb.js):
// агрегаты для экрана статистики пары. Участие — по users.group_ids, как в
// правилах коллекций: у распущенной пары статистика остаётся.
// Суперюзер смотрит любую пару.
func CoupleStats(r *router.Router[*core.RequestEvent], svc *stats.Service, now func() time.Time, log *slog.Logger) {
	r.GET("/api/couple/stats", func(e *core.RequestEvent) error {
		gid := e.Request.URL.Query().Get("groupId")
		if gid == "" {
			return e.JSON(http.StatusBadRequest, map[string]any{"ok": false, "error": "no_group"})
		}
		if !e.HasSuperuserAuth() && !slices.Contains(e.Auth.GetStringSlice("group_ids"), gid) {
			return e.JSON(http.StatusForbidden, map[string]any{"ok": false, "error": "not_member"})
		}
		out, err := svc.CoupleStats(e.Request.Context(), gid, now())
		if err != nil {
			log.ErrorContext(e.Request.Context(), "couple stats", "group", gid, "err", err)
			return e.JSON(http.StatusInternalServerError, map[string]any{"ok": false, "error": "internal"})
		}
		return e.JSON(http.StatusOK, out)
	}).Bind(apis.RequireAuth())
}
