// Package ice выдаёт адреса STUN/TURN для голоса в комнатах «Смотрим вместе».
//
// Только свой coturn (PLAN.md, решение 4): публичные STUN (Google у апстрима)
// видят IP обоих участников. Пароль TURN не общий, как у апстрима, а временный
// по REST API coturn (`use-auth-secret`): имя `<срок>:<uid>`, пароль —
// base64(HMAC-SHA1(секрет, имя)). Утёкший пароль живёт до срока.
package ice

import (
	"crypto/hmac"
	"crypto/sha1" //nolint:gosec // HMAC-SHA1 — требование coturn REST API, не наш выбор
	"encoding/base64"
	"strconv"
	"time"
)

// Server — элемент RTCConfiguration.iceServers.
type Server struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username,omitempty"`
	Credential string   `json:"credential,omitempty"`
}

// TURN — свой coturn. Host пуст — серверов нет вовсе (только прямое
// соединение в одной сети).
type TURN struct {
	Host   string
	Port   int
	Secret string
	TTL    time.Duration
}

// Servers — STUN и, если задан секрет, TURN с временными ключами для uid.
func Servers(t TURN, uid string, now time.Time) []Server {
	if t.Host == "" {
		return []Server{}
	}
	port := t.Port
	if port == 0 {
		port = 3478
	}
	addr := t.Host + ":" + strconv.Itoa(port)
	out := []Server{{URLs: []string{"stun:" + addr}}}
	if t.Secret == "" || uid == "" {
		return out
	}
	ttl := t.TTL
	if ttl <= 0 {
		ttl = 12 * time.Hour
	}
	user, pass := Credentials(t.Secret, uid, now.Add(ttl))
	return append(out, Server{
		URLs:       []string{"turn:" + addr + "?transport=udp", "turn:" + addr + "?transport=tcp"},
		Username:   user,
		Credential: pass,
	})
}

// Credentials — временные имя и пароль coturn, действующие до expires.
func Credentials(secret, uid string, expires time.Time) (username, credential string) {
	username = strconv.FormatInt(expires.Unix(), 10) + ":" + uid
	mac := hmac.New(sha1.New, []byte(secret))
	mac.Write([]byte(username))
	return username, base64.StdEncoding.EncodeToString(mac.Sum(nil))
}
