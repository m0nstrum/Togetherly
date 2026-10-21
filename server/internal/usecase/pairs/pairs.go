// Package pairs — операции над парой (коллекция groups), которые у апстрима
// жили в hotpath (Postgres) и которые JS-хуки зовут по /internal/*.
//
// Форк держит группы в PocketBase, поэтому сохранение записи само запускает
// хуки (groups_membership ведёт users.group_ids) и рассылку в Centrifugo —
// то, что hotpath делал руками в `_после_правки_пары`.
package pairs

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Service — операции над парами поверх приложения PocketBase.
type Service struct {
	app core.App
}

// New — сервис над app.
func New(app core.App) *Service { return &Service{app: app} }

const groupsCol = "groups"

// ErrNotFound — пары нет.
var ErrNotFound = errors.New("pairs: пара не найдена")

// AcceptInput — приём кода приглашения (тело /internal/pair-accept).
type AcceptInput struct {
	OwnerUID    string `json:"owner_uid"`
	MyUID       string `json:"my_uid"`
	CodeGroupID string `json:"code_group_id"`
	OwnerName   string `json:"owner_name"`
	OwnerAvatar string `json:"owner_avatar"`
	MyName      string `json:"my_name"`
	MyAvatar    string `json:"my_avatar"`
}

// AcceptResult — ответ hotpath, который invite.pb.js отдаёт клиенту как есть.
type AcceptResult struct {
	Success  bool   `json:"success"`
	Message  string `json:"message"`
	PairID   string `json:"pairId,omitempty"`
	Restored bool   `json:"restored,omitempty"`
}

// Accept — порт `/internal/pair-accept` hotpath один в один по ветвлению:
// код привязан к паре → войти в неё; у приглашающего есть живая пара с
// местом → войти; есть общая распущенная → поднять со всей историей; иначе
// завести новую.
func (s *Service) Accept(ctx context.Context, in AcceptInput) (AcceptResult, error) {
	owner, me := strings.TrimSpace(in.OwnerUID), strings.TrimSpace(in.MyUID)
	if owner == "" || me == "" || owner == me {
		return AcceptResult{Message: "bad params"}, nil
	}
	if in.OwnerName == "" {
		in.OwnerName = "Partner"
	}
	names := map[string]string{owner: in.OwnerName, me: in.MyName}
	avatars := map[string]string{owner: in.OwnerAvatar, me: in.MyAvatar}

	var res *AcceptResult
	err := s.app.RunInTransaction(func(tx core.App) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		join := func(gid string) (*AcceptResult, error) {
			g, err := tx.FindRecordById(groupsCol, gid)
			if err != nil {
				return nil, nil //nolint:nilerr // пары нет — пробуем следующую ветку
			}
			members := Members(g)
			disbanded := g.GetBool("disbanded")
			if contains(members, me) {
				if disbanded {
					clearWaiting(g)
					g.Set("disbanded", false)
					g.Set("disbanded_at", "")
					if err := tx.Save(g); err != nil {
						return nil, err
					}
					return &AcceptResult{Success: true, Message: "Reconnected!", PairID: gid, Restored: true}, nil
				}
				return &AcceptResult{Success: true, Message: "Connected!", PairID: gid}, nil
			}
			limit := g.GetInt("max_members")
			if limit <= 0 {
				limit = 2
			}
			if len(members) >= limit {
				if disbanded {
					// Место держат ушедшие: пробуем другие ветки.
					return nil, nil
				}
				return &AcceptResult{Message: "Группа заполнена"}, nil
			}
			g.Set("members", append(members, me))
			setMapKey(g, "member_names", me, names[me])
			setMapKey(g, "member_avatars", me, avatars[me])
			clearWaiting(g)
			g.Set("disbanded", false)
			if err := tx.Save(g); err != nil {
				return nil, err
			}
			return &AcceptResult{Success: true, Message: "Joined the group!", PairID: gid}, nil
		}

		var err error
		if in.CodeGroupID != "" {
			if res, err = join(in.CodeGroupID); err != nil {
				return err
			}
		}
		if res == nil {
			live, err := groupsOf(tx, owner, true, 5)
			if err != nil {
				return err
			}
			for _, g := range live {
				r, err := join(g.Id)
				if err != nil {
					return err
				}
				if r != nil && r.Success {
					res = r
					break
				}
			}
		}
		if res == nil {
			shared, err := sharedGroup(tx, owner, me)
			if err != nil {
				return err
			}
			if shared != nil {
				shared.Set("members", []string{owner, me})
				for uid := range names {
					setMapKey(shared, "member_names", uid, names[uid])
					setMapKey(shared, "member_avatars", uid, avatars[uid])
				}
				clearWaiting(shared)
				shared.Set("disbanded", false)
				shared.Set("disbanded_at", "")
				if err := tx.Save(shared); err != nil {
					return err
				}
				res = &AcceptResult{Success: true, Message: "Reconnected!", PairID: shared.Id, Restored: true}
			}
		}
		if res == nil {
			col, err := tx.FindCollectionByNameOrId(groupsCol)
			if err != nil {
				return err
			}
			g := core.NewRecord(col)
			g.Set("members", []string{owner, me})
			g.Set("member_names", names)
			g.Set("member_avatars", avatars)
			g.Set("max_members", 2)
			g.Set("relationship_type", "couple")
			g.Set("custom_relationship_types", []any{})
			g.Set("start_date", now())
			g.Set("created_at", now())
			g.Set("disbanded", false)
			if err := tx.Save(g); err != nil {
				return err
			}
			res = &AcceptResult{Success: true, Message: "Connected!", PairID: g.Id}
		}
		return nil
	})
	if err != nil {
		return AcceptResult{}, fmt.Errorf("pairs: приём кода: %w", err)
	}
	return *res, nil
}

