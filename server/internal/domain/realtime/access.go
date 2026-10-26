package realtime

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"strings"
)

// Scope — что нужно проверить, чтобы выдать подписку на канал.
type Scope struct {
	// Kind: pair (участник пары Target), user (сам Target или его пара),
	// loc (геоканал пары двух людей A и B), watch (комната с кодом Target).
	// Пусто — канал не выдаётся.
	Kind   string
	Target string
	A, B   string
}

// SubscribeScope разбирает имя канала. Каналы сигналинга (`signal:`,
// `locsignal:`) проверяются как их основные (`pair:`, `loc:`), а рисование
// (`draw:`) — как канал пары.
func SubscribeScope(channel, uid string) Scope {
	switch {
	case strings.HasPrefix(channel, "signal:"):
		channel = "pair:" + channel[len("signal:"):]
	case strings.HasPrefix(channel, "locsignal:"):
		channel = "loc:" + channel[len("locsignal:"):]
	}
	ns, rest, ok := strings.Cut(channel, ":")
	if !ok {
		return Scope{}
	}
	switch ns {
	case "pair", "draw":
		return Scope{Kind: "pair", Target: rest}
	case "user":
		return Scope{Kind: "user", Target: rest}
	case "loc":
		// loc:pair_<a>_<b> — геопозиция только своей настоящей пары.
		p := strings.Split(rest, "_")
		if len(p) == 3 && p[0] == "pair" && (p[1] == uid || p[2] == uid) {
			return Scope{Kind: "loc", A: p[1], B: p[2]}
		}
	case "watch":
		return Scope{Kind: "watch", Target: rest}
	}
	return Scope{}
}

const roomAlphabet = "abcdefghjkmnpqrstuvwxyz23456789"

// RoomCode — код комнаты совместного просмотра пары: восемь знаков из
// HMAC-SHA256(groupID, secret). Повторяет `$security.hs256` JS-хуков: буквы
// берутся по кодам символов hex-записи подписи.
func RoomCode(groupID, secret string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(groupID))
	digest := hex.EncodeToString(mac.Sum(nil))
	var b strings.Builder
	for i := range 8 {
		b.WriteByte(roomAlphabet[int(digest[i])%len(roomAlphabet)])
	}
	return b.String()
}

// Открытая комната просмотра — код из десяти знаков: шесть случайных и
// четыре подписи от них. Подпись знает только сервер, поэтому набранный
// руками код честно отвечает «комнаты нет», а хранить ничего не нужно.
// Длина 10 не пересекается с кодом пары (8).

// NewOpenRoom — свежий код открытой комнаты; random — 6 случайных байт.
func NewOpenRoom(random []byte, secret string) string {
	var b strings.Builder
	for i := range 6 {
		b.WriteByte(roomAlphabet[int(random[i%len(random)])%len(roomAlphabet)])
	}
	head := b.String()
	return head + openRoomTail(head, secret)
}

// IsOpenRoom — код открытой комнаты, выданный этим сервером.
func IsOpenRoom(room, secret string) bool {
	return len(room) == 10 && hmac.Equal([]byte(openRoomTail(room[:6], secret)), []byte(room[6:]))
}

func openRoomTail(head, secret string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte("watch-open:" + head))
	sum := mac.Sum(nil)
	var b strings.Builder
	for i := range 4 {
		b.WriteByte(roomAlphabet[int(sum[i])%len(roomAlphabet)])
	}
	return b.String()
}

// pairRoomChars — знаки, которые даёт RoomCode: он берёт коды символов
// hex-записи, и их всего шестнадцать.
const pairRoomChars = "efghjkuvwxyz2345"

// LooksLikePairRoom — код по форме похож на комнату пары.
func LooksLikePairRoom(room string) bool {
	if len(room) != 8 {
		return false
	}
	for _, r := range room {
		if !strings.ContainsRune(pairRoomChars, r) {
			return false
		}
	}
	return true
}
