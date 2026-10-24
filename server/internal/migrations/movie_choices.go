package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

func init() {
	m.Register(func(app core.App) error {
		if _, err := app.FindCollectionByNameOrId("fork_movie_choices"); err == nil {
			return nil
		}
		col := base("fork_movie_choices")
		col.Fields.Add(
			&core.TextField{Name: "group_id", Required: true},
			&core.TextField{Name: "author_uid", Required: true},
			&core.TextField{Name: "movie_tag", Required: true, Max: 64},
			&core.TextField{Name: "state", Required: true, Max: E2ESealedMax},
		)
		col.AddIndex("uq_fork_movie_choice", true, "group_id, author_uid, movie_tag", "")
		if err := app.Save(col); err != nil {
			return err
		}
		return ApplyRules(app)
	}, nil, "1760000013_fork_movie_choices.go")
}
