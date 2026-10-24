package handler_test

import (
	"context"
	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/safefetch"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/meta"
	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"net/http"
	"strings"
	"testing"
	"time"
)

type mapFetcher struct {
	urls    []string
	invalid bool
}

func (f *mapFetcher) Get(ctx context.Context, raw string, headers map[string]string) (safefetch.Response, error) {
	f.urls = append(f.urls, raw)
	if len(headers) != 1 || headers["User-Agent"] == "" {
		panic("unexpected forwarded headers")
	}
	if strings.HasSuffix(raw, "/planet") {
		source := "https://tiles.openfreemap.org/planet/20261001_120000_pt/{z}/{x}/{y}.pbf"
		if f.invalid {
			source = "https://evil.test/{z}/{x}/{y}.pbf"
		}
		return safefetch.Response{Status: 200, ContentType: "application/json", Body: []byte(`{"tiles":["` + source + `"]}`)}, nil
	}
	return safefetch.Response{Status: 200, ContentType: "application/x-protobuf", Body: []byte{1, 2, 3}}, nil
}
func (f *mapFetcher) GetManual(ctx context.Context, raw string, headers map[string]string) (safefetch.Response, error) {
	return f.Get(ctx, raw, headers)
}

func TestMapProxyAndCache(t *testing.T) {
	for _, invalid := range []bool{false, true} {
		app := testutil.NewApp(t)
		fetch := &mapFetcher{invalid: invalid}
		svc := meta.New(fetch, 1<<20, time.Now)
		app.OnServe().BindFunc(func(e *core.ServeEvent) error {
			handler.MapTiles(e.Router, svc, &handler.IPLimiter{Max: 100, Window: time.Minute})
			return e.Next()
		})
		code, body := testutil.Do(t, app, http.MethodGet, "/api/fork/map/tilejson", "", "")
		if invalid {
			require.Equal(t, 502, code, body)
			continue
		}
		require.Equal(t, 200, code, body)
		assert.Contains(t, body, "/api/fork/map/tiles/20261001_120000_pt/{z}/{x}/{y}.pbf")
		assert.NotContains(t, body, "openfreemap.org")
		for i := 0; i < 2; i++ {
			code, body = testutil.Do(t, app, http.MethodGet, "/api/fork/map/tiles/20261001_120000_pt/2/1/3.pbf?url=https://evil.test", "", "")
			require.Equal(t, 200, code, body)
			require.Equal(t, string([]byte{1, 2, 3}), body)
		}
		require.Len(t, fetch.urls, 2, "metadata and a single cached tile fetch")
		assert.Equal(t, "https://tiles.openfreemap.org/planet/20261001_120000_pt/2/1/3.pbf", fetch.urls[1])
		for _, path := range []string{"latest/15/0/0.pbf", "latest/2/4/0.pbf", "latest/2/0/4.pbf", "latest/-1/0/0.pbf", "latest/2/01/0.pbf", "arbitrary.url/0/0/0.pbf"} {
			code, _ = testutil.Do(t, app, http.MethodGet, "/api/fork/map/tiles/"+path, "", "")
			assert.Equal(t, 404, code, path)
		}
		assert.Len(t, fetch.urls, 2, "bad coordinates cannot reach upstream")
	}
}
