package pocketbase

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
	"github.com/pocketbase/pocketbase/tools/types"
	"github.com/spf13/cast"

	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
)

// economyFields — поля `users`, которые ведут только серверные пути (монеты,
// покупки, награды, пробы). Правило коллекции пускает владельца писать в
// свою запись любое поле, поэтому клиенту разрешено прислать их лишь пустыми.
var economyFields = []string{
	"coins", "owned_themes", "owned_icons", "owned_features", "granted_badges",
	"dev_coins_granted", "ad_rewards_date", "ad_rewards_today",
	"last_daily_bonus_ms", "last_memory_reward_ms",
	"last_daily_bonus_at", "last_memory_reward_at",
	"partner_invite_reward_granted", "partner_invite_rewarded_keys",
	"mood_streak_rewards",
	"plus", "plus_platform", "last_plus_grant_ms", "plus_trial_until",
	"ad_grants", "ad_views_date", "ad_views_today",
}

// adCounters пустым значением не обходятся: ноль или пустая дата обнуляют
// суточный потолок. Клиент их только читает — любое появление в теле отказ.
var adCounters = []string{"ad_rewards_date", "ad_rewards_today", "ad_views_date", "ad_views_today", "ad_grants"}

// bindUsersGuard — страж записи `users` (бывший users_guard.pb.js): чужую
// запись не правят, экономику клиент не пишет, бан-лист почты при
// регистрации; смена имени или аватара доезжает до записей пар.
func bindUsersGuard(app core.App) {
	svc := pairs.New(app)
	app.OnRecordUpdateRequest("users").BindFunc(func(e *core.RecordRequestEvent) error {
		if e.HasSuperuserAuth() {
			return e.Next()
		}
		if e.Auth == nil || e.Record.Id != e.Auth.Id {
			return router.NewApiError(http.StatusForbidden, "cannot update other user's record", nil)
		}
		body := requestBody(e)
		if err := checkEconomy(body); err != nil {
			return err
		}
		for k := range body {
			if slices.Contains(adCounters, fieldName(k)) {
				return router.NewApiError(http.StatusForbidden, "read-only economy field", nil)
			}
		}
		orig := e.Record.Original()
		prevAvatar, prevName := orig.GetString("avatar_url"), orig.GetString("display_name")
		if err := e.Next(); err != nil {
			return err
		}
		syncMemberProfile(e.App, svc, e.Record, prevAvatar, prevName)
		return nil
	})

	app.OnRecordCreateRequest("users").BindFunc(func(e *core.RecordRequestEvent) error {
		if e.HasSuperuserAuth() {
			return e.Next()
		}
		body := requestBody(e)
		if email, _ := body["email"].(string); email != "" && emailBanned(e.App, email) {
			return router.NewApiError(http.StatusForbidden, "registration blocked", nil)
		}
		if err := checkEconomy(body); err != nil {
			return err
		}
		return e.Next()
	})
}

func requestBody(e *core.RecordRequestEvent) map[string]any {
	info, err := e.RequestInfo()
	if err != nil || info.Body == nil {
		return map[string]any{}
	}
	return info.Body
}

// checkEconomy отказывает, если клиент прислал непустое поле экономики.
// Сверяем тело запроса, а не запись: присланное пустым — дефолт схемы.
// Поле с модификатором (`coins+`, `+owned_themes`) — всегда отказ: оно
// меняет значение, а не задаёт его.
func checkEconomy(body map[string]any) error {
	for k, v := range body {
		f := fieldName(k)
		if slices.Contains(economyFields, f) && (k != f || !emptyValue(v)) {
			return router.NewApiError(http.StatusForbidden, "read-only economy field", nil)
		}
	}
	return nil
}

// fieldName — имя поля без модификатора PocketBase: `coins+`, `coins-`,
// `+tags` и `slug:autogenerate` пишут в то же поле, что и `coins`, `tags`,
// `slug`. Стражи, сверяющие тело запроса по имени, смотрят на него.
func fieldName(key string) string {
	key, _, _ = strings.Cut(key, ":")
	key = strings.TrimPrefix(key, "+")
	return strings.TrimRight(key, "+-")
}

func emptyValue(v any) bool {
	if v == nil {
		return true
	}
	// JSON-поля приходят сырыми байтами.
	if raw, ok := v.(types.JSONRaw); ok {
		var x any
		return len(raw) == 0 || (json.Unmarshal(raw, &x) == nil && emptyValue(x))
	}
	// Остальное — разобранным по типам полей: числа, срезы, карты разных
	// типов, поэтому через reflect, а не перечнем.
	switch rv := reflect.ValueOf(v); rv.Kind() {
	case reflect.String, reflect.Slice, reflect.Map, reflect.Array:
		return rv.Len() == 0
	case reflect.Bool:
		return !rv.Bool()
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64,
		reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64,
		reflect.Float32, reflect.Float64:
		return cast.ToFloat64(v) == 0
	}
	return false
}

// emailBanned — почта в бан-листе pb_data/.banned_emails (по адресу в
// строке, правится без перезапуска). Нет файла — регистрация открыта.
func emailBanned(app core.App, email string) bool {
	raw, err := os.ReadFile(filepath.Join(app.DataDir(), ".banned_emails"))
	if err != nil {
		return false
	}
	email = strings.ToLower(strings.TrimSpace(email))
	return slices.ContainsFunc(strings.Split(string(raw), "\n"), func(s string) bool {
		return strings.ToLower(strings.TrimSpace(s)) == email
	})
}

// syncMemberProfile — новое имя или аватар в member_names/member_avatars
// всех живых пар человека: партнёр читает их из записи пары, а клиентская
// правка карт иногда терялась. Шифр личным ключом (E2E) в пару не идёт —
// туда клиент пишет шифр ключа пары сам.
func syncMemberProfile(app core.App, svc *pairs.Service, u *core.Record, prevAvatar, prevName string) {
	avatar, name := u.GetString("avatar_url"), u.GetString("display_name")
	if strings.HasPrefix(avatar, "e2e1.") || strings.HasPrefix(name, "e2e1.") {
		return
	}
	if avatar == prevAvatar && name == prevName {
		return
	}
	groups, err := svc.GroupsOfUser(u.Id, true)
	if err != nil {
		app.Logger().Error("профиль в пары не доехал", "uid", u.Id, "err", err)
		return
	}
	for _, g := range groups {
		maps := map[string]map[string]any{}
		if avatar != "" && memberValue(g, "member_avatars", u.Id) != avatar {
			maps["member_avatars"] = map[string]any{u.Id: avatar}
		}
		if name != "" && memberValue(g, "member_names", u.Id) != name {
			maps["member_names"] = map[string]any{u.Id: name}
		}
		if len(maps) == 0 {
			continue
		}
		if _, err := svc.Write(context.Background(), pairs.WriteInput{GroupID: g.Id, MapSet: maps}); err != nil {
			app.Logger().Error("профиль в пару не доехал", "uid", u.Id, "group", g.Id, "err", err)
		}
	}
}

func memberValue(g *core.Record, field, uid string) string {
	m := map[string]any{}
	_ = g.UnmarshalJSONField(field, &m)
	s, _ := m[uid].(string)
	return s
}
