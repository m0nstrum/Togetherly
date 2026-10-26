package handler

import (
	"net/http"
	"slices"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
)

// UserCard — GET /api/user/card?uid=… (бывший user_card.pb.js): публичная
// карточка человека из своей пары. Правило коллекции `users` пускает читать
// только себя, а партнёру нужны баннер, значок, рамка и ночная сцена
// маскота. Почта, монеты и служебные отметки сюда не попадают.
//
// Членство сверяем по `live_group_ids` обоих — то же быстрое правило, что и в
// парных коллекциях.
func UserCard(r *router.Router[*core.RequestEvent]) {
	r.GET("/api/user/card", func(e *core.RequestEvent) error {
		uid := e.Request.URL.Query().Get("uid")
		if uid == "" {
			return e.JSON(http.StatusBadRequest, map[string]any{"ok": false, "error": "no uid"})
		}
		rec, err := e.App.FindRecordById("users", uid)
		if err != nil {
			return e.JSON(http.StatusNotFound, map[string]any{"ok": false, "error": "not found"})
		}
		if uid != e.Auth.Id && !sharePair(e.Auth.GetStringSlice("live_group_ids"), rec.GetStringSlice("live_group_ids")) {
			return e.JSON(http.StatusForbidden, map[string]any{"ok": false, "error": "not in your pair"})
		}
		badges := rec.GetStringSlice("granted_badges")
		if badges == nil {
			badges = []string{}
		}
		return e.JSON(http.StatusOK, map[string]any{
			"ok":           true,
			"id":           rec.Id,
			"display_name": rec.GetString("display_name"),
			"avatar_url":   rec.GetString("avatar_url"),
			"banner_url":   rec.GetString("banner_url"),
			// GIF в баннере у апстрима шевелился только с Плюсом; в Tethered
			// всё открыто всем.
			"banner_live":    true,
			"badge":          rec.GetString("badge"),
			"frame":          rec.GetString("frame"),
			"gender":         rec.GetString("gender"),
			"birth_date":     rec.GetString("birth_date"),
			"mascot_sleep":   rec.Get("mascot_sleep"),
			"granted_badges": badges,
		})
	}).Bind(apis.RequireAuth())
}

// sharePair — есть ли у двух людей общая живая пара.
func sharePair(mine, theirs []string) bool {
	for _, g := range mine {
		if g != "" && slices.Contains(theirs, g) {
			return true
		}
	}
	return false
}
