package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// wish_reminders — напоминания вишлиста (docs/WISHLIST.md):
//   - wishes.skip — неделя, на которую пара попросила другое «желание
//     недели» (общее поле: выбор недели одинаков у обоих);
//   - wish_reservations.until — срок «Дарю», виден только дарящему.
//
// Оба — шифр ключа пары.
func init() {
	m.Register(func(app core.App) error {
		for name, field := range map[string]string{"wishes": "skip", "wish_reservations": "until"} {
			col, err := app.FindCollectionByNameOrId(name)
			if err != nil || col.Fields.GetByName(field) != nil {
				continue
			}
			col.Fields.Add(&core.TextField{Name: field, Max: E2ESealedMax})
			if err := app.Save(col); err != nil {
				return err
			}
		}
		return nil
	}, nil, "1760000018_wish_reminders.go")
}
