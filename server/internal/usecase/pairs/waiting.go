package pairs

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
	"strings"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// Пара «с пустым местом» (handler.Waiting): второе место держит заглушка, а
// войти в него можно по коду (claim_token) с подтверждением хозяина.

// codeAlphabet — без похожих символов (0/O, 1/I), как у hotpath.
const codeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

// Result — ответ пути: Status — HTTP-код, Body — JSON как у hotpath.
type Result struct {
	Status int
	Body   map[string]any
}

func ok(body map[string]any) Result { return Result{Status: 200, Body: body} }
func fail(status int, msg string) Result {
	return Result{Status: status, Body: map[string]any{"success": false, "message": msg}}
}

// WaitingCreateInput — тело /internal/waiting-create.
type WaitingCreateInput struct {
	UID               string `json:"uid"`
	PlaceholderName   string `json:"placeholder_name"`
	PlaceholderAvatar string `json:"placeholder_avatar"`
	ReturnDate        string `json:"return_date"`
	MyName            string `json:"my_name"`
	MyAvatar          string `json:"my_avatar"`
}

// WaitingCreate заводит пару с заглушкой и кодом второго места. Живой пары у
// человека быть не должно: проверка и выдача кода — в одной транзакции.
func (s *Service) WaitingCreate(ctx context.Context, in WaitingCreateInput) (Result, error) {
	uid := strings.TrimSpace(in.UID)
	name := truncate(strings.TrimSpace(in.PlaceholderName), 60)
	if uid == "" || name == "" {
		return fail(400, "Впишите имя"), nil
	}
	var res Result
	err := s.app.RunInTransaction(func(tx core.App) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		mine, err := groupsOf(tx, uid, true, 5)
		if err != nil {
			return err
		}
		for _, g := range mine {
			if len(Members(g)) > 1 || g.GetString("claim_token") != "" {
				res = fail(400, "У вас уже есть пара")
				return nil
			}
		}
		code, err := freeCode(tx)
		if err != nil {
			return err
		}
		if code == "" {
			res = fail(500, "Не удалось выдать код")
			return nil
		}
		col, err := tx.FindCollectionByNameOrId(groupsCol)
		if err != nil {
			return err
		}
		g := core.NewRecord(col)
		g.Set("members", []string{uid})
		g.Set("member_names", map[string]string{uid: in.MyName})
		g.Set("member_avatars", map[string]string{uid: in.MyAvatar})
		g.Set("max_members", 2)
		g.Set("relationship_type", "couple")
		g.Set("custom_relationship_types", []any{})
		g.Set("created_at", now())
		g.Set("disbanded", false)
		g.Set("waiting_mode", true)
		g.Set("placeholder_name", name)
		g.Set("placeholder_avatar", in.PlaceholderAvatar)
		g.Set("return_date", in.ReturnDate)
		g.Set("claim_token", code)
		if err := tx.Save(g); err != nil {
			return err
		}
		res = ok(map[string]any{"success": true, "pairId": g.Id, "code": code})
		return nil
	})
	if err != nil {
		return Result{}, fmt.Errorf("pairs: waiting-create: %w", err)
	}
	return res, nil
}

// WaitingReset выдаёт новый код второго места. Занятое место кодом не
// освобождается.
func (s *Service) WaitingReset(ctx context.Context, groupID, uid string) (Result, error) {
	if groupID == "" || uid == "" {
		return fail(400, "Не указана пара"), nil
	}
	var res Result
	err := s.app.RunInTransaction(func(tx core.App) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		g, err := tx.FindRecordById(groupsCol, groupID)
		if err != nil {
			res = fail(404, "Пара не найдена")
			return nil
		}
		members := Members(g)
		switch {
		case !contains(members, uid):
			res = fail(403, "Это не ваша пара")
			return nil
		case len(members) > 1:
			res = fail(400, "Место уже занято")
			return nil
		}
		code, err := freeCode(tx)
		if err != nil {
			return err
		}
		if code == "" {
			res = fail(500, "Не удалось выдать код")
			return nil
		}
		g.Set("claim_token", code)
		g.Set("claim_uid", "")
		g.Set("claim_name", "")
		g.Set("claim_at", 0)
		g.Set("waiting_mode", true)
		if err := tx.Save(g); err != nil {
			return err
		}
		res = ok(map[string]any{"success": true, "code": code})
		return nil
	})
	if err != nil {
		return Result{}, fmt.Errorf("pairs: waiting-reset: %w", err)
	}
	return res, nil
}

// ClaimApproveInput — тело /internal/pair-claim-approve.
type ClaimApproveInput struct {
	GroupID     string `json:"group_id"`
	ClaimUID    string `json:"claim_uid"`
	ClaimName   string `json:"claim_name"`
	ClaimAvatar string `json:"claim_avatar"`
}

// ClaimApprove — хозяин подтвердил претендента: место занимается, код
// гасится. Повтор того же подтверждения участника не задваивает.
func (s *Service) ClaimApprove(ctx context.Context, in ClaimApproveInput) (Result, error) {
	if in.GroupID == "" || in.ClaimUID == "" {
		return Result{Status: 400, Body: map[string]any{"ok": false, "error": "bad params"}}, nil
	}
	var res Result
	err := s.app.RunInTransaction(func(tx core.App) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		g, err := tx.FindRecordById(groupsCol, in.GroupID)
		if err != nil {
			res = Result{Status: 404, Body: map[string]any{"ok": false, "error": "no group"}}
			return nil
		}
		members := Members(g)
		if !contains(members, in.ClaimUID) {
			limit := g.GetInt("max_members")
			if limit <= 0 {
				limit = 2
			}
			if len(members) >= limit {
				res = Result{Status: 400, Body: map[string]any{"ok": false, "error": "full"}}
				return nil
			}
			members = append(members, in.ClaimUID)
		}
		g.Set("members", members)
		setMapKey(g, "member_names", in.ClaimUID, in.ClaimName)
		setMapKey(g, "member_avatars", in.ClaimUID, in.ClaimAvatar)
		clearWaiting(g)
		if err := tx.Save(g); err != nil {
			return err
		}
		res = Result{Status: 200, Body: map[string]any{"ok": true, "members": members}}
		return nil
	})
	if err != nil {
		return Result{}, fmt.Errorf("pairs: claim-approve: %w", err)
	}
	return res, nil
}

// freeCode — незанятый код второго места; пусто — не нашли за 12 попыток.
func freeCode(app core.App) (string, error) {
	for range 12 {
		code, err := randomCode(8)
		if err != nil {
			return "", err
		}
		if _, err := app.FindFirstRecordByFilter(groupsCol, "claim_token = {:c}", dbx.Params{"c": code}); err != nil {
			return code, nil
		}
	}
	return "", nil
}

func randomCode(n int) (string, error) {
	var b strings.Builder
	max := big.NewInt(int64(len(codeAlphabet)))
	for range n {
		i, err := rand.Int(rand.Reader, max)
		if err != nil {
			return "", err
		}
		b.WriteByte(codeAlphabet[i.Int64()])
	}
	return b.String(), nil
}

func truncate(s string, n int) string {
	r := []rune(s)
	if len(r) > n {
		return string(r[:n])
	}
	return s
}
