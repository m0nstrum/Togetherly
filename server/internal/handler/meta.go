package handler

import (
	"errors"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"

	dmeta "github.com/m0nstrum/togetherly/server/internal/domain/meta"
	"github.com/m0nstrum/togetherly/server/internal/usecase/meta"
)

// Meta — meta gateway:
//
//	GET /api/meta/fetch?url=…   — ответ стороннего адреса как есть. Белый
//	                              список — без входа, остальное — вошедшим
//	                              (usecase/meta.Fetch). Лимит запросов на IP,
//	                              а адресов вне списка — ещё и на аккаунт
//	                              (perUser): регистрация открыта, и без него
//	                              любой вошедший качал бы через нас что
//	                              угодно (CODE_AUDIT M8, BACKLOG T5).
//	                              С X-Meta-Redirect: manual — без перехода
//	                              по редиректу: 3xx и Location как есть.
//	GET /api/link/preview?url=… — карточка товара (форма ответа апстрима).
func Meta(r *router.Router[*core.RequestEvent], svc *meta.Service, limit, perUser *IPLimiter, log *slog.Logger) {
	r.GET("/api/meta/fetch", func(e *core.RequestEvent) error {
		now := time.Now()
		if !limit.Allow(e.RealIP(), now) {
			return e.TooManyRequestsError("Слишком часто.", nil)
		}
		raw := e.Request.URL.Query().Get("url")
		if _, listed := dmeta.Allowed(raw); !listed && e.Auth != nil && !perUser.Allow(e.Auth.Id, now) {
			log.WarnContext(e.Request.Context(), "meta/fetch: квота аккаунта", "uid", e.Auth.Id)
			return e.TooManyRequestsError("Слишком много ссылок за час.", nil)
		}
		fetch := svc.Fetch
		if e.Request.Header.Get("X-Meta-Redirect") == "manual" {
			fetch = svc.FetchManual
		}
		res, err := fetch(e.Request.Context(), raw, e.Auth != nil)
		switch {
		case errors.Is(err, meta.ErrNotAllowed):
			return e.ForbiddenError("Адрес не разрешён.", nil)
		case err != nil:
			log.WarnContext(e.Request.Context(), "meta/fetch", "err", err)
			return router.NewApiError(http.StatusBadGateway, "Провайдер не ответил.", nil)
		}
		e.Response.Header().Set("Content-Type", res.ContentType)
		e.Response.Header().Set("Cache-Control", "private, max-age=3600")
		e.Response.Header().Set("X-Content-Type-Options", "nosniff")
		e.Response.Header().Set("Content-Security-Policy", "sandbox")
		if res.FinalURL != "" {
			e.Response.Header().Set("X-Final-URL", res.FinalURL)
		}
		if res.Location != "" {
			e.Response.Header().Set("Location", res.Location)
		}
		return e.Blob(res.Status, res.ContentType, res.Body)
	})

	r.GET("/api/link/preview", func(e *core.RequestEvent) error {
		raw := e.Request.URL.Query().Get("url")
		if raw == "" {
			return e.JSON(http.StatusBadRequest, map[string]any{"success": false, "message": "url required"})
		}
		p, ok, err := svc.LinkPreview(e.Request.Context(), raw)
		if errors.Is(err, meta.ErrNotAllowed) {
			return e.JSON(http.StatusBadRequest, map[string]any{"success": false, "message": "only http(s)"})
		}
		if err != nil || !ok {
			return e.JSON(http.StatusOK, map[string]any{"success": false, "message": "fetch failed"})
		}
		return e.JSON(http.StatusOK, map[string]any{
			"success": true, "title": p.Title, "image": p.Image, "shop": p.Shop,
			"price": p.Price, "currency": p.Currency,
		})
	}).Bind(apis.RequireAuth())
}

// IPLimiter — простое окно: не больше Max запросов с ключа (IP или id
// аккаунта) за Window.
type IPLimiter struct {
	Max    int
	Window time.Duration

	mu    sync.Mutex
	seen  map[string]*window
	swept time.Time
}

type window struct {
	start time.Time
	n     int
}

// Allow — можно ли обслужить запрос с ip в момент now.
func (l *IPLimiter) Allow(ip string, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.seen == nil {
		l.seen = map[string]*window{}
	}
	if now.Sub(l.swept) > l.Window {
		for k, w := range l.seen {
			if now.Sub(w.start) > l.Window {
				delete(l.seen, k)
			}
		}
		l.swept = now
	}
	w, ok := l.seen[ip]
	if !ok || now.Sub(w.start) > l.Window {
		l.seen[ip] = &window{start: now, n: 1}
		return true
	}
	w.n++
	return w.n <= l.Max
}
