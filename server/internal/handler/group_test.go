package handler_test

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/groupops"
)

type groupWorld struct {
	app        core.App
	now        time.Time
	alice, bob string
	eve        string
}

const (
	gPair = "grppairaaaaaaaa"
	gA    = "grpalice0000001"
	gB    = "grpbob000000001"
	gE    = "grpeve000000001"
)

func newGroupWorld(t *testing.T) *groupWorld {
	app := testutil.NewApp(t)
	w := &groupWorld{app: app, now: time.Date(2026, 10, 20, 12, 0, 0, 0, time.UTC)}
	svc := groupops.New(app, func() time.Time { return w.now })
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.Group(e.Router, svc, slog.New(slog.NewTextHandler(io.Discard, nil)))
		return e.Next()
	})
	testutil.Group(t, app, gPair, gA, gB)
	testutil.Group(t, app, "grppairbbbbbbbb", gE)
	_, w.alice = testutil.User(t, app, gA, gPair)
	_, w.bob = testutil.User(t, app, gB, gPair)
	_, w.eve = testutil.User(t, app, gE, "grppairbbbbbbbb")
	return w
}

func (w *groupWorld) post(t *testing.T, path, tok, body string) (int, map[string]any) {
	t.Helper()
	code, raw := testutil.Do(t, w.app, http.MethodPost, "/api/group/"+path, tok, body)
	out := map[string]any{}
	_ = json.Unmarshal([]byte(raw), &out)
	return code, out
}

func (w *groupWorld) group(t *testing.T) *core.Record {
	g, err := w.app.FindRecordById("groups", gPair)
	require.NoError(t, err)
	return g
}

func TestGroupPatchMapAndLeave(t *testing.T) {
	w := newGroupWorld(t)
	code, _ := w.post(t, "patch-map", w.alice, `{"groupId":"`+gPair+`","field":"member_moods","value":"e2e1.m"}`)
	require.Equal(t, http.StatusOK, code)
	code, _ = w.post(t, "patch-map", w.bob, `{"groupId":"`+gPair+`","field":"member_moods","value":"e2e1.b"}`)
	require.Equal(t, http.StatusOK, code)
	moods := map[string]any{}
	require.NoError(t, w.group(t).UnmarshalJSONField("member_moods", &moods))
	assert.Equal(t, map[string]any{gA: "e2e1.m", gB: "e2e1.b"}, moods)

	code, _ = w.post(t, "patch-map", w.alice, `{"groupId":"`+gPair+`","field":"member_moods","uid":"`+gB+`","value":"x"}`)
	assert.Equal(t, http.StatusForbidden, code, "от чужого имени")
	code, _ = w.post(t, "patch-map", w.alice, `{"groupId":"`+gPair+`","field":"members","value":"x"}`)
	assert.Equal(t, http.StatusBadRequest, code)
	code, _ = w.post(t, "patch-map", w.eve, `{"groupId":"`+gPair+`","field":"member_moods","value":"x"}`)
	assert.Equal(t, http.StatusForbidden, code, "не участник")
	code, _ = w.post(t, "patch-map", w.alice, `{"groupId":"nope","field":"member_moods","value":"x"}`)
	assert.Equal(t, http.StatusNotFound, code)
	code, _ = w.post(t, "patch-map", w.alice, `{"groupId":"`+gPair+`","field":"member_moods","value":null}`)
	require.Equal(t, http.StatusOK, code)
	moods = map[string]any{}
	require.NoError(t, w.group(t).UnmarshalJSONField("member_moods", &moods))
	assert.NotContains(t, moods, gA, "null удаляет ключ")

	code, res := w.post(t, "increment", w.alice, `{"groupId":"`+gPair+`","field":"xp","by":5}`)
	require.Equal(t, http.StatusOK, code)
	assert.EqualValues(t, 5, res["value"])
	code, res = w.post(t, "increment", w.alice, `{"groupId":"`+gPair+`","field":"memories_count","by":1}`)
	assert.Equal(t, true, res["noop"])
	code, _ = w.post(t, "increment", w.alice, `{"groupId":"`+gPair+`","field":"coins","by":1}`)
	assert.Equal(t, http.StatusBadRequest, code)

	code, _ = w.post(t, "leave", w.alice, `{"groupId":"`+gPair+`"}`)
	require.Equal(t, http.StatusOK, code)
	g := w.group(t)
	assert.Equal(t, []string{gB}, g.GetStringSlice("members"))
	assert.False(t, g.GetBool("disbanded"))
	code, _ = w.post(t, "leave", w.bob, `{"groupId":"`+gPair+`"}`)
	require.Equal(t, http.StatusOK, code)
	assert.True(t, w.group(t).GetBool("disbanded"), "ушёл последний")
	code, res = w.post(t, "leave", w.bob, `{"groupId":"`+gPair+`"}`)
	assert.Equal(t, http.StatusForbidden, code)
	assert.Equal(t, "pair disbanded", res["error"])
}

