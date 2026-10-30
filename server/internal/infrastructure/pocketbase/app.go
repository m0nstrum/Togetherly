// Package pocketbase собирает приложение PocketBase форка: миграции, JS-хуки
// апстрима, Go-роуты, рассылку в Centrifugo, почту и статику.
package pocketbase

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"net/url"
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
	"github.com/m0nstrum/togetherly/server/internal/domain/watchproxy"
	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/backup"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/centrifugo"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/fcm"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/metrics"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/safefetch"
	wproxy "github.com/m0nstrum/togetherly/server/internal/infrastructure/watchproxy"
	"github.com/m0nstrum/togetherly/server/internal/usecase/account"
	"github.com/m0nstrum/togetherly/server/internal/usecase/e2eretention"
	"github.com/m0nstrum/togetherly/server/internal/usecase/groupops"
	"github.com/m0nstrum/togetherly/server/internal/usecase/meta"
	"github.com/m0nstrum/togetherly/server/internal/usecase/movies"
	"github.com/m0nstrum/togetherly/server/internal/usecase/music"
	pushes "github.com/m0nstrum/togetherly/server/internal/usecase/notify"
	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
	"github.com/m0nstrum/togetherly/server/internal/usecase/pethome"
	"github.com/m0nstrum/togetherly/server/internal/usecase/records"
	"github.com/m0nstrum/togetherly/server/internal/usecase/ring"
	"github.com/m0nstrum/togetherly/server/internal/usecase/stats"
	"github.com/m0nstrum/togetherly/server/internal/usecase/widgetanim"

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

	mx := metrics.New()
	mx.Bind(app)
	bindMetrics(app, cfg.MetricsAddr, mx, log)

	pub := centrifugo.New(cfg.Centrifugo.API, cfg.Centrifugo.APIKey, cfg.Centrifugo.Timeout)
	bindRealtime(app, pub, mx.Published, cfg.Centrifugo.Timeout, log)
	bindCapsules(app, time.Now, log)
	bindHeld(app, time.Now, log)
	bindMemoryDates(app, time.Now)
	bindGuards(app)
	bindE2EGuards(app)
	app.Cron().MustAdd("e2e_retention", "17 * * * *", func() {
		if err := e2eretention.Sweep(app, time.Now()); err != nil {
			log.Error("E2E retention", "err", err)
		}
	})
	bindAllFree(app)
	handler.EmailCaseLogin(app)
	acc := bindAccount(app, log)
	gateway := meta.New(safefetch.New(safefetch.Options{}), 64<<20, time.Now)
	maps := meta.New(safefetch.New(safefetch.Options{MaxBytes: 8 << 20}), 64<<20, time.Now)
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

	notify := bindWake(app, fcm.Options{
		Credentials: cfg.FCM.Credentials, CredentialsFile: cfg.FCM.CredentialsFile,
		TTL: cfg.FCM.TTL, Timeout: cfg.FCM.Timeout, Endpoint: cfg.FCM.Endpoint,
	}, pub, cfg.FCM.Timeout, log)
	bindCompat(app, cfg.CompatAddr, notify, log)
	proxyInfo := bindWatchProxy(app, cfg, mx, log)

	turn := ice.TURN{Host: cfg.TURN.Host, Port: cfg.TURN.Port, Secret: cfg.TURN.Secret, TTL: cfg.TURN.TTL}
	groups := groupops.New(app, time.Now)
	anim := widgetanim.New(app)
	// Добор раскадровок, до которых клиент не дозвался.
	app.Cron().MustAdd("widgetAnimSweep", "*/10 * * * *", func() { anim.Sweep(context.Background()) })
	ringer := ring.New(ringPairs{app}, ringPublisher{notify}, ring.Options{}, time.Now)
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.GET("/api/fork/realtime-key", func(event *core.RequestEvent) error {
			if !pub.Enabled() {
				return event.JSON(http.StatusServiceUnavailable, map[string]any{"error": "realtime_unavailable"})
			}
			return event.JSON(http.StatusOK, map[string]any{"v": 1, "alg": "Ed25519", "key": pub.PublicKey(), "time": time.Now().UnixMilli()})
		}).Bind(apis.RequireAuth("users"))
		handler.WatchRTC(e.Router, turn, time.Now)
		handler.Ring(e.Router, ringer, log)
		handler.ScheduleDelete(e.Router, acc, time.Now, log)
		handler.MapTiles(e.Router, maps, &handler.IPLimiter{Max: 600, Window: time.Minute})
		// Адреса вне белого списка (превью ссылок, картинки из заметок) —
		// не больше 300 в час на аккаунт: человеку хватает с запасом.
		handler.Meta(e.Router, gateway, &handler.IPLimiter{Max: 120, Window: time.Minute},
			&handler.IPLimiter{Max: 300, Window: time.Hour}, log)
		handler.Movies(e.Router, films, log)
		handler.UserCard(e.Router)
		handler.Group(e.Router, groups, log)
		handler.PetHome(e.Router, pethome.New(app))
		handler.WidgetAnim(e.Router, anim)
		handler.Calls(e.Router, pushes.New(app, notify, time.Now), time.Now)
		handler.InviteAccept(e.Router, pairs.New(app), log)
		handler.CoupleStats(e.Router, stats.New(app), time.Now, log)
		handler.Waiting(e.Router, pairs.New(app), time.Now, log)
		handler.InviteWeb(e.Router, handler.InvitePage{
			AppName: cfg.AppName, Scheme: cfg.Invite.Scheme,
			PlayURL: cfg.Invite.PlayURL, RuStoreURL: cfg.Invite.RuStoreURL, APKURL: cfg.Invite.APKURL,
			AndroidPackage: cfg.Invite.AndroidPackage, AndroidFingerprints: cfg.Invite.Fingerprints(),
			IOSAppID: cfg.Invite.IOSAppID,
		})
		handler.RealtimeTokens(e.Router, cfg.Centrifugo.TokenHMAC)
		handler.WatchRooms(e.Router, cfg.Centrifugo.TokenHMAC, pub)
		handler.PasswordReset(e.Router, time.Now, log)
		handler.EmailChange(e.Router, time.Now, log)
		handler.Music(e.Router, music.New(safefetch.New(safefetch.Options{Timeout: 8 * time.Second, MaxBytes: 1 << 20})), log)
		handler.WatchProxy(e.Router, proxyInfo)
		if _, err := os.Stat(cfg.PublicDir); err == nil {
			e.Router.GET("/{path...}", apis.Static(os.DirFS(cfg.PublicDir), false))
		}
		return e.Next()
	})
}

