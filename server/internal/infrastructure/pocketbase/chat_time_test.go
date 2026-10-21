package pocketbase_test

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/config"
	tpb "github.com/m0nstrum/togetherly/server/internal/infrastructure/pocketbase"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
)

// Сообщение из офлайна встаёт на время написания, а сбитые часы старой
// сборки не перемешивают переписку (апстрим, обращение 409).
func TestChatMessageTime(t *testing.T) {
	app := testutil.NewApp(t)
	tpb.Configure(app, config.Config{
		HooksDir: t.TempDir() + "/none", PublicDir: t.TempDir() + "/none",
	}, slog.New(slog.NewTextHandler(io.Discard, nil)))
	testutil.Group(t, app, pairA, alice, bob)
	_, aTok := testutil.User(t, app, alice, pairA)

	send := func(t *testing.T, ts, sentAt int64) int64 {
		body := `{"group_id":"` + pairA + `","user_uid":"` + alice + `","text":"e2e1.k.n.ct","ts":` +
			strconv.FormatInt(ts, 10)
		if sentAt > 0 {
			body += `,"sent_at":` + strconv.FormatInt(sentAt, 10)
		}
		code, res := testutil.Do(t, app, http.MethodPost, "/api/collections/chat_messages/records", aTok, body+"}")
		require.Equal(t, http.StatusOK, code, res)
		var rec struct {
			TS float64 `json:"ts"`
		}
		require.NoError(t, json.Unmarshal([]byte(res), &rec))
		return int64(rec.TS)
	}
	now := time.Now().UnixMilli()
	hour := time.Hour.Milliseconds()

	t.Run("из офлайна — время написания", func(t *testing.T) {
		assert.InDelta(t, now-2*hour, send(t, now-2*hour, time.Now().UnixMilli()), 5000)
	})
	t.Run("старая сборка со сбитыми часами — время сервера", func(t *testing.T) {
		assert.InDelta(t, time.Now().UnixMilli(), send(t, now-2*hour, 0), 5000)
	})
}
