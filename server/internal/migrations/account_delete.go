package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

func init() {
	m.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}
		// Когда стереть аккаунт (usecase/account). Пусто — не помечен.
		if users.Fields.GetByName("delete_after") == nil {
			users.Fields.Add(&core.DateField{Name: "delete_after", Hidden: true})
		}
		return app.Save(users)
	}, nil, "1760000001_account_delete_after.go")
}
