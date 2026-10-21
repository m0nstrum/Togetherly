package safefetch_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/infrastructure/safefetch"
)

func TestPublic(t *testing.T) {
	for addr, want := range map[string]bool{
		"8.8.8.8": true, "2a00:1450::1": true,
		"127.0.0.1": false, "10.1.2.3": false, "172.16.0.1": false, "192.168.1.1": false,
		"169.254.169.254": false, "100.64.0.1": false, "0.0.0.0": false, "::1": false,
		"fd00::1": false, "fe80::1": false, "224.0.0.1": false,
	} {
		assert.Equal(t, want, safefetch.Public(netip.MustParseAddr(addr)), addr)
	}
}

// Без разрешения петли загрузчик не ходит на внутренний адрес — ни напрямую,
// ни через редирект с публичного (здесь — с другого петлевого) адреса.
func TestDeniesInternal(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("secret"))
	}))
	defer srv.Close()

	_, err := safefetch.New(safefetch.Options{AllowAnyPort: true}).Get(context.Background(), srv.URL, nil)
	assert.ErrorIs(t, err, safefetch.ErrDenied)

	// Сокращённую запись Go вовсе не считает адресом — запроса нет.
	_, err = safefetch.New(safefetch.Options{}).Get(context.Background(), "http://127.1:80/", nil)
	assert.Error(t, err)

	_, err = safefetch.New(safefetch.Options{}).Get(context.Background(), "file:///etc/passwd", nil)
	assert.ErrorIs(t, err, safefetch.ErrDenied)
}

func TestRedirectsAndLimits(t *testing.T) {
	hops := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/loop":
			hops++
			http.Redirect(w, r, "/loop", http.StatusFound)
		case "/big":
			_, _ = w.Write(make([]byte, 4096))
		case "/file":
			http.Redirect(w, r, "file:///etc/passwd", http.StatusFound)
		default:
			http.Redirect(w, r, "/big", http.StatusFound)
		}
	}))
	defer srv.Close()
	c := safefetch.New(safefetch.Options{AllowLoopback: true, AllowAnyPort: true, MaxBytes: 1000, MaxRedirects: 3})

	resp, err := c.Get(context.Background(), srv.URL+"/start", nil)
	require.NoError(t, err)
	assert.Len(t, resp.Body, 1000, "тело обрезано")
	assert.Contains(t, resp.FinalURL, "/big")

	_, err = c.Get(context.Background(), srv.URL+"/loop", nil)
	assert.ErrorIs(t, err, safefetch.ErrDenied)
	assert.LessOrEqual(t, hops, 4)

	_, err = c.Get(context.Background(), srv.URL+"/file", nil)
	assert.ErrorIs(t, err, safefetch.ErrDenied)
}
