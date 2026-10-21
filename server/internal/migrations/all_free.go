package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Плюс открыт у всех (решение 1): тем, кто завёлся до хука bindAllFree.
func init() {
	m.Register(func(app core.App) error {
		_, err := app.DB().NewQuery("UPDATE users SET plus = TRUE").Execute()
		return err
	}, nil, "1760000002_all_free.go")
}
