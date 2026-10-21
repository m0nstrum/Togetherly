package pocketbase_test

import (
	"io"
	"log/slog"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/config"
	tpb "github.com/m0nstrum/togetherly/server/internal/infrastructure/pocketbase"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
)

const (
	pairA = "pairaaaaaaaaaaa"
	pairB = "pairbbbbbbbbbbb"
	alice = "aliceaaaaaaaaaa"
	bob   = "bobbbbbbbbbbbbb"
	eve   = "eveeeeeeeeeeeee"
)

type world struct {
	app              *tests.TestApp
	aTok, bTok, eTok string
}

// newWorld — приложение со всеми хуками форка (без JS-хуков и сети), пара
// alice+bob и посторонняя eve в своей паре.
func newWorld(t *testing.T) *world {
	t.Helper()
	app := testutil.NewApp(t)
	tpb.Configure(app, config.Config{HooksDir: t.TempDir() + "/none", PublicDir: t.TempDir() + "/none"},
		slog.New(slog.NewTextHandler(io.Discard, nil)))
	testutil.Group(t, app, pairA, alice, bob)
	testutil.Group(t, app, pairB, eve)
	w := &world{app: app}
	_, w.aTok = testutil.User(t, app, alice, pairA)
	_, w.bTok = testutil.User(t, app, bob, pairA)
	_, w.eTok = testutil.User(t, app, eve, pairB)
	return w
}

func (w *world) do(t *testing.T, method, url, tok, body string) (int, string) {
	t.Helper()
	return testutil.Do(t, w.app, method, url, tok, body)
}

func TestGroupCreateOnlyWithSelf(t *testing.T) {
	w := newWorld(t)
	code, _ := w.do(t, http.MethodPost, "/api/collections/groups/records", w.eTok, `{"members":["`+eve+`","`+alice+`"]}`)
	assert.Equal(t, http.StatusForbidden, code, "вписать чужого в свою группу")

	code, _ = w.do(t, http.MethodPost, "/api/collections/groups/records", w.eTok, `{"members":["`+eve+`"]}`)
	assert.Equal(t, http.StatusOK, code, "своя группа")

	// Повтор создания существующей пары (upsert клиента) — штатное «не уникально».
	code, body := w.do(t, http.MethodPost, "/api/collections/groups/records", w.aTok, `{"id":"`+pairA+`","members":["`+alice+`","`+bob+`"]}`)
	assert.Equal(t, http.StatusBadRequest, code)
	assert.Contains(t, body, "validation_not_unique")
}

func TestLiveLocationChannel(t *testing.T) {
	w := newWorld(t)
	post := func(tok, uid, channel string) int {
		code, _ := w.do(t, http.MethodPost, "/api/collections/live_location/records", tok,
			`{"channel":"`+channel+`","user_uid":"`+uid+`","data":{}}`)
		return code
	}
	assert.Equal(t, http.StatusOK, post(w.aTok, alice, "pair_"+alice+"_"+bob), "своя пара")
	assert.Equal(t, http.StatusOK, post(w.aTok, alice, pairA), "канал — id своей группы")
	assert.NotEqual(t, http.StatusOK, post(w.eTok, eve, "pair_"+alice+"_"+bob), "чужая пара")
	assert.NotEqual(t, http.StatusOK, post(w.eTok, eve, "pair_"+alice+"_"+eve), "с собой, но не в паре")
	assert.NotEqual(t, http.StatusOK, post(w.eTok, eve, pairA), "id чужой группы")
}

func TestPresenceAndAvatarsOnlyForPair(t *testing.T) {
	w := newWorld(t)
	save := func(col string, fields map[string]any) string {
		c, err := w.app.FindCollectionByNameOrId(col)
		require.NoError(t, err)
		r := core.NewRecord(c)
		for k, v := range fields {
			r.Set(k, v)
		}
		require.NoError(t, w.app.Save(r))
		return r.Id
	}
	presence := save("user_presence", map[string]any{"user_uid": alice, "seen_at": 1})
	avatar := save("media", map[string]any{"uid": alice, "group_id": alice, "kind": "avatars"})

	for _, tc := range []struct{ col, id string }{{"user_presence", presence}, {"media", avatar}} {
		code, _ := w.do(t, http.MethodGet, "/api/collections/"+tc.col+"/records/"+tc.id, w.bTok, "")
		assert.Equal(t, http.StatusOK, code, "%s: партнёр", tc.col)
		code, _ = w.do(t, http.MethodGet, "/api/collections/"+tc.col+"/records/"+tc.id, w.eTok, "")
		assert.NotEqual(t, http.StatusOK, code, "%s: посторонний", tc.col)
	}
}

