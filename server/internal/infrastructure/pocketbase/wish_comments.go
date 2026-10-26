package pocketbase

import (
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// bindWishComments: удалённое желание уносит комментарии к нему. Удалить
// чужой комментарий автор желания не может (правило коллекции), поэтому
// уборка — на сервере.
func bindWishComments(app core.App) {
	app.OnRecordAfterDeleteSuccess("wishes").BindFunc(func(e *core.RecordEvent) error {
		recs, err := e.App.FindAllRecords("wish_comments", dbx.HashExp{"wish_id": e.Record.Id})
		if err != nil {
			e.App.Logger().Warn("комментарии желания не найдены", "wish", e.Record.Id, "err", err)
			return e.Next()
		}
		for _, r := range recs {
			if err := e.App.Delete(r); err != nil {
				e.App.Logger().Warn("комментарий желания не удалён", "id", r.Id, "err", err)
			}
		}
		return e.Next()
	})
}
