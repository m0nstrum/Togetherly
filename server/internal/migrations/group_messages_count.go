package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// group_messages_count — счётчик сообщений пары для достижений. Клиент читал
// `messages_count`, а поля в схеме не было: инкремент молча пропадал, и
// достижения за переписку не открывались. Поле заводим и заполняем по факту.
func init() {
	m.Register(func(app core.App) error {
		col, err := app.FindCollectionByNameOrId("groups")
		if err != nil || col.Fields.GetByName("messages_count") != nil {
			return nil
		}
		col.Fields.Add(&core.NumberField{Name: "messages_count", OnlyInt: true})
		if err := app.Save(col); err != nil {
			return err
		}
		if _, err := app.FindCollectionByNameOrId("chat_messages"); err != nil {
			return nil
		}
		_, err = app.DB().NewQuery(`UPDATE groups SET messages_count =
			(SELECT COUNT(*) FROM chat_messages WHERE chat_messages.group_id = groups.id)`).Execute()
		return err
	}, nil, "1760000021_group_messages_count.go")
}
