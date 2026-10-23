// Package migrations — схема базы форка (S4).
//
// Первая миграция поднимает пустую базу до схемы, с которой работает клиент:
//
//  1. коллекции из pocketbase/collections_schema.json апстрима, кроме
//     выкинутых ([Dropped]);
//  2. поля встроенной коллекции users, которых в той схеме нет;
//  3. коллекции, которых нет в схеме апстрима: custom_moods (создан на проде
//     руками), love_tests и miss_you_events (жили в hotpath/Postgres);
//  4. правила доступа из domain/access — поверх всего, что пришло из схемы.
package migrations

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"

	"github.com/m0nstrum/togetherly/server/internal/domain/access"
	"github.com/m0nstrum/togetherly/server/internal/migrations/schema"
)

// Dropped — коллекции апстрима, которых в форке нет (API_INVENTORY.md §4).
var Dropped = map[string]bool{
	"iap_purchases":   true,
	"redeem_codes":    true,
	"wallet_waitlist": true,
	"migration_flags": true,
}

func init() {
	m.Register(up, nil, "1760000000_tethered_init.go")
}

func up(app core.App) error {
	if err := importUpstream(app); err != nil {
		return fmt.Errorf("схема апстрима: %w", err)
	}
	if err := extendUsers(app); err != nil {
		return fmt.Errorf("поля users: %w", err)
	}
	for _, build := range []func(core.App) (*core.Collection, error){customMoods, loveTests, missYouEvents} {
		col, err := build(app)
		if err != nil {
			return err
		}
		if err := app.Save(col); err != nil {
			return fmt.Errorf("коллекция %s: %w", col.Name, err)
		}
	}
	return ApplyRules(app)
}

func importUpstream(app core.App) error {
	var doc struct {
		Collections []map[string]any `json:"collections"`
	}
	if err := json.Unmarshal(schema.UpstreamJSON, &doc); err != nil {
		return err
	}
	keep := make([]map[string]any, 0, len(doc.Collections))
	for _, c := range doc.Collections {
		name, _ := c["name"].(string)
		if Dropped[name] {
			continue
		}
		withAutodates(c)
		keep = append(keep, c)
	}
	data, err := json.Marshal(keep)
	if err != nil {
		return err
	}
	return app.ImportCollectionsByMarshaledJSON(data, false)
}

// withAutodates добавляет created/updated, если их нет. Генератор схемы
// апстрима (gen_schema.py) не выгрузил их у коллекций, созданных старой
// версией PocketBase, хотя на проде они есть: на них стоят индексы, а клиент
// синхронизируется по `updated`.
func withAutodates(c map[string]any) {
	fields, _ := c["fields"].([]any)
	has := map[string]bool{}
	for _, f := range fields {
		if m, ok := f.(map[string]any); ok {
			name, _ := m["name"].(string)
			has[name] = true
		}
	}
	for _, d := range []struct {
		name     string
		onUpdate bool
	}{{"created", false}, {"updated", true}} {
		if !has[d.name] {
			fields = append(fields, map[string]any{
				"name": d.name, "type": "autodate", "onCreate": true, "onUpdate": d.onUpdate,
			})
		}
	}
	c["fields"] = fields
}

// ApplyRules ставит правила из domain/access. У каждой коллекции схемы
// правило обязано быть описано: забытая коллекция — ошибка, а не тихий
// доступ «только суперпользователю» или «всем».
func ApplyRules(app core.App) error {
	cols, err := app.FindAllCollections()
	if err != nil {
		return err
	}
	var errs []error
	for _, col := range cols {
		if col.System {
			continue
		}
		r, ok := access.Collections[col.Name]
		if !ok {
			errs = append(errs, fmt.Errorf("нет правил доступа для %q (domain/access)", col.Name))
			continue
		}
		col.ListRule, col.ViewRule = r.List, r.View
		col.CreateRule, col.UpdateRule, col.DeleteRule = r.Create, r.Update, r.Delete
		if err := app.Save(col); err != nil {
			errs = append(errs, fmt.Errorf("правила %s: %w", col.Name, err))
		}
	}
	return errors.Join(errs...)
}

const jsonMax = 5_000_000

