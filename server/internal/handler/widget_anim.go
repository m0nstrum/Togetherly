package handler

import (
	"errors"
	"net/http"
	"os"
	"regexp"
	"slices"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"

	"github.com/m0nstrum/togetherly/server/internal/usecase/widgetanim"
)

var mediaIDChars = regexp.MustCompile(`[^a-zA-Z0-9_]`)

// WidgetAnim — раскадровка живого фото для виджета (бывший widget_anim.pb.js):
//
//	POST /api/widget/anim/prepare {mediaId} — сделать (идемпотентно);
//	GET  /api/widget/anim/sheet?id=…        — отдать webp.
//
// Файл — своей пары или свой: правило коллекции пускает участников читать,
// но резать чужой файл нельзя.
func WidgetAnim(r *router.Router[*core.RequestEvent], svc *widgetanim.Service) {
	media := func(e *core.RequestEvent, raw string) (*core.Record, error) {
		id := mediaIDChars.ReplaceAllString(raw, "")
		if id == "" {
			return nil, e.JSON(http.StatusBadRequest, map[string]any{"error": "no mediaId"})
		}
		rec, err := e.App.FindRecordById("media", id)
		if err != nil {
			return nil, e.JSON(http.StatusNotFound, map[string]any{"error": "media not found"})
		}
		if rec.GetString("uid") != e.Auth.Id && !slices.Contains(e.Auth.GetStringSlice("group_ids"), rec.GetString("group_id")) {
			return nil, e.JSON(http.StatusForbidden, map[string]any{"error": "not your media"})
		}
		return rec, nil
	}

	r.POST("/api/widget/anim/prepare", func(e *core.RequestEvent) error {
		var body struct {
			MediaID string `json:"mediaId"`
		}
		_ = e.BindBody(&body)
		rec, deny := media(e, body.MediaID)
		if rec == nil {
			return deny
		}
		m, err := svc.Prepare(e.Request.Context(), rec)
		switch {
		case errors.Is(err, widgetanim.ErrUnsupported):
			return e.JSON(http.StatusUnprocessableEntity, map[string]any{"error": "unsupported file"})
		case errors.Is(err, widgetanim.ErrUnavailable):
			return e.JSON(http.StatusServiceUnavailable, map[string]any{"error": "unavailable"})
		case err != nil:
			e.App.Logger().Warn("widget_anim: prepare", "media", rec.Id, "err", err)
			return e.JSON(http.StatusInternalServerError, map[string]any{"error": "prepare failed"})
		}
		return e.JSON(http.StatusOK, map[string]any{"ok": true, "ready": true, "manifest": m})
	}).Bind(apis.RequireAuth())

	r.GET("/api/widget/anim/sheet", func(e *core.RequestEvent) error {
		rec, deny := media(e, e.Request.URL.Query().Get("id"))
		if rec == nil {
			return deny
		}
		raw, err := os.ReadFile(svc.SheetPath(rec.Id))
		if err != nil {
			return e.JSON(http.StatusNotFound, map[string]any{"error": "not prepared"})
		}
		// Раскадровка по id неизменна: виджет не тянет её на каждом обновлении.
		e.Response.Header().Set("Cache-Control", "private, max-age=2592000, immutable")
		return e.Blob(http.StatusOK, "image/webp", raw)
	}).Bind(apis.RequireAuth())
}
