package pocketbase_test

import (
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
