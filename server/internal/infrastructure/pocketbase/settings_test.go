package pocketbase

import (
	"fmt"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/config"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
)

// Решение 3: вход по паролю — значит, перебор пароля упирается в лимит.
func TestLoginRateLimit(t *testing.T) {
	app := testutil.NewApp(t)
	s := app.Settings()
	applySettings(s, config.Config{AppName: "Tethered", RateLimits: true, TrustedProxyHeader: "X-Forwarded-For"})
	require.NoError(t, app.Save(s))
	assert.Equal(t, []string{"X-Forwarded-For"}, app.Settings().TrustedProxy.Headers)
	assert.Zero(t, app.Settings().Logs.MaxDays, "журнал запросов не хранится")
	assert.False(t, app.Settings().Logs.LogIP)

	u, _ := testutil.User(t, app, "limituser000001")
	body := fmt.Sprintf(`{"identity":%q,"password":"wrong-password"}`, u.Email())
	var codes []int
	for range 11 {
		code, _ := testutil.Do(t, app, http.MethodPost, "/api/collections/users/auth-with-password", "", body)
		codes = append(codes, code)
	}
	assert.Equal(t, http.StatusBadRequest, codes[9], "десятая попытка — просто неверный пароль")
	assert.Equal(t, http.StatusTooManyRequests, codes[10], "одиннадцатая — лимит")
}
