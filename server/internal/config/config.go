// Package config — настройки сервера из переменных окружения (TETHERED_*).
package config

import (
	"errors"
	"fmt"
	"net"
	"net/url"
	"strings"
	"time"

	"github.com/knadh/koanf/providers/env"
	"github.com/knadh/koanf/v2"

	"github.com/m0nstrum/togetherly/server/internal/infrastructure/backup"
)

// Config — всё, что сервер берёт из окружения.
type Config struct {
	// HTTPAddr — где слушает PocketBase.
	HTTPAddr string `koanf:"http_addr"`
	// DataDir — база SQLite и файлы (pb_data).
	DataDir string `koanf:"data_dir"`
	// HooksDir — JS-хуки (server/pb_hooks), пока не перенесены на Go.
	HooksDir string `koanf:"hooks_dir"`
	// PublicDir — статика (комнаты «Смотрим вместе», лендинг приглашения).
	PublicDir string `koanf:"public_dir"`
	// AppURL — внешний адрес сервера: ссылки в письмах.
	AppURL string `koanf:"app_url"`
	// AppName — имя отправителя писем.
	AppName string `koanf:"app_name"`
	// CompatAddr — внутренний API для JS-хуков апстрима (их hotpath). Адрес
	// зашит в хуках; пустой — не поднимать.
	CompatAddr string `koanf:"compat_addr"`
	// MetricsAddr — где отдавать /metrics для Prometheus. Пусто — не
	// отдавать. Наружу не публиковать.
	MetricsAddr string `koanf:"metrics_addr"`
	// LogLevel — debug, info, warn, error.
	LogLevel string `koanf:"log_level"`
	// TrustedProxyHeader — заголовок с адресом клиента от своего прокси
	// (X-Forwarded-For за Caddy). Пусто — адрес соединения. Без него за
	// прокси все клиенты для лимитов — один IP.
	TrustedProxyHeader string `koanf:"trusted_proxy_header"`
	// RateLimits — защита входа, сброса пароля и регистрации от перебора.
	RateLimits bool `koanf:"rate_limits"`
	// PoiskkinoKey — свой ключ api.poiskkino.dev: запасной источник поиска
	// фильмов, когда Викиданные пусты. Пустой — только Викиданные.
	PoiskkinoKey string `koanf:"poiskkino_key"`

	Centrifugo Centrifugo `koanf:"centrifugo"`
	SMTP       SMTP       `koanf:"smtp"`
	TURN       TURN       `koanf:"turn"`
	Backup     Backup     `koanf:"backup"`
	WatchProxy WatchProxy `koanf:"watch_proxy"`
	FCM        FCM        `koanf:"fcm"`
}

// Backup — встроенные бэкапы PocketBase (zip в pb_data/backups). Cron пуст —
// выключены. С AgeRecipients каждый бэкап шифруется в Dir, а открытый zip
// удаляется (infrastructure/backup).
type Backup struct {
	Cron    string `koanf:"cron"`
	MaxKeep int    `koanf:"max_keep"`
	// AgeRecipients — публичные ключи age (`age1…`) через пробел или запятую.
	AgeRecipients string `koanf:"age_recipients"`
	// Dir — каталог зашифрованных бэкапов, вне pb_data.
	Dir string `koanf:"dir"`
}

// WatchProxy — прокси роликов «Смотрим вместе» (PLAN S11). По умолчанию
// выключен: трафик площадок идёт через сервер, а в РФ это может подпадать
// под запрет средств обхода блокировок — решает оператор.
type WatchProxy struct {
	Enabled bool `koanf:"enabled"`
	// Addr — где слушает TLS-прокси.
	Addr string `koanf:"addr"`
	// PublicURL — как его видит телефон; пусто — домен AppURL и порт Addr.
	PublicURL string `koanf:"public_url"`
	// Сертификат: явные файлы или хранилище Caddy (том caddy-data).
	CertFile string `koanf:"cert_file"`
	KeyFile  string `koanf:"key_file"`
	CaddyDir string `koanf:"caddy_dir"`
	// Hosts — белый список через запятую; пусто — площадки по умолчанию.
	Hosts string `koanf:"hosts"`
	// DailyMB — лимит на человека в сутки; 0 — без лимита.
	DailyMB int `koanf:"daily_mb"`
}

// FCM — будильник через свой Firebase-проект (PLAN S12): JSON сервисного
// аккаунта строкой или путём к файлу. Оба пусты — выключен, телефоны будит
// только сокет фонового сервиса.
type FCM struct {
	Credentials     string        `koanf:"credentials"`
	CredentialsFile string        `koanf:"credentials_file"`
	TTL             time.Duration `koanf:"ttl"`
	Timeout         time.Duration `koanf:"timeout"`
	// Endpoint — адрес FCM вместо fcm.googleapis.com (тесты).
	Endpoint string `koanf:"endpoint"`
}

// TURN — свой coturn для голоса в комнатах «Смотрим вместе». Secret — тот же,
// что `static-auth-secret` в turnserver.conf.
type TURN struct {
	Host   string        `koanf:"host"`
	Port   int           `koanf:"port"`
	Secret string        `koanf:"secret"`
	TTL    time.Duration `koanf:"ttl"`
}

