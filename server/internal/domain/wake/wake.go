// Package wake решает, кого будить пушем FCM по изменению записи (PLAN S12).
//
// Пуш — только будильник: в Google уходит `{type: "sync", event: <id>}`, а
// само событие телефон забирает с нашего сервера по id. Здесь чистая логика:
// какие изменения достойны пуша и кому он адресован.
package wake

// Record — то, что нужно знать о записи.
type Record interface {
	CollectionName() string
	String(field string) string
}

// author — поле автора записи: его самого не будим.
var author = map[string]string{
	"chat_messages": "user_uid",
	"mood_entries":  "user_uid",
	"miss_you":      "user_uid",
	"memories":      "author_uid",
}

// Targets — кого будить. [members] — участники пары записи (по `group_id`);
// их ищет вызывающий, только если [NeedsMembers] вернул true.
//
// Повторяет PbPushService клиента: о чём он рисует уведомление, о том и
// будим. Настройки уведомлений и «тихую ночь» проверяет телефон.
func Targets(event string, r Record, members []string) []string {
	switch r.CollectionName() {
	case "gifts":
		if event != "create" || r.String("state") != "sent" {
			return nil
		}
		return nonEmpty(r.String("recipient_uid"))
	case "chat_messages", "memories":
		if event != "create" {
			return nil
		}
	case "mood_entries", "miss_you":
		if event != "create" && event != "update" {
			return nil
		}
	default:
		return nil
	}
	who := r.String(author[r.CollectionName()])
	var out []string
	for _, uid := range members {
		if uid != "" && uid != who {
			out = append(out, uid)
		}
	}
	return out
}

// NeedsMembers — нужны ли [Targets] участники пары. Подарку они не нужны,
// а запросу в базу ради записи, которая никого не будит, незачем.
func NeedsMembers(event string, r Record) bool {
	switch r.CollectionName() {
	case "chat_messages", "memories":
		return event == "create"
	case "mood_entries", "miss_you":
		return event == "create" || event == "update"
	}
	return false
}

func nonEmpty(uid string) []string {
	if uid == "" {
		return nil
	}
	return []string{uid}
}
