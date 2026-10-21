// Package chat — правила сообщений чата, которые ставит сервер.
package chat

import "time"

const (
	// ClockSkew — насколько часы телефона могут расходиться с сервером, чтобы
	// ещё верить отметке сообщения (сборки без `sent_at`).
	ClockSkew = 2 * time.Minute
	// OfflineMax — сообщение из офлайна старше этого встаёт на время
	// доставки: такая давность — уже мусор в часах.
	OfflineMax = 7 * 24 * time.Hour
)

// MessageTime — `ts` сообщения в мс (как `время_сообщения` в hotpath
// апстрима). [own] — `ts` телефона, [server] — часы сервера, [sent] — часы
// телефона в момент отправки (`sent_at`, 0 у старых сборок).
//
// С [sent] разница с сервером — сдвиг часов телефона, и на неё правится
// время написания: сообщение из офлайна встаёт туда, где его написали, а не
// ответом на то, что пришло, пока оно ждало сети.
func MessageTime(own, server, sent int64) int64 {
	if own <= 0 {
		return server
	}
	if sent > 0 {
		written := own + (server - sent)
		if written > server || server-written > OfflineMax.Milliseconds() {
			return server
		}
		return written
	}
	if d := server - own; d > ClockSkew.Milliseconds() || -d > ClockSkew.Milliseconds() {
		return server
	}
	return own
}
