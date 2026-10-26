// Package pethome stores an encrypted shared home with atomic version checks.
// The server never decrypts furnishings, nicknames, care history or cozy credit.
package pethome

import (
	"database/sql"
	"errors"
	"regexp"
	"slices"
	"strings"

	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

var (
	ErrDenied        = errors.New("pet home: access denied")
	ErrConflict      = errors.New("pet home: revision conflict")
	ErrInvalid       = errors.New("pet home: invalid request")
	operationPattern = regexp.MustCompile(`^[a-f0-9]{32}$`)
)

type Service struct{ app core.App }

func New(app core.App) *Service { return &Service{app: app} }

func allowed(app core.App, group, uid string, write bool) error {
	g, err := app.FindRecordById("groups", group)
	if err != nil || !slices.Contains(pairs.Members(g), uid) || (write && g.GetBool("disbanded")) {
		return ErrDenied
	}
	return nil
}

func record(app core.App, group string) (*core.Record, error) {
	r, err := app.FindFirstRecordByFilter("pet_homes", "group_id = {:g}", dbx.Params{"g": group})
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return r, err
}

func (s *Service) Read(group, uid string) (*core.Record, error) {
	if err := allowed(s.app, group, uid, false); err != nil {
		return nil, err
	}
	return record(s.app, group)
}

func (s *Service) Write(group, uid string, revision int, operation, state string) (*core.Record, error) {
	if revision < 0 || revision >= 2147483647 || !operationPattern.MatchString(operation) ||
		len(state) > 128<<10 || !strings.HasPrefix(state, "e2e1.") || len(state) < 32 {
		return nil, ErrInvalid
	}
	var result *core.Record
	err := s.app.RunInTransaction(func(tx core.App) error {
		// Recheck live membership INSIDE the same transaction as the update.
		if err := allowed(tx, group, uid, true); err != nil {
			return err
		}
		r, err := record(tx, group)
		if err != nil {
			return err
		}
		var operations []string
		if r != nil {
			if err := r.UnmarshalJSONField("operations", &operations); err != nil {
				return err
			}
			// A retry after a lost response does not spend/reward a second time.
			if slices.Contains(operations, operation) {
				result = r
				return nil
			}
			if r.GetInt("revision") != revision {
				return ErrConflict
			}
		} else {
			if revision != 0 {
				return ErrConflict
			}
			col, err := tx.FindCollectionByNameOrId("pet_homes")
			if err != nil {
				return err
			}
			r = core.NewRecord(col)
			r.Set("group_id", group)
		}
		operations = append(operations, operation)
		if len(operations) > 128 {
			operations = operations[len(operations)-128:]
		}
		r.Set("state", state)
		r.Set("revision", revision+1)
		r.Set("operations", operations)
		if err := tx.Save(r); err != nil {
			return err
		}
		result = r
		return nil
	})
	return result, err
}
