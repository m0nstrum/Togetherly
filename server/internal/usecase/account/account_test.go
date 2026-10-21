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
