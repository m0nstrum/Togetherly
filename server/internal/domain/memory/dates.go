// Package memory — правила записей ленты, которые ставит сервер.
package memory

import (
	"strings"
	"time"
)

// ClockSkew — расхождение часов телефона, которое ещё не считается спешкой.
const ClockSkew = 2 * time.Minute

// ClampFuture — даты воспоминания без будущего (как `даты_воспоминания` в
// hotpath апстрима). Дату записи и момент занесения ставит телефон автора;
// когда его часы спешат, запись встаёт в ленте выше всего нового и висит
// там, пока время её не догонит.
//
// Прошлое не трогаем: запись без сети приезжает позже, а задним числом даты
// ставят нарочно. Если момент занесения [added] впереди сервера, часы
// спешат: оба времени сдвигаются назад на расхождение. Дата, которая и после
// этого впереди, становится текущей. Нулевое время — «даты нет».
func ClampFuture(created, added, now time.Time) (time.Time, time.Time) {
	if !added.IsZero() && added.Sub(now) > ClockSkew {
		shift := added.Sub(now)
		added = now
		if !created.IsZero() {
			created = created.Add(-shift)
		}
	}
	if !created.IsZero() && created.Sub(now) > ClockSkew {
		created = now
	}
	return created, added
}

// ParseDate — дата телефона или базы (ISO, с «Z» или пробелом); мусор — ноль.
func ParseDate(s string) time.Time {
	s = strings.Replace(strings.TrimSpace(s), " ", "T", 1)
	for _, layout := range []string{time.RFC3339Nano, "2006-01-02T15:04:05.999999999", "2006-01-02T15:04:05.999999999Z07:00"} {
		if t, err := time.Parse(layout, s); err == nil {
			return t.UTC()
		}
	}
	return time.Time{}
}

// FormatDate — дата в том виде, что пишет телефон.
func FormatDate(t time.Time) string { return t.UTC().Format("2006-01-02T15:04:05.000000Z") }
