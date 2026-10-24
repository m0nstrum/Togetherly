package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Matched clips remain ciphertext; match_tag is a keyed, opaque deduplication tag.
func init() {
	m.Register(func(app core.App) error {
		if _, err := app.FindCollectionByNameOrId("fork_reels_matches"); err == nil {
			return nil
		}
		col := base("fork_reels_matches")
		col.Fields.Add(
			&core.TextField{Name: "group_id", Required: true},
			&core.TextField{Name: "author_uid", Required: true},
			&core.TextField{Name: "match_tag", Required: true, Max: 64},
			&core.TextField{Name: "state", Required: true, Max: E2ESealedMax},
		)
		col.AddIndex("uq_fork_reels_match", true, "group_id, match_tag", "")
		if err := app.Save(col); err != nil {
			return err
		}
		return ApplyRules(app)
	}, nil, "1760000012_fork_reels_matches.go")
}
