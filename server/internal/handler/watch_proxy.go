package handler

import (
	"net/http"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
)

// WatchProxyInfo — что телефон знает о прокси роликов (PLAN S11).
type WatchProxyInfo struct {
	Enabled bool     `json:"enabled"`
	URL     string   `json:"url,omitempty"`
	Hosts   []string `json:"hosts,omitempty"`
}

// WatchProxy — GET /api/fork/watch-proxy: включён ли прокси, куда идти и
// какие площадки через него пускать (тот же список, что проверяет сервер).
func WatchProxy(r *router.Router[*core.RequestEvent], info WatchProxyInfo) {
	r.GET("/api/fork/watch-proxy", func(e *core.RequestEvent) error {
		if !info.Enabled {
			return e.JSON(http.StatusOK, WatchProxyInfo{})
		}
		return e.JSON(http.StatusOK, info)
	}).Bind(apis.RequireAuth())
}
