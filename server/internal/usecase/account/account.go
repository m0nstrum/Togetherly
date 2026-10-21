// Package account — удаление аккаунта с отсрочкой.
//
// Клиент (UserData.deleteAccount) зовёт POST /api/account/schedule-delete и
// выходит. Неделю запись жива вместе с парами: вход паролем снимает пометку и
// возвращает всё. По истечении срока ночная задача распускает пары человека и
// стирает его запись и личные следы. У апстрима это делал хук
// account_delete_grace.pb.js, которого в репозитории нет.
package account

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/types"

	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
)

// Grace — сколько аккаунт живёт после запроса на удаление.
const Grace = 7 * 24 * time.Hour

const field = "delete_after"

// Service — удаление аккаунтов.
type Service struct{ app core.App }

// New — сервис над app.
func New(app core.App) *Service { return &Service{app: app} }

// Schedule помечает аккаунт к удалению через Grace.
func (s *Service) Schedule(ctx context.Context, user *core.Record, now time.Time) (time.Time, error) {
	if err := ctx.Err(); err != nil {
		return time.Time{}, err
	}
	at := now.Add(Grace).UTC()
	user.Set(field, at)
	if err := s.app.Save(user); err != nil {
		return time.Time{}, fmt.Errorf("account: пометка: %w", err)
	}
	return at, nil
}

// Cancel снимает пометку (вход паролем в срок).
func (s *Service) Cancel(user *core.Record) error {
	if user.GetDateTime(field).IsZero() {
		return nil
	}
	user.Set(field, nil)
	if err := s.app.Save(user); err != nil {
		return fmt.Errorf("account: снятие пометки: %w", err)
	}
	return nil
}

// Personal — личные следы человека, которые стираются вместе с ним: коллекция
// и поле с его id. Записи пары (чат, воспоминания) остаются у партнёра.
var Personal = []struct{ Collection, Field string }{
	{"invite_codes", "owner_uid"},
	{"user_presence", "user_uid"},
	{"live_location", "user_uid"},
	{"wish_reservations", "uid"},
	{"chest_opens", "user_uid"},
}

// PurgeDue стирает аккаунты, чей срок наступил: пары распускаются, личные
// записи и аватары удаляются, затем сама запись. Возвращает число стёртых.
func (s *Service) PurgeDue(ctx context.Context, now time.Time) (int, error) {
	due, err := s.app.FindRecordsByFilter("users",
		field+" != '' && "+field+" <= {:now}", "", 200, 0,
		dbx.Params{"now": now.UTC().Format(types.DefaultDateLayout)})
	if err != nil {
		return 0, err
	}
	var errs []error
	n := 0
	for _, u := range due {
		if err := ctx.Err(); err != nil {
			return n, err
		}
		if err := s.purge(u, now); err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", u.Id, err))
			continue
		}
		n++
	}
	return n, errors.Join(errs...)
}

func (s *Service) purge(u *core.Record, now time.Time) error {
	return s.app.RunInTransaction(func(tx core.App) error {
		groups, err := pairs.New(tx).GroupsOfUser(u.Id, false)
		if err != nil {
			return err
		}
		for _, g := range groups {
			if g.GetBool("disbanded") {
				continue
			}
			g.Set("disbanded", true)
			g.Set("disbanded_at", now.UTC().Format(types.DefaultDateLayout))
			if err := tx.Save(g); err != nil {
				return err
			}
		}
		for _, p := range Personal {
			recs, err := tx.FindRecordsByFilter(p.Collection, p.Field+" = {:uid}", "", 0, 0, dbx.Params{"uid": u.Id})
			if err != nil {
				continue // коллекции может не быть в схеме
			}
			for _, r := range recs {
				if err := tx.Delete(r); err != nil {
					return err
				}
			}
		}
		avatars, err := tx.FindRecordsByFilter("media",
			"uid = {:uid} && (kind = 'avatar' || kind = 'avatars' || kind = 'banner' || kind = 'banners')",
			"", 0, 0, dbx.Params{"uid": u.Id})
		if err == nil {
			for _, r := range avatars {
				if err := tx.Delete(r); err != nil {
					return err
				}
			}
		}
		return tx.Delete(u)
	})
}
