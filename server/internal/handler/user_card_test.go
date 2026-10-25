package handler_test

import (
	"net/http"
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"

	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
)

// Карточку партнёра видит только своя пара; почты в ней нет.
func TestUserCard(t *testing.T) {
	app := testutil.NewApp(t)
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.UserCard(e.Router)
		return e.Next()
	})
	testutil.Group(t, app, "paircardaaaaaaa", "cardalice000001", "cardbob00000001")
	testutil.Group(t, app, "paircardbbbbbbb", "cardeve00000001")
	_, alice := testutil.User(t, app, "cardalice000001", "paircardaaaaaaa")
	bob, _ := testutil.User(t, app, "cardbob00000001", "paircardaaaaaaa")
	bob.Set("banner_url", "e2e1.k.n.c")
	if err := app.Save(bob); err != nil {
		t.Fatal(err)
	}
	_, eve := testutil.User(t, app, "cardeve00000001", "paircardbbbbbbb")

	code, body := testutil.Do(t, app, http.MethodGet, "/api/user/card?uid=cardbob00000001", alice, "")
	assert.Equal(t, http.StatusOK, code, body)
	assert.Contains(t, body, `"banner_url":"e2e1.k.n.c"`)
	assert.NotContains(t, body, "example.org", "почты в карточке нет")

	code, _ = testutil.Do(t, app, http.MethodGet, "/api/user/card?uid=cardbob00000001", eve, "")
	assert.Equal(t, http.StatusForbidden, code)
	code, _ = testutil.Do(t, app, http.MethodGet, "/api/user/card?uid=cardeve00000001", eve, "")
	assert.Equal(t, http.StatusOK, code, "свою — всегда")
	code, _ = testutil.Do(t, app, http.MethodGet, "/api/user/card?uid=nobody", alice, "")
	assert.Equal(t, http.StatusNotFound, code)
	code, _ = testutil.Do(t, app, http.MethodGet, "/api/user/card?uid=cardbob00000001", "", "")
	assert.Equal(t, http.StatusUnauthorized, code)
}
