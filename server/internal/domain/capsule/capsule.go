// Package capsule — «капсула времени»: воспоминание, запечатанное до даты.
//
// У апстрима дата открытия проверялась только на клиенте (AUDIT §1), а сервер
// отдавал содержимое сразу. Здесь правила для сервера: пока капсула
// запечатана, наружу уходят только метаданные, а содержимое нельзя ни
// подменить, ни распечатать раньше срока через API. После E2E (S9) то же
// обеспечит ключ, выданный по времени.
//
// Данные — JSON `memories.data` из lib/models/memory.dart (toJson).
package capsule

import "time"

// visible — ключи data, которые видны и пока капсула запечатана: без них
// лента не нарисует карточку «откроется такого-то».
var visible = map[string]bool{
	"id": true, "groupId": true, "type": true, "authorUid": true, "authorName": true,
	"authorAvatar": true, "createdAt": true, "editedAt": true, "addedAt": true, "tz": true,
	"sealed": true, "openAt": true, "isPinned": true, "savedBy": true, "reactions": true,
	"commentsCount": true, "dailyTaskId": true,
	OpenedMark: true,
}

// sealControls меняет только автор: иначе партнёр распечатал бы капсулу раньше.
var sealControls = []string{"sealed", "openAt"}

// OpenedMark — отметка сервера, что капсула открылась и запись «тронута»,
// чтобы клиенты перечитали её целиком.
const OpenedMark = "capsuleOpened"

// Sealed — запечатана ли капсула в момент now. Битая дата — не капсула.
func Sealed(data map[string]any, now time.Time) bool {
	if data == nil || data["sealed"] != true {
		return false
	}
	s, _ := data["openAt"].(string)
	at, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		return false
	}
	return now.Before(at)
}

// Redact — копия data только с видимыми ключами.
func Redact(data map[string]any) map[string]any {
	out := make(map[string]any, len(visible))
	for k, v := range data {
		if visible[k] {
			out[k] = v
		}
	}
	return out
}

// MergeUpdate — data, которую можно сохранить поверх stored, пока капсула
// запечатана: содержимое берётся из stored (клиент мог прислать обрезанную
// копию), печать и дату меняет только автор.
func MergeUpdate(stored, incoming map[string]any, byAuthor bool) map[string]any {
	out := make(map[string]any, len(stored)+len(incoming))
	for k, v := range incoming {
		if visible[k] {
			out[k] = v
		}
	}
	for k, v := range stored {
		if !visible[k] {
			out[k] = v
		}
	}
	if !byAuthor {
		for _, k := range sealControls {
			if v, ok := stored[k]; ok {
				out[k] = v
			} else {
				delete(out, k)
			}
		}
	}
	delete(out, OpenedMark)
	if v, ok := stored[OpenedMark]; ok {
		out[OpenedMark] = v
	}
	return out
}
