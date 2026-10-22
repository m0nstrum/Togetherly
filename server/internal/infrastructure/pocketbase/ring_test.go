package pocketbase_test

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/config"
	tpb "github.com/m0nstrum/togetherly/server/internal/infrastructure/pocketbase"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
)

// UX L6: звонок будит закрытое приложение партнёра пушем без содержимого.
func TestRingWakesPartner(t *testing.T) {
	g := testutil.NewFakeFCM(t)
	app := testutil.NewApp(t)
	tpb.Configure(app, config.Config{
		HooksDir: t.TempDir() + "/none", PublicDir: t.TempDir() + "/none",
		FCM: config.FCM{Credentials: g.Credentials, Endpoint: g.URL, TTL: 10 * time.Minute, Timeout: 5 * time.Second},
	}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	testutil.Group(t, app, pairA, alice, bob)
	testutil.Group(t, app, pairB, eve)
	_, aTok := testutil.User(t, app, alice, pairA)
	_, bTok := testutil.User(t, app, bob, pairA)
	_, mTok := testutil.User(t, app, eve, pairB)

	code, body := testutil.Do(t, app, http.MethodPost, "/api/fork/push-token", bTok, `{"token":"bob-phone"}`)
	require.Equal(t, http.StatusOK, code, body)

	code, _ = testutil.Do(t, app, http.MethodPost, "/api/fork/ring", "", `{"group_id":"`+pairA+`"}`)
	assert.Equal(t, http.StatusUnauthorized, code)
	code, _ = testutil.Do(t, app, http.MethodPost, "/api/fork/ring", mTok, `{"group_id":"`+pairA+`"}`)
	assert.Equal(t, http.StatusForbidden, code, "чужая пара")

	code, body = testutil.Do(t, app, http.MethodPost, "/api/fork/ring", aTok, `{"group_id":"`+pairA+`"}`)
	require.Equal(t, http.StatusOK, code, body)
	code, _ = testutil.Do(t, app, http.MethodPost, "/api/fork/ring", aTok, `{"group_id":"`+pairA+`"}`)
	assert.Equal(t, http.StatusTooManyRequests, code, "чаще раза в 10 с")

	require.Eventually(t, func() bool { return len(g.Messages()) == 1 }, 5*time.Second, 20*time.Millisecond)
	m := g.Messages()[0]
	assert.Equal(t, "bob-phone", m["token"])
	raw, _ := json.Marshal(m)
	assert.NotContains(t, string(raw), pairA, "в Google — только id события")
	assert.NotContains(t, string(raw), alice)

	event := m["data"].(map[string]any)["event"].(string)
	code, body = testutil.Do(t, app, http.MethodPost, "/api/fork/wake", bTok, `{"event":"`+event+`"}`)
	require.Equal(t, http.StatusOK, code, body)
	assert.Contains(t, body, `"thread":"call"`)
	assert.Contains(t, body, `"from":"`+alice+`"`)
}
