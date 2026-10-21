package config_test

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/config"
)

func TestLoadDefaults(t *testing.T) {
	cfg, err := config.Load()
	require.NoError(t, err)
	assert.Equal(t, "0.0.0.0:8090", cfg.HTTPAddr)
	assert.Equal(t, 5*time.Second, cfg.Centrifugo.Timeout)
	assert.False(t, cfg.SMTP.Enabled())
}

func TestLoadEnv(t *testing.T) {
	t.Setenv("TETHERED_HTTP_ADDR", "127.0.0.1:9000")
	t.Setenv("TETHERED_CENTRIFUGO__API", "http://centrifugo:8000/api")
	t.Setenv("TETHERED_CENTRIFUGO__API_KEY", "k")
	t.Setenv("TETHERED_CENTRIFUGO__TIMEOUT", "2s")
	t.Setenv("TETHERED_SMTP__HOST", "mail.example.org")
	t.Setenv("TETHERED_SMTP__PORT", "465")
	t.Setenv("TETHERED_SMTP__SENDER", "noreply@example.org")
	cfg, err := config.Load()
	require.NoError(t, err)
	assert.Equal(t, "127.0.0.1:9000", cfg.HTTPAddr)
	assert.Equal(t, "k", cfg.Centrifugo.APIKey)
	assert.Equal(t, 2*time.Second, cfg.Centrifugo.Timeout)
	assert.Equal(t, 465, cfg.SMTP.Port)
	assert.True(t, cfg.SMTP.Enabled())
}

func TestValidate(t *testing.T) {
	t.Setenv("TETHERED_CENTRIFUGO__API", "http://centrifugo:8000/api")
	_, err := config.Load()
	assert.ErrorContains(t, err, "задаются вместе")

	t.Setenv("TETHERED_CENTRIFUGO__API_KEY", "k")
	t.Setenv("TETHERED_SMTP__HOST", "mail.example.org")
	_, err = config.Load()
	assert.ErrorContains(t, err, "SENDER")
}

func TestWatchProxy(t *testing.T) {
	t.Setenv("TETHERED_APP_URL", "https://pair.example.org")
	t.Setenv("TETHERED_WATCH_PROXY__ENABLED", "true")
	_, err := config.Load()
	require.Error(t, err, "без сертификата прокси не включить")

	t.Setenv("TETHERED_WATCH_PROXY__CADDY_DIR", "/caddy")
	t.Setenv("TETHERED_WATCH_PROXY__HOSTS", ".youtube.com, .googlevideo.com ,")
	cfg, err := config.Load()
	require.NoError(t, err)
	assert.Equal(t, "https://pair.example.org:8443", cfg.WatchProxyURL())
	assert.Equal(t, []string{".youtube.com", ".googlevideo.com"}, cfg.WatchProxy.HostList())
	assert.Equal(t, 3072, cfg.WatchProxy.DailyMB)
}
