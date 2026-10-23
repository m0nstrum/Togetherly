package handler

import (
	"encoding/json"
	dmeta "github.com/m0nstrum/togetherly/server/internal/domain/meta"
	"github.com/m0nstrum/togetherly/server/internal/usecase/meta"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
	"net/http"
	"strings"
	"time"
)

// MapTiles exposes only the fixed map provider. No user headers or IP are
// forwarded; the existing bounded LRU caches responses shared by all clients.
func MapTiles(r *router.Router[*core.RequestEvent], svc *meta.Service, limit *IPLimiter) {
	r.GET("/api/fork/map/tilejson", func(e *core.RequestEvent) error {
		if !limit.Allow(e.RealIP(), time.Now()) {
			return e.TooManyRequestsError("Too many map requests.", nil)
		}
		res, err := svc.Fetch(e.Request.Context(), dmeta.MapOrigin+"/planet", false)
		if err != nil || res.Status != http.StatusOK {
			return router.NewApiError(http.StatusBadGateway, "Map provider unavailable.", nil)
		}
		var doc struct {
			Tiles []string `json:"tiles"`
		}
		if json.Unmarshal(res.Body, &doc) != nil || len(doc.Tiles) == 0 {
			return router.NewApiError(http.StatusBadGateway, "Invalid map metadata.", nil)
		}
		version, ok := dmeta.MapTemplateVersion(doc.Tiles[0])
		if !ok {
			return router.NewApiError(http.StatusBadGateway, "Invalid map source.", nil)
		}
		e.Response.Header().Set("Cache-Control", "public, max-age=3600")
		return e.JSON(http.StatusOK, map[string]any{"tilejson": "3.0.0", "maxzoom": 14, "tiles": []string{"/api/fork/map/tiles/" + version + "/{z}/{x}/{y}.pbf"}})
	})
	r.GET("/api/fork/map/tiles/{version}/{z}/{x}/{tile}", func(e *core.RequestEvent) error {
		p := e.Request.PathValue
		tile := p("tile")
		if !strings.HasSuffix(tile, ".pbf") {
			return e.NotFoundError("Invalid tile.", nil)
		}
		upstream, ok := dmeta.MapTileURL(p("version"), p("z"), p("x"), strings.TrimSuffix(tile, ".pbf"))
		if !ok {
			return e.NotFoundError("Invalid tile.", nil)
		}
		if !limit.Allow(e.RealIP(), time.Now()) {
			return e.TooManyRequestsError("Too many map requests.", nil)
		}
		res, err := svc.Fetch(e.Request.Context(), upstream, false)
		if err != nil {
			return router.NewApiError(http.StatusBadGateway, "Map provider unavailable.", nil)
		}
		if res.Status != http.StatusOK {
			return e.NotFoundError("Tile unavailable.", nil)
		}
		e.Response.Header().Set("Cache-Control", "public, max-age=21600")
		e.Response.Header().Set("X-Content-Type-Options", "nosniff")
		return e.Blob(http.StatusOK, "application/vnd.mapbox-vector-tile", res.Body)
	})
}
