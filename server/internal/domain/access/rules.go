// Package access — правила доступа API ко всем коллекциям в одном месте.
//
// Апстрим держал их в двух расходящихся местах: в
// pocketbase/collections_schema.json (через `@request.auth.group_ids`) и в
// pocketbase/apply_acl.py (через join к groups). Форк берёт первый вариант —
// он опирается на скрытое поле `users.group_ids`, которое ведёт хук
// bindMembership, и не требует тяжёлых join'ов. Миграция применяет эти
// правила поверх импортированной схемы, так что источник истины — этот файл.
//
// Правило — фильтр PocketBase. nil — доступ только суперпользователю
// (и серверному коду через $app.save), "" — доступ всем.
package access

// Rules — пять правил коллекции.
type Rules struct {
	List, View, Create, Update, Delete *string
}

const authed = `@request.auth.id != ""`

func s(v string) *string { return &v }

// same — одно правило на все пять операций.
func same(expr string) Rules {
	return Rules{List: s(expr), View: s(expr), Create: s(expr), Update: s(expr), Delete: s(expr)}
}

// readOnly — читать могут по expr, писать — только сервер.
func readOnly(expr string) Rules {
	return Rules{List: s(expr), View: s(expr)}
}

// member — запись принадлежит паре из поля groupField: читать и писать
// могут только её участники.
func member(groupField string) Rules {
	r := readOnly(memberExpr(groupField))
	r.Create = s(liveMemberExpr(groupField))
	r.Update = s(liveMemberExpr(groupField))
	r.Delete = s(liveMemberExpr(groupField))
	return r
}

func memberExpr(groupField string) string {
	return authed + ` && @request.auth.group_ids.id ?= ` + groupField
}

func liveMemberExpr(groupField string) string {
	return authed + ` && @request.auth.live_group_ids.id ?= ` + groupField
}

// memberAuthored — как member, но создать запись можно только от своего
// имени. Автор и пара неизменны; совместные поля ограничивает страж.
func memberAuthored(groupField, authorField string) Rules {
	r := member(groupField)
	r.Create = s(liveMemberExpr(groupField) + ` && ` + authorField + ` = @request.auth.id`)
	r.Update = s(liveMemberExpr(groupField) + ` && @request.body.` + groupField + `:changed = false && @request.body.` + authorField + `:changed = false`)
	return r
}

// Personal state is readable by the pair, writable only by its author.
func personalAuthored(groupField, authorField string) Rules {
	r := memberAuthored(groupField, authorField)
	r.Update = s(*r.Update + ` && ` + authorField + ` = @request.auth.id`)
	r.Delete = s(liveMemberExpr(groupField) + ` && ` + authorField + ` = @request.auth.id`)
	return r
}

// A shared choice additionally has an immutable deduplication tag.
func privateLiveAuthored(groupField, authorField, tagField string) Rules {
	r := memberAuthored(groupField, authorField)
	ownLive := liveMemberExpr(groupField) + ` && ` + authorField + ` = @request.auth.id`
	r.Update = s(ownLive + ` && @request.body.` + groupField + `:changed = false` +
		` && @request.body.` + authorField + `:changed = false` +
		` && @request.body.` + tagField + `:changed = false`)
	r.Delete = s(ownLive)
	return r
}

// Matches are append-only: no rewriting a clip, author or deduplication tag.
func immutableAuthored(groupField, authorField string) Rules {
	r := memberAuthored(groupField, authorField)
	r.Update = nil
	return r
}

// own — запись принадлежит человеку из поля ownerField.
func own(ownerField string) Rules {
	return same(authed + ` && ` + ownerField + ` = @request.auth.id`)
}

