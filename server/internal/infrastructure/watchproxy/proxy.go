// Package watchproxy — HTTPS CONNECT-прокси роликов «Смотрим вместе»
// (PLAN S11). Браузер комнаты в приложении ходит к площадкам через него:
// снаружи виден только TLS к нашему домену, TLS до площадки сквозной.
package watchproxy

import (
	"context"
	"crypto/tls"
	"encoding/base64"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/m0nstrum/togetherly/server/internal/domain/watchproxy"
)

// Authenticator — действителен ли токен входа [token] пользователя [user].
type Authenticator func(ctx context.Context, user, token string) bool

// Options — зависимости прокси.
type Options struct {
	Policy watchproxy.Policy
	Quota  *watchproxy.Quota
	Auth   Authenticator
	// Dial — соединение с площадкой; по умолчанию net.Dialer.
	Dial func(ctx context.Context, network, addr string) (net.Conn, error)
	Now  func() time.Time
	Log  *slog.Logger
	// Observe — учёт для метрик: исход попытки соединения.
	Observe func(result string)
	// Bytes — сколько прошло через закрытое соединение.
	Bytes       func(n int64)
	DialTimeout time.Duration
	IdleTimeout time.Duration
}

// Proxy — http.Handler, понимающий только CONNECT.
type Proxy struct {
	o Options
}

// New — прокси с умолчаниями для пустых полей.
func New(o Options) *Proxy {
	if o.Now == nil {
		o.Now = time.Now
	}
	if o.Log == nil {
		o.Log = slog.Default()
	}
	if o.Observe == nil {
		o.Observe = func(string) {}
	}
	if o.Bytes == nil {
		o.Bytes = func(int64) {}
	}
	if o.Quota == nil {
		o.Quota = &watchproxy.Quota{}
	}
	if o.DialTimeout == 0 {
		o.DialTimeout = 10 * time.Second
	}
	if o.IdleTimeout == 0 {
		o.IdleTimeout = 2 * time.Minute
	}
	if o.Dial == nil {
		d := &net.Dialer{Timeout: o.DialTimeout}
		o.Dial = d.DialContext
	}
	return &Proxy{o: o}
}

func (p *Proxy) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Не CONNECT — отвечаем как обычный сайт, без подсказок, что тут прокси.
	if r.Method != http.MethodConnect {
		http.NotFound(w, r)
		return
	}
	user, token, ok := basicAuth(r.Header.Get("Proxy-Authorization"))
	if !ok || !p.o.Auth(r.Context(), user, token) {
		w.Header().Set("Proxy-Authenticate", `Basic realm="tethered"`)
		p.o.Observe("auth")
		http.Error(w, "", http.StatusProxyAuthRequired)
		return
	}
	target, err := p.o.Policy.Target(r.Host)
	if err != nil {
		p.o.Observe("denied")
		http.Error(w, "", http.StatusForbidden)
		return
	}
	if p.o.Quota.Left(user, p.o.Now()) <= 0 {
		p.o.Observe("quota")
		http.Error(w, "", http.StatusTooManyRequests)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), p.o.DialTimeout)
	up, err := p.o.Dial(ctx, "tcp", target)
	cancel()
	if err != nil {
		p.o.Observe("dial")
		http.Error(w, "", http.StatusBadGateway)
		return
	}
	hj, ok := w.(http.Hijacker)
	if !ok {
		_ = up.Close()
		http.Error(w, "", http.StatusInternalServerError)
		return
	}
	client, buf, err := hj.Hijack()
	if err != nil {
		_ = up.Close()
		return
	}
	if _, err := client.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n")); err != nil {
		_ = client.Close()
		_ = up.Close()
		return
	}
	p.o.Observe("ok")
	// Клиент мог прислать начало TLS вместе с CONNECT — оно уже в буфере.
	var head []byte
	if n := buf.Reader.Buffered(); n > 0 {
		head, _ = buf.Reader.Peek(n)
	}
	p.o.Bytes(p.pipe(user, client, up, head))
}

// pipe гонит байты в обе стороны, пока одна не закроется, не замолчит
// дольше IdleTimeout или не кончится лимит. Возвращает, сколько прошло.
func (p *Proxy) pipe(user string, client, up net.Conn, head []byte) int64 {
	var (
		mu    sync.Mutex
		total int64
	)
	count := func(n int) error {
		mu.Lock()
		total += int64(n)
		mu.Unlock()
		p.o.Quota.Add(user, int64(n), p.o.Now())
		if p.o.Quota.Left(user, p.o.Now()) <= 0 {
			return errQuota
		}
		return nil
	}
	if len(head) > 0 {
		if _, err := up.Write(head); err != nil {
			_ = client.Close()
			_ = up.Close()
			return 0
		}
	}
	// Простой считается по соединению целиком: долгая закачка идёт к
	// клиенту, а клиент при этом минутами молчит — это не простой.
	var active atomic.Int64
	active.Store(time.Now().UnixNano())
	done := make(chan struct{}, 2)
	cp := func(dst, src net.Conn) {
		_ = copyIdle(dst, src, p.o.IdleTimeout, &active, count)
		// Закрыть обе стороны: вторая горутина выйдет из Read.
		_ = dst.Close()
		_ = src.Close()
		done <- struct{}{}
	}
	go cp(up, client)
	go cp(client, up)
	<-done
	<-done
	mu.Lock()
	defer mu.Unlock()
	return total
}

var errQuota = errors.New("watchproxy: лимит на сегодня исчерпан")

func copyIdle(dst, src net.Conn, idle time.Duration, active *atomic.Int64, count func(int) error) error {
	buf := make([]byte, 32<<10)
	for {
		_ = src.SetReadDeadline(time.Now().Add(idle))
		n, err := src.Read(buf)
		if n > 0 {
			active.Store(time.Now().UnixNano())
			if _, werr := dst.Write(buf[:n]); werr != nil {
				return werr
			}
			if cerr := count(n); cerr != nil {
				return cerr
			}
		}
		if err != nil {
			var ne net.Error
			if errors.As(err, &ne) && ne.Timeout() &&
				time.Since(time.Unix(0, active.Load())) < idle {
				continue // молчит эта сторона, а не соединение
			}
			if errors.Is(err, io.EOF) {
				return nil
			}
			return err
		}
	}
}

func basicAuth(h string) (user, pass string, ok bool) {
	const prefix = "Basic "
	if len(h) < len(prefix) || !strings.EqualFold(h[:len(prefix)], prefix) {
		return "", "", false
	}
	raw, err := base64.StdEncoding.DecodeString(h[len(prefix):])
	if err != nil {
		return "", "", false
	}
	user, pass, ok = strings.Cut(string(raw), ":")
	return user, pass, ok && user != "" && pass != ""
}

// Server — TLS-сервер прокси. HTTP/2 выключен: CONNECT нужен по HTTP/1.1,
// чтобы забрать соединение целиком.
func Server(addr string, h http.Handler, cert func(*tls.ClientHelloInfo) (*tls.Certificate, error)) *http.Server {
	return &http.Server{
		Addr:              addr,
		Handler:           h,
		ReadHeaderTimeout: 10 * time.Second,
		TLSConfig: &tls.Config{
			MinVersion:     tls.VersionTLS12,
			NextProtos:     []string{"http/1.1"},
			GetCertificate: cert,
		},
		TLSNextProto: map[string]func(*http.Server, *tls.Conn, http.Handler){},
	}
}
