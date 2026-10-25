package pocketbase_test

import (
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Запись `users`: чужую не правят, экономику клиент не пишет (пустым —
// можно), имя и аватар доезжают до пары, а шифр личным ключом — нет.
func TestUsersGuard(t *testing.T) {
	w := newWorld(t)
	path := "/api/collections/users/records/" + alice
	patch := func(tok, body string) int {
		code, _ := w.do(t, http.MethodPatch, path, tok, body)
		return code
	}
	assert.NotEqual(t, http.StatusOK, patch(w.bTok, `{"display_name":"x"}`), "чужая запись")
	for _, body := range []string{`{"coins":100}`, `{"plus":true}`, `{"owned_themes":["x"]}`, `{"ad_views_today":0}`, `{"ad_grants":{}}`} {
		assert.Equal(t, http.StatusForbidden, patch(w.aTok, body), body)
	}
	code, body := w.do(t, http.MethodPatch, path, w.aTok, `{"coins":0,"owned_themes":[],"plus":false,"gender":"f"}`)
	assert.Equal(t, http.StatusOK, code, body)

	require.Equal(t, http.StatusOK, patch(w.aTok, `{"display_name":"Аня","avatar_url":"https://x/a.png"}`))
	g, err := w.app.FindRecordById("groups", pairA)
	require.NoError(t, err)
	names, avatars := map[string]any{}, map[string]any{}
	require.NoError(t, g.UnmarshalJSONField("member_names", &names))
	require.NoError(t, g.UnmarshalJSONField("member_avatars", &avatars))
	assert.Equal(t, "Аня", names[alice])
	assert.Equal(t, "https://x/a.png", avatars[alice])

	require.Equal(t, http.StatusOK, patch(w.aTok, `{"display_name":"e2e1.k.n.c"}`))
	g, err = w.app.FindRecordById("groups", pairA)
	require.NoError(t, err)
	require.NoError(t, g.UnmarshalJSONField("member_names", &names))
	assert.Equal(t, "Аня", names[alice], "шифр личным ключом в пару не идёт")
}

func TestUsersRegistrationGuard(t *testing.T) {
	w := newWorld(t)
	require.NoError(t, os.WriteFile(filepath.Join(w.app.DataDir(), ".banned_emails"), []byte("\nBad@Example.org\n"), 0o600))
	reg := func(email, extra string) int {
		code, _ := w.do(t, http.MethodPost, "/api/collections/users/records", "",
			`{"email":"`+email+`","password":"password123","passwordConfirm":"password123"`+extra+`}`)
		return code
	}
	assert.Equal(t, http.StatusForbidden, reg("bad@example.org", ""))
	assert.Equal(t, http.StatusForbidden, reg("new1@example.org", `,"coins":500`))
	assert.Equal(t, http.StatusOK, reg("new2@example.org", `,"coins":0`))
}
