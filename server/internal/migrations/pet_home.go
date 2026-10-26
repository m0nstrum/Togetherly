package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// The home is opaque ciphertext. Only the compare-and-swap operation can write.
func init() {
	m.Register(func(app core.App) error {
		if _, err := app.FindCollectionByNameOrId("pet_homes"); err == nil {
			return nil
		}
		col := base("pet_homes")
		col.Fields.Add(
			&core.TextField{Name: "group_id", Required: true},
			&core.TextField{Name: "state", Required: true, Max: 128 << 10},
			&core.NumberField{Name: "revision", OnlyInt: true},
			&core.JSONField{Name: "operations", MaxSize: 8 << 10, Hidden: true},
		)
		col.AddIndex("uq_pet_home_group", true, "group_id", "")
		if err := app.Save(col); err != nil {
			return err
		}
		return ApplyRules(app)
	}, nil, "1760000024_pet_home.go")
}
