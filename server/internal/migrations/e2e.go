package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Коллекции E2E (docs/fork/E2E.md §5–7, PLAN S8). Сервер хранит и раздаёт
// публичные ключи и шифртекст ключей; подделать их не может — подписи и
// MAC проверяет клиент. Стражи на Go — infrastructure/pocketbase/e2e.go.
func init() {
	m.Register(func(app core.App) error {
		for _, build := range []func() *core.Collection{e2eIdentities, e2eGrants, e2eHandshake, e2eBackups} {
			col := build()
			if _, err := app.FindCollectionByNameOrId(col.Name); err == nil {
				continue
			}
			if err := app.Save(col); err != nil {
				return err
			}
		}
		return ApplyRules(app)
	}, nil, "1760000002_e2e_keys.go")
}

// e2e_identities — ключ аккаунта и подписанный им список устройств, по
// записи на человека. `devices` — DeviceList из lib/fork/e2e/devices.dart.
func e2eIdentities() *core.Collection {
	col := base("e2e_identities")
	col.Fields.Add(
		&core.TextField{Name: "user_uid", Required: true},
		&core.TextField{Name: "account_key", Required: true, Max: 64},
		&core.NumberField{Name: "version", OnlyInt: true},
		&core.JSONField{Name: "devices", MaxSize: 64 << 10},
	)
	col.AddIndex("uq_e2e_identities_user", true, "user_uid", "")
	return col
}

// e2e_grants — ключ пары эпохи `epoch`, выданный устройству `to_device`
// человека `to_uid` устройством автора `user_uid` (PairKeyGrant).
func e2eGrants() *core.Collection {
	col := base("e2e_grants")
	col.Fields.Add(
		&core.TextField{Name: "group_id", Required: true},
		&core.TextField{Name: "user_uid", Required: true},
		&core.TextField{Name: "to_uid", Required: true},
		&core.TextField{Name: "to_device", Required: true, Max: 64},
		&core.NumberField{Name: "epoch", OnlyInt: true, Min: ptr(1.0)},
		&core.JSONField{Name: "data", MaxSize: 8 << 10},
	)
	col.AddIndex("uq_e2e_grants", true, "group_id, epoch, to_device", "")
	col.AddIndex("idx_e2e_grants_to", false, "to_uid", "")
	return col
}

// e2e_handshake — сообщения обмена ключами внутри пары: подтверждение
// приглашения (§6.2) и шаги сверки эмодзи (§6.3). Короткоживущие.
func e2eHandshake() *core.Collection {
	col := base("e2e_handshake")
	col.Fields.Add(
		&core.TextField{Name: "group_id", Required: true},
		&core.TextField{Name: "user_uid", Required: true},
		&core.TextField{Name: "session", Required: true, Max: 64},
		&core.SelectField{Name: "kind", Required: true, MaxSelect: 1, Values: []string{
			"invite_proof", "sas_start", "sas_accept", "sas_reveal", "sas_done", "sas_cancel",
		}},
		&core.JSONField{Name: "data", MaxSize: 64 << 10},
	)
	col.AddIndex("idx_e2e_handshake_group", false, "group_id, created", "")
	return col
}

// e2e_backups — бэкап ключей (§7): соль, параметры Argon2id и шифртекст.
func e2eBackups() *core.Collection {
	col := base("e2e_backups")
	col.Fields.Add(
		&core.TextField{Name: "user_uid", Required: true},
		&core.JSONField{Name: "data", MaxSize: 1 << 20},
	)
	col.AddIndex("uq_e2e_backups_user", true, "user_uid", "")
	return col
}

func ptr[T any](v T) *T { return &v }

// e2eSealedFields — текстовые поля, которые клиент шифрует на месте
// (lib/fork/e2e/record_codec.dart, PLAN S9). Шифртекст длиннее текста: UTF-8,
// тег, nonce и base64 — до 4/3 от байтов плюс ~60 символов. Стандартный
// предел PocketBase в 5000 символов кириллическое сообщение в 5000 знаков
// уже не пропустит.
var e2eSealedFields = map[string][]string{
	"chat_messages": {"user_name", "text", "pin_title", "reply_to_name", "reply_to_text"},
}

// E2ESealedMax — предел длины шифрованного поля.
const E2ESealedMax = 32000

func init() {
	m.Register(func(app core.App) error {
		return widenSealed(app, e2eSealedFields)
	}, nil, "1760000003_e2e_sealed_fields.go")
	m.Register(func(app core.App) error {
		return widenSealed(app, map[string][]string{"memory_comments": {"text"}})
	}, nil, "1760000005_e2e_sealed_comments.go")
	m.Register(func(app core.App) error {
		return widenSealed(app, e2eSealedRest)
	}, nil, "1760000006_e2e_sealed_rest.go")
}