func TestGroupRecordActivity(t *testing.T) {
	w := newGroupWorld(t)
	col, err := w.app.FindCollectionByNameOrId("mascots")
	require.NoError(t, err)
	m := core.NewRecord(col)
	m.Set("group_id", gPair)
	m.Set("mascot_id", "cat")
	require.NoError(t, w.app.Save(m))
	g := w.group(t)
	g.Set("active_mascot_id", "cat")
	require.NoError(t, w.app.Save(g))

	day := func(tok, today string) map[string]any {
		code, res := w.post(t, "record-activity", tok, `{"groupId":"`+gPair+`","today":"`+today+`"}`)
		require.Equal(t, http.StatusOK, code, res)
		return res
	}
	assert.Equal(t, true, day(w.alice, "2026-10-20")["pending"])
	assert.Equal(t, true, day(w.alice, "2026-10-20")["pending"], "второй заход того же")
	res := day(w.bob, "2026-10-20")
	assert.EqualValues(t, 1, res["streak"])
	assert.EqualValues(t, 1, res["mascotStreak"])
	assert.Equal(t, true, day(w.alice, "2026-10-20")["already"])

	day(w.bob, "2026-10-21")
	res = day(w.alice, "2026-10-21")
	assert.EqualValues(t, 2, res["streak"])
	assert.EqualValues(t, 2, res["mascotStreak"])
	m, err = w.app.FindRecordById("mascots", m.Id)
	require.NoError(t, err)
	assert.Equal(t, 2, m.GetInt("record_streak"))

	// Пропуск дня — серия заново.
	day(w.alice, "2026-10-23")
	res = day(w.bob, "2026-10-23")
	assert.EqualValues(t, 1, res["streak"])

	code, _ := w.post(t, "record-activity", w.alice, `{"groupId":"`+gPair+`","today":"20-10-2026"}`)
	assert.Equal(t, http.StatusBadRequest, code)
	code, _ = w.post(t, "record-activity", w.eve, `{"groupId":"`+gPair+`","today":"2026-10-24"}`)
	assert.Equal(t, http.StatusForbidden, code)
}

