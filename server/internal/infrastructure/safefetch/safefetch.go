// Package safefetch — HTTP-клиент для запросов по адресам, которые прислал
// пользователь (превью ссылок, метаданные). Защита от SSRF:
//
//   - IP проверяется в момент соединения (net.Dialer.Control видит адрес, к
//     которому реально подключаемся), поэтому её не обходят ни редиректы, ни
//     DNS rebinding, ни записи вроде http://127.1 или http://2130706433 — у
//     загрузчика апстрима (pocketbase/link_fetcher) проверка шла до
//     соединения, а резолв — заново;
//   - только порты 80 и 443, только http(s), не больше MaxRedirects переходов;
//   - тело ограничено по размеру, общий таймаут;
//   - переменные HTTP_PROXY игнорируются: через прокси проверка IP теряет смысл.
package safefetch

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"strconv"
	"syscall"
	"time"
)

// ErrDenied — адрес трогать нельзя.
var ErrDenied = errors.New("safefetch: адрес запрещён")

// Options — настройки клиента.
type Options struct {
	Timeout      time.Duration
	MaxBytes     int64
	MaxRedirects int
	UserAgent    string
	// AllowLoopback — только для тестов (httptest слушает 127.0.0.1).
	AllowLoopback bool
	// AllowAnyPort — только для тестов (httptest слушает случайный порт).
	AllowAnyPort bool
}

// Client — безопасный загрузчик.
type Client struct {
	http *http.Client
	opt  Options
}

// New — клиент с разумными значениями по умолчанию.
func New(opt Options) *Client {
	if opt.Timeout == 0 {
		opt.Timeout = 8 * time.Second
	}
	if opt.MaxBytes == 0 {
		opt.MaxBytes = 512 << 10
	}
	if opt.MaxRedirects == 0 {
		opt.MaxRedirects = 4
	}
	if opt.UserAgent == "" {
		opt.UserAgent = "Mozilla/5.0 (compatible; TetheredBot/1.0)"
	}
	dialer := &net.Dialer{
		Timeout: opt.Timeout,
		Control: func(_, address string, _ syscall.RawConn) error {
			return checkAddr(address, opt)
		},
	}
	transport := &http.Transport{
		Proxy:                 nil,
		DialContext:           dialer.DialContext,
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          20,
		IdleConnTimeout:       30 * time.Second,
		TLSHandshakeTimeout:   opt.Timeout,
		ResponseHeaderTimeout: opt.Timeout,
	}
	return &Client{opt: opt, http: &http.Client{
		Timeout:   opt.Timeout,
		Transport: transport,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) > opt.MaxRedirects {
				return fmt.Errorf("%w: слишком много переходов", ErrDenied)
			}
			return checkScheme(req)
		},
	}}
}

// Response — итог запроса.
type Response struct {
	FinalURL    string
	Status      int
	ContentType string
	Body        []byte
}

// Get загружает url (GET) с заголовками headers.
func (c *Client) Get(ctx context.Context, url string, headers map[string]string) (Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return Response{}, fmt.Errorf("%w: %v", ErrDenied, err)
	}
	if err := checkScheme(req); err != nil {
		return Response{}, err
	}
	req.Header.Set("User-Agent", c.opt.UserAgent)
	req.Header.Set("Accept-Language", "ru,en;q=0.8")
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		if errors.Is(err, ErrDenied) {
			return Response{}, err
		}
		return Response{}, fmt.Errorf("safefetch: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, c.opt.MaxBytes))
	if err != nil {
		return Response{}, fmt.Errorf("safefetch: чтение: %w", err)
	}
	return Response{
		FinalURL:    resp.Request.URL.String(),
		Status:      resp.StatusCode,
		ContentType: resp.Header.Get("Content-Type"),
		Body:        body,
	}, nil
}

func checkScheme(req *http.Request) error {
	if s := req.URL.Scheme; s != "http" && s != "https" {
		return fmt.Errorf("%w: только http(s)", ErrDenied)
	}
	if req.URL.User != nil {
		return fmt.Errorf("%w: адрес с учётными данными", ErrDenied)
	}
	return nil
}

// checkAddr — адрес, к которому подключаемся, публичный и на разрешённом порту.
func checkAddr(address string, opt Options) error {
	host, portStr, err := net.SplitHostPort(address)
	if err != nil {
		return fmt.Errorf("%w: %v", ErrDenied, err)
	}
	port, _ := strconv.Atoi(portStr)
	if !opt.AllowAnyPort && port != 80 && port != 443 {
		return fmt.Errorf("%w: порт %d", ErrDenied, port)
	}
	ip, err := netip.ParseAddr(host)
	if err != nil {
		return fmt.Errorf("%w: не IP %q", ErrDenied, host)
	}
	if !Public(ip.Unmap()) && !(opt.AllowLoopback && ip.Unmap().IsLoopback()) {
		return fmt.Errorf("%w: внутренний адрес %s", ErrDenied, ip)
	}
	return nil
}

var cgnat = netip.MustParsePrefix("100.64.0.0/10")

// Public — адрес из публичного интернета.
func Public(ip netip.Addr) bool {
	return ip.IsValid() && ip.IsGlobalUnicast() && !ip.IsPrivate() &&
		!ip.IsLoopback() && !ip.IsLinkLocalUnicast() && !cgnat.Contains(ip)
}
