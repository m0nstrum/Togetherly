package pocketbase

import (
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// bindCommentsCount — счётчик комментариев под воспоминанием ведёт сервер
// (бывший comments_count.pb.js). Клиент прибавлял единицу оптимистично и ещё
// раз операцией очереди, которая умеет повторять отправку, — бейдж расходился
// с фактом в обе стороны. Считаем по факту записи.
//
// Счётчик лежит в json-поле `data` воспоминания (`commentsCount` — открытый
// ключ и при шифровании), пишем только при расхождении: иначе каждый
// комментарий рождал бы лишнее realtime-событие на всю пару.
func bindCommentsCount(app core.App) {
	recount := func(e *core.RecordEvent) error {
		recountComments(e.App, e.Record.GetString("memory_id"))
		return e.Next()
	}
	app.OnRecordAfterCreateSuccess("memory_comments").BindFunc(recount)
	app.OnRecordAfterUpdateSuccess("memory_comments").BindFunc(recount)
	app.OnRecordAfterDeleteSuccess("memory_comments").BindFunc(recount)
}

func recountComments(app core.App, memoryID string) {
	if memoryID == "" {
		return
	}
	memory, err := app.FindRecordById("memories", memoryID)
	if err != nil {
		return // воспоминание удалили — считать нечего
	}
	n, err := app.CountRecords("memory_comments", dbx.HashExp{"memory_id": memoryID, "deleted": false})
	if err != nil {
		app.Logger().Warn("счётчик комментариев: не посчитал", "memory", memoryID, "err", err)
		return
	}
	data := map[string]any{}
	_ = memory.UnmarshalJSONField("data", &data)
	if cur, ok := data["commentsCount"].(float64); (ok && int64(cur) == n) || (!ok && n == 0) {
		return
	}
	data["commentsCount"] = n
	memory.Set("data", data)
	if err := app.Save(memory); err != nil {
		app.Logger().Warn("счётчик комментариев: не сохранил", "memory", memoryID, "err", err)
	}
}