func TestGroupMissYou(t *testing.T) {
	w := newGroupWorld(t)
	miss := func(body string) map[string]any {
		code, res := w.post(t, "miss-you", w.alice, `{"groupId":"`+gPair+`",`+body+`}`)
		require.Equal(t, http.StatusOK, code, res)
		return res
	}
	record := func() *core.Record {
		r, err := w.app.FindFirstRecordByFilter("miss_you", "user_uid = {:u}", map[string]any{"u": gA})
		require.NoError(t, err)
		return r
	}
	res := miss(`"weekday":2`)
	assert.EqualValues(t, 1, res["count"])
	assert.Nil(t, res["buffered"], "первое нажатие — сразу в базу")

	res = miss(`"count":3,"weekday":2,"vibe":"want_hug"`)
	assert.Equal(t, true, res["buffered"])
	assert.EqualValues(t, 4, res["count"], "в ответе — с накопленным")
	assert.Equal(t, 1, record().GetInt("count"), "хвост пока в памяти")

	w.now = w.now.Add(11 * time.Second)
	res = miss(`"weekday":2,"vibe":"thinking_of_you","text":"hi"`)
	assert.EqualValues(t, 5, res["count"])
	r := record()
	assert.Equal(t, 5, r.GetInt("count"))
	assert.JSONEq(t, `{"2":5}`, r.GetString("by_weekday"))
	assert.JSONEq(t, `{"miss_you":1,"want_hug":3,"thinking_of_you":1}`, r.GetString("by_vibe"))
	assert.Equal(t, "thinking_of_you", r.GetString("last_vibe"))
	assert.Equal(t, "hi", r.GetString("last_vibe_text"))

	w.now = w.now.Add(11 * time.Second)
	res = miss(`"count":99,"vibe":"hack"`)
	assert.EqualValues(t, 6, res["count"], "больше двадцати — одно нажатие")
	assert.Contains(t, record().GetString("by_vibe"), `"miss_you":2`, "чужой тип — «скучаю»")

	code, _ := w.post(t, "miss-you", w.eve, `{"groupId":"`+gPair+`"}`)
	assert.Equal(t, http.StatusForbidden, code)
}

// Продовые правила серии: соседний день (разные пояса), день — по первому,
// остаток ожидания не считается; оборванную серию маскот помнит, и её можно
// вернуть за ролик.
func TestGroupStreakRules(t *testing.T) {
	w := newGroupWorld(t)
	g := w.group(t)
	g.Set("active_mascot_id", "cat")
	require.NoError(t, w.app.Save(g))
	day := func(tok, today string) map[string]any {
		code, res := w.post(t, "record-activity", tok, `{"groupId":"`+gPair+`","today":"`+today+`"}`)
		require.Equal(t, http.StatusOK, code, res)
		return res
	}
	// У неё уже 17-е, у него ещё 16-е — день общий и считается 16-м.
	day(w.alice, "2026-10-17")
	res := day(w.bob, "2026-10-16")
	assert.EqualValues(t, 1, res["streak"])
	assert.Equal(t, "2026-10-16", w.group(t).GetString("streak_last_opened_date"))
	assert.Empty(t, w.group(t).GetString("streak_pending_uid"), "ожидание снято")
	for _, d := range []string{"2026-10-17", "2026-10-18"} {
		day(w.alice, d)
		res = day(w.bob, d)
	}
	assert.EqualValues(t, 3, res["mascotStreak"])

	// Остаток ожидания с датой закрытого дня не засчитывает новый.
	g = w.group(t)
	g.Set("streak_pending_date", "2026-10-18")
	g.Set("streak_pending_uid", gA)
	require.NoError(t, w.app.Save(g))
	assert.Equal(t, true, day(w.bob, "2026-10-19")["pending"])

	restore := func() (int, map[string]any) {
		return w.post(t, "record-activity", w.alice, `{"groupId":"`+gPair+`","today":"2026-10-22","restore":true}`)
	}
	// Пара не заходила 19–21-го: на 22-е пропуск закрывается вчерашним днём.
	code, res := restore()
	require.Equal(t, http.StatusOK, code, res)
	assert.EqualValues(t, 3, res["streak"])
	day(w.alice, "2026-10-22")
	res = day(w.bob, "2026-10-22")
	assert.EqualValues(t, 4, res["mascotStreak"], "серия продолжилась")

	// Обрыв после возврата пары: зачёт сбросил в единицу, ролик возвращает.
	day(w.alice, "2026-10-25")
	res = day(w.bob, "2026-10-25")
	assert.EqualValues(t, 1, res["mascotStreak"])
	code, res = w.post(t, "record-activity", w.alice, `{"groupId":"`+gPair+`","today":"2026-10-25","restore":true}`)
	require.Equal(t, http.StatusOK, code, res)
	assert.EqualValues(t, 5, res["streak"], "1 + прежние 4")
	code, _ = w.post(t, "record-activity", w.alice, `{"groupId":"`+gPair+`","today":"2026-10-25","restore":true}`)
	assert.Equal(t, http.StatusConflict, code, "второй раз за тот же обрыв нечего")
}
