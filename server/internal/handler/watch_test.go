package handler_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/golang-jwt/jwt/v5"
	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/domain/realtime"
	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/centrifugo"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
)

type fakePresence map[string]centrifugo.Client

func (p fakePresence) Presence(context.Context, string) (map[string]centrifugo.Client, error) {
	return p, nil
}

// Открытая комната — по ссылке любому; комната пары — участнику или
// странице по поручительству приложения; набранный руками код — «нет».
func TestWatchRooms(t *testing.T) {
	const secret = "watch-secret"
	app := testutil.NewApp(t)
	presence := fakePresence{}
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.WatchRooms(e.Router, secret, presence)
		return e.Next()
	})
	testutil.Group(t, app, "watchpairaaaaaa", "watchalice00001", "watchbob0000001")
	_, alice := testutil.User(t, app, "watchalice00001", "watchpairaaaaaa")
	_, eve := testutil.User(t, app, "watcheve0000001")
	post := func(path, tok, body string) (int, map[string]any) {
		code, raw := testutil.Do(t, app, http.MethodPost, path, tok, body)
		out := map[string]any{}
		_ = json.Unmarshal([]byte(raw), &out)
		return code, out
	}

	code, res := post("/api/watch/room", alice, `{"groupId":"watchpairaaaaaa"}`)
	require.Equal(t, http.StatusOK, code, res)
	pairRoom := res["room"].(string)
	assert.Equal(t, realtime.RoomCode("watchpairaaaaaa", secret), pairRoom)
	assert.True(t, realtime.LooksLikePairRoom(pairRoom))
	code, _ = post("/api/watch/room", eve, `{"groupId":"watchpairaaaaaa"}`)
	assert.Equal(t, http.StatusForbidden, code)

	_, res = post("/api/watch/new", "", "")
	open := res["room"].(string)
	assert.Len(t, open, 10)
	code, res = post("/api/watch/token", "", `{"room":"`+open+`"}`)
	require.Equal(t, http.StatusOK, code, res)
	assert.Equal(t, "open", res["kind"])
	claims := jwt.MapClaims{}
	_, err := jwt.ParseWithClaims(res["subscriptionToken"].(string), claims, func(*jwt.Token) (any, error) { return []byte(secret), nil })
	require.NoError(t, err)
	assert.Equal(t, "watch:"+open, claims["channel"])

	code, _ = post("/api/watch/token", "", `{"room":"`+open[:9]+`x"}`)
	assert.Equal(t, http.StatusNotFound, code, "набранный руками код")

	code, res = post("/api/watch/token", alice, `{"room":"`+pairRoom+`"}`)
	require.Equal(t, http.StatusOK, code, res)
	assert.Equal(t, "member", res["kind"])
	code, _ = post("/api/watch/token", eve, `{"room":"`+pairRoom+`"}`)
	assert.Equal(t, http.StatusForbidden, code)
	code, _ = post("/api/watch/token", "", `{"room":"`+pairRoom+`"}`)
	assert.Equal(t, http.StatusUnauthorized, code)

	// Приложение в комнате — одна страница без входа проходит, вторая нет.
	presence["c1"] = centrifugo.Client{User: "watchalice00001", Info: map[string]any{"app": float64(1)}}
	code, res = post("/api/watch/token", "", `{"room":"`+pairRoom+`"}`)
	require.Equal(t, http.StatusOK, code, res)
	assert.Equal(t, "vouch", res["kind"])
	guest := res["userId"].(string)
	presence["c2"] = centrifugo.Client{User: guest, Info: map[string]any{"vouch": float64(1)}}
	code, res = post("/api/watch/token", "", `{"room":"`+pairRoom+`","guest":"`+guest+`"}`)
	assert.Equal(t, http.StatusOK, code, "та же вкладка после перезагрузки")
	code, _ = post("/api/watch/token", "", `{"room":"`+pairRoom+`"}`)
	assert.Equal(t, http.StatusUnauthorized, code, "мест нет")
	code, _ = post("/api/watch/token", "", `{"room":"a/b"}`)
	assert.Equal(t, http.StatusBadRequest, code)
}
