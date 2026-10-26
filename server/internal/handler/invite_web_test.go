package handler_test

import (
	"net/http"
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
)

func TestInviteWeb(t *testing.T) {
	app := testutil.NewApp(t)
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.InviteWeb(e.Router, handler.InvitePage{
			AppName: "Tethered", Scheme: "tethered", APKURL: "https://example.org/apk",
			AndroidPackage: "io.example.app", AndroidFingerprints: []string{"AA:BB"},
		})
		return e.Next()
	})
	owner, _ := testutil.User(t, app, "webowner0000001")
	owner.Set("display_name", `Аня<script>`)
	require.NoError(t, app.Save(owner))
	col, err := app.FindCollectionByNameOrId("invite_codes")
	require.NoError(t, err)
	c := core.NewRecord(col)
	c.Set("code", "HQ792S")
	c.Set("owner_uid", "webowner0000001")
	require.NoError(t, app.Save(c))

	code, body := testutil.Do(t, app, http.MethodGet, "/invite/hq792s", "", "")
	require.Equal(t, http.StatusOK, code)
	assert.Contains(t, body, "Аняscript зовёт вас в Tethered", "имя без разметки")
	assert.NotContains(t, body, "<script>alert")
	assert.Contains(t, body, `href="tethered://invite/HQ792S"`)
	assert.Contains(t, body, `"tethered://invite/HQ792S"+(location.hash||"")`, "секрет из фрагмента доезжает до приложения")
	assert.Contains(t, body, "https://example.org/apk")
	assert.NotContains(t, body, "Google Play", "пустой магазин не показывается")

	code, body = testutil.Do(t, app, http.MethodGet, "/invite/", "", "")
	assert.Equal(t, http.StatusOK, code)
	assert.Contains(t, body, "В ссылке нет кода")
	code, body = testutil.Do(t, app, http.MethodGet, "/invite", "", "")
	assert.Contains(t, body, "В ссылке нет кода")
	code, _ = testutil.Do(t, app, http.MethodGet, "/invite/%3C%3E", "", "")
	assert.Equal(t, http.StatusBadRequest, code)
	code, body = testutil.Do(t, app, http.MethodGet, "/invite/NOPE12", "", "")
	assert.Equal(t, http.StatusOK, code)
	assert.Contains(t, body, "Тебя приглашают в Tethered")

	code, body = testutil.Do(t, app, http.MethodGet, "/.well-known/assetlinks.json", "", "")
	assert.Equal(t, http.StatusOK, code)
	assert.Contains(t, body, `"package_name":"io.example.app"`)
	code, _ = testutil.Do(t, app, http.MethodGet, "/.well-known/apple-app-site-association", "", "")
	assert.Equal(t, http.StatusNotFound, code, "без appID не раздаём")
}
