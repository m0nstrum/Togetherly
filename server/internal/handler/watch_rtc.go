// Package handler — HTTP-роуты форка поверх роутера PocketBase.
package handler

import (
	"net/http"
	"time"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"

	"github.com/m0nstrum/togetherly/server/internal/domain/ice"
)

// WatchRTC — GET /api/watch/rtc → {success, iceServers}. Заменяет
// pocketbase/pb_hooks/watch_rtc.pb.js: только свой coturn, временные ключи.
func WatchRTC(r *router.Router[*core.RequestEvent], turn ice.TURN, now func() time.Time) {
	r.GET("/api/watch/rtc", func(e *core.RequestEvent) error {
		return e.JSON(http.StatusOK, map[string]any{
			"success":    true,
			"iceServers": ice.Servers(turn, e.Auth.Id, now()),
		})
	}).Bind(apis.RequireAuth())
}
