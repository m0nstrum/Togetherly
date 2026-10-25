package handler_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/notify"
)

// fakePubs — опубликованные уведомления: канал и заголовок.
type fakePubs struct{ channels, titles []string }

func (p *fakePubs) Publish(_ context.Context, ch string, data any) error {
	rec, _ := data.(map[string]any)["record"].(map[string]any)
	title, _ := rec["title"].(string)
	p.channels = append(p.channels, ch)
	p.titles = append(p.titles, title)
	return nil
}

func TestCalls(t *testing.T) {
	app := testutil.NewApp(t)
	pub := &fakePubs{}
	now := time.Date(2026, 10, 20, 20, 0, 0, 0, time.UTC)
	clock := func() time.Time { return now }
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.Calls(e.Router, notify.New(app, pub, clock), clock)
		return e.Next()
	})
	testutil.Group(t, app, "callpairaaaaaaa", "callalice000001", "callbob00000001")
	alice, aTok := testutil.User(t, app, "callalice000001", "callpairaaaaaaa")
	alice.Set("display_name", "Аня")
	require.NoError(t, app.Save(alice))
	_, bTok := testutil.User(t, app, "callbob00000001", "callpairaaaaaaa")
	_, eve := testutil.User(t, app, "calleve00000001")
	post := func(path, tok, body string) map[string]any {
		code, raw := testutil.Do(t, app, http.MethodPost, path, tok, body)
		out := map[string]any{"_code": float64(code)}
		_ = json.Unmarshal([]byte(raw), &out)
		return out
	}

	res := post("/api/draw/invite", aTok, `{"group_id":"callpairaaaaaaa"}`)
	assert.Equal(t, true, res["sent"], res)
	require.Len(t, pub.channels, 1)
	assert.Equal(t, "user:callbob00000001", pub.channels[0], "автору не шлём")
	assert.Contains(t, pub.titles[0], "Аня зовёт порисовать")
	assert.Equal(t, "too soon", post("/api/draw/invite", aTok, `{"group_id":"callpairaaaaaaa"}`)["why"])
	now = now.Add(31 * time.Minute)
	assert.Equal(t, true, post("/api/draw/invite", aTok, `{"group_id":"callpairaaaaaaa"}`)["sent"])
	assert.EqualValues(t, 403, post("/api/draw/invite", eve, `{"group_id":"callpairaaaaaaa"}`)["_code"])

	// Бобу, который выключил рисование, не шлём.
	bob, err := app.FindRecordById("users", "callbob00000001")
	require.NoError(t, err)
	bob.Set("notif_synced_at", "2026-10-01T00:00:00Z")
	require.NoError(t, app.Save(bob))
	now = now.Add(31 * time.Minute)
	n := len(pub.channels)
	post("/api/draw/invite", aTok, `{"group_id":"callpairaaaaaaa"}`)
	assert.Len(t, pub.channels, n, "выключено в настройках")

	// Лента: зов виден партнёру, но не себе; выход гасит.
	res = post("/api/reels/invite", aTok, `{"group_id":"callpairaaaaaaa","feed":"tiktok"}`)
	assert.Equal(t, true, res["sent"], res)
	assert.Contains(t, pub.titles[len(pub.titles)-1], "Аня зовёт смотреть TikTok")
	active := func(tok string) map[string]any {
		_, raw := testutil.Do(t, app, http.MethodGet, "/api/reels/active?group_id=callpairaaaaaaa", tok, "")
		out := map[string]any{}
		_ = json.Unmarshal([]byte(raw), &out)
		return out
	}
	assert.Equal(t, true, active(bTok)["active"])
	assert.Equal(t, "tiktok", active(bTok)["feed"])
	assert.Equal(t, false, active(aTok)["active"])
	assert.Equal(t, "too soon", post("/api/reels/invite", aTok, `{"group_id":"callpairaaaaaaa","feed":"tiktok"}`)["why"])
	now = now.Add(2 * time.Minute)
	assert.Equal(t, true, post("/api/reels/invite", aTok, `{"group_id":"callpairaaaaaaa","feed":"tiktok","again":true}`)["sent"], "кнопкой — через минуту")
	post("/api/reels/invite", aTok, `{"group_id":"callpairaaaaaaa","stop":true}`)
	assert.Equal(t, false, active(bTok)["active"])
}
