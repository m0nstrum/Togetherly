// Package testutil — тестовое приложение PocketBase со схемой форка и вызовы
// его HTTP API без сети.
package testutil

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"
	"github.com/stretchr/testify/require"

	// Схема форка.
	_ "github.com/m0nstrum/togetherly/server/internal/migrations"
)

// NewApp — пустая база с применёнными миграциями. Чистится в t.Cleanup.
func NewApp(t testing.TB) *tests.TestApp {
	t.Helper()
	app, err := tests.NewTestAppWithConfig(core.BaseAppConfig{DataDir: t.TempDir(), EncryptionEnv: "pb_test_env"})
	require.NoError(t, err)
	require.NoError(t, app.RunAllMigrations())
	t.Cleanup(app.Cleanup)
	return app
}

var (
	routersMu sync.Mutex
	routers   = map[core.App]http.Handler{}
)

// Router — штатный роутер PocketBase с OnServe-хуками app, собранный один раз
// (повторная сборка дублирует маршруты).
func Router(t testing.TB, app core.App) http.Handler {
	t.Helper()
	routersMu.Lock()
	defer routersMu.Unlock()
	if h, ok := routers[app]; ok {
		return h
	}
	r, err := apis.NewRouter(app)
	require.NoError(t, err)
	var mux http.Handler
	err = app.OnServe().Trigger(&core.ServeEvent{App: app, Router: r}, func(e *core.ServeEvent) error {
		m, err := e.Router.BuildMux()
		mux = m
		return err
	})
	require.NoError(t, err)
	routers[app] = mux
	return mux
}

// Do — запрос к API: код ответа и тело.
func Do(t testing.TB, app core.App, method, url, token, body string) (int, string) {
	t.Helper()
	req := httptest.NewRequest(method, url, bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", token)
	}
	rec := httptest.NewRecorder()
	Router(t, app).ServeHTTP(rec, req)
	return rec.Code, rec.Body.String()
}

// User — пользователь с паролем password123 и группами groups (group_ids
// обычно ведёт JS-хук groups_membership, в тестах его нет).
func User(t testing.TB, app core.App, id string, groups ...string) (*core.Record, string) {
	t.Helper()
	col, err := app.FindCollectionByNameOrId("users")
	require.NoError(t, err)
	u := core.NewRecord(col)
	u.Id = id
	u.SetEmail(id + "@example.org")
	u.SetPassword("password123")
	u.Set("group_ids", groups)
	u.Set("live_group_ids", groups)
	require.NoError(t, app.Save(u))
	tok, err := u.NewAuthToken()
	require.NoError(t, err)
	return u, tok
}

// Group — пара с составом members.
func Group(t testing.TB, app core.App, id string, members ...string) *core.Record {
	t.Helper()
	col, err := app.FindCollectionByNameOrId("groups")
	require.NoError(t, err)
	g := core.NewRecord(col)
	g.Id = id
	g.Set("members", members)
	g.Set("max_members", 2)
	require.NoError(t, app.Save(g))
	return g
}