// bindWatchProxy поднимает прокси роликов (PLAN S11), если оператор его
// включил. Пускает по токену входа: Basic uid:токен.
func bindWatchProxy(app core.App, cfg config.Config, mx *metrics.Metrics, log *slog.Logger) handler.WatchProxyInfo {
	w := cfg.WatchProxy
	if !w.Enabled {
		return handler.WatchProxyInfo{}
	}
	hosts := w.HostList()
	if len(hosts) == 0 {
		hosts = watchproxy.DefaultHosts
	}
	domain := ""
	if u, err := url.Parse(cfg.WatchProxyURL()); err == nil {
		domain = u.Hostname()
	}
	certs := &wproxy.CertFiles{CertFile: w.CertFile, KeyFile: w.KeyFile, CaddyDir: w.CaddyDir, Domain: domain}
	p := wproxy.New(wproxy.Options{
		Policy: watchproxy.Policy{Hosts: hosts},
		Quota:  &watchproxy.Quota{Daily: int64(w.DailyMB) << 20},
		Auth: func(_ context.Context, user, token string) bool {
			rec, err := app.FindAuthRecordByToken(token, core.TokenTypeAuth)
			return err == nil && rec.Id == user && rec.Collection().Name == "users"
		},
		Log:     log,
		Observe: mx.ProxyConn,
		Bytes:   mx.ProxyBytes,
	})
	srv := wproxy.Server(w.Addr, p, certs.GetCertificate)
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		go func() {
			if err := srv.ListenAndServeTLS("", ""); err != nil && !errors.Is(err, http.ErrServerClosed) {
				log.Error("прокси роликов", "err", err)
			}
		}()
		log.Info("прокси роликов включён", "addr", w.Addr, "url", cfg.WatchProxyURL())
		return e.Next()
	})
	app.OnTerminate().BindFunc(func(e *core.TerminateEvent) error {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(ctx)
		return e.Next()
	})
	return handler.WatchProxyInfo{Enabled: true, URL: cfg.WatchProxyURL(), Hosts: hosts}
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

