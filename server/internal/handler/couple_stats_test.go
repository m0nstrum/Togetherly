package handler_test

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/stats"
)

func TestCoupleStats(t *testing.T) {
	app := testutil.NewApp(t)
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.CoupleStats(e.Router, stats.New(app), time.Now, slog.New(slog.NewTextHandler(io.Discard, nil)))
		return e.Next()
	})
	testutil.Group(t, app, "statpairaaaaaaa", "statalice000001", "statbob00000001")
	_, alice := testutil.User(t, app, "statalice000001", "statpairaaaaaaa")
	_, eve := testutil.User(t, app, "stateve00000001")
	save := func(col string, set map[string]any) {
		c, err := app.FindCollectionByNameOrId(col)
		require.NoError(t, err)
		r := core.NewRecord(c)
		for k, v := range set {
			r.Set(k, v)
		}
		require.NoError(t, app.Save(r))
	}
	save("chat_messages", map[string]any{"group_id": "statpairaaaaaaa", "user_uid": "statalice000001", "ts": time.Now().UnixMilli()})
	save("miss_you", map[string]any{"group_id": "statpairaaaaaaa", "user_uid": "statbob00000001", "count": 7, "by_weekday": `{"2":7}`})
	save("gifts", map[string]any{"group_id": "statpairaaaaaaa", "sender_uid": "statalice000001", "recipient_uid": "statbob00000001", "state": "sent", "gift_key": "rose"})
	save("watch_history", map[string]any{"group_id": "statpairaaaaaaa", "url": "e2e1.u", "kind": "e2e1.k1", "added_by": "statalice000001"})
	aliceRec, err := app.FindRecordById("users", "statalice000001")
	require.NoError(t, err)
	aliceRec.Set("display_name", "e2e1.name")
	require.NoError(t, app.Save(aliceRec))

	code, body := testutil.Do(t, app, http.MethodGet, "/api/couple/stats?groupId=statpairaaaaaaa", alice, "")
	require.Equal(t, http.StatusOK, code, body)
	var out struct {
		OK       bool
		Totals   map[string]float64
		ByMember struct {
			MissYou []struct {
				UID string
				C   int
			}
		}
		Members []struct{ UID string }
	}
	require.NoError(t, json.Unmarshal([]byte(body), &out))
	assert.True(t, out.OK)
	assert.EqualValues(t, 1, out.Totals["messages"])
	assert.EqualValues(t, 7, out.Totals["missYou"])
	assert.EqualValues(t, 1, out.Totals["gifts"])
	assert.Len(t, out.Members, 2)
	// B9: имена и площадки просмотров — шифр, их подставляет клиент.
	assert.NotContains(t, body, "e2e1.", "шифр не уходит в ответ")
	require.Len(t, out.ByMember.MissYou, 1)
	assert.Equal(t, 7, out.ByMember.MissYou[0].C)

	code, _ = testutil.Do(t, app, http.MethodGet, "/api/couple/stats?groupId=statpairaaaaaaa", eve, "")
	assert.Equal(t, http.StatusForbidden, code)
	code, _ = testutil.Do(t, app, http.MethodGet, "/api/couple/stats", alice, "")
	assert.Equal(t, http.StatusBadRequest, code)
}