func extendUsers(app core.App) error {
	users, err := app.FindCollectionByNameOrId("users")
	if err != nil {
		return err
	}
	groups, err := app.FindCollectionByNameOrId("groups")
	if err != nil {
		return err
	}
	add := func(f core.Field) {
		if users.Fields.GetByName(f.GetName()) == nil {
			users.Fields.Add(f)
		}
	}
	for _, n := range []string{
		"display_name", "avatar_url", "banner_url", "gender", "birth_date", "badge", "frame",
		"pair_id", "invite_code", "notif_synced_at", "task_rewards_date", "ad_rewards_date",
	} {
		add(&core.TextField{Name: n})
	}
	for _, n := range []string{
		"coins", "theme_mode", "theme_id", "last_daily_bonus_ms", "last_memory_reward_ms",
		"last_plus_grant_ms", "plus_trial_until", "ad_rewards_today",
	} {
		add(&core.NumberField{Name: n})
	}
	for _, n := range []string{
		"plus", "dev_coins_granted", "partner_invite_reward_granted",
		"notif_miss_you", "notif_new_memory", "notif_mood", "notif_chat", "notif_draw",
		"notif_comments", "notif_chest_off",
	} {
		add(&core.BoolField{Name: n})
	}
	for _, n := range []string{
		"pair_ids", "solo_timers", "mascot_sleep", "custom_themes", "miss_you_wishes",
		"owned_features", "owned_icons", "owned_themes", "granted_badges", "task_rewards_ids",
		"partner_invite_rewarded_keys", "mood_streak_rewards", "ad_grants",
	} {
		add(&core.JSONField{Name: n, MaxSize: jsonMax})
	}
	// Пары пользователя. Ведёт хук groups_membership, на нём держатся правила
	// доступа всех парных коллекций. Клиенту не отдаётся.
	add(&core.RelationField{Name: "live_group_ids", CollectionId: groups.Id, MaxSelect: 1000, Hidden: true})
	add(&core.RelationField{Name: "group_ids", CollectionId: groups.Id, MaxSelect: 1000, Hidden: true})
	return app.Save(users)
}

func base(name string) *core.Collection {
	col := core.NewBaseCollection(name)
	col.Fields.Add(
		&core.AutodateField{Name: "created", OnCreate: true},
		&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
	)
	return col
}

// custom_moods — свои настроения пары: картинка 512×512 и подпись
// (lib/services/custom_mood_service.dart).
func customMoods(core.App) (*core.Collection, error) {
	col := base("custom_moods")
	col.Fields.Add(
		&core.TextField{Name: "group_id", Required: true},
		&core.TextField{Name: "author_uid", Required: true},
		&core.TextField{Name: "mood_id", Required: true},
		&core.TextField{Name: "label", Max: 64},
		&core.TextField{Name: "emoji", Max: 32},
		&core.NumberField{Name: "score"},
		&core.NumberField{Name: "sort"},
		&core.FileField{Name: "image", MaxSelect: 1, MaxSize: 2 << 20, MimeTypes: []string{"image/png", "image/webp", "image/jpeg"}},
	)
	col.AddIndex("idx_custom_moods_group", false, "group_id, sort", "")
	return col, nil
}

// love_tests — ответы теста пары (pocketbase/hotpath/love_mascots_tables.sql).
func loveTests(core.App) (*core.Collection, error) {
	col := base("love_tests")
	col.Fields.Add(
		&core.TextField{Name: "group_id", Required: true},
		&core.TextField{Name: "user_uid", Required: true},
		&core.JSONField{Name: "data", MaxSize: jsonMax},
		&core.NumberField{Name: "total"},
	)
	col.AddIndex("uq_love_tests_group_user", true, "group_id, user_uid", "")
	return col, nil
}

// miss_you_events — история импульсов «Скучаю», живёт трое суток
// (pocketbase/hotpath/miss_you_events.sql). Пишет только сервер.
func missYouEvents(core.App) (*core.Collection, error) {
	col := base("miss_you_events")
	col.Fields.Add(
		&core.TextField{Name: "group_id", Required: true},
		&core.TextField{Name: "user_uid", Required: true},
		&core.TextField{Name: "vibe", Required: true},
		&core.TextField{Name: "text"},
		&core.NumberField{Name: "count", OnlyInt: true},
		&core.TextField{Name: "reply_to"},
	)
	col.AddIndex("idx_miss_you_events_group_created", false, "group_id, created", "")
	return col, nil
}
