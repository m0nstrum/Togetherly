package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// wish_place — точка «Места» на карте у желания (docs/WISHLIST.md): шифр
// ключа пары. «Вы оба рядом» считает телефон — серверу координаты не нужны.
// Карту для выбора точки телефон берёт тайлами через наш /api/fork/map: по
// ним сервер видит район, который смотрели, но не саму точку.
func init() {
	m.Register(func(app core.App) error {
		col, err := app.FindCollectionByNameOrId("wishes")
		if err != nil || col.Fields.GetByName("place") != nil {
			return nil
		}
		col.Fields.Add(&core.TextField{Name: "place", Max: E2ESealedMax})
		return app.Save(col)
	}, nil, "1760000019_wish_place.go")
}
