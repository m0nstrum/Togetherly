package pairs_test

import (
	"context"
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	_ "github.com/m0nstrum/togetherly/server/internal/migrations"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
)

func newApp(t *testing.T) *tests.TestApp {
	t.Helper()
	return testutil.NewApp(t)
}

func group(t *testing.T, app core.App, members []string, disbanded bool) *core.Record {
	t.Helper()
	col, err := app.FindCollectionByNameOrId("groups")
	require.NoError(t, err)
	g := core.NewRecord(col)
	g.Set("members", members)
	g.Set("max_members", 2)
	g.Set("disbanded", disbanded)
	require.NoError(t, app.Save(g))
	return g
}

func reload(t *testing.T, app core.App, id string) *core.Record {
	t.Helper()
	g, err := app.FindRecordById("groups", id)
	require.NoError(t, err)
	return g
}

func TestAccept(t *testing.T) {
	ctx := context.Background()

	t.Run("новая пара", func(t *testing.T) {
		app := newApp(t)
		res, err := pairs.New(app).Accept(ctx, pairs.AcceptInput{OwnerUID: "alice", MyUID: "bob", OwnerName: "Алиса", MyName: "Боб"})
		require.NoError(t, err)
		require.True(t, res.Success)
		g := reload(t, app, res.PairID)
		assert.ElementsMatch(t, []string{"alice", "bob"}, pairs.Members(g))
		assert.Contains(t, g.GetString("member_names"), "Боб")
	})

	t.Run("вход в живую пару приглашающего с местом", func(t *testing.T) {
		app := newApp(t)
		g := group(t, app, []string{"alice"}, false)
		res, err := pairs.New(app).Accept(ctx, pairs.AcceptInput{OwnerUID: "alice", MyUID: "bob"})
		require.NoError(t, err)
		assert.Equal(t, g.Id, res.PairID)
		assert.Equal(t, "Joined the group!", res.Message)
		assert.ElementsMatch(t, []string{"alice", "bob"}, pairs.Members(reload(t, app, g.Id)))
	})

	t.Run("повтор своего кода — та же пара", func(t *testing.T) {
		app := newApp(t)
		g := group(t, app, []string{"alice", "bob"}, false)
		res, err := pairs.New(app).Accept(ctx, pairs.AcceptInput{OwnerUID: "alice", MyUID: "bob", CodeGroupID: g.Id})
		require.NoError(t, err)
		assert.True(t, res.Success)
		assert.Equal(t, g.Id, res.PairID)
	})

	t.Run("пара по коду заполнена", func(t *testing.T) {
		app := newApp(t)
		g := group(t, app, []string{"alice", "carol"}, false)
		res, err := pairs.New(app).Accept(ctx, pairs.AcceptInput{OwnerUID: "alice", MyUID: "bob", CodeGroupID: g.Id})
		require.NoError(t, err)
		assert.False(t, res.Success)
		assert.Equal(t, "Группа заполнена", res.Message)
	})

	t.Run("общая распущенная пара поднимается", func(t *testing.T) {
		app := newApp(t)
		g := group(t, app, []string{"alice", "bob"}, true)
		res, err := pairs.New(app).Accept(ctx, pairs.AcceptInput{OwnerUID: "alice", MyUID: "bob"})
		require.NoError(t, err)
		assert.True(t, res.Restored)
		assert.Equal(t, g.Id, res.PairID)
		assert.False(t, reload(t, app, g.Id).GetBool("disbanded"))
	})

	t.Run("подстрока чужого id не делает участником", func(t *testing.T) {
		app := newApp(t)
		group(t, app, []string{"xalicex", "bob"}, false)
		res, err := pairs.New(app).Accept(ctx, pairs.AcceptInput{OwnerUID: "alice", MyUID: "dave"})
		require.NoError(t, err)
		assert.ElementsMatch(t, []string{"alice", "dave"}, pairs.Members(reload(t, app, res.PairID)))
	})

	t.Run("неверные параметры", func(t *testing.T) {
		res, err := pairs.New(newApp(t)).Accept(ctx, pairs.AcceptInput{OwnerUID: "a", MyUID: "a"})
		require.NoError(t, err)
		assert.False(t, res.Success)
	})
}

func TestWrite(t *testing.T) {
	ctx := context.Background()
	app := newApp(t)
	g := group(t, app, []string{"alice", "bob"}, false)
	svc := pairs.New(app)

	_, err := svc.Write(ctx, pairs.WriteInput{
		GroupID: g.Id,
		Set:     map[string]any{"relationship_type": "married", "nope": 1},
		Inc:     map[string]float64{"memories_count": 2, "drawings_count": -5},
		MapSet:  map[string]map[string]any{"member_moods": {"alice": "happy"}},
		ArrAdd:  map[string][]any{"custom_statuses": {"a", "a", "b"}},
	})
	require.NoError(t, err)
	got := reload(t, app, g.Id)
	assert.Equal(t, "married", got.GetString("relationship_type"))
	assert.Equal(t, 2, got.GetInt("memories_count"))
	assert.Equal(t, 0, got.GetInt("drawings_count"), "счётчик не уходит в минус")
	assert.JSONEq(t, `{"alice":"happy"}`, got.GetString("member_moods"))
	assert.JSONEq(t, `["a","b"]`, got.GetString("custom_statuses"))

	_, err = svc.Write(ctx, pairs.WriteInput{GroupID: g.Id, MapDel: map[string][]string{"member_moods": {"alice"}}})
	require.NoError(t, err)
	assert.JSONEq(t, `{}`, reload(t, app, g.Id).GetString("member_moods"))

	_, err = svc.Write(ctx, pairs.WriteInput{GroupID: "missingmissing1"})
	assert.ErrorIs(t, err, pairs.ErrNotFound)

	created, err := svc.Write(ctx, pairs.WriteInput{GroupID: "newgroupnewgrp1", Mode: "create", Set: map[string]any{"members": []string{"x"}}})
	require.NoError(t, err)
	assert.Equal(t, "newgroupnewgrp1", created.Id)
}
