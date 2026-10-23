package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Backfill existing installs immediately, without waiting for a membership change.
func init() {
	m.Register(func(app core.App) error {
		if err := extendUsers(app); err != nil {
			return err
		}
		_, err := app.DB().NewQuery(`UPDATE users SET live_group_ids = COALESCE((SELECT json_group_array(g.id) FROM groups g WHERE g.disbanded = false AND EXISTS (SELECT 1 FROM json_each(g.members) m WHERE m.value = users.id)), '[]')`).Execute()
		if err != nil {
			return err
		}
		return ApplyRules(app)
	}, nil, "1760000011_live_groups.go")
}