// Centrifugo — HTTP API для публикации изменений.
type Centrifugo struct {
	API     string        `koanf:"api"`
	APIKey  string        `koanf:"api_key"`
	Timeout time.Duration `koanf:"timeout"`
}

// SMTP — свой почтовый сервер (вместо Gmail-релея апстрима).
type SMTP struct {
	Host     string `koanf:"host"`
	Port     int    `koanf:"port"`
	Username string `koanf:"username"`
	Password string `koanf:"password"`
	Sender   string `koanf:"sender"`
	TLS      bool   `koanf:"tls"`
}

// Enabled — задан ли почтовый сервер.
func (s SMTP) Enabled() bool { return s.Host != "" }

const prefix = "TETHERED_"

// Load читает окружение. Вложенность — через двойное подчёркивание:
// TETHERED_CENTRIFUGO__API_KEY → centrifugo.api_key.
func Load() (Config, error) {
	k := koanf.New(".")
	if err := k.Load(env.Provider(prefix, ".", func(key string) string {
		key = strings.ToLower(strings.TrimPrefix(key, prefix))
		return strings.ReplaceAll(key, "__", ".")
	}), nil); err != nil {
		return Config{}, fmt.Errorf("config: окружение: %w", err)
	}
	cfg := Config{
		HTTPAddr:   "0.0.0.0:8090",
		DataDir:    "pb_data",
		HooksDir:   "pb_hooks",
		PublicDir:  "pb_public",
		AppName:    "Tethered",
		CompatAddr: "127.0.0.1:8120",
		LogLevel:   "info",
		RateLimits: true,
		Centrifugo: Centrifugo{Timeout: 5 * time.Second},
		SMTP:       SMTP{Port: 587, TLS: false},
		TURN:       TURN{Port: 3478, TTL: 12 * time.Hour},
		Backup:     Backup{MaxKeep: 7},
		WatchProxy: WatchProxy{Addr: "0.0.0.0:8443", DailyMB: 3072},
		FCM:        FCM{TTL: 10 * time.Minute, Timeout: 10 * time.Second},
	}
	if err := k.Unmarshal("", &cfg); err != nil {
		return Config{}, fmt.Errorf("config: разбор: %w", err)
	}
	return cfg, cfg.Validate()
}

// Validate проверяет согласованность настроек.
func (c Config) Validate() error {
	var errs []error
	if c.HTTPAddr == "" {
		errs = append(errs, errors.New("TETHERED_HTTP_ADDR пуст"))
	}
	if (c.Centrifugo.API == "") != (c.Centrifugo.APIKey == "") {
		errs = append(errs, errors.New("TETHERED_CENTRIFUGO__API и TETHERED_CENTRIFUGO__API_KEY задаются вместе"))
	}
	if w := c.WatchProxy; w.Enabled {
		if (w.CertFile == "" || w.KeyFile == "") && w.CaddyDir == "" {
			errs = append(errs, errors.New("TETHERED_WATCH_PROXY: нужен сертификат — CERT_FILE и KEY_FILE или CADDY_DIR"))
		}
		if w.PublicURL == "" && c.AppURL == "" {
			errs = append(errs, errors.New("TETHERED_WATCH_PROXY__PUBLIC_URL пуст, и вывести его из TETHERED_APP_URL нечем"))
		}
	}
	if c.Backup.AgeRecipients != "" {
		if _, err := backup.ParseRecipients(c.Backup.AgeRecipients); err != nil {
			errs = append(errs, fmt.Errorf("TETHERED_BACKUP__AGE_RECIPIENTS: %w", err))
		}
		if c.Backup.Dir == "" {
			errs = append(errs, errors.New("TETHERED_BACKUP__DIR обязателен при TETHERED_BACKUP__AGE_RECIPIENTS"))
		}
	}
	if c.SMTP.Enabled() && c.SMTP.Sender == "" {
		errs = append(errs, errors.New("TETHERED_SMTP__SENDER обязателен при заданном SMTP"))
	}
	return errors.Join(errs...)
}

// HostList — белый список прокси; пусто — nil (берутся площадки по умолчанию).
func (w WatchProxy) HostList() []string {
	var out []string
	for _, h := range strings.Split(w.Hosts, ",") {
		if h = strings.TrimSpace(h); h != "" {
			out = append(out, h)
		}
	}
	return out
}

// WatchProxyURL — адрес прокси для телефона: PublicURL или домен AppURL с
// портом Addr.
func (c Config) WatchProxyURL() string {
	if c.WatchProxy.PublicURL != "" {
		return c.WatchProxy.PublicURL
	}
	u, err := url.Parse(c.AppURL)
	if err != nil || u.Hostname() == "" {
		return ""
	}
	_, port, err := net.SplitHostPort(c.WatchProxy.Addr)
	if err != nil || port == "" {
		return ""
	}
	return "https://" + net.JoinHostPort(u.Hostname(), port)
}