// clearWaiting гасит «ждём человека»: место занято, ждать некого.
func clearWaiting(g *core.Record) {
	g.Set("waiting_mode", false)
	g.Set("claim_token", "")
	g.Set("claim_uid", "")
	g.Set("claim_name", "")
	g.Set("claim_at", 0)
}

// GroupsOf — пары человека, свежие первыми (как фильтр members ~ uid).
func (s *Service) GroupsOf(ctx context.Context, uid string, live bool) ([]*core.Record, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return groupsOf(s.app, uid, live, 20)
}

// GroupsOfUser — то же без контекста запроса: для стражей внутри хуков.
func (s *Service) GroupsOfUser(uid string, live bool) ([]*core.Record, error) {
	return groupsOf(s.app, uid, live, 20)
}

func groupsOf(app core.App, uid string, live bool, limit int) ([]*core.Record, error) {
	filter := "members ~ {:uid}"
	if live {
		filter += " && disbanded = false"
	}
	recs, err := app.FindRecordsByFilter(groupsCol, filter, "-updated", limit, 0, dbx.Params{"uid": quoted(uid)})
	if err != nil {
		return nil, err
	}
	// `~` ищет подстроку в JSON — отсекаем ложные совпадения точной проверкой.
	out := recs[:0]
	for _, r := range recs {
		if contains(Members(r), uid) {
			out = append(out, r)
		}
	}
	return out, nil
}

func sharedGroup(app core.App, a, b string) (*core.Record, error) {
	recs, err := groupsOf(app, a, false, 50)
	if err != nil {
		return nil, err
	}
	for _, r := range recs {
		if contains(Members(r), b) {
			return r, nil
		}
	}
	return nil, nil
}

// Group — запись пары по id.
func (s *Service) Group(ctx context.Context, id string) (*core.Record, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	g, err := s.app.FindRecordById(groupsCol, id)
	if err != nil {
		return nil, ErrNotFound
	}
	return g, nil
}

// GroupByClaimToken — живая пара по коду второго места.
func (s *Service) GroupByClaimToken(ctx context.Context, token string) (*core.Record, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	g, err := s.app.FindFirstRecordByFilter(groupsCol, "claim_token = {:t} && disbanded = false", dbx.Params{"t": token})
	if err != nil {
		return nil, ErrNotFound
	}
	return g, nil
}

