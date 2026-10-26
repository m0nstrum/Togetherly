package handler_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/golang-jwt/jwt/v5"
	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/domain/realtime"
	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
)

// Подписку получает только своя действующая пара; токен подписан общим
// ключом и несёт канал.
func TestRealtimeTokens(t *testing.T) {
	const secret = "rt-secret"
	app := testutil.NewApp(t)
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.RealtimeTokens(e.Router, secret)
		return e.Next()
	})
	testutil.Group(t, app, "rtpairaaaaaaaaa", "rtalice00000001", "rtbob000000001x")
	gone := testutil.Group(t, app, "rtpairbbbbbbbbb", "rtalice00000001", "rteve0000000001")
	gone.Set("disbanded", true)
	require.NoError(t, app.Save(gone))
	_, alice := testutil.User(t, app, "rtalice00000001", "rtpairaaaaaaaaa")
	testutil.User(t, app, "rtbob000000001x", "rtpairaaaaaaaaa")
	_, eve := testutil.User(t, app, "rteve0000000001")

	sub := func(tok, channel string) (int, jwt.MapClaims) {
		code, body := testutil.Do(t, app, http.MethodPost, "/api/centrifugo/subscription-token", tok, `{"channel":"`+channel+`"}`)
		if code != http.StatusOK {
			return code, nil
		}
		var res struct{ Token string }
		require.NoError(t, json.Unmarshal([]byte(body), &res))
		claims := jwt.MapClaims{}
		_, err := jwt.ParseWithClaims(res.Token, claims, func(*jwt.Token) (any, error) { return []byte(secret), nil })
		require.NoError(t, err)
		return code, claims
	}
	room := realtime.RoomCode("rtpairaaaaaaaaa", secret)
	for _, ch := range []string{"pair:rtpairaaaaaaaaa", "signal:rtpairaaaaaaaaa", "draw:rtpairaaaaaaaaa",
		"user:rtalice00000001", "user:rtbob000000001x", "loc:pair_rtalice00000001_rtbob000000001x", "watch:" + room} {
		code, claims := sub(alice, ch)
		if assert.Equal(t, http.StatusOK, code, ch) {
			assert.Equal(t, ch, claims["channel"])
			assert.Equal(t, "rtalice00000001", claims["sub"])
		}
	}
	_, claims := sub(alice, "watch:"+room)
	assert.Equal(t, map[string]any{"app": float64(1)}, claims["info"], "экран комнаты — не зритель")

	for _, ch := range []string{"pair:rtpairbbbbbbbbb", "user:rteve0000000001", "loc:pair_rtalice00000001_rteve0000000001",
		"watch:" + realtime.RoomCode("rtpairbbbbbbbbb", secret), "watch:aaaaaaaa", "server:x"} {
		code, _ := sub(alice, ch)
		assert.Equal(t, http.StatusForbidden, code, ch)
	}
	code, _ := sub(eve, "pair:rtpairaaaaaaaaa")
	assert.Equal(t, http.StatusForbidden, code)
	code, _ = sub(eve, "loc:pair_rtalice00000001_rtbob000000001x")
	assert.Equal(t, http.StatusForbidden, code, "чужая пара в геоканале")
	code, _ = sub(alice, "")
	assert.Equal(t, http.StatusBadRequest, code)
	code, _ = sub("", "pair:rtpairaaaaaaaaa")
	assert.Equal(t, http.StatusUnauthorized, code)

	code, body := testutil.Do(t, app, http.MethodPost, "/api/centrifugo/connection-token", eve, "")
	assert.Equal(t, http.StatusOK, code, body)
}
