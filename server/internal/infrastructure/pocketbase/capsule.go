package pocketbase

import (
	"encoding/json"
	"log/slog"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"

	"github.com/m0nstrum/togetherly/server/internal/domain/capsule"
)

const memoriesCol = "memories"

// bindCapsules — капсулы времени на сервере (domain/capsule, S6).
func bindCapsules(app core.App, now func() time.Time, log *slog.Logger) {
	// Ответы API и встроенный realtime PocketBase.
	app.OnRecordEnrich(memoriesCol).BindFunc(func(e *core.RecordEnrichEvent) error {
		if data := dataOf(e.Record); capsule.Sealed(data, now()) {
			e.Record.Set("data", capsule.Redact(data))
		}
		return e.Next()
	})

	// Правка через API: содержимое запечатанной капсулы меняет только сервер.
	app.OnRecordUpdateRequest(memoriesCol).BindFunc(func(e *core.RecordRequestEvent) error {
		if e.HasSuperuserAuth() {
			return e.Next()
		}
		orig := e.Record.Original()
		stored := dataOf(orig)
		if !capsule.Sealed(stored, now()) {
			return e.Next()
		}
		byAuthor := e.Auth != nil && e.Auth.Id == orig.GetString("author_uid")
		e.Record.Set("data", capsule.MergeUpdate(stored, dataOf(e.Record), byAuthor))
		return e.Next()
	})

	// Открытие: клиенты синхронизируются по `updated`, поэтому в срок запись
	// надо тронуть — тогда они перечитают её целиком и получат событие.
	app.Cron().MustAdd("capsules_open", "*/5 * * * *", func() {
		if err := openDue(app, now()); err != nil {
			log.Error("капсулы: открытие", "err", err)
		}
	})
}

// openDue трогает капсулы, срок которых наступил.
func openDue(app core.App, now time.Time) error {
	recs, err := app.FindRecordsByFilter(memoriesCol,
		"data.sealed = true && data.openAt <= {:now}", "", 500, 0,
		dbx.Params{"now": now.UTC().Format("2006-01-02T15:04:05.000Z")})
	if err != nil {
		return err
	}
	for _, r := range recs {
		data := dataOf(r)
		if data[capsule.OpenedMark] == true || capsule.Sealed(data, now) {
			continue
		}
		data[capsule.OpenedMark] = true
		r.Set("data", data)
		if err := app.Save(r); err != nil {
			return err
		}
	}
	return nil
}

// sanitizeForBroadcast — копия записи для рассылки в Centrifugo: запечатанная
// капсула уходит без содержимого.
func sanitizeForBroadcast(rec *core.Record, now time.Time) *core.Record {
	if rec.Collection().Name != memoriesCol {
		return rec
	}
	data := dataOf(rec)
	if !capsule.Sealed(data, now) {
		return rec
	}
	c := rec.Clone()
	c.Set("data", capsule.Redact(data))
	return c
}

func dataOf(r *core.Record) map[string]any {
	if r == nil {
		return nil
	}
	var raw []byte
	switch v := r.Get("data").(type) {
	case []byte:
		raw = v
	case string:
		raw = []byte(v)
	default:
		raw, _ = json.Marshal(v)
	}
	m := map[string]any{}
	if err := json.Unmarshal(raw, &m); err != nil || m == nil {
		return map[string]any{}
	}
	return m
}
