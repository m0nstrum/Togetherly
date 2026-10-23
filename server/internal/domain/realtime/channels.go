// Package realtime описывает, в какие каналы Centrifugo уходит изменение
// записи. Чистая логика без PocketBase: её проверяют тесты и использует
// публикатор из infrastructure/centrifugo.
package realtime

// Record — то, что нужно знать о записи для выбора каналов.
type Record interface {
	CollectionName() string
	RecordID() string
	String(field string) string
	Strings(field string) []string
}

// Event — тип изменения записи.
type Event string

const (
	EventCreate Event = "create"
	EventUpdate Event = "update"
	EventDelete Event = "delete"
)

// published — коллекции, изменения которых рассылаются клиентам. Состав и
// каналы повторяют прод апстрима (pocketbase/pb-cgo/main.go), чтобы клиент не
// заметил разницы.
var published = map[string]bool{
	"chat_messages": true, "mood_entries": true, "memories": true,
	"memory_comments": true, "mascots": true, "miss_you": true, "gifts": true,
	"user_presence": true, "live_sessions": true, "live_session_presence": true,
	"live_session_chat": true, "live_location": true, "canvas_strokes": true,
	"canvas_meta": true, "canvas_live": true, "canvas_catalogue": true,
	"widget_data": true, "chat_typing": true, "chat_reads": true, "groups": true,
	"watch_history": true, "cycle_entries": true, "wishes": true,
	"wish_categories": true, "custom_moods": true, "watch_videos": true,
	// Форк, E2E: шаги обмена ключами и выданные ключи пары (шифртекст) —
	// в канал пары, чтобы сверка эмодзи шла без опроса.
	"e2e_handshake": true, "e2e_grants": true,
	// Форк: заряд телефона партнёра (шифром) — сразу в канал пары.
	"fork_battery":       true,
	"fork_reels_matches": true,
	"fork_movie_choices": true,
}

// IsPublished — рассылаются ли изменения коллекции.
func IsPublished(collection string) bool { return published[collection] }

// Channels — каналы для записи:
//
//	user:<uid>     — присутствие и изменения групп участника;
//	loc:<channel>  — геопозиция;
//	pair:<groupId> — всё остальное парное.
//
// Пустой результат — записи некуда рассылать.
func Channels(r Record) []string {
	if r == nil || !published[r.CollectionName()] {
		return nil
	}
	switch r.CollectionName() {
	case "user_presence":
		return nonEmpty("user:", r.String("user_uid"))
	case "live_location":
		return nonEmpty("loc:", r.String("channel"))
	case "live_sessions":
		return nonEmpty("pair:", r.RecordID())
	case "live_session_presence", "live_session_chat":
		return nonEmpty("pair:", r.String("pair_id"))
	case "groups":
		// Кроме канала пары — личные каналы участников: иначе приглашающий не
		// увидит появление пары до перезапуска приложения.
		out := nonEmpty("pair:", r.RecordID())
		for _, uid := range r.Strings("members") {
			if uid != "" {
				out = append(out, "user:"+uid)
			}
		}
		return out
	default:
		return nonEmpty("pair:", r.String("group_id"))
	}
}

func nonEmpty(prefix, id string) []string {
	if id == "" {
		return nil
	}
	return []string{prefix + id}
}
