// Package records — серверное создание записей для JS-хуков апстрима
// (/internal/record у hotpath): например, «салют» из gifts.pb.js кладёт
// воспоминание в пару. Правила доступа не проверяются — путь только с петли.
package records

import (
	"context"
	"errors"
	"fmt"

	"github.com/pocketbase/pocketbase/core"
)

// Service создаёт записи от имени сервера.
type Service struct{ app core.App }

// New — сервис над app.
func New(app core.App) *Service { return &Service{app: app} }

// ErrForbidden — коллекция не для серверной записи.
var ErrForbidden = errors.New("records: коллекция недоступна")

// Create — новая запись в collection из fields (неизвестные поля
// пропускаются, как в hotpath). Пользователей так не заводят.
func (s *Service) Create(ctx context.Context, collection string, fields map[string]any) (*core.Record, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	col, err := s.app.FindCollectionByNameOrId(collection)
	if err != nil || col.System || col.IsAuth() {
		return nil, ErrForbidden
	}
	r := core.NewRecord(col)
	if id, _ := fields["id"].(string); id != "" {
		r.Id = id
	}
	for name, v := range fields {
		f := col.Fields.GetByName(name)
		if f == nil || f.GetSystem() || name == "id" {
			continue
		}
		r.Set(name, v)
	}
	if err := s.app.Save(r); err != nil {
		return nil, fmt.Errorf("records: %s: %w", collection, err)
	}
	return r, nil
}
