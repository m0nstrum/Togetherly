package pocketbase

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"slices"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
	"github.com/pocketbase/pocketbase/tools/types"
)

// memberMaps — словари пары по участникам: в каждом человек правит только
// свой ключ. Шифр значения привязан к `поле/uid`, а ключ пары у обоих общий,
// так что подделка партнёром открывалась бы как настоящая.
var memberMaps = []string{"member_names", "member_avatars", "member_cards", "member_moods",
	"member_ailments", "member_birthdays"}

// pairingFields — поля ожидания пары: их пишут только роуты приглашений.
var pairingFields = []string{"claim_token", "claim_uid", "claim_name", "claim_at", "waiting_mode"}

// bindGroupsGuard — страж прямой правки записи пары (бывший
// groups_guard.pb.js): в составе можно убрать только себя и никого не
// добавить, в словарях участников — менять только свой ключ, поля ожидания
// пары закрыты. Роуты /api/group/* пишут мимо этого хука.
func bindGroupsGuard(app core.App) {
	app.OnRecordUpdateRequest("groups").BindFunc(func(e *core.RecordRequestEvent) error {
		if e.HasSuperuserAuth() || e.Auth == nil {
			return e.Next()
		}
		body := requestBody(e)
		saved := e.Record.Original()
		me := e.Auth.Id
		deny := func(msg string) error { return router.NewApiError(http.StatusForbidden, msg, nil) }

		if raw, ok := body["members"]; ok {
			var next []string
			if !decodeBody(raw, &next) {
				return deny("members must be a list")
			}
			current := saved.GetStringSlice("members")
			for _, m := range next {
				if !slices.Contains(current, m) {
					return deny("cannot add members directly")
				}
			}
			for _, m := range current {
				if m != me && !slices.Contains(next, m) {
					return deny("cannot remove another member")
				}
			}
		}

		for _, field := range memberMaps {
			raw, ok := body[field]
			if !ok {
				continue
			}
			next := map[string]json.RawMessage{}
			if raw != nil && !decodeBody(raw, &next) {
				return deny(field + " must be an object")
			}
			current := map[string]json.RawMessage{}
			_ = saved.UnmarshalJSONField(field, &current)
			for _, m := range [2]map[string]json.RawMessage{current, next} {
				for k := range m {
					if k == me {
						continue
					}
					was, hadWas := current[k]
					now, hasNow := next[k]
					if hadWas != hasNow || !sameJSON(was, now) {
						return deny("cannot change another member's " + field)
					}
				}
			}
		}

		for _, f := range pairingFields {
			if _, ok := body[f]; ok {
				return deny("read-only pairing field: " + f)
			}
		}
		return e.Next()
	})
}

// decodeBody разбирает значение поля из тела запроса в out: JSON-поля
// приходят сырыми байтами, прочие — уже разобранными.
func decodeBody(raw any, out any) bool {
	var data []byte
	switch x := raw.(type) {
	case types.JSONRaw:
		data = x
	case string:
		data = []byte(x)
	default:
		var err error
		if data, err = json.Marshal(x); err != nil {
			return false
		}
	}
	if len(bytes.TrimSpace(data)) == 0 || string(bytes.TrimSpace(data)) == "null" {
		return true
	}
	return json.Unmarshal(data, out) == nil
}

// sameJSON — одно и то же ли значение, без учёта пробелов и порядка ключей.
func sameJSON(a, b json.RawMessage) bool {
	var x, y any
	if json.Unmarshal(a, &x) != nil || json.Unmarshal(b, &y) != nil {
		return bytes.Equal(a, b)
	}
	ja, _ := json.Marshal(x)
	jb, _ := json.Marshal(y)
	return bytes.Equal(ja, jb)
}

// bindMembership ведёт скрытые users.group_ids (все пары, с распущенными —
// надгробия распада должны долетать) и users.live_group_ids (только
// действующие) — бывший groups_membership.pb.js. На них стоят быстрые
// правила парных коллекций без джойна groups.
func bindMembership(app core.App) {
	resync := func(e *core.RecordEvent, uids []string) {
		seen := map[string]bool{}
		for _, uid := range uids {
			if uid == "" || seen[uid] {
				continue
			}
			seen[uid] = true
			if err := resyncMembership(e.App, uid); err != nil {
				e.App.Logger().Error("членство не пересчитано", "uid", uid, "err", err)
			}
		}
	}
	app.OnRecordAfterCreateSuccess("groups").BindFunc(func(e *core.RecordEvent) error {
		resync(e, e.Record.GetStringSlice("members"))
		return e.Next()
	})
	// Запись пары пишется постоянно (счётчики, статусы) — пересчёт только при
	// смене состава или распаде.
	app.OnRecordAfterUpdateSuccess("groups").BindFunc(func(e *core.RecordEvent) error {
		cur, old := e.Record.GetStringSlice("members"), e.Record.Original().GetStringSlice("members")
		a, b := slices.Sorted(slices.Values(cur)), slices.Sorted(slices.Values(old))
		if !slices.Equal(a, b) || e.Record.GetBool("disbanded") != e.Record.Original().GetBool("disbanded") {
			resync(e, append(cur, old...))
		}
		return e.Next()
	})
	app.OnRecordAfterDeleteSuccess("groups").BindFunc(func(e *core.RecordEvent) error {
		resync(e, e.Record.GetStringSlice("members"))
		return e.Next()
	})
}

// resyncMembership пересчитывает group_ids и live_group_ids человека прямым
// SQL: поля скрытые, валидация записи тут не нужна.
func resyncMembership(app core.App, uid string) error {
	const of = `SELECT json_group_array(g.id) FROM groups g WHERE %s EXISTS (SELECT 1 FROM json_each(CASE WHEN json_valid(g.members) THEN g.members ELSE '[]' END) je WHERE je.value = {:uid})`
	_, err := app.DB().NewQuery(`UPDATE users SET
		group_ids = COALESCE((` + fmt.Sprintf(of, "") + `), '[]'),
		live_group_ids = COALESCE((` + fmt.Sprintf(of, "g.disbanded = false AND") + `), '[]')
		WHERE id = {:uid}`).Bind(dbx.Params{"uid": uid}).Execute()
	return err
}
