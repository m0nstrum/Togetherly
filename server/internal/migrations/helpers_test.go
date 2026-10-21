package migrations_test

import (
	"net/http"
	"net/http/httptest"
	"sync"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
)

var (
	routersMu sync.Mutex
	routers   = map[core.App]http.Handler{}
)

// apisRouter — штатный роутер PocketBase с OnServe-хуками приложения, как в
// tests.ApiScenario. Собирается один раз на приложение: повторная сборка
// дублирует маршруты.
func apisRouter(app core.App) (http.Handler, error) {
	routersMu.Lock()
	defer routersMu.Unlock()
	if h, ok := routers[app]; ok {
		return h, nil
	}
	h, err := buildRouter(app)
	if err == nil {
		routers[app] = h
	}
	return h, err
}

func buildRouter(app core.App) (http.Handler, error) {
	r, err := apis.NewRouter(app)
	if err != nil {
		return nil, err
	}
	var mux http.Handler
	ev := &core.ServeEvent{App: app, Router: r}
	err = app.OnServe().Trigger(ev, func(e *core.ServeEvent) error {
		m, err := e.Router.BuildMux()
		mux = m
		return err
	})
	return mux, err
}

func newRecorder() *httptest.ResponseRecorder { return httptest.NewRecorder() }
