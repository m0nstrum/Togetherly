package pocketbase_test

import (
	"encoding/json"
	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"net/http"
	"testing"
)

func TestPairAuthorship(t *testing.T) {
	w := newWorld(t)
	for _, tc := range []struct {
		col, author, group string
		shared             bool
	}{
		{"fork_battery", "user_uid", "group_id", false},
		{"mood_entries", "user_uid", "group_id", false},
		{"widget_data", "user_uid", "group_id", false},
		{"chat_messages", "user_uid", "group_id", true},
		{"live_session_chat", "uid", "pair_id", true},
	} {
		t.Run(tc.col, func(t *testing.T) {
			col, err := w.app.FindCollectionByNameOrId(tc.col)
			require.NoError(t, err)
			r := core.NewRecord(col)
			r.Set(tc.author, alice)
			r.Set(tc.group, pairA)
			r.Set("timestamp", 1)
			r.Set("ts", 1)
			require.NoError(t, w.app.Save(r))
			path := "/api/collections/" + tc.col + "/records/" + r.Id
			code, body := w.do(t, http.MethodPatch, path, w.aTok, `{}`)
			require.Equal(t, http.StatusOK, code, body)
			for _, token := range []string{w.aTok, w.bTok} {
				for _, patch := range []string{`{"` + tc.author + `":"` + bob + `"}`, `{"` + tc.group + `":"` + pairB + `"}`} {
					code, _ = w.do(t, http.MethodPatch, path, token, patch)
					assert.NotEqual(t, http.StatusOK, code, "identity cannot be reassigned")
				}
			}
			code, _ = w.do(t, http.MethodPatch, path, w.bTok, `{"reactions":{}}`)
			if tc.shared && tc.col != "memories" {
				assert.Equal(t, http.StatusOK, code)
			} else {
				assert.NotEqual(t, http.StatusOK, code)
			}
			code, _ = w.do(t, http.MethodDelete, path, w.bTok, "")
			assert.NotEqual(t, http.StatusNoContent, code)
			code, _ = w.do(t, http.MethodDelete, path, w.aTok, "")
			assert.Equal(t, http.StatusNoContent, code)
		})
	}
}

// Чужое желание партнёр отмечает сбывшимся (дата — в шифре `enc`), ставит
// «я тоже хочу» и двигает в общем порядке; название не трогает.
func TestWishSharedFields(t *testing.T) {
	w := newWorld(t)
	col, err := w.app.FindCollectionByNameOrId("wishes")
	require.NoError(t, err)
	r := core.NewRecord(col)
	r.Set("author_uid", alice)
	r.Set("group_id", pairA)
	r.Set("title", "e2e1.k.n.c")
	require.NoError(t, w.app.Save(r))
	path := "/api/collections/wishes/records/" + r.Id

	for _, patch := range []string{
		`{"done":true,"done_by":"` + bob + `","enc":"e2e1.k.n.c"}`,
		`{"also":"e2e1.k.n.c"}`,
		`{"pos":"e2e1.k.n.c"}`,
		`{"skip":"e2e1.k.n.c"}`,
		`{"memory":"e2e1.k.n.c"}`,
	} {
		code, body := w.do(t, http.MethodPatch, path, w.bTok, patch)
		assert.Equal(t, http.StatusOK, code, patch+" "+body)
	}
	for _, patch := range []string{`{"title":"x"}`, `{"due":"e2e1.k.n.c"}`} {
		code, _ := w.do(t, http.MethodPatch, path, w.bTok, patch)
		assert.Equal(t, http.StatusForbidden, code, patch)
	}
	code, body := w.do(t, http.MethodPatch, path, w.aTok, `{"due":"e2e1.k.n.c"}`)
	assert.Equal(t, http.StatusOK, code, body)
}

