package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// tzCollections — коллекции, куда приложение пишет время в UTC и рядом пояс
// автора `tz` (`±HH:MM`, lib/utils/pair_time.dart). Без поля PocketBase молча
// выбрасывал пояс, и PairTime.read принимал новую запись за старую: время
// уезжало на смещение автора (комментарии к воспоминаниям — по Гринвичу).
// У `memories` пояс есть и в `data`, колонка — для порядка и чтения fromPb.
// Поле открытое: серверу смещение ничего не говорит сверх времени записи.
var tzCollections = []string{"memories", "memory_comments", "mood_entries"}

func init() {
	m.Register(func(app core.App) error {
		for _, name := range tzCollections {
			col, err := app.FindCollectionByNameOrId(name)
			if err != nil || col.Fields.GetByName("tz") != nil {
				continue
			}
			col.Fields.Add(&core.TextField{Name: "tz", Max: 8})
			if err := app.Save(col); err != nil {
				return err
			}
		}
		return nil
	}, nil, "1760000025_pair_time_tz.go")
}
