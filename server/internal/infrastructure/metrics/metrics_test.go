package metrics_test

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/infrastructure/metrics"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
)

func scrape(t *testing.T, m *metrics.Metrics) string {
	t.Helper()
	rec := httptest.NewRecorder()
	m.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	body, err := io.ReadAll(rec.Body)
	require.NoError(t, err)
	return string(body)
}

func TestMetrics(t *testing.T) {
	app := testutil.NewApp(t)
	m := metrics.New()
	m.Bind(app)

	u, tok := testutil.User(t, app, "metricsuser0001")
	testutil.Do(t, app, http.MethodGet, "/api/health", "", "")
	code, _ := testutil.Do(t, app, http.MethodGet, "/api/collections/users/records/"+u.Id, tok, "")
	require.Equal(t, http.StatusOK, code)
	code, _ = testutil.Do(t, app, http.MethodGet, "/api/collections/users/records/nosuchrecord00", tok, "")
	require.Equal(t, http.StatusNotFound, code)
	require.NoError(t, app.CreateBackup(context.Background(), "pb_backup_m.zip"))
	m.Published(nil)

	out := scrape(t, m)
	assert.Contains(t, out, `tethered_http_requests_total{code="2xx",method="GET",route="GET /api/health"} 1`)
	assert.Contains(t, out, `tethered_http_requests_total{code="2xx",method="GET",route="GET /api/collections/{collection}/records/{id}"} 1`)
	assert.Contains(t, out, `tethered_http_requests_total{code="4xx",method="GET",route="GET /api/collections/{collection}/records/{id}"} 1`)
	assert.Contains(t, out, `tethered_backups_total{result="ok"} 1`)
	assert.Contains(t, out, `tethered_centrifugo_publishes_total{result="ok"} 1`)
	assert.Contains(t, out, `tethered_db_size_bytes{file="data.db"}`)

	// Ни id людей, ни адресов, ни почты.
	for _, leak := range []string{u.Id, "metricsuser0001", "example.org", "192.0.2."} {
		assert.False(t, strings.Contains(out, leak), leak)
	}
}