// bindMetrics отдаёт /metrics на отдельном адресе (не через Caddy).
func bindMetrics(app core.App, addr string, mx *metrics.Metrics, log *slog.Logger) {
	if addr == "" {
		return
	}
	mux := http.NewServeMux()
	mux.Handle("GET /metrics", mx.Handler())
	srv := &http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		go func() {
			if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
				log.Error("метрики", "addr", addr, "err", err)
			}
		}()
		return e.Next()
	})
	app.OnTerminate().BindFunc(func(e *core.TerminateEvent) error {
		_ = srv.Close()
		return e.Next()
	})
}

// bindCompat поднимает на петле внутренний API для JS-хуков апстрима
// (handler.Compat). Адрес зашит в хуках — 127.0.0.1:8120.
func bindCompat(app core.App, addr string, pub handler.Publisher, log *slog.Logger) {
	if addr == "" {
		return
	}
	srv := &http.Server{Addr: addr, Handler: handler.Compat(pairs.New(app), records.New(app), pushes.New(app, pub, time.Now), log), ReadHeaderTimeout: 5 * time.Second}
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
func bindRealtime(app core.App, pub *centrifugo.Publisher, observe func(error), timeout time.Duration, log *slog.Logger) {
	if !pub.Enabled() {
		log.Warn("Centrifugo не настроен: живых обновлений не будет")
		return
	}
	publish := func(ev realtime.Event, rec *core.Record) {
		ev, ok := heldEvent(ev, rec)
		if !ok {
			return
		}
		r := recordAdapter{rec}
		channels := realtime.Channels(r)
		if len(channels) == 0 {
			return
		}
		payload := broadcastPayload(ev, rec)
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), timeout)
			defer cancel()
			for _, ch := range channels {
				err := pub.Publish(ctx, ch, payload)
				observe(err)
				if err != nil {
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
		user, channels := realtime.Revoked(recordAdapter{e.Record})
		revoke(pub, user, channels, timeout, log)
		return e.Next()
	})
}

// revoke снимает подписки, право на которые пропало вместе с записью (D11).
func revoke(pub *centrifugo.Publisher, user string, channels []string, timeout time.Duration, log *slog.Logger) {
	if user == "" {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), timeout)
		defer cancel()
		for _, ch := range channels {
			if err := pub.Unsubscribe(ctx, user, ch); err != nil {
				log.Warn("centrifugo: снятие подписки", "channel", ch, "err", err)
			}
		}
	}()
}

// broadcastPayload — публикация изменения записи: то, что получает клиент из
// Centrifugo и из ящика будильника FCM.
func broadcastPayload(ev realtime.Event, rec *core.Record) map[string]any {
	return map[string]any{"event": ev, "collection": rec.Collection().Name, "record": sanitizeForBroadcast(rec, time.Now())}
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
	// Журнал запросов PocketBase хранит URL с id пользователя: адреса превью,
	// поиск фильмов и мест — то, что в записях лежит шифром. Не храним
	// вовсе (MaxDays = 0 выключает и запись журнала).
	s.Logs.MaxDays = 0
	s.Logs.LogIP = false
	s.Logs.LogAuthId = false
}

// rateLimitRules — лимиты на IP (решение 3: вход только по паролю, значит
// нужна защита от перебора). Общих лимитов на запись нет: рисование и чат
// создают записи пачками.
var rateLimitRules = []core.RateLimitRule{
	// PLAN 1.8: short invitation codes and expensive external previews.
	{Label: "POST /api/invite/accept", MaxRequests: 10, Duration: 300},
	{Label: "POST /api/waiting/claim", MaxRequests: 10, Duration: 300},
	{Label: "/api/link/preview", MaxRequests: 30, Duration: 60},
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
