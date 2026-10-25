package handler

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"

	"github.com/m0nstrum/togetherly/server/internal/usecase/music"
)

// Music — GET /api/music/yandex?track=<номер> (бывший music.pb.js). Ответ в
// форме API Яндекса: `{"result":[{id,title,artists,coverUri}]}`.
func Music(r *router.Router[*core.RequestEvent], svc *music.Service, log *slog.Logger) {
	r.GET("/api/music/yandex", func(e *core.RequestEvent) error {
		id := e.Request.URL.Query().Get("track")
		if id == "" {
			return e.JSON(http.StatusBadRequest, map[string]string{"error": "track required"})
		}
		tr, err := svc.Track(e.Request.Context(), id)
		var up music.UpstreamError
		switch {
		case errors.Is(err, music.ErrBadTrack):
			return e.JSON(http.StatusBadRequest, map[string]string{"error": "bad track id"})
		case errors.Is(err, music.ErrNotFound):
			return e.JSON(http.StatusNotFound, map[string]string{"error": "track not found"})
		case errors.As(err, &up):
			log.WarnContext(e.Request.Context(), "music yandex upstream", "track", id, "status", up.Status)
			return e.JSON(http.StatusBadGateway, map[string]string{"error": up.Error()})
		case err != nil:
			return e.JSON(http.StatusBadGateway, map[string]string{"error": "fetch failed"})
		}
		return e.JSON(http.StatusOK, map[string]any{"result": []music.Track{tr}})
	})
}
