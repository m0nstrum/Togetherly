// Package pocketbase собирает приложение PocketBase форка: миграции, JS-хуки
// апстрима, Go-роуты, рассылку в Centrifugo, почту и статику.
package pocketbase

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
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
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/backup"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/centrifugo"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/safefetch"
	"github.com/m0nstrum/togetherly/server/internal/usecase/account"
	"github.com/m0nstrum/togetherly/server/internal/usecase/meta"
	"github.com/m0nstrum/togetherly/server/internal/usecase/movies"
	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
	"github.com/m0nstrum/togetherly/server/internal/usecase/records"

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

	pub := centrifugo.New(cfg.Centrifugo.API, cfg.Centrifugo.APIKey, cfg.Centrifugo.Timeout)
	bindRealtime(app, pub, cfg.Centrifugo.Timeout, log)
	bindCapsules(app, time.Now, log)
	bindGuards(app)
	bindAllFree(app)
	acc := bindAccount(app, log)
	gateway := meta.New(safefetch.New(safefetch.Options{}), 64<<20, time.Now)
	// Записи Викиданных тяжёлые: сотни килобайт на фильм.
	films := movies.New(safefetch.New(safefetch.Options{Timeout: 15 * time.Second, MaxBytes: 8 << 20}),
		&handler.IPLimiter{Max: 60, Window: 10 * time.Minute}, movies.Options{PoiskkinoKey: cfg.PoiskkinoKey}, time.Now)
	bindSettings(app, cfg, log)
	if cfg.Backup.AgeRecipients != "" {
		// Ключи уже проверены config.Validate.
		if err := backup.Bind(app, backup.Options{Dir: cfg.Backup.Dir, Recipients: cfg.Backup.AgeRecipients, MaxKeep: cfg.Backup.MaxKeep}, log); err != nil {
			log.Error("шифрование бэкапов", "err", err)
		}
	} else if cfg.Backup.Cron != "" {
		log.Warn("бэкапы без шифрования: задайте TETHERED_BACKUP__AGE_RECIPIENTS")
	}

	bindCompat(app, cfg.CompatAddr, pub, log)

	turn := ice.TURN{Host: cfg.TURN.Host, Port: cfg.TURN.Port, Secret: cfg.TURN.Secret, TTL: cfg.TURN.TTL}
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.WatchRTC(e.Router, turn, time.Now)
		handler.ScheduleDelete(e.Router, acc, time.Now, log)
		handler.Meta(e.Router, gateway, &handler.IPLimiter{Max: 120, Window: time.Minute}, log)
		handler.Movies(e.Router, films, log)
		if _, err := os.Stat(cfg.PublicDir); err == nil {
			e.Router.GET("/{path...}", apis.Static(os.DirFS(cfg.PublicDir), false))
		}
		return e.Next()
	})
}

// bindAccount — отложенное удаление аккаунтов: вход паролем снимает пометку,
// ночная задача стирает тех, чей срок наступил.
func bindAccount(app core.App, log *slog.Logger) *account.Service {
	svc := account.New(app)
	app.OnRecordAuthWithPasswordRequest("users").BindFunc(func(e *core.RecordAuthWithPasswordRequestEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		if e.Record != nil {
			if err := svc.Cancel(e.Record); err != nil {
				log.Error("отмена удаления аккаунта", "err", err)
			}
		}
		return nil
	})
	app.Cron().MustAdd("accounts_purge", "30 3 * * *", func() {
		n, err := svc.PurgeDue(context.Background(), time.Now())
		if err != nil {
			log.Error("удаление аккаунтов", "err", err)
		}
		if n > 0 {
			log.Info("аккаунты стёрты по сроку", "count", n)
		}
	})
	return svc
}

// bindCompat поднимает на петле внутренний API для JS-хуков апстрима
// (handler.Compat). Адрес зашит в хуках — 127.0.0.1:8120.
func bindCompat(app core.App, addr string, pub *centrifugo.Publisher, log *slog.Logger) {
	if addr == "" {
		return
	}
	srv := &http.Server{Addr: addr, Handler: handler.Compat(pairs.New(app), records.New(app), pub, log), ReadHeaderTimeout: 5 * time.Second}
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		go func() {
			if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
				log.Error("внутренний API для хуков", "addr", addr, "err", err)
			}
		}()
		return e.Next()
	})
	app.OnTerminate().BindFunc(func(e *core.TerminateEvent) error {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(ctx)
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
		payload := map[string]any{"event": ev, "collection": r.CollectionName(), "record": sanitizeForBroadcast(rec, time.Now())}
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
		applySettings(s, cfg)
		if err := e.App.Save(s); err != nil {
			log.Error("настройки PocketBase не сохранены", "err", err)
		}
		return nil
	})
}

// applySettings переносит конфиг в настройки PocketBase.
func applySettings(s *core.Settings, cfg config.Config) {
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
	s.RateLimits.Enabled = cfg.RateLimits
	s.RateLimits.Rules = rateLimitRules
	if cfg.TrustedProxyHeader != "" {
		s.TrustedProxy.Headers = []string{cfg.TrustedProxyHeader}
		// Caddy затирает присланный клиентом заголовок своим: адрес
		// клиента — правый.
		s.TrustedProxy.UseLeftmostIP = false
	}
	s.Backups.Cron = cfg.Backup.Cron
	s.Backups.CronMaxKeep = cfg.Backup.MaxKeep
}

// rateLimitRules — лимиты на IP (решение 3: вход только по паролю, значит
// нужна защита от перебора). Общих лимитов на запись нет: рисование и чат
// создают записи пачками.
var rateLimitRules = []core.RateLimitRule{
	{Label: "*:authWithPassword", MaxRequests: 10, Duration: 60},
	{Label: "*:requestPasswordReset", MaxRequests: 3, Duration: 300},
	{Label: "*:confirmPasswordReset", MaxRequests: 10, Duration: 300},
	{Label: "*:requestVerification", MaxRequests: 3, Duration: 300},
	{Label: "*:requestEmailChange", MaxRequests: 3, Duration: 300},
	{Label: "users:create", Audience: "@guest", MaxRequests: 10, Duration: 3600},
}

// recordAdapter отдаёт запись PocketBase домену realtime.
type recordAdapter struct{ *core.Record }

func (r recordAdapter) CollectionName() string        { return r.Collection().Name }
func (r recordAdapter) RecordID() string              { return r.Id }
func (r recordAdapter) String(field string) string    { return r.GetString(field) }
func (r recordAdapter) Strings(field string) []string { return r.GetStringSlice(field) }
