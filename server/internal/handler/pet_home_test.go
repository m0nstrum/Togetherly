package handler_test

import (
	"encoding/json"
	"fmt"
	"github.com/m0nstrum/togetherly/server/internal/usecase/groupops"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/pethome"
	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/require"
)

func TestPetHomeAccessCASAndRetry(t *testing.T) {
	app := testutil.NewApp(t)
	app.OnServe().BindFunc(func(e *core.ServeEvent) error { handler.PetHome(e.Router, pethome.New(app)); return e.Next() })
	testutil.Group(t, app, gPair, gA, gB)
	_, alice := testutil.User(t, app, gA, gPair)
	_, bob := testutil.User(t, app, gB, gPair)
	_, eve := testutil.User(t, app, gE)
	path := "/api/pet-home/" + gPair
	post := func(token string, revision int, op string, state string) (int, string) {
		b, _ := json.Marshal(map[string]any{"revision": revision, "operation": op, "state": state})
		return testutil.Do(t, app, http.MethodPost, path, token, string(b))
	}
	state := "e2e1." + strings.Repeat("a", 100)
	op := strings.Repeat("a", 32)
	code, _ := testutil.Do(t, app, http.MethodGet, path, "", "")
	require.Equal(t, 401, code)
	code, _ = testutil.Do(t, app, http.MethodGet, path, eve, "")
	require.Equal(t, 403, code)
	code, raw := testutil.Do(t, app, http.MethodGet, path, alice, "")
	require.Equal(t, 200, code)
	require.Contains(t, raw, `"revision":0`)
	code, _ = post(alice, 0, op, `{"home":"plaintext"}`)
	require.Equal(t, 400, code)
	code, raw = post(alice, 0, op, state)
	require.Equal(t, 200, code)
	require.Contains(t, raw, `"revision":1`)
	require.NotContains(t, raw, "operations")
	code, raw = post(alice, 0, op, state)
	require.Equal(t, 200, code)
	require.Contains(t, raw, `"revision":1`)
	code, _ = post(bob, 0, strings.Repeat("b", 32), state)
	require.Equal(t, 409, code)
	code, _ = post(eve, 1, strings.Repeat("c", 32), state)
	require.Equal(t, 403, code)
	code, _ = testutil.Do(t, app, http.MethodPost, "/api/collections/pet_homes/records", alice, `{"group_id":"`+gPair+`","state":"x"}`)
	require.Equal(t, 403, code)
	// Two clients race from the same version: exactly one can commit.
	_ = testutil.Router(t, app)
	var wg sync.WaitGroup
	codes := make(chan int, 2)
	for i, token := range []string{alice, bob} {
		wg.Add(1)
		go func(i int, token string) {
			defer wg.Done()
			code, _ := post(token, 1, fmt.Sprintf("%032x", i+1), state)
			codes <- code
		}(i, token)
	}
	wg.Wait()
	close(codes)
	got := map[int]int{}
	for c := range codes {
		got[c]++
	}
	require.Equal(t, map[int]int{200: 1, 409: 1}, got)
	r, err := app.FindFirstRecordByData("pet_homes", "group_id", gPair)
	require.NoError(t, err)
	code, _ = testutil.Do(t, app, http.MethodPatch, "/api/collections/pet_homes/records/"+r.Id, alice, `{"revision":999}`)
	require.Equal(t, 403, code)
	code, _ = testutil.Do(t, app, http.MethodDelete, "/api/collections/pet_homes/records/"+r.Id, alice, "")
	require.Equal(t, 403, code)
	// Revocation is checked against current group contents, not a stale JWT.
	g, err := app.FindRecordById("groups", gPair)
	require.NoError(t, err)
	g.Set("members", []string{gA})
	require.NoError(t, app.Save(g))
	code, _ = post(bob, 2, strings.Repeat("d", 32), state)
	require.Equal(t, 403, code)
	code, _ = testutil.Do(t, app, http.MethodGet, path, bob, "")
	require.Equal(t, 403, code)
	g.Set("disbanded", true)
	require.NoError(t, app.Save(g))
	code, _ = post(alice, 2, strings.Repeat("e", 32), state)
	require.Equal(t, 403, code)
	code, _ = testutil.Do(t, app, http.MethodGet, path, alice, "")
	require.Equal(t, 200, code, "archive remains readable")
}

func TestPetGrowthSurvivesStreakReset(t *testing.T) {
	w := newGroupWorld(t)
	g, err := w.app.FindRecordById("groups", gPair)
	require.NoError(t, err)
	g.Set("active_mascot_id", "catalog_pet")
	g.Set("streak_last_opened_date", "2026-10-01")
	g.Set("mascot_streaks", map[string]any{"catalog_pet": map[string]any{"s": 30, "d": "2026-10-01"}})
	require.NoError(t, w.app.Save(g))
	svc := groupops.New(w.app, func() time.Time { return w.now })
	_, err = svc.RecordActivity(gPair, gA, "2026-10-20")
	require.NoError(t, err)
	_, err = svc.RecordActivity(gPair, gB, "2026-10-20")
	require.NoError(t, err)
	g, err = w.app.FindRecordById("groups", gPair)
	require.NoError(t, err)
	var states map[string]map[string]any
	require.NoError(t, g.UnmarshalJSONField("mascot_streaks", &states))
	require.EqualValues(t, 1, states["catalog_pet"]["s"])
	require.EqualValues(t, 30, states["catalog_pet"]["best"])
	w.now = w.now.AddDate(0, 0, 1)
	_, err = svc.RecordActivity(gPair, gA, "2026-10-21")
	require.NoError(t, err)
	_, err = svc.RecordActivity(gPair, gB, "2026-10-21")
	require.NoError(t, err)
	g, err = w.app.FindRecordById("groups", gPair)
	require.NoError(t, err)
	require.NoError(t, g.UnmarshalJSONField("mascot_streaks", &states))
	require.EqualValues(t, 2, states["catalog_pet"]["s"])
	require.EqualValues(t, 30, states["catalog_pet"]["best"])
}
