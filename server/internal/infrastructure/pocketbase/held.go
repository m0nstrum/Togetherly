package pocketbase

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"

	"github.com/m0nstrum/togetherly/server/internal/domain/realtime"
)

const chatCol = "chat_messages"

// heldRelease — как часто выпускать отложенные сообщения: «отправить утром»
// приходит в пределах этого шага от срока.
const heldRelease = 15 * time.Second

// bindHeld — отложенные сообщения (`deliver_at`, «отправить утром»). До срока
// сообщение видит только автор: флаг `held` ставит сервер по сроку, правило
// чтения прячет его от партнёра, рассылка и будильник молчат. В срок воркер
// снимает флаг и ставит время сообщения на срок — партнёр получает его как
// новое.
func bindHeld(app core.App, now func() time.Time, log *slog.Logger) {
	hold := func(e *core.RecordRequestEvent) error {
		e.Record.Set("held", e.Record.GetInt("deliver_at") > int(now().UnixMilli()))
		return e.Next()
	}
	app.OnRecordCreateRequest(chatCol).BindFunc(hold)
	app.OnRecordUpdateRequest(chatCol).BindFunc(func(e *core.RecordRequestEvent) error {
		// Выпустить раньше («отправить сейчас») может только автор, сдвинув
		// срок; совместные поля партнёра флаг не трогают.
		if e.Record.GetInt("deliver_at") == e.Record.Original().GetInt("deliver_at") {
			e.Record.Set("held", e.Record.Original().GetBool("held"))
			return e.Next()
		}
		return hold(e)
	})
	// Выпущенное автором раньше срока встаёт в переписку временем выпуска.
	app.OnRecordUpdate(chatCol).BindFunc(func(e *core.RecordEvent) error {
		if e.Record.Original().GetBool("held") && !e.Record.GetBool("held") {
			if at := e.Record.GetInt("deliver_at"); at > 0 {
				e.Record.Set("ts", at)
			}
		}
		return e.Next()
	})

	// Воркер живёт, пока сервер обслуживает запросы.
	stop := make(chan struct{})
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		go func() {
			t := time.NewTicker(heldRelease)
			defer t.Stop()
			for {
				select {
				case <-stop:
					return
				case <-t.C:
					if err := releaseDue(app, now()); err != nil {
						log.Warn("отложенные сообщения: выпуск", "err", err)
					}
				}
			}
		}()
		return e.Next()
	})
	app.OnTerminate().BindFunc(func(e *core.TerminateEvent) error {
		select {
		case <-stop:
		default:
			close(stop)
		}
		return e.Next()
	})
}

// releaseDue выпускает сообщения, срок которых наступил. Удалённое автором
// до срока остаётся придержанным: партнёр не должен увидеть даже надгробие.
// Запись, которая не сохранилась, не задерживает остальные.
func releaseDue(app core.App, now time.Time) error {
	recs, err := app.FindRecordsByFilter(chatCol, "held = true && deleted != true && deliver_at <= {:now}", "deliver_at", 200, 0,
		dbx.Params{"now": now.UnixMilli()})
	if err != nil {
		return err
	}
	var errs []error
	for _, r := range recs {
		r.Set("held", false)
		if err := app.SaveWithContext(context.Background(), r); err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", r.Id, err))
		}
	}
	return errors.Join(errs...)
}

// heldEvent — как изменение записи видят партнёр и его телефон. Придержанное
// сообщение не рассылается; выпущенное приходит как новое.
func heldEvent(ev realtime.Event, rec *core.Record) (realtime.Event, bool) {
	if rec.Collection().Name != chatCol {
		return ev, true
	}
	switch {
	// Придержанное партнёру не рассылалось — и удаление тоже: событие несёт
	// запись целиком, ключ пары у партнёра есть.
	case rec.GetBool("held"):
		return ev, false
	case ev == realtime.EventDelete:
		return ev, true
	case ev == realtime.EventUpdate && rec.Original().GetBool("held"):
		return realtime.EventCreate, true
	}
	return ev, true
}
