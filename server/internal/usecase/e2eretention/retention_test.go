package e2eretention_test

import (
	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/e2eretention"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/require"
	"testing"
	"time"
)

func TestRetentionPreservesHistoryKeys(t *testing.T) {
	app := testutil.NewApp(t)
	now := time.Now().UTC()
	uid := "aliceaaaaaaaaaa"
	testutil.User(t, app, uid)
	save := func(col string, age time.Duration, fields map[string]any) *core.Record {
		c, err := app.FindCollectionByNameOrId(col)
		require.NoError(t, err)
		r := core.NewRecord(c)
		for k, v := range fields {
			r.Set(k, v)
		}
		r.Set("created", now.Add(-age).Format("2006-01-02 15:04:05.000Z"))
		require.NoError(t, app.Save(r))
		_, err = app.DB().NewQuery("UPDATE " + col + " SET created = {:created} WHERE id = {:id}").Bind(dbx.Params{"created": now.Add(-age).Format("2006-01-02 15:04:05.000Z"), "id": r.Id}).Execute()
		require.NoError(t, err)
		return r
	}
	save("e2e_identities", 0, map[string]any{"user_uid": uid, "account_key": "public", "devices": map[string]any{"devices": []any{map[string]any{"id": "active"}}}})
	handshake := func(kind string, age time.Duration) *core.Record {
		return save("e2e_handshake", age, map[string]any{"group_id": "pair", "user_uid": uid, "session": "s", "kind": kind})
	}
	freshSAS := handshake("sas_start", time.Minute)
	oldSAS := handshake("sas_start", 48*time.Hour)
	proof := handshake("invite_proof", 7*24*time.Hour)
	expiredProof := handshake("invite_proof", 31*24*time.Hour)
	grant := func(device string, age time.Duration) *core.Record {
		return save("e2e_grants", age, map[string]any{"group_id": "archived-pair", "user_uid": uid, "to_uid": uid, "to_device": device, "epoch": 1})
	}
	active := grant("active", 365*24*time.Hour)
	revoked := grant("revoked", 31*24*time.Hour)
	fresh := grant("recently-removed", 24*time.Hour)
	require.NoError(t, e2eretention.Sweep(app, now))
	for _, r := range []*core.Record{freshSAS, proof, active, fresh} {
		_, err := app.FindRecordById(r.Collection(), r.Id)
		require.NoError(t, err, "must keep %s", r.Id)
	}
	for _, r := range []*core.Record{oldSAS, expiredProof, revoked} {
		_, err := app.FindRecordById(r.Collection(), r.Id)
		require.Error(t, err, "must remove %s", r.Id)
	}
	require.NoError(t, e2eretention.Sweep(app, now))
}
