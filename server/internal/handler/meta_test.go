package handler_test

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/safefetch"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/meta"
)

func TestIPLimiter(t *testing.T) {
	l := &handler.IPLimiter{Max: 2, Window: time.Minute}
	now := time.Unix(0, 0)
	assert.True(t, l.Allow("1.1.1.1", now))
	assert.True(t, l.Allow("1.1.1.1", now))
	assert.False(t, l.Allow("1.1.1.1", now))
	assert.True(t, l.Allow("2.2.2.2", now), "другой IP")
	assert.True(t, l.Allow("1.1.1.1", now.Add(2*time.Minute)), "новое окно")
}

// T5 (CODE_AUDIT M8): адреса вне белого списка — квота на аккаунт; белый
// список ею не считается.
func TestMetaFetchPerAccountQuota(t *testing.T) {
	app := testutil.NewApp(t)
	fetch := &textFetcher{}
	svc := meta.New(fetch, 1<<20, time.Now)
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.Meta(e.Router, svc, &handler.IPLimiter{Max: 100, Window: time.Minute},
			&handler.IPLimiter{Max: 2, Window: time.Hour}, slog.New(slog.DiscardHandler))
		return e.Next()
	})
	_, alice := testutil.User(t, app, "quotaalice00001")
	_, bob := testutil.User(t, app, "quotabob0000001")
	page := func(n int) string {
		return "/api/meta/fetch?url=" + url.QueryEscape(fmt.Sprintf("https://example.org/p%d", n))
	}
	for i := range 2 {
		code, body := testutil.Do(t, app, http.MethodGet, page(i), alice, "")
		require.Equal(t, http.StatusOK, code, body)
	}
	code, _ := testutil.Do(t, app, http.MethodGet, page(3), alice, "")
	assert.Equal(t, http.StatusTooManyRequests, code, "третья чужая ссылка за час")
	assert.Len(t, fetch.urls, 2, "отказ — до запроса наружу")

	oembed := "/api/meta/fetch?url=" + url.QueryEscape("https://www.youtube.com/oembed?url=x")
	code, body := testutil.Do(t, app, http.MethodGet, oembed, alice, "")
	assert.Equal(t, http.StatusOK, code, "белый список квотой не считается: "+body)

	code, _ = testutil.Do(t, app, http.MethodGet, page(4), bob, "")
	assert.Equal(t, http.StatusOK, code, "у другого аккаунта своя квота")
}

type textFetcher struct{ urls []string }

func (f *textFetcher) Get(_ context.Context, raw string, _ map[string]string) (safefetch.Response, error) {
	f.urls = append(f.urls, raw)
	return safefetch.Response{Status: 200, ContentType: "text/html", Body: []byte("<title>x</title>")}, nil
}

func (f *textFetcher) GetManual(ctx context.Context, raw string, h map[string]string) (safefetch.Response, error) {
	return f.Get(ctx, raw, h)
}
