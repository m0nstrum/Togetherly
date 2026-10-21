// Package pocketbase собирает приложение PocketBase форка: миграции, JS-хуки
// апстрима, Go-роуты, рассылку в Centrifugo, почту и статику.
package pocketbase

import (
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"time"

	pb "github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/plugins/jsvm"

	"github.com/m0nstrum/togetherly/server/internal/config"
	"github.com/m0nstrum/togetherly/server/internal/domain/ice"
	"github.com/m0nstrum/togetherly/server/internal/domain/realtime"
	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/centrifugo"

	// Миграции регистрируются в init().
	_ "github.com/m0nstrum/togetherly/server/internal/migrations"
)

// New собирает приложение. Запуск — app.Start() (команды PocketBase: serve,
// superuser, migrate).
func New(cfg config.Config, log *slog.Logger) *pb.PocketBase {
	app := pb.NewWithConfig(pb.Config{DefaultDataDir: cfg.DataDir, HideStartBanner: true})
	Configure(app, cfg, log)
	return app
}

// Configure вешает на app всё, кроме создания: отдельно, чтобы тесты могли
// собрать то же самое поверх тестового приложения.
func Configure(app core.App, cfg config.Config, log *slog.Logger) {
	if _, err := os.Stat(cfg.HooksDir); err == nil {
		jsvm.MustRegister(app, jsvm.Config{
			HooksDir: cfg.HooksDir,
			// JS-миграции апстрима не нужны: схема — в Go (internal/migrations).
			MigrationsDir: filepath.Join(cfg.DataDir, "no_js_migrations"),
			HooksPoolSize: 8,
		})
	} else {
		log.Warn("JS-хуки не найдены, роуты апстрима недоступны", "dir", cfg.HooksDir)
	}

	bindRealtime(app, centrifugo.New(cfg.Centrifugo.API, cfg.Centrifugo.APIKey, cfg.Centrifugo.Timeout), cfg.Centrifugo.Timeout, log)
	bindSettings(app, cfg, log)

	turn := ice.TURN{Host: cfg.TURN.Host, Port: cfg.TURN.Port, Secret: cfg.TURN.Secret, TTL: cfg.TURN.TTL}
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.WatchRTC(e.Router, turn, time.Now)
		if _, err := os.Stat(cfg.PublicDir); err == nil {
			e.Router.GET("/{path...}", apis.Static(os.DirFS(cfg.PublicDir), false))
		}
		return e.Next()
	})
}

// bindRealtime рассылает изменения записей в Centrifugo. Отправка в фоне:
// ответ клиенту сеть не ждёт, сбой Centrifugo запись не ломает.
func bindRealtime(app core.App, pub *centrifugo.Publisher, timeout time.Duration, log *slog.Logger) {
	if !pub.Enabled() {
		log.Warn("Centrifugo не настроен: живых обновлений не будет")
		return
	}
	publish := func(ev realtime.Event, rec *core.Record) {
		r := recordAdapter{rec}
		channels := realtime.Channels(r)
		if len(channels) == 0 {
			return
		}
		payload := map[string]any{"event": ev, "collection": r.CollectionName(), "record": rec}
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), timeout)
			defer cancel()
			for _, ch := range channels {
				if err := pub.Publish(ctx, ch, payload); err != nil {
					log.Warn("centrifugo: публикация", "channel", ch, "err", err)
				}
			}
		}()
	}
	app.OnRecordAfterCreateSuccess().BindFunc(func(e *core.RecordEvent) error {
		publish(realtime.EventCreate, e.Record)
		return e.Next()
	})
	app.OnRecordAfterUpdateSuccess().BindFunc(func(e *core.RecordEvent) error {
		publish(realtime.EventUpdate, e.Record)
		return e.Next()
	})
	app.OnRecordAfterDeleteSuccess().BindFunc(func(e *core.RecordEvent) error {
		publish(realtime.EventDelete, e.Record)
		return e.Next()
	})
}

// bindSettings переносит в настройки PocketBase адрес, имя и свой SMTP
// (вместо Gmail-релея апстрима).
func bindSettings(app core.App, cfg config.Config, log *slog.Logger) {
	app.OnBootstrap().BindFunc(func(e *core.BootstrapEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		s := e.App.Settings()
		s.Meta.AppName = cfg.AppName
		if cfg.AppURL != "" {
			s.Meta.AppURL = cfg.AppURL
		}
		if cfg.SMTP.Enabled() {
			s.SMTP.Enabled = true
			s.SMTP.Host = cfg.SMTP.Host
			s.SMTP.Port = cfg.SMTP.Port
			s.SMTP.Username = cfg.SMTP.Username
			s.SMTP.Password = cfg.SMTP.Password
			s.SMTP.TLS = cfg.SMTP.TLS
			s.Meta.SenderAddress = cfg.SMTP.Sender
			s.Meta.SenderName = cfg.AppName
		}
		if err := e.App.Save(s); err != nil {
			log.Error("настройки PocketBase не сохранены", "err", err)
		}
		return nil
	})
}

// recordAdapter отдаёт запись PocketBase домену realtime.
type recordAdapter struct{ *core.Record }

func (r recordAdapter) CollectionName() string        { return r.Collection().Name }
func (r recordAdapter) RecordID() string              { return r.Id }
func (r recordAdapter) String(field string) string    { return r.GetString(field) }
func (r recordAdapter) Strings(field string) []string { return r.GetStringSlice(field) }
