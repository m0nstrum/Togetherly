package pocketbase_test

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/config"
	tpb "github.com/m0nstrum/togetherly/server/internal/infrastructure/pocketbase"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
)

// S12: сообщение будит партнёра пушем без содержимого, событие он забирает
// со своего сервера.
func TestWakeOnChatMessage(t *testing.T) {
	g := testutil.NewFakeFCM(t)
	app := testutil.NewApp(t)
	tpb.Configure(app, config.Config{
		HooksDir: t.TempDir() + "/none", PublicDir: t.TempDir() + "/none",
		FCM: config.FCM{Credentials: g.Credentials, Endpoint: g.URL, TTL: 10 * time.Minute, Timeout: 5 * time.Second},
	}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	testutil.Group(t, app, pairA, alice, bob)
	_, aTok := testutil.User(t, app, alice, pairA)
	_, bTok := testutil.User(t, app, bob, pairA)

	code, body := testutil.Do(t, app, http.MethodPost, "/api/fork/push-token", "", `{"token":"bob-phone"}`)
	require.Equal(t, http.StatusUnauthorized, code, body)
	code, body = testutil.Do(t, app, http.MethodPost, "/api/fork/push-token", bTok, `{"token":"bob-phone"}`)
	require.Equal(t, http.StatusOK, code, body)
	assert.Contains(t, body, `"enabled":true`, "телефон может гасить фоновый сокет")
	code, _ = testutil.Do(t, app, http.MethodGet, "/api/collections/push_tokens/records", bTok, "")
	assert.NotEqual(t, http.StatusOK, code, "токены через API не читаются")

	col, err := app.FindCollectionByNameOrId("chat_messages")
	require.NoError(t, err)
	newMsg := func(uid string) *core.Record {
		r := core.NewRecord(col)
		r.Set("group_id", pairA)
		r.Set("user_uid", uid)
		r.Set("text", "e2e1.k.n.ct")
		r.Set("ts", strconv.FormatInt(time.Now().UnixMilli(), 10))
		return r
	}
	msg := core.NewRecord(col)
	msg.Set("group_id", pairA)
	msg.Set("user_uid", alice)
	msg.Set("text", "e2e1.k.n.ct")
	msg.Set("ts", strconv.FormatInt(time.Now().UnixMilli(), 10))
	require.NoError(t, app.Save(msg))

	require.Eventually(t, func() bool { return len(g.Messages()) == 1 }, 5*time.Second, 20*time.Millisecond)
	m := g.Messages()[0]
	assert.Equal(t, "bob-phone", m["token"])
	data := m["data"].(map[string]any)
	assert.Len(t, data, 2, "только type и event")
	assert.Equal(t, "sync", data["type"])
	raw, _ := json.Marshal(m)
	assert.NotContains(t, string(raw), pairA, "id пары в Google не уходит")
	assert.NotContains(t, string(raw), msg.Id)

	event := data["event"].(string)
	code, _ = testutil.Do(t, app, http.MethodPost, "/api/fork/wake", aTok, `{"event":"`+event+`"}`)
	assert.Equal(t, http.StatusNotFound, code, "чужое событие")
	code, body = testutil.Do(t, app, http.MethodPost, "/api/fork/wake", bTok, `{"event":"`+event+`"}`)
	require.Equal(t, http.StatusOK, code, body)
	var got struct {
		Channel string `json:"channel"`
		Data    struct {
			Event      string         `json:"event"`
			Collection string         `json:"collection"`
			Record     map[string]any `json:"record"`
		} `json:"data"`
	}
	require.NoError(t, json.Unmarshal([]byte(body), &got))
	assert.Equal(t, "pair:"+pairA, got.Channel)
	assert.Equal(t, "create", got.Data.Event)
	assert.Equal(t, "chat_messages", got.Data.Collection)
	assert.Equal(t, msg.Id, got.Data.Record["id"])

	// Своё сообщение Боба Боба не будит; токен Алисы не заведён — и её тоже.
	reply := newMsg(bob)
	require.NoError(t, app.Save(reply))
	time.Sleep(100 * time.Millisecond)
	assert.Len(t, g.Messages(), 1)

	// Knowing another device token does not transfer ownership.
	code, body = testutil.Do(t, app, http.MethodPost, "/api/fork/push-token", aTok, `{"token":"bob-phone"}`)
	require.Equal(t, http.StatusConflict, code, body)
	code, _ = testutil.Do(t, app, http.MethodDelete, "/api/fork/push-token", aTok, `{"token":"bob-phone"}`)
	require.Equal(t, http.StatusOK, code)
	tok, err := app.FindFirstRecordByData("push_tokens", "token", "bob-phone")
	require.NoError(t, err)
	assert.Equal(t, bob, tok.GetString("user_uid"), "foreign registration and logout preserve owner")
	// The actual phone rotates its FCM token when changing account.
	code, body = testutil.Do(t, app, http.MethodPost, "/api/fork/push-token", aTok, `{"token":"alice-phone"}`)
	require.Equal(t, http.StatusOK, code, body)

	// Мёртвый токен забывается.
	g.Dead["alice-phone"] = true
	again := newMsg(bob) // wakes Alice at the freshly rotated token
	require.NoError(t, app.Save(again))
	require.Eventually(t, func() bool {
		_, err := app.FindFirstRecordByData("push_tokens", "token", "alice-phone")
		return err != nil
	}, 5*time.Second, 20*time.Millisecond)
}
