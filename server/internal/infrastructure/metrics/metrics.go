// Package metrics — метрики сервера для Prometheus (PLAN S10).
//
// Только про сервер, не про людей: в метках шаблон маршрута, метод и класс
// ответа — без uid, IP, id записей и текста запросов. Отдаются на отдельном
// адресе (TETHERED_METRICS_ADDR), наружу через Caddy не публикуются.
package metrics

import (
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Metrics — свой реестр (не глобальный: тесты собирают по приложению).
type Metrics struct {
	Registry *prometheus.Registry

	requests   *prometheus.CounterVec
	duration   *prometheus.HistogramVec
	publishes  *prometheus.CounterVec
	backups    *prometheus.CounterVec
	lastBackup prometheus.Gauge
}

// New — реестр со стандартными метриками Go и процесса.
func New() *Metrics {
	m := &Metrics{
		Registry: prometheus.NewRegistry(),
		requests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "tethered_http_requests_total",
			Help: "HTTP-запросы по шаблону маршрута, методу и классу ответа.",
		}, []string{"route", "method", "code"}),
		duration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "tethered_http_request_duration_seconds",
			Help:    "Время ответа по шаблону маршрута.",
			Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10},
		}, []string{"route"}),
		publishes: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "tethered_centrifugo_publishes_total",
			Help: "Публикации в Centrifugo: ok или error.",
		}, []string{"result"}),
		backups: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "tethered_backups_total",
			Help: "Бэкапы: ok или error.",
		}, []string{"result"}),
		lastBackup: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "tethered_backup_last_success_timestamp_seconds",
			Help: "Когда последний бэкап удался (unix).",
		}),
	}
	m.Registry.MustRegister(
		collectors.NewGoCollector(),
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
		m.requests, m.duration, m.publishes, m.backups, m.lastBackup,
	)
	return m
}

// Bind вешает учёт запросов и бэкапов и размер базы на app.
func (m *Metrics) Bind(app core.App) {
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		e.Router.BindFunc(m.observe)
		return e.Next()
	})
	app.OnBackupCreate().BindFunc(func(e *core.BackupEvent) error {
		err := e.Next()
		if err != nil {
			m.backups.WithLabelValues("error").Inc()
			return err
		}
		m.backups.WithLabelValues("ok").Inc()
		m.lastBackup.SetToCurrentTime()
		return nil
	})
	for _, f := range []string{"data.db", "auxiliary.db"} {
		path := filepath.Join(app.DataDir(), f)
		m.Registry.MustRegister(prometheus.NewGaugeFunc(prometheus.GaugeOpts{
			Name:        "tethered_db_size_bytes",
			Help:        "Размер файлов SQLite (без WAL).",
			ConstLabels: prometheus.Labels{"file": f},
		}, func() float64 {
			st, err := os.Stat(path)
			if err != nil {
				return 0
			}
			return float64(st.Size())
		}))
	}
}

func (m *Metrics) observe(e *core.RequestEvent) error {
	start := time.Now()
	err := e.Next()
	route := e.Request.Pattern
	if route == "" {
		route = "unmatched"
	}
	m.requests.WithLabelValues(route, e.Request.Method, codeClass(statusOf(e, err))).Inc()
	m.duration.WithLabelValues(route).Observe(time.Since(start).Seconds())
	return err
}

// statusOf — код ответа: записанный, а если обработчик вернул ошибку и
// ответ ещё не записан, — код этой ошибки (её запишет PocketBase позже).
func statusOf(e *core.RequestEvent, err error) int {
	if err != nil && !e.Written() {
		var api *router.ApiError
		if errors.As(err, &api) {
			return api.Status
		}
		return http.StatusInternalServerError
	}
	if s := e.Status(); s != 0 {
		return s
	}
	return http.StatusOK
}

func codeClass(code int) string {
	return strconv.Itoa(code/100) + "xx"
}

// Published — учесть публикацию в Centrifugo.
func (m *Metrics) Published(err error) {
	if err != nil {
		m.publishes.WithLabelValues("error").Inc()
		return
	}
	m.publishes.WithLabelValues("ok").Inc()
}

// Handler — /metrics.
func (m *Metrics) Handler() http.Handler {
	return promhttp.HandlerFor(m.Registry, promhttp.HandlerOpts{})
}
