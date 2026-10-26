package pocketbase

import (
	"context"
	"errors"

	"github.com/pocketbase/pocketbase/core"

	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
)

// bindCounters — счётчики пары для достижений и профиля ведёт сервер
// (бывший counters.pb.js): messages_count по сообщениям, drawings_count по
// каталогу холстов, memories_count по ленте без мягко удалённых. Клиент их
// только читает: его инкременты терялись в очереди и расходились с фактом.
//
// Правка — инкремент внутри транзакции пары (не ниже нуля); сбой счётчика
// не отменяет саму запись.
func bindCounters(app core.App) {
	svc := pairs.New(app)
	inc := func(e *core.RecordEvent, field string, by float64) {
		g := e.Record.GetString("group_id")
		if g == "" {
			return
		}
		_, err := svc.Write(context.Background(), pairs.WriteInput{GroupID: g, Inc: map[string]float64{field: by}})
		if err != nil && !errors.Is(err, pairs.ErrNotFound) {
			e.App.Logger().Warn("счётчик пары не сдвинулся", "field", field, "group", g, "err", err)
		}
	}
	app.OnRecordAfterCreateSuccess("chat_messages").BindFunc(func(e *core.RecordEvent) error {
		inc(e, "messages_count", 1)
		return e.Next()
	})
	app.OnRecordAfterCreateSuccess("canvas_catalogue").BindFunc(func(e *core.RecordEvent) error {
		inc(e, "drawings_count", 1)
		return e.Next()
	})
	app.OnRecordAfterDeleteSuccess("canvas_catalogue").BindFunc(func(e *core.RecordEvent) error {
		inc(e, "drawings_count", -1)
		return e.Next()
	})
	// Любая запись ленты, кем бы ни заведена: клиентом или самим сервером.
	app.OnRecordAfterCreateSuccess("memories").BindFunc(func(e *core.RecordEvent) error {
		if !e.Record.GetBool("deleted") {
			inc(e, "memories_count", 1)
		}
		return e.Next()
	})
	app.OnRecordAfterDeleteSuccess("memories").BindFunc(func(e *core.RecordEvent) error {
		if !e.Record.GetBool("deleted") {
			inc(e, "memories_count", -1)
		}
		return e.Next()
	})
	// Мягкое удаление и его отмена; прочие правки счётчик не трогают.
	app.OnRecordAfterUpdateSuccess("memories").BindFunc(func(e *core.RecordEvent) error {
		now, was := e.Record.GetBool("deleted"), e.Record.Original().GetBool("deleted")
		if now != was {
			by := 1.0
			if now {
				by = -1
			}
			inc(e, "memories_count", by)
		}
		return e.Next()
	})
}
