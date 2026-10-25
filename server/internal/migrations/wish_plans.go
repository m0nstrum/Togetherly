package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// wish_plans — «Хочу с тобой» (docs/WISHLIST.md): срок желания (`due`),
// «я тоже хочу» (`also`) и общий порядок карточек (`pos`). Все три — шифр
// ключа пары: сервер не знает ни дат, ни того, кто чего хочет.
func init() {
	m.Register(func(app core.App) error {
		col, err := app.FindCollectionByNameOrId("wishes")
		if err != nil {
			return nil
		}
		changed := false
		for _, name := range []string{"due", "also", "pos"} {
			if col.Fields.GetByName(name) != nil {
				continue
			}
			col.Fields.Add(&core.TextField{Name: name, Max: E2ESealedMax})
			changed = true
		}
		if !changed {
			return nil
		}
		return app.Save(col)
	}, nil, "1760000016_wish_plans.go")
}
