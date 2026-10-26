package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// wish_memory — сбывшееся желание привязано к воспоминанию (docs/WISHLIST.md):
// id воспоминания шифром ключа пары. Привязывает любой из пары, как отметку.
func init() {
	m.Register(func(app core.App) error {
		col, err := app.FindCollectionByNameOrId("wishes")
		if err != nil || col.Fields.GetByName("memory") != nil {
			return nil
		}
		col.Fields.Add(&core.TextField{Name: "memory", Max: E2ESealedMax})
		return app.Save(col)
	}, nil, "1760000020_wish_memory.go")
}
