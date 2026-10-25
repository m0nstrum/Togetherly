package pocketbase

import (
	"time"

	"github.com/pocketbase/pocketbase/core"

	"github.com/m0nstrum/togetherly/server/internal/domain/memory"
)

// bindMemoryDates — даты воспоминания без будущего (domain/memory): колонка
// created_at и открытые ключи data.createdAt / data.addedAt. Очередь
// присылает запись целиком и при правке, поэтому проверка на обе операции.
func bindMemoryDates(app core.App, now func() time.Time) {
	clamp := func(e *core.RecordRequestEvent) error {
		body := requestBody(e)
		data := dataOf(e.Record)
		_, colSent := body["created_at"]
		created := time.Time{}
		if colSent {
			created = e.Record.GetDateTime("created_at").Time()
		} else if s, ok := data["createdAt"].(string); ok {
			created = memory.ParseDate(s)
		}
		added := time.Time{}
		if s, ok := data["addedAt"].(string); ok {
			added = memory.ParseDate(s)
		}
		c, a := memory.ClampFuture(created, added, now())
		changed := false
		if !c.Equal(created) {
			if colSent {
				e.Record.Set("created_at", c)
			}
			if _, ok := data["createdAt"]; ok {
				data["createdAt"] = memory.FormatDate(c)
				changed = true
			}
		}
		if !a.Equal(added) {
			data["addedAt"] = memory.FormatDate(a)
			changed = true
		}
		if changed {
			e.Record.Set("data", data)
		}
		return e.Next()
	}
	app.OnRecordCreateRequest(memoriesCol).BindFunc(clamp)
	app.OnRecordUpdateRequest(memoriesCol).BindFunc(clamp)
}
