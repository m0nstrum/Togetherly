package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// e2e_links — привязка нового устройства к аккаунту по QR (docs/E2E.md
// §5.3). Новое устройство кладёт сюда свои публичные ключи и MAC от секрета
// из QR, старое — ключи аккаунта и пар шифром (`payload`). Секрета сервер не
// видит: подменить ключи устройства или подсунуть свой ключ аккаунта не
// может. Запись живёт минуты (usecase/e2eretention).
func init() {
	m.Register(func(app core.App) error {
		if _, err := app.FindCollectionByNameOrId("e2e_links"); err == nil {
			return nil
		}
		col := base("e2e_links")
		col.Fields.Add(
			&core.TextField{Name: "user_uid", Required: true},
			&core.JSONField{Name: "device", MaxSize: 4 << 10},
			&core.TextField{Name: "mac", Required: true, Max: 128},
			&core.TextField{Name: "payload", Max: 256 << 10},
		)
		col.AddIndex("idx_e2e_links_user", false, "user_uid", "")
		if err := app.Save(col); err != nil {
			return err
		}
		return ApplyRules(app)
	}, nil, "1760000015_e2e_links.go")
}