func TestCapsule(t *testing.T) {
	w := newWorld(t)
	future := time.Now().Add(48 * time.Hour).UTC().Format("2006-01-02T15:04:05.000Z")
	col, err := w.app.FindCollectionByNameOrId("memories")
	require.NoError(t, err)
	m := core.NewRecord(col)
	m.Set("group_id", pairA)
	m.Set("author_uid", alice)
	m.Set("data", map[string]any{"type": "text", "authorUid": alice, "sealed": true, "openAt": future, "text": "секрет", "reactions": map[string]any{}})
	require.NoError(t, w.app.Save(m))
	url := "/api/collections/memories/records/" + m.Id

	t.Run("содержимое не отдаётся", func(t *testing.T) {
		for _, tok := range []string{w.aTok, w.bTok} {
			code, body := w.do(t, http.MethodGet, url, tok, "")
			require.Equal(t, http.StatusOK, code)
			assert.NotContains(t, body, "секрет")
			assert.Contains(t, body, future)
		}
		_, list := w.do(t, http.MethodGet, "/api/collections/memories/records", w.bTok, "")
		assert.NotContains(t, list, "секрет")
	})

	t.Run("обрезанная копия от клиента не стирает содержимое", func(t *testing.T) {
		code, _ := w.do(t, http.MethodPatch, url, w.bTok, `{"data":{"type":"text","authorUid":"`+alice+`","sealed":false,"openAt":"2020-01-01T00:00:00.000Z","reactions":{"`+bob+`":"❤"}}}`)
		require.Equal(t, http.StatusOK, code)
		got, err := w.app.FindRecordById("memories", m.Id)
		require.NoError(t, err)
		data := got.GetString("data")
		assert.Contains(t, data, "секрет")
		assert.Contains(t, data, future, "партнёр не распечатал раньше срока")
		assert.Contains(t, data, "❤")
	})

	t.Run("после срока — целиком", func(t *testing.T) {
		got, err := w.app.FindRecordById("memories", m.Id)
		require.NoError(t, err)
		data := strings.Replace(got.GetString("data"), future, "2020-01-01T00:00:00.000Z", 1)
		got.Set("data", data)
		require.NoError(t, w.app.Save(got))
		_, body := w.do(t, http.MethodGet, url, w.bTok, "")
		assert.Contains(t, body, "секрет")
	})
}

// S5: удаление аккаунта через API и отмена входом паролем.
func TestScheduleDeleteAndLoginCancels(t *testing.T) {
	w := newWorld(t)
	code, body := w.do(t, http.MethodPost, "/api/account/schedule-delete", w.aTok, `{}`)
	require.Equal(t, http.StatusOK, code, body)
	u, err := w.app.FindRecordById("users", alice)
	require.NoError(t, err)
	assert.False(t, u.GetDateTime("delete_after").IsZero())

	code, _ = w.do(t, http.MethodPost, "/api/account/schedule-delete", "", `{}`)
	assert.NotEqual(t, http.StatusOK, code, "без входа")

	code, body = w.do(t, http.MethodPost, "/api/collections/users/auth-with-password", "",
		`{"identity":"`+alice+`@example.org","password":"password123"}`)
	require.Equal(t, http.StatusOK, code, body)
	assert.NotContains(t, body, "delete_after", "поле скрыто")
	u, err = w.app.FindRecordById("users", alice)
	require.NoError(t, err)
	assert.True(t, u.GetDateTime("delete_after").IsZero(), "вход паролем снял пометку")
}

// S5: meta gateway не работает открытым прокси, превью — только вошедшим.
func TestMetaGatewayGuards(t *testing.T) {
	w := newWorld(t)
	code, _ := w.do(t, http.MethodGet, "/api/meta/fetch?url="+"http%3A%2F%2F127.0.0.1%3A8090%2Fapi%2Fhealth", "", "")
	assert.Equal(t, http.StatusForbidden, code, "внутренний адрес")
	code, _ = w.do(t, http.MethodGet, "/api/meta/fetch?url="+"https%3A%2F%2Fevil.example.org%2F", "", "")
	assert.Equal(t, http.StatusForbidden, code, "чужой хост")
	code, _ = w.do(t, http.MethodGet, "/api/link/preview?url=https%3A%2F%2Fexample.org", "", "")
	assert.Equal(t, http.StatusUnauthorized, code, "превью без входа")
	code, body := w.do(t, http.MethodGet, "/api/link/preview?url=javascript%3Aalert(1)", w.aTok, "")
	assert.Equal(t, http.StatusBadRequest, code, body)
}