// WriteInput — тело /internal/group-write.
type WriteInput struct {
	GroupID string                    `json:"group_id"`
	Mode    string                    `json:"mode"` // patch | create
	Set     map[string]any            `json:"set"`
	Inc     map[string]float64        `json:"inc"`
	MapSet  map[string]map[string]any `json:"map_set"`
	MapDel  map[string][]string       `json:"map_del"`
	ArrAdd  map[string][]any          `json:"arr_add"`
}

// Write — точечная правка пары: set, inc (не ниже нуля), map_set/map_del по
// ключам JSON-объекта, arr_add без повторов. Неизвестные поля пропускаются.
func (s *Service) Write(ctx context.Context, in WriteInput) (*core.Record, error) {
	if strings.TrimSpace(in.GroupID) == "" {
		return nil, errors.New("pairs: пустой group_id")
	}
	var out *core.Record
	err := s.app.RunInTransaction(func(tx core.App) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		g, err := tx.FindRecordById(groupsCol, in.GroupID)
		if err != nil {
			if in.Mode != "create" {
				return ErrNotFound
			}
			col, err := tx.FindCollectionByNameOrId(groupsCol)
			if err != nil {
				return err
			}
			g = core.NewRecord(col)
			g.Id = in.GroupID
			g.Set("created_at", now())
		}
		fields := g.Collection().Fields
		kind := func(name string) string {
			f := fields.GetByName(name)
			if f == nil || f.GetSystem() {
				return ""
			}
			return f.Type()
		}
		for f, v := range in.Set {
			if kind(f) != "" {
				g.Set(f, v)
			}
		}
		for f, d := range in.Inc {
			if kind(f) == core.FieldTypeNumber {
				g.Set(f, max(0, g.GetFloat(f)+d))
			}
		}
		for f, kv := range in.MapSet {
			if kind(f) != core.FieldTypeJSON {
				continue
			}
			m := jsonMap(g, f)
			for k, v := range kv {
				m[k] = v
			}
			g.Set(f, m)
		}
		for f, keys := range in.MapDel {
			if kind(f) != core.FieldTypeJSON {
				continue
			}
			m := jsonMap(g, f)
			for _, k := range keys {
				delete(m, k)
			}
			g.Set(f, m)
		}
		for f, vals := range in.ArrAdd {
			if kind(f) != core.FieldTypeJSON {
				continue
			}
			arr := jsonArray(g, f)
			for _, v := range vals {
				if !containsAny(arr, v) {
					arr = append(arr, v)
				}
			}
			g.Set(f, arr)
		}
		if err := tx.Save(g); err != nil {
			return err
		}
		out = g
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("pairs: правка %s: %w", in.GroupID, err)
	}
	return out, nil
}

// Members — состав пары.
func Members(g *core.Record) []string {
	var raw []any
	_ = json.Unmarshal(jsonBytes(g, "members"), &raw)
	out := make([]string, 0, len(raw))
	for _, v := range raw {
		if s := fmt.Sprint(v); v != nil && s != "" {
			out = append(out, s)
		}
	}
	return out
}

func jsonBytes(g *core.Record, field string) []byte {
	switch v := g.Get(field).(type) {
	case nil:
		return nil
	case []byte:
		return v
	case string:
		return []byte(v)
	default:
		b, _ := json.Marshal(v)
		return b
	}
}

func jsonMap(g *core.Record, field string) map[string]any {
	m := map[string]any{}
	_ = json.Unmarshal(jsonBytes(g, field), &m)
	if m == nil {
		m = map[string]any{}
	}
	return m
}

func jsonArray(g *core.Record, field string) []any {
	var a []any
	_ = json.Unmarshal(jsonBytes(g, field), &a)
	return a
}

func setMapKey(g *core.Record, field, key string, value any) {
	m := jsonMap(g, field)
	m[key] = value
	g.Set(field, m)
}

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

func containsAny(list []any, v any) bool {
	vb, _ := json.Marshal(v)
	for _, x := range list {
		xb, _ := json.Marshal(x)
		if string(xb) == string(vb) {
			return true
		}
	}
	return false
}

// quoted — uid в кавычках: `members ~ "uid"` ищет элемент JSON-массива, а не
// подстроку чужого id.
func quoted(uid string) string { return `"` + uid + `"` }

// now — время в формате дат PocketBase.
func now() string { return types.NowDateTime().String() }
