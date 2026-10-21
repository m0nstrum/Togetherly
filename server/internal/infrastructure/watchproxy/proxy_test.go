package watchproxy_test

import (
	"context"
	"crypto/tls"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/domain/watchproxy"
	proxy "github.com/m0nstrum/togetherly/server/internal/infrastructure/watchproxy"
)

type setup struct {
	proxyURL string
	quota    *watchproxy.Quota
	results  []string
}

func newSetup(t *testing.T, daily int64) *setup {
	t.Helper()
	site := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ролик"))
	}))
	t.Cleanup(site.Close)
	s := &setup{quota: &watchproxy.Quota{Daily: daily}}
	p := proxy.New(proxy.Options{
		Policy: watchproxy.Policy{Hosts: watchproxy.DefaultHosts},
		Quota:  s.quota,
		Auth: func(_ context.Context, user, token string) bool {
			return user == "alice" && token == "good"
		},
		// Любой разрешённый хост ведёт на подставную площадку.
		Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
			var d net.Dialer
			return d.DialContext(ctx, network, site.Listener.Addr().String())
		},
		Observe: func(result string) { s.results = append(s.results, result) },
	})
	srv := httptest.NewUnstartedServer(p)
	srv.StartTLS()
	t.Cleanup(srv.Close)
	s.proxyURL = srv.URL
	return s
}

func (s *setup) get(t *testing.T, user, pass, target string) (string, error) {
	t.Helper()
	u, err := url.Parse(s.proxyURL)
	require.NoError(t, err)
	u.User = url.UserPassword(user, pass)
	c := &http.Client{
		Timeout: 5 * time.Second,
		Transport: &http.Transport{
			Proxy:           http.ProxyURL(u),
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true}, //nolint:gosec // самоподписанные в тесте
		},
	}
	res, err := c.Get(target)
	if err != nil {
		return "", err
	}
	defer func() { _ = res.Body.Close() }()
	b, err := io.ReadAll(res.Body)
	return string(b), err
}

func TestProxyPassesAllowedHost(t *testing.T) {
	s := newSetup(t, 0)
	body, err := s.get(t, "alice", "good", "https://www.youtube.com/watch")
	require.NoError(t, err)
	assert.Equal(t, "ролик", body)
	assert.Contains(t, s.results, "ok")
}

func TestProxyRefuses(t *testing.T) {
	s := newSetup(t, 0)

	_, err := s.get(t, "alice", "bad", "https://www.youtube.com/")
	assert.ErrorContains(t, err, "Proxy Authentication Required")

	_, err = s.get(t, "alice", "good", "https://evil.example.com/")
	assert.ErrorContains(t, err, "Forbidden")

	assert.Equal(t, []string{"auth", "denied"}, s.results)
}

func TestProxyQuota(t *testing.T) {
	s := newSetup(t, 1)
	s.quota.Add("alice", 1, time.Now())
	_, err := s.get(t, "alice", "good", "https://www.youtube.com/")
	assert.ErrorContains(t, err, "Too Many Requests")
}

func TestProxyLooksLikeSiteForPlainRequests(t *testing.T) {
	s := newSetup(t, 0)
	c := &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}} //nolint:gosec // тест
	res, err := c.Get(s.proxyURL + "/")
	require.NoError(t, err)
	_ = res.Body.Close()
	assert.Equal(t, http.StatusNotFound, res.StatusCode)
}
