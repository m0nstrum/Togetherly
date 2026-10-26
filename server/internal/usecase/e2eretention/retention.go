// Package e2eretention removes expired negotiation messages and unusable grants.
package e2eretention

import (
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"time"
)

// Sweep is bounded per run. Never age out a grant for an active device: old
// epochs remain necessary for encrypted history, including archived pairs.
func Sweep(app core.App, now time.Time) error {
	params := dbx.Params{
		"sas": now.Add(-24 * time.Hour).UTC().Format("2006-01-02 15:04:05.000Z"),
		"old": now.Add(-30 * 24 * time.Hour).UTC().Format("2006-01-02 15:04:05.000Z"),
		// Привязка по QR длится минуты: дольше запись с ключами не держим.
		"link": now.Add(-15 * time.Minute).UTC().Format("2006-01-02 15:04:05.000Z"),
	}
	return app.RunInTransaction(func(tx core.App) error {
		if _, err := tx.DB().NewQuery(`DELETE FROM e2e_links WHERE created < {:link}`).Bind(params).Execute(); err != nil {
			return err
		}
		_, err := tx.DB().NewQuery(`DELETE FROM e2e_handshake WHERE id IN (
			SELECT id FROM e2e_handshake WHERE (kind != 'invite_proof' AND created < {:sas})
			OR created < {:old} ORDER BY created LIMIT 5000
		)`).Bind(params).Execute()
		if err != nil {
			return err
		}
		_, err = tx.DB().NewQuery(`DELETE FROM e2e_grants WHERE id IN (
			SELECT g.id FROM e2e_grants g LEFT JOIN users u ON u.id = g.to_uid
			LEFT JOIN e2e_identities i ON i.user_uid = g.to_uid
			WHERE g.created < {:old} AND (u.id IS NULL OR (
			json_type(CASE WHEN json_valid(i.devices) THEN i.devices ELSE '{}' END, '$.devices') = 'array'
			AND NOT EXISTS (SELECT 1 FROM json_each(CASE WHEN json_valid(i.devices) THEN i.devices ELSE '{}' END, '$.devices') d
				WHERE json_extract(CASE WHEN json_valid(d.value) THEN d.value ELSE '{}' END, '$.id') = g.to_device)
			)) ORDER BY g.created LIMIT 5000
		)`).Bind(params).Execute()
		return err
	})
}
