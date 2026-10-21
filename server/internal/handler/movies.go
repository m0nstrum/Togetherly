package handler

import (
	"errors"
	"log/slog"
	"net/http"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"

	"github.com/m0nstrum/togetherly/server/internal/usecase/movies"
)

// Movies — GET /api/movies/search?q=…&lang=… (бывший hotpath). Ответ в
// форме poiskkino; 429 — человек ищет слишком часто, 503 с data.reason —
// источники не ответили (quota — ещё и ключ poiskkino на сегодня кончился).
func Movies(r *router.Router[*core.RequestEvent], svc *movies.Service, log *slog.Logger) {
	r.GET("/api/movies/search", func(e *core.RequestEvent) error {
		q := e.Request.URL.Query()
		res, err := svc.Search(e.Request.Context(), e.Auth.Id, q.Get("q"), q.Get("lang"))
		switch {
		case errors.Is(err, movies.ErrRateLimited):
			return e.TooManyRequestsError("too many searches", nil)
		case err != nil:
			log.WarnContext(e.Request.Context(), "movies/search", "err", err)
			reason := "source"
			if errors.Is(err, movies.ErrQuota) {
				reason = "quota"
			}
			return e.JSON(http.StatusServiceUnavailable, map[string]any{
				"status": http.StatusServiceUnavailable, "message": "movie search failed",
				"data": map[string]string{"reason": reason},
			})
		}
		return e.JSON(http.StatusOK, res)
	}).Bind(apis.RequireAuth())
}
