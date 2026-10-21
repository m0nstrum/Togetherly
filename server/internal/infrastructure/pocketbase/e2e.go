package pocketbase

import (
	"encoding/json"
	"net/http"
	"slices"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"

	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
)

// bindE2EGuards — проверки коллекций E2E, которых нет в правилах (S8).
//
// Подделку ключей ловит клиент (подписи, MAC, сверка). Здесь — только то,
// что сервер может проверить честно: чужой список устройств не перезаписать,
// версию списка не откатить, ключ пары не выдать постороннему.
func bindE2EGuards(app core.App) {
	identity := func(e *core.RecordRequestEvent) error {
		if e.HasSuperuserAuth() || e.Auth == nil {
			return e.Next()
		}
		if e.Record.GetString("user_uid") != e.Auth.Id {
			return router.NewApiError(http.StatusForbidden, "Ключи можно публиковать только свои.", nil)
		}
		v := e.Record.GetInt("version")
		if listVersion(e.Record) != v {
			return router.NewApiError(http.StatusBadRequest, "Версия записи не совпадает с версией списка устройств.", nil)
		}
		if old := e.Record.Original(); !old.IsNew() && v <= old.GetInt("version") {
			return router.NewApiError(http.StatusConflict, "Список устройств можно только продвинуть вперёд.", nil)
		}
		return e.Next()
	}
	app.OnRecordCreateRequest("e2e_identities").BindFunc(identity)
	app.OnRecordUpdateRequest("e2e_identities").BindFunc(identity)

	app.OnRecordCreateRequest("e2e_grants").BindFunc(func(e *core.RecordRequestEvent) error {
		if e.HasSuperuserAuth() || e.Auth == nil {
			return e.Next()
		}
		g, err := e.App.FindRecordById("groups", e.Record.GetString("group_id"))
		if err != nil || !slices.Contains(pairs.Members(g), e.Record.GetString("to_uid")) {
			return router.NewApiError(http.StatusForbidden, "Ключ пары выдаётся только участнику пары.", nil)
		}
		return e.Next()
	})
}

// listVersion — версия внутри подписанного списка устройств; -1, если её нет.
func listVersion(r *core.Record) int {
	var l struct {
		Version *int `json:"version"`
	}
	if err := json.Unmarshal([]byte(r.GetString("devices")), &l); err != nil || l.Version == nil {
		return -1
	}
	return *l.Version
}
