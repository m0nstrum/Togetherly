package pocketbase

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log/slog"
	"strings"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"

	"github.com/m0nstrum/togetherly/server/internal/domain/realtime"
	wakedom "github.com/m0nstrum/togetherly/server/internal/domain/wake"
	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/fcm"
	"github.com/m0nstrum/togetherly/server/internal/usecase/wake"
)

const pushTokensCol = "push_tokens"

// pushTokens — токены FCM в коллекции push_tokens.
type pushTokens struct{ app core.App }

func (t pushTokens) Tokens(_ context.Context, uid string) ([]string, error) {
	recs, err := t.app.FindRecordsByFilter(pushTokensCol, "user_uid = {:u}", "", 20, 0, dbx.Params{"u": uid})
	if err != nil {
		return nil, err
	}
	out := make([]string, 0, len(recs))
	for _, r := range recs {
		out = append(out, r.GetString("token"))
	}
	return out, nil
}

func (t pushTokens) Forget(_ context.Context, token string) error {
	r, err := t.app.FindFirstRecordByData(pushTokensCol, "token", token)
	if err != nil {
		return nil // уже нет
	}
	return t.app.Delete(r)
}

// Register never transfers an existing token between accounts. A real device
// switching accounts obtains a fresh token from FCM instead.
func (t pushTokens) Register(_ context.Context, uid, token string) error {
	return t.app.RunInTransaction(func(tx core.App) error {
		r, err := tx.FindFirstRecordByData(pushTokensCol, "token", token)
		if err == nil {
			if r.GetString("user_uid") != uid {
				return wake.ErrTokenOwned
			}
			return nil
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		col, err := tx.FindCollectionByNameOrId(pushTokensCol)
		if err != nil {
			return err
		}
		r = core.NewRecord(col)
		r.Set("token", token)
		r.Set("user_uid", uid)
		return tx.Save(r)
	})
}

// Unregister — забыть токен при выходе; чужой не трогаем.
func (t pushTokens) Unregister(_ context.Context, uid, token string) error {
	r, err := t.app.FindFirstRecordByData(pushTokensCol, "token", token)
	if err != nil || r.GetString("user_uid") != uid {
		return nil
	}
	return t.app.Delete(r)
}

// wakeRecord отдаёт запись домену wake.
type wakeRecord struct{ *core.Record }

func (r wakeRecord) CollectionName() string     { return r.Collection().Name }
func (r wakeRecord) String(field string) string { return r.GetString(field) }

// bindWake — будильник FCM (PLAN S12). Без ключа Firebase — выключен, и
// [pub] возвращается как есть.
func bindWake(app core.App, opt fcm.Options, pub handler.Publisher, timeout time.Duration, log *slog.Logger) handler.Publisher {
	sender, err := fcm.New(opt)
	if err != nil {
		log.Error("FCM: ключ не годится, будильник выключен", "err", err)
	}
	tokens := pushTokens{app}
	var send wake.Sender
	if sender != nil {
		send = sender
	}
	svc := wake.New(send, tokens, wake.Options{TTL: opt.TTL}, time.Now)

	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.Wake(e.Router, tokens, svc, log)
		return e.Next()
	})
	if !svc.Enabled() {
		log.Info("FCM не настроен: телефоны будит только сокет фонового сервиса")
		return pub
	}

	fire := func(uids []string, channel string, data any) {
		if len(uids) == 0 {
			return
		}
		// Снимок сейчас: запись после хука может поменяться.
		raw, err := json.Marshal(data)
		if err != nil {
			log.Warn("FCM: событие", "err", err)
			return
		}
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), timeout)
			defer cancel()
			for _, uid := range uids {
				if err := svc.Wake(ctx, uid, channel, json.RawMessage(raw)); err != nil {
					log.Warn("FCM: не разбудили", "err", err)
				}
			}
		}()
	}
	onRecord := func(ev realtime.Event, rec *core.Record) {
		ev, ok := heldEvent(ev, rec)
		if !ok {
			return
		}
		r := wakeRecord{rec}
		var members []string
		if wakedom.NeedsMembers(string(ev), r) {
			g, err := app.FindRecordById("groups", rec.GetString("group_id"))
			if err != nil {
				return
			}
			members = g.GetStringSlice("members")
		}
		uids := wakedom.Targets(string(ev), r, members)
		channels := realtime.Channels(recordAdapter{rec})
		if len(uids) == 0 || len(channels) == 0 {
			return
		}
		fire(uids, channels[0], broadcastPayload(ev, rec))
	}
	app.OnRecordAfterCreateSuccess().BindFunc(func(e *core.RecordEvent) error {
		onRecord(realtime.EventCreate, e.Record)
		return e.Next()
	})
	app.OnRecordAfterUpdateSuccess().BindFunc(func(e *core.RecordEvent) error {
		onRecord(realtime.EventUpdate, e.Record)
		return e.Next()
	})
	return wakingPublisher{pub: pub, fire: fire}
}

// wakingPublisher — публикатор для уведомлений хуков (/internal/notify):
// кроме канала `user:<uid>` будит и телефоны этого человека.
type wakingPublisher struct {
	pub  handler.Publisher
	fire func(uids []string, channel string, data any)
}

func (w wakingPublisher) Publish(ctx context.Context, channel string, data any) error {
	err := w.pub.Publish(ctx, channel, data)
	if uid, ok := strings.CutPrefix(channel, "user:"); ok && uid != "" {
		w.fire([]string{uid}, channel, data)
	}
	// Centrifugo мог быть недоступен, а пуш ушёл: ошибка всё равно видна.
	return err
}
