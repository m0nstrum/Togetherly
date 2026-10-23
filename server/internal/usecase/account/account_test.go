package account_test

import (
	"context"
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/account"
)

func TestPurgeDue(t *testing.T) {
	ctx := context.Background()
	app := testutil.NewApp(t)
	svc := account.New(app)
	g := testutil.Group(t, app, "pairaaaaaaaaaaa", "aliceaaaaaaaaaa", "bobbbbbbbbbbbbb")
	alice, _ := testutil.User(t, app, "aliceaaaaaaaaaa", g.Id)
	bob, _ := testutil.User(t, app, "bobbbbbbbbbbbbb", g.Id)

	col, err := app.FindCollectionByNameOrId("invite_codes")
	require.NoError(t, err)
	code := core.NewRecord(col)
	code.Set("code", "AB2C3D")
	code.Set("owner_uid", alice.Id)
	require.NoError(t, app.Save(code))

	now := time.Now()
	_, err = svc.Schedule(ctx, alice, now)
	require.NoError(t, err)

	n, err := svc.PurgeDue(ctx, now.Add(time.Hour))
	require.NoError(t, err)
	assert.Zero(t, n, "срок не наступил")

	n, err = svc.PurgeDue(ctx, now.Add(account.Grace+time.Minute))
	require.NoError(t, err)
	assert.Equal(t, 1, n)

	_, err = app.FindRecordById("users", alice.Id)
	assert.Error(t, err, "запись стёрта")
	_, err = app.FindRecordById("users", bob.Id)
	assert.NoError(t, err, "партнёра не трогаем")
	_, err = app.FindRecordById("invite_codes", code.Id)
	assert.Error(t, err, "личные записи стёрты")
	pair, err := app.FindRecordById("groups", g.Id)
	require.NoError(t, err)
	assert.True(t, pair.GetBool("disbanded"), "пара распущена, история у партнёра")
}

func TestCancel(t *testing.T) {
	ctx := context.Background()
	app := testutil.NewApp(t)
	svc := account.New(app)
	u, _ := testutil.User(t, app, "aliceaaaaaaaaaa")
	now := time.Now()
	_, err := svc.Schedule(ctx, u, now)
	require.NoError(t, err)
	require.NoError(t, svc.Cancel(u))
	n, err := svc.PurgeDue(ctx, now.Add(account.Grace+time.Hour))
	require.NoError(t, err)
	assert.Zero(t, n)
}

// Removing Alice deletes both directions of key grants, while Bob's own
// backup, identity and device token survive the cleanup.
func TestPurgeSecretsAndTokens(t *testing.T) {
	app := testutil.NewApp(t)
	svc := account.New(app)
	g := testutil.Group(t, app, "pairaaaaaaaaaaa", "aliceaaaaaaaaaa", "bobbbbbbbbbbbbb")
	alice, _ := testutil.User(t, app, "aliceaaaaaaaaaa", g.Id)
	bob, _ := testutil.User(t, app, "bobbbbbbbbbbbbb", g.Id)
	type saved struct {
		collection, id string
		removed        bool
	}
	var records []saved
	for _, name := range []string{"e2e_backups", "e2e_identities", "e2e_grants", "e2e_handshake", "push_tokens", "fork_battery", "fork_reels_matches"} {
		col, err := app.FindCollectionByNameOrId(name)
		require.NoError(t, err)
		for _, u := range []*core.Record{alice, bob} {
			r := core.NewRecord(col)
			for _, field := range col.Fields {
				if tf, ok := field.(*core.TextField); ok && tf.Required && !tf.PrimaryKey {
					r.Set(tf.Name, "test-"+u.Id)
				}
			}
			r.Set("user_uid", u.Id)
			r.Set("author_uid", u.Id)
			r.Set("group_id", g.Id)
			r.Set("to_uid", bob.Id)
			r.Set("kind", "sas_start")
			r.Set("epoch", 1)
			require.NoError(t, app.Save(r))
			records = append(records, saved{name, r.Id, u.Id == alice.Id})
		}
		if name == "e2e_grants" {
			r := core.NewRecord(col)
			r.Set("group_id", g.Id)
			r.Set("user_uid", bob.Id)
			r.Set("to_uid", alice.Id)
			r.Set("to_device", "alice-device")
			r.Set("epoch", 1)
			require.NoError(t, app.Save(r))
			records = append(records, saved{name, r.Id, true})
		}
	}
	now := time.Now()
	_, err := svc.Schedule(context.Background(), alice, now)
	require.NoError(t, err)
	n, err := svc.PurgeDue(context.Background(), now.Add(account.Grace+time.Minute))
	require.NoError(t, err)
	require.Equal(t, 1, n)
	for _, r := range records {
		_, err := app.FindRecordById(r.collection, r.id)
		if r.removed {
			assert.Error(t, err, r.collection)
		} else {
			assert.NoError(t, err, r.collection)
		}
	}
}
