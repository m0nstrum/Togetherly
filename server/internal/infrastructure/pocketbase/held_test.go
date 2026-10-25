package pocketbase_test

import (
	"encoding/json"
	"net/http"
	"strconv"
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/domain/realtime"
	tpb "github.com/m0nstrum/togetherly/server/internal/infrastructure/pocketbase"
)

// «Отправить утром»: до срока сообщение видит только автор, его не
// рассылают; в срок оно приходит партнёру как новое, временем срока.
func TestHeldMessages(t *testing.T) {
	w := newWorld(t)
	due := time.Now().Add(time.Hour).UnixMilli()
	code, body := w.do(t, http.MethodPost, "/api/collections/chat_messages/records", w.aTok,
		`{"group_id":"`+pairA+`","user_uid":"`+alice+`","text":"e2e1.k.n.c","ts":1,"deliver_at":`+strconv.FormatInt(due, 10)+`,"held":false}`)
	require.Equal(t, http.StatusOK, code, body)
	var created struct{ ID string }
	require.NoError(t, json.Unmarshal([]byte(body), &created))
	path := "/api/collections/chat_messages/records/" + created.ID

	rec, err := w.app.FindRecordById("chat_messages", created.ID)
	require.NoError(t, err)
	assert.True(t, rec.GetBool("held"), "флаг ставит сервер, а не тело")
	_, ok := tpb.HeldEvent(realtime.EventCreate, rec)
	assert.False(t, ok, "придержанное не рассылается")

	code, _ = w.do(t, http.MethodGet, path, w.bTok, "")
	assert.Equal(t, http.StatusNotFound, code, "партнёр до срока не видит")
	_, list := w.do(t, http.MethodGet, "/api/collections/chat_messages/records", w.bTok, "")
	assert.NotContains(t, list, created.ID)
	code, _ = w.do(t, http.MethodGet, path, w.aTok, "")
	assert.Equal(t, http.StatusOK, code, "автор видит своё")
	code, _ = w.do(t, http.MethodPatch, path, w.aTok, `{"held":false}`)
	require.Equal(t, http.StatusOK, code)
	rec, err = w.app.FindRecordById("chat_messages", created.ID)
	require.NoError(t, err)
	assert.True(t, rec.GetBool("held"), "флаг не снять руками")

	require.NoError(t, tpb.ReleaseDue(w.app, time.Now()))
	rec, err = w.app.FindRecordById("chat_messages", created.ID)
	require.NoError(t, err)
	assert.True(t, rec.GetBool("held"), "срок не наступил")

	require.NoError(t, tpb.ReleaseDue(w.app, time.UnixMilli(due+1)))
	rec, err = w.app.FindRecordById("chat_messages", created.ID)
	require.NoError(t, err)
	assert.False(t, rec.GetBool("held"))
	assert.EqualValues(t, due, rec.GetInt("ts"), "встаёт в переписку временем срока")
	code, _ = w.do(t, http.MethodGet, path, w.bTok, "")
	assert.Equal(t, http.StatusOK, code)
}

// «Отправить сейчас»: автор сдвигает срок на текущий момент.
func TestHeldSendNow(t *testing.T) {
	w := newWorld(t)
	due := time.Now().Add(time.Hour).UnixMilli()
	code, body := w.do(t, http.MethodPost, "/api/collections/chat_messages/records", w.aTok,
		`{"group_id":"`+pairA+`","user_uid":"`+alice+`","ts":1,"deliver_at":`+strconv.FormatInt(due, 10)+`}`)
	require.Equal(t, http.StatusOK, code, body)
	var created struct{ ID string }
	require.NoError(t, json.Unmarshal([]byte(body), &created))
	var events []realtime.Event
	w.app.OnRecordAfterUpdateSuccess("chat_messages").BindFunc(func(e *core.RecordEvent) error {
		if ev, ok := tpb.HeldEvent(realtime.EventUpdate, e.Record); ok {
			events = append(events, ev)
		}
		return e.Next()
	})
	now := time.Now().UnixMilli()
	code, body = w.do(t, http.MethodPatch, "/api/collections/chat_messages/records/"+created.ID, w.aTok,
		`{"deliver_at":`+strconv.FormatInt(now, 10)+`}`)
	require.Equal(t, http.StatusOK, code, body)
	rec, err := w.app.FindRecordById("chat_messages", created.ID)
	require.NoError(t, err)
	assert.False(t, rec.GetBool("held"))
	assert.EqualValues(t, now, rec.GetInt("ts"))
	assert.Equal(t, []realtime.Event{realtime.EventCreate}, events, "партнёру выпущенное приходит как новое")
}
