package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// fork_battery — заряд телефона участника пары (просьба владельца 22.10).
// Одна запись на человека в паре; уровень и «заряжается» лежат в `state`
// шифром ключа пары (lib/fork/battery/battery_share.dart) — сервер видит
// только, что запись обновилась.
func init() {
	m.Register(func(app core.App) error {
		if _, err := app.FindCollectionByNameOrId("fork_battery"); err == nil {
			return nil
		}
		col := base("fork_battery")
		col.Fields.Add(
			&core.TextField{Name: "group_id", Required: true},
			&core.TextField{Name: "user_uid", Required: true},
			&core.TextField{Name: "state", Max: E2ESealedMax},
		)
		col.AddIndex("uq_fork_battery_member", true, "group_id, user_uid", "")
		if err := app.Save(col); err != nil {
			return err
		}
		return ApplyRules(app)
	}, nil, "1760000010_fork_battery.go")
}
