package pocketbase

import "github.com/pocketbase/pocketbase/core"

// bindAllFree — решение 1 на сервере: Плюс открыт у всех. Хуки апстрима
// проверяют `users.plus` сами (зов в ленту, карточка, сундук), поэтому
// флаг ставится каждому при создании; старым — миграция all_free. Сторож
// апстрима (users_guard.pb.js) не даёт клиенту менять поле — и не надо.
func bindAllFree(app core.App) {
	app.OnRecordCreate("users").BindFunc(func(e *core.RecordEvent) error {
		e.Record.Set("plus", true)
		return e.Next()
	})
}
