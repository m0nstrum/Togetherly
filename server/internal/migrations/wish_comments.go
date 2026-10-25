package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// wish_comments — комментарии к желаниям «Хочу с тобой» (docs/WISHLIST.md).
// Текст — шифр ключа пары; править и удалять — только автору комментария.
// Удалённое желание уносит свои комментарии (pocketbase.bindWishComments).
func init() {
	m.Register(func(app core.App) error {
		if _, err := app.FindCollectionByNameOrId("wish_comments"); err == nil {
			return nil
		}
		col := base("wish_comments")
		col.Fields.Add(
			&core.TextField{Name: "group_id", Required: true},
			&core.TextField{Name: "wish_id", Required: true},
			&core.TextField{Name: "author_uid", Required: true},
			&core.TextField{Name: "text", Max: E2ESealedMax},
		)
		col.AddIndex("idx_wish_comments_wish", false, "wish_id", "")
		col.AddIndex("idx_wish_comments_group", false, "group_id", "")
		if err := app.Save(col); err != nil {
			return err
		}
		return ApplyRules(app)
	}, nil, "1760000017_wish_comments.go")
}
