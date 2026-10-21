package pairs_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
)

func TestWaiting(t *testing.T) {
	ctx := context.Background()
	app := newApp(t)
	svc := pairs.New(app)

	res, err := svc.WaitingCreate(ctx, pairs.WaitingCreateInput{UID: "alice", PlaceholderName: "Боб", MyName: "Алиса"})
	require.NoError(t, err)
	require.Equal(t, 200, res.Status, res.Body)
	gid := res.Body["pairId"].(string)
	code := res.Body["code"].(string)
	assert.Len(t, code, 8)
	g := reload(t, app, gid)
	assert.True(t, g.GetBool("waiting_mode"))
	assert.Equal(t, code, g.GetString("claim_token"))

	again, err := svc.WaitingCreate(ctx, pairs.WaitingCreateInput{UID: "alice", PlaceholderName: "Ещё"})
	require.NoError(t, err)
	assert.Equal(t, 400, again.Status, "вторая пара с пустым местом")

	empty, err := svc.WaitingCreate(ctx, pairs.WaitingCreateInput{UID: "carol"})
	require.NoError(t, err)
	assert.Equal(t, 400, empty.Status, "без имени заглушки")

	found, err := svc.GroupByClaimToken(ctx, code)
	require.NoError(t, err)
	assert.Equal(t, gid, found.Id)

	stranger, err := svc.WaitingReset(ctx, gid, "eve")
	require.NoError(t, err)
	assert.Equal(t, 403, stranger.Status)

	reset, err := svc.WaitingReset(ctx, gid, "alice")
	require.NoError(t, err)
	require.Equal(t, 200, reset.Status)
	assert.NotEqual(t, code, reset.Body["code"])

	ap, err := svc.ClaimApprove(ctx, pairs.ClaimApproveInput{GroupID: gid, ClaimUID: "bob", ClaimName: "Боб"})
	require.NoError(t, err)
	require.Equal(t, 200, ap.Status)
	g = reload(t, app, gid)
	assert.ElementsMatch(t, []string{"alice", "bob"}, pairs.Members(g))
	assert.False(t, g.GetBool("waiting_mode"))
	assert.Empty(t, g.GetString("claim_token"))

	repeat, err := svc.ClaimApprove(ctx, pairs.ClaimApproveInput{GroupID: gid, ClaimUID: "bob"})
	require.NoError(t, err)
	assert.Equal(t, 200, repeat.Status, "повтор не задваивает")
	assert.Len(t, pairs.Members(reload(t, app, gid)), 2)

	full, err := svc.ClaimApprove(ctx, pairs.ClaimApproveInput{GroupID: gid, ClaimUID: "dave"})
	require.NoError(t, err)
	assert.Equal(t, "full", full.Body["error"])

	taken, err := svc.WaitingReset(ctx, gid, "alice")
	require.NoError(t, err)
	assert.Equal(t, 400, taken.Status, "место занято")
}
