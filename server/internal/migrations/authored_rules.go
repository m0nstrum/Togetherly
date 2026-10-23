package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

func init() {
	m.Register(func(app core.App) error { return ApplyRules(app) }, nil, "1760000014_authored_rules.go")
}