// e2eSealedRest — поля шага 4 (PLAN S9): желания, рисунки, настроения,
// виджеты, «скучаю».
var e2eSealedRest = map[string][]string{
	"wishes":           {"title", "note", "done_note", "url", "image", "shop", "symbol"},
	"wish_categories":  {"title", "note", "symbol"},
	"canvas_catalogue": {"name"},
	"mood_entries":     {"mood_id", "label", "image_path"},
	"custom_moods":     {"label", "emoji"},
	"widget_data": {"status", "mood_emoji", "mood_label", "message", "music_title", "music_artist",
		"music_url", "music_cover_url", "photo_url", "photo_for_partner_url"},
	"miss_you":        {"last_vibe_text"},
	"miss_you_events": {"text"},
}

// widenSealed поднимает предел длины текстовых полей до E2ESealedMax.
func widenSealed(app core.App, sealed map[string][]string) error {
	for name, fields := range sealed {
		col, err := app.FindCollectionByNameOrId(name)
		if err != nil {
			continue // коллекции нет — схема ещё не накатана, нечего расширять
		}
		changed := false
		for _, f := range fields {
			tf, ok := col.Fields.GetByName(f).(*core.TextField)
			if !ok || (tf.Max >= E2ESealedMax) {
				continue
			}
			tf.Max = E2ESealedMax
			changed = true
		}
		if !changed {
			continue
		}
		if err := app.Save(col); err != nil {
			return err
		}
	}
	return nil
}

func init() {
	m.Register(func(app core.App) error {
		return addEncField(app, "cycle_entries")
	}, nil, "1760000004_e2e_moved_fields.go")
	m.Register(func(app core.App) error {
		return addEncField(app, "groups")
	}, nil, "1760000007_e2e_moved_groups.go")
	// «Шифровать всё» (docs/fork/E2E.md, дополнение 2026-10-23): ссылки и
	// облик сообщений, авторы воспоминаний, вещи желаний, раскраски, маскоты.
	m.Register(func(app core.App) error {
		if err := widenSealed(app, e2eSealedMax); err != nil {
			return err
		}
		if err := addEncField(app, "chat_messages", "wishes", "canvas_meta"); err != nil {
			return err
		}
		return addMemberCards(app)
	}, nil, "1760000008_e2e_sealed_max.go")
}

// e2eSealedMax — поля, добавленные к шифруемым в «шифровать всё».
var e2eSealedMax = map[string][]string{
	"chat_messages": {"pin_thumb", "voice_url", "voice_peaks", "note_url", "note_thumb",
		"note_shape", "note_hearts", "face"},
	"memories":        {"author_name", "author_avatar"},
	"memory_comments": {"author_name", "author_avatar"},
	"wishes":          {"kind", "category", "currency"},
	"canvas_meta":     {"coloring_id", "coloring_mode", "coloring_outline"},
	"mascots":         {"name", "image_url"},
	"groups":          {"chat_background", "placeholder_name", "placeholder_avatar"},
	"gifts":           {"note", "reply", "place", "date", "photo", "sound", "sound_meta"},
	"users":           {"name", "display_name", "avatar_url", "banner_url", "gender", "birth_date"},
	"watch_history":   {"url", "title", "thumb", "kind"},
	"watch_videos":    {"title"},
}

// addMemberCards заводит groups.member_cards: карточка профиля каждого
// участника для партнёра (баннер, пол, день рождения) шифром ключа пары —
// сам профиль в users зашифрован личным ключом и партнёру не виден.
func addMemberCards(app core.App) error {
	col, err := app.FindCollectionByNameOrId("groups")
	if err != nil {
		return nil
	}
	if col.Fields.GetByName("member_cards") != nil {
		return nil
	}
	col.Fields.Add(&core.JSONField{Name: "member_cards", MaxSize: jsonMax})
	return app.Save(col)
}

// addEncField заводит текстовое поле `enc`: туда клиент переносит поля,
// которые на месте не зашифровать (даты; SealKind.moved).
func addEncField(app core.App, names ...string) error {
	for _, name := range names {
		col, err := app.FindCollectionByNameOrId(name)
		if err != nil {
			continue
		}
		if col.Fields.GetByName("enc") != nil {
			continue
		}
		col.Fields.Add(&core.TextField{Name: "enc", Max: E2ESealedMax})
		if err := app.Save(col); err != nil {
			return err
		}
	}
	return nil
}
