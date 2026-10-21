package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// push_tokens — токены FCM устройств (PLAN S12, usecase/wake). Токен
// принадлежит одному человеку: тот же телефон под другим входом
// перехватывает его.
func init() {
	m.Register(func(app core.App) error {
		if _, err := app.FindCollectionByNameOrId("push_tokens"); err == nil {
			return nil
		}
		col := base("push_tokens")
		col.Fields.Add(
			&core.TextField{Name: "user_uid", Required: true},
			&core.TextField{Name: "token", Required: true, Max: 4096},
		)
		col.AddIndex("uq_push_tokens_token", true, "token", "")
		col.AddIndex("idx_push_tokens_user", false, "user_uid", "")
		if err := app.Save(col); err != nil {
			return err
		}
		return ApplyRules(app)
	}, nil, "1760000009_push_tokens.go")
}
