// Package watchproxy — правила прокси роликов «Смотрим вместе» (PLAN S11).
//
// Прокси пускает только к площадкам из белого списка и только на 443:
// TLS до площадки сквозной, сервер видит домен, а не ролик. Каждому человеку
// — дневной лимит трафика.
package watchproxy

import (
	"errors"
	"net"
	"strings"
	"sync"
	"time"
)

// DefaultHosts — площадки плеера комнаты и то, без чего они не играют.
// `.x` — сам домен и все поддомены.
var DefaultHosts = []string{
	".youtube.com", ".youtube-nocookie.com", ".googlevideo.com", ".ytimg.com",
	".ggpht.com", "jnn-pa.googleapis.com", "youtubei.googleapis.com",
	".vimeo.com", ".vimeocdn.com", "vod-adaptive-ak.vimeocdn.com",
}

// ErrTarget — адрес CONNECT не годится (не 443 или не по списку).
var ErrTarget = errors.New("watchproxy: адрес не разрешён")

// Policy — белый список.
type Policy struct {
	Hosts []string
}

// Allowed — можно ли к [host] (без порта, без учёта регистра).
func (p Policy) Allowed(host string) bool {
	h := strings.TrimSuffix(strings.ToLower(host), ".")
	if h == "" || net.ParseIP(h) != nil {
		return false
	}
	for _, rule := range p.Hosts {
		r := strings.ToLower(rule)
		if strings.HasPrefix(r, ".") {
			if h == r[1:] || strings.HasSuffix(h, r) {
				return true
			}
		} else if h == r {
			return true
		}
	}
	return false
}

// Target — адрес CONNECT `host:443`; иное — [ErrTarget].
func (p Policy) Target(hostport string) (string, error) {
	host, port, err := net.SplitHostPort(hostport)
	if err != nil || port != "443" || !p.Allowed(host) {
		return "", ErrTarget
	}
	return net.JoinHostPort(strings.ToLower(host), port), nil
}

// Quota — дневной лимит байт на человека. Считается в памяти: после
// перезапуска сервер щедр — лимит защищает от злоупотребления, не бухгалтерия.
type Quota struct {
	Daily int64

	mu   sync.Mutex
	day  string
	used map[string]int64
}

func (q *Quota) roll(now time.Time) {
	d := now.UTC().Format(time.DateOnly)
	if q.day != d || q.used == nil {
		q.day = d
		q.used = map[string]int64{}
	}
}

// Left — сколько байт у [user] осталось на сегодня; без лимита — всегда >0.
func (q *Quota) Left(user string, now time.Time) int64 {
	if q.Daily <= 0 {
		return 1 << 62
	}
	q.mu.Lock()
	defer q.mu.Unlock()
	q.roll(now)
	return q.Daily - q.used[user]
}

// Add записывает [n] байт на [user].
func (q *Quota) Add(user string, n int64, now time.Time) {
	if q.Daily <= 0 || n <= 0 {
		return
	}
	q.mu.Lock()
	defer q.mu.Unlock()
	q.roll(now)
	q.used[user] += n
}