// Комментарии к желанию: пишут оба, правит и удаляет только автор
// комментария, чужая пара не видит; удалённое желание уносит комментарии.
func TestWishComments(t *testing.T) {
	w := newWorld(t)
	col, err := w.app.FindCollectionByNameOrId("wishes")
	require.NoError(t, err)
	wish := core.NewRecord(col)
	wish.Set("author_uid", alice)
	wish.Set("group_id", pairA)
	wish.Set("title", "e2e1.k.n.c")
	require.NoError(t, w.app.Save(wish))

	const list = "/api/collections/wish_comments/records"
	code, body := w.do(t, http.MethodPost, list, w.bTok,
		`{"group_id":"`+pairA+`","wish_id":"`+wish.Id+`","author_uid":"`+bob+`","text":"e2e1.k.n.c"}`)
	require.Equal(t, http.StatusOK, code, body)
	var created struct{ ID string }
	require.NoError(t, json.Unmarshal([]byte(body), &created))
	id := created.ID

	code, _ = w.do(t, http.MethodPost, list, w.aTok,
		`{"group_id":"`+pairA+`","wish_id":"`+wish.Id+`","author_uid":"`+bob+`","text":"x"}`)
	assert.NotEqual(t, http.StatusOK, code, "от чужого имени")
	code, _ = w.do(t, http.MethodPatch, list+"/"+id, w.aTok, `{"text":"x"}`)
	assert.NotEqual(t, http.StatusOK, code, "чужой комментарий не правят")
	code, body = w.do(t, http.MethodGet, list+"/"+id, w.eTok, "")
	assert.NotEqual(t, http.StatusOK, code, body)
	code, _ = w.do(t, http.MethodGet, list+"/"+id, w.aTok, "")
	assert.Equal(t, http.StatusOK, code)

	code, _ = w.do(t, http.MethodDelete, "/api/collections/wishes/records/"+wish.Id, w.aTok, "")
	require.Equal(t, http.StatusNoContent, code)
	_, err = w.app.FindRecordById("wish_comments", id)
	assert.Error(t, err, "комментарий ушёл вместе с желанием")
}

// Счётчик комментариев под воспоминанием ведёт сервер: создание, мягкое
// удаление и удаление записи; прочие ключи `data` остаются.
func TestCommentsCount(t *testing.T) {
	w := newWorld(t)
	mcol, err := w.app.FindCollectionByNameOrId("memories")
	require.NoError(t, err)
	mem := core.NewRecord(mcol)
	mem.Set("group_id", pairA)
	mem.Set("author_uid", alice)
	mem.Set("data", map[string]any{"type": "text", "e2e": "e2e1.k.n.c"})
	require.NoError(t, w.app.Save(mem))
	count := func() any {
		r, err := w.app.FindRecordById("memories", mem.Id)
		require.NoError(t, err)
		data := map[string]any{}
		require.NoError(t, r.UnmarshalJSONField("data", &data))
		assert.Equal(t, "e2e1.k.n.c", data["e2e"])
		return data["commentsCount"]
	}
	ccol, err := w.app.FindCollectionByNameOrId("memory_comments")
	require.NoError(t, err)
	add := func() *core.Record {
		c := core.NewRecord(ccol)
		c.Set("group_id", pairA)
		c.Set("memory_id", mem.Id)
		c.Set("author_uid", bob)
		c.Set("text", "x")
		require.NoError(t, w.app.Save(c))
		return c
	}
	a, b := add(), add()
	assert.EqualValues(t, 2, count())
	a.Set("deleted", true)
	require.NoError(t, w.app.Save(a))
	assert.EqualValues(t, 1, count())
	require.NoError(t, w.app.Delete(b))
	assert.EqualValues(t, 0, count())
}

// Счётчики пары: сообщения, холсты и лента (мягкое удаление тоже считается).
func TestPairCounters(t *testing.T) {
	w := newWorld(t)
	save := func(name string, set map[string]any) *core.Record {
		col, err := w.app.FindCollectionByNameOrId(name)
		require.NoError(t, err)
		r := core.NewRecord(col)
		r.Set("group_id", pairA)
		for k, v := range set {
			r.Set(k, v)
		}
		require.NoError(t, w.app.Save(r))
		return r
	}
	count := func(f string) float64 {
		g, err := w.app.FindRecordById("groups", pairA)
		require.NoError(t, err)
		return g.GetFloat(f)
	}
	save("chat_messages", map[string]any{"user_uid": alice, "ts": 1})
	save("chat_messages", map[string]any{"user_uid": bob, "ts": 2})
	assert.EqualValues(t, 2, count("messages_count"))

	c := save("canvas_catalogue", map[string]any{"name": "x", "canvas_id": "c1"})
	assert.EqualValues(t, 1, count("drawings_count"))
	require.NoError(t, w.app.Delete(c))
	require.NoError(t, w.app.Delete(save("canvas_catalogue", map[string]any{"name": "y", "canvas_id": "c2"})))
	assert.EqualValues(t, 0, count("drawings_count"), "ниже нуля не уходит")

	m := save("memories", map[string]any{"author_uid": alice})
	save("memories", map[string]any{"author_uid": alice, "deleted": true})
	assert.EqualValues(t, 1, count("memories_count"))
	m.Set("deleted", true)
	require.NoError(t, w.app.Save(m))
	assert.EqualValues(t, 0, count("memories_count"))
	m, err := w.app.FindRecordById("memories", m.Id) // как в настоящем запросе
	require.NoError(t, err)
	m.Set("deleted", false)
	require.NoError(t, w.app.Save(m))
	assert.EqualValues(t, 1, count("memories_count"))
}