// Collections — правила форка. Коллекции, которых здесь нет, не создаются
// (их нет и в схеме форка, см. migrations.Dropped).
var Collections = map[string]Rules{
	// Пара. Список и чтение — по своему members (до появления group_ids у
	// создателя группа уже должна быть ему видна). Состав при правке
	// защищает bindGroupsGuard, при создании — страж на Go (только ты).
	"groups": {
		List:   s(authed + ` && members ?~ @request.auth.id`),
		View:   s(authed + ` && members ?~ @request.auth.id`),
		Create: s(authed + ` && members ?~ @request.auth.id && disbanded = false`),
		Update: s(liveMemberExpr("id")),
		Delete: s(liveMemberExpr("id")),
	},

	// Своя запись пользователя: остальных видно только через /api/user/card.
	"users": {
		List:   s(`id = @request.auth.id`),
		View:   s(`id = @request.auth.id`),
		Create: s(""), // регистрация по почте открыта
		Update: s(`id = @request.auth.id`),
	},

	"invite_codes": own("owner_uid"),

	"memories":        memberAuthored("group_id", "author_uid"),
	"memory_comments": personalAuthored("group_id", "author_uid"),
	"wish_comments":   personalAuthored("group_id", "author_uid"),
	"mood_entries":    personalAuthored("group_id", "user_uid"),
	"chat_messages":   memberAuthored("group_id", "user_uid"),
	"chat_reads":      personalAuthored("group_id", "user_uid"),
	"chat_typing":     personalAuthored("group_id", "user_uid"),
	"widget_data":     personalAuthored("group_id", "user_uid"),
	"miss_you":        personalAuthored("group_id", "user_uid"),
	"wish_categories": memberAuthored("group_id", "author_uid"),
	"custom_moods":    memberAuthored("group_id", "author_uid"),
	"love_tests":      personalAuthored("group_id", "user_uid"),
	// Форк: заряд телефона — пишет только сам участник, читает пара.
	"fork_battery":       personalAuthored("group_id", "user_uid"),
	"fork_reels_matches": immutableAuthored("group_id", "author_uid"),
	"fork_movie_choices": privateLiveAuthored("group_id", "author_uid", "movie_tag"),

	"canvas_strokes":   member("group_id"),
	"canvas_meta":      member("group_id"),
	"canvas_catalogue": member("group_id"),
	"canvas_live":      member("group_id"),
	"mascots":          member("group_id"),
	"watch_history":    member("group_id"),
	"watch_videos":     member("group_id"),

	"miss_you_events": readOnly(memberExpr("group_id")),
	"gifts":           readOnly(memberExpr("group_id")),
	"chest_opens":     readOnly(authed + ` && user_uid = @request.auth.id`),

	// Совместный просмотр: сессия — по своему id (он же id группы).
	"live_sessions":         member("id"),
	"live_session_presence": personalAuthored("pair_id", "user_uid"),
	"live_session_chat":     memberAuthored("pair_id", "uid"),

	// Цикл: партнёр видит только то, чем поделились.
	"cycle_entries": {
		List:   s(memberExpr("group_id") + ` && (user_uid = @request.auth.id || shared = true)`),
		View:   s(memberExpr("group_id") + ` && (user_uid = @request.auth.id || shared = true)`),
		Create: s(liveMemberExpr("group_id") + ` && user_uid = @request.auth.id`),
		Update: s(liveMemberExpr("group_id") + ` && user_uid = @request.auth.id`),
		Delete: s(liveMemberExpr("group_id") + ` && user_uid = @request.auth.id`),
	},

	"wishes": {
		List:   s(memberExpr("group_id")),
		View:   s(memberExpr("group_id")),
		Create: s(liveMemberExpr("group_id") + ` && author_uid = @request.auth.id`),
		Update: s(*memberAuthored("group_id", "author_uid").Update),
		Delete: s(liveMemberExpr("group_id") + ` && author_uid = @request.auth.id`),
	},
	"wish_reservations": {
		List:   s(authed + ` && uid = @request.auth.id`),
		View:   s(authed + ` && uid = @request.auth.id`),
		Create: s(liveMemberExpr("group_id") + ` && uid = @request.auth.id`),
		Update: s(liveMemberExpr("group_id") + ` && uid = @request.auth.id`),
		Delete: s(liveMemberExpr("group_id") + ` && uid = @request.auth.id`),
	},

	// Присутствие видят только участники твоих пар (у апстрима — любой
	// вошедший, AUDIT §2).
	"user_presence": {
		List:   s(authed + ` && (user_uid = @request.auth.id || @request.auth.live_group_ids.members ?~ user_uid)`),
		View:   s(authed + ` && (user_uid = @request.auth.id || @request.auth.live_group_ids.members ?~ user_uid)`),
		Create: s(authed + ` && user_uid = @request.auth.id`),
		Update: s(authed + ` && user_uid = @request.auth.id`),
		Delete: s(authed + ` && user_uid = @request.auth.id`),
	},

	// Аватары и баннеры видят только участники твоих пар (у апстрима —
	// любой вошедший, AUDIT §2).
	"media": {
		List: s(authed + ` && (uid = @request.auth.id || @request.auth.live_group_ids.id ?= group_id || @request.auth.live_group_ids.members ?~ uid)`),
		View: s(authed + ` && (uid = @request.auth.id || @request.auth.live_group_ids.id ?= group_id || @request.auth.live_group_ids.members ?~ uid)`),
		// Апстрим пускал создать запись с чужим group_id, если uid — свой
		// (условие через «или»): посторонний подкладывал файл в чужую пару.
		// Теперь автор — всегда ты, а пара — только твоя. group_id = свой id —
		// путь аватара `avatars/<uid>/…` (lib/services/media_service.dart).
		Create: s(authed + ` && uid = @request.auth.id && (group_id = "" || group_id = @request.auth.id || @request.auth.live_group_ids.id ?= group_id)`),
		Update: s(authed + ` && ((uid = @request.auth.id && (group_id = "" || group_id = @request.auth.id)) || @request.auth.live_group_ids.id ?= group_id)`),
		Delete: s(authed + ` && ((uid = @request.auth.id && (group_id = "" || group_id = @request.auth.id)) || @request.auth.live_group_ids.id ?= group_id)`),
	},

	// Геопозиция. Канал — `pair_<uidA>_<uidB>` или id группы (если партнёр
	// неизвестен). В апстриме создать точку можно было в любом канале (AUDIT
	// §2): createRule проверял только автора. Теперь канал обязан быть своим;
	// что `pair_a_b` — настоящая пара автора, проверяет страж на Go
	// (infrastructure/pocketbase/guards.go).
	"live_location": {
		List:   s(authed + ` && (channel ~ @request.auth.id || @request.auth.group_ids.id ?= channel)`),
		View:   s(authed + ` && (channel ~ @request.auth.id || @request.auth.group_ids.id ?= channel)`),
		Create: s(authed + ` && user_uid = @request.auth.id && (channel ~ @request.auth.id || @request.auth.group_ids.id ?= channel)`),
		Update: s(authed + ` && user_uid = @request.auth.id && (channel ~ @request.auth.id || @request.auth.group_ids.id ?= channel)`),
		Delete: s(authed + ` && user_uid = @request.auth.id`),
	},

	// E2E (docs/E2E.md). Ключ аккаунта и список устройств видят свои и
	// партнёры по парам; правка — только своя, версию списка держит страж.
	"e2e_identities": {
		List:   s(authed + ` && (user_uid = @request.auth.id || @request.auth.live_group_ids.members ?~ user_uid)`),
		View:   s(authed + ` && (user_uid = @request.auth.id || @request.auth.live_group_ids.members ?~ user_uid)`),
		Create: s(authed + ` && user_uid = @request.auth.id`),
		Update: s(authed + ` && user_uid = @request.auth.id`),
	},
	// Выданный ключ пары видят выдавший и получатель. Выдать — только в своей
	// паре и от своего имени; что получатель — участник пары, проверяет страж.
	// Править нельзя: выдача неизменна, новая эпоха — новая запись.
	"e2e_grants": {
		List:   s(authed + ` && (to_uid = @request.auth.id || user_uid = @request.auth.id)`),
		View:   s(authed + ` && (to_uid = @request.auth.id || user_uid = @request.auth.id)`),
		Create: s(liveMemberExpr("group_id") + ` && user_uid = @request.auth.id`),
	},
	"e2e_handshake": {
		List:   s(memberExpr("group_id")),
		View:   s(memberExpr("group_id")),
		Create: s(liveMemberExpr("group_id") + ` && user_uid = @request.auth.id`),
		Delete: s(liveMemberExpr("group_id") + ` && user_uid = @request.auth.id`),
	},
	"e2e_backups": own("user_uid"),
	// Привязка устройства по QR (§5.3): только свои записи.
	"e2e_links": own("user_uid"),

	// Токены FCM устройств (PLAN S12): пишет и читает только сервер через
	// /api/fork/push-token — чужой токен не прочитать и не подменить.
	"push_tokens": {},

	// Справочники: читают все, пишет сервер.
	"catalog_items": readOnly(""),
	"app_config":    readOnly(""),

	// Копилка пары живёт от рекламы, которой в форке нет; коллекция остаётся,
	// пока на неё ссылаются хуки сундука (см. API_INVENTORY.md). Только сервер.
	"pair_jars": {},
}
