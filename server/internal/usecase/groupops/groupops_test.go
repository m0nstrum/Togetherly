package groupops_test

import (
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/groupops"
)

const (
	pair  = "grppairaaaaaaaa"
	alice = "usralice0000001"
	bob   = "usrbob000000001"
	eve   = "usreve000000001"
)

type world struct {
	app core.App
	svc *groupops.Service
	now time.Time
}

// newWorld — пара alice+bob; часы сервиса двигает тест.
func newWorld(t *testing.T) *world {
	app := testutil.NewApp(t)
	testutil.Group(t, app, pair, alice, bob)
	w := &world{app: app, now: time.Date(2026, 10, 20, 12, 0, 0, 0, time.UTC)}
	w.svc = groupops.New(app, func() time.Time { return w.now })
	return w
}

func (w *world) group(t *testing.T) *core.Record {
	t.Helper()
	g, err := w.app.FindRecordById("groups", pair)
	require.NoError(t, err)
	return g
}

func (w *world) set(t *testing.T, fields map[string]any) {
	t.Helper()
	g := w.group(t)
	for k, v := range fields {
		g.Set(k, v)
	}
	require.NoError(t, w.app.Save(g))
}

func (w *world) streaks(t *testing.T) map[string]map[string]any {
	t.Helper()
	out := map[string]map[string]any{}
	require.NoError(t, w.group(t).UnmarshalJSONField("mascot_streaks", &out))
	return out
}

func TestCheck(t *testing.T) {
	w := newWorld(t)
	assert.NoError(t, w.svc.Check(pair))
	assert.ErrorIs(t, w.svc.Check("nope"), groupops.ErrNotFound)
	w.set(t, map[string]any{"disbanded": true})
	assert.ErrorIs(t, w.svc.Check(pair), groupops.ErrDisbanded)
}

func TestBadParamsAndStrangers(t *testing.T) {
	w := newWorld(t)
	assert.ErrorIs(t, w.svc.PatchMap("", alice, "member_moods", "x"), groupops.ErrBadParams)
	assert.ErrorIs(t, w.svc.PatchMap(pair, "", "member_moods", "x"), groupops.ErrBadParams)
	assert.ErrorIs(t, w.svc.PatchMap(pair, alice, "streak_days", 99), groupops.ErrBadParams,
		"правятся только словари участников")
	assert.ErrorIs(t, w.svc.PatchMap(pair, eve, "member_moods", "x"), groupops.ErrNotMember)
	assert.ErrorIs(t, w.svc.PatchMap("nope", alice, "member_moods", "x"), groupops.ErrNotFound)

	_, err := w.svc.Increment(pair, eve, "xp", 1)
	assert.ErrorIs(t, err, groupops.ErrNotMember)
	_, err = w.svc.Increment("", alice, "xp", 1)
	assert.ErrorIs(t, err, groupops.ErrBadParams)
	res, err := w.svc.Increment(pair, eve, "drawings_count", 1)
	require.NoError(t, err, "счётчики сервера — «готово» без проверок и записи")
	assert.True(t, res.Noop)

	assert.ErrorIs(t, w.svc.Leave(pair, ""), groupops.ErrBadParams)
	assert.ErrorIs(t, w.svc.Leave(pair, eve), groupops.ErrNotMember)

	for _, day := range []string{"", "2026-1-2", "20-10-2026", "2026-02-30"} {
		_, err = w.svc.RecordActivity(pair, alice, day)
		assert.ErrorIs(t, err, groupops.ErrBadParams, day)
		_, err = w.svc.RestoreStreak(pair, alice, day)
		assert.ErrorIs(t, err, groupops.ErrBadParams, day)
	}
	_, err = w.svc.RecordActivity(pair, eve, "2026-10-20")
	assert.ErrorIs(t, err, groupops.ErrNotMember)
	_, err = w.svc.MissYou(groupops.MissInput{GroupID: pair})
	assert.ErrorIs(t, err, groupops.ErrBadParams)
}

func TestIncrementAccumulates(t *testing.T) {
	w := newWorld(t)
	for _, by := range []float64{5, 3, -2} {
		_, err := w.svc.Increment(pair, alice, "xp", by)
		require.NoError(t, err)
	}
	res, err := w.svc.Increment(pair, bob, "xp", 4)
	require.NoError(t, err)
	assert.EqualValues(t, 10, res.Value)
	assert.Equal(t, 10, w.group(t).GetInt("xp"))
}

// Ушедший уносит свои ключи из словарей; партнёрские остаются. Ушёл
// последний — пара распалась, время — по часам сервиса.
func TestLeaveCleansMemberMaps(t *testing.T) {
	w := newWorld(t)
	for _, f := range []string{"member_names", "member_avatars", "member_moods", "member_ailments"} {
		require.NoError(t, w.svc.PatchMap(pair, alice, f, "e2e1.a"))
		require.NoError(t, w.svc.PatchMap(pair, bob, f, "e2e1.b"))
	}
	require.NoError(t, w.svc.Leave(pair, alice))
	g := w.group(t)
	assert.Equal(t, []string{bob}, g.GetStringSlice("members"))
	for _, f := range []string{"member_names", "member_avatars", "member_moods", "member_ailments"} {
		m := map[string]any{}
		require.NoError(t, g.UnmarshalJSONField(f, &m))
		assert.Equal(t, map[string]any{bob: "e2e1.b"}, m, f)
	}
	assert.False(t, g.GetBool("disbanded"))

	w.now = time.Date(2026, 10, 21, 8, 30, 0, 0, time.UTC)
	require.NoError(t, w.svc.Leave(pair, bob))
	g = w.group(t)
	assert.Empty(t, g.GetStringSlice("members"))
	assert.True(t, g.GetBool("disbanded"))
	assert.True(t, g.GetDateTime("disbanded_at").Time().Equal(w.now))
}

// Ожидание: повторный заход того же человека не двигает дату, а его же заход
// через день — двигает; отметка партнёра двухдневной давности — не общий
// день, ожидать начинает пришедший.
func TestPendingDay(t *testing.T) {
	w := newWorld(t)
	_, err := w.svc.RecordActivity(pair, alice, "2026-10-20")
	require.NoError(t, err)
	res, err := w.svc.RecordActivity(pair, alice, "2026-10-21")
	require.NoError(t, err)
	assert.True(t, res.Pending)
	assert.Equal(t, "2026-10-20", w.group(t).GetString("streak_pending_date"),
		"соседний день того же — та же отметка")

	_, err = w.svc.RecordActivity(pair, alice, "2026-10-23")
	require.NoError(t, err)
	assert.Equal(t, "2026-10-23", w.group(t).GetString("streak_pending_date"))

	res, err = w.svc.RecordActivity(pair, bob, "2026-10-25")
	require.NoError(t, err)
	assert.True(t, res.Pending, "партнёр был два дня назад — день не общий")
	g := w.group(t)
	assert.Equal(t, bob, g.GetString("streak_pending_uid"))
	assert.Equal(t, "2026-10-25", g.GetString("streak_pending_date"))
	assert.Zero(t, g.GetInt("streak_days"))
}

func both(t *testing.T, w *world, day string) groupops.Activity {
	t.Helper()
	_, err := w.svc.RecordActivity(pair, alice, day)
	require.NoError(t, err)
	res, err := w.svc.RecordActivity(pair, bob, day)
	require.NoError(t, err)
	require.False(t, res.Pending, day)
	return res
}

// Обрыв серии маскота от двух дней запоминается: сколько было, когда
// оборвалось и сколько потеряла пара — для возврата за ролик.
func TestBrokenStreakIsRemembered(t *testing.T) {
	w := newWorld(t)
	w.set(t, map[string]any{"active_mascot_id": "cat"})
	for _, d := range []string{"2026-10-10", "2026-10-11", "2026-10-12"} {
		both(t, w, d)
	}
	res := both(t, w, "2026-10-15")
	assert.Equal(t, 1, res.Streak)
	assert.Equal(t, 1, res.MascotStreak)
	cat := w.streaks(t)["cat"]
	assert.EqualValues(t, 3, cat["lost"])
	assert.Equal(t, "2026-10-15", cat["lost_d"])
	assert.EqualValues(t, 3, cat["lost_g"], "пара потеряла свои три дня")
	assert.EqualValues(t, 3, cat["best"])

	// Серия маскота с одного дня — помнить нечего.
	w2 := newWorld(t)
	w2.set(t, map[string]any{"active_mascot_id": "cat"})
	both(t, w2, "2026-10-10")
	both(t, w2, "2026-10-15")
	assert.NotContains(t, w2.streaks(t)["cat"], "lost")
}

// Память обрыва едет за серией, пока та идёт подряд, и не теряется при
// сменах дня.
func TestLostMemoryCarriesWhileInRow(t *testing.T) {
	w := newWorld(t)
	w.set(t, map[string]any{"active_mascot_id": "cat"})
	for _, d := range []string{"2026-10-10", "2026-10-11", "2026-10-14", "2026-10-15"} {
		both(t, w, d)
	}
	cat := w.streaks(t)["cat"]
	assert.EqualValues(t, 2, cat["s"])
	assert.EqualValues(t, 2, cat["lost"])
	assert.Equal(t, "2026-10-14", cat["lost_d"])
}

func TestRestoreWindow(t *testing.T) {
	w := newWorld(t)
	_, err := w.svc.RestoreStreak(pair, alice, "2026-10-20")
	assert.ErrorIs(t, err, groupops.ErrNothingToRestore, "маскота нет")
	_, err = w.svc.RestoreStreak(pair, eve, "2026-10-20")
	assert.ErrorIs(t, err, groupops.ErrNotMember)

	w.set(t, map[string]any{"active_mascot_id": "cat"})
	for _, d := range []string{"2026-10-10", "2026-10-11", "2026-10-12"} {
		both(t, w, d)
	}
	// Вчера ещё были — пропуска нет, возвращать нечего.
	_, err = w.svc.RestoreStreak(pair, alice, "2026-10-13")
	assert.ErrorIs(t, err, groupops.ErrNothingToRestore)
	// Пропуск дольше окна — поздно.
	_, err = w.svc.RestoreStreak(pair, alice, "2026-10-17")
	assert.ErrorIs(t, err, groupops.ErrNothingToRestore)

	// Обрыв после возврата пары: в окне трёх дней — да, позже — нет.
	both(t, w, "2026-10-15")
	_, err = w.svc.RestoreStreak(pair, alice, "2026-10-19")
	assert.ErrorIs(t, err, groupops.ErrNothingToRestore, "четыре дня после обрыва")
	out, err := w.svc.RestoreStreak(pair, alice, "2026-10-18")
	require.NoError(t, err)
	assert.Equal(t, 4, out.Streak, "1 + прежние 3")
	assert.Equal(t, 4, out.GroupStreak)
	assert.Equal(t, 4, w.group(t).GetInt("streak_days"))
	cat := w.streaks(t)["cat"]
	assert.NotContains(t, cat, "lost", "память обрыва потрачена")
	assert.EqualValues(t, 4, cat["best"])
}

// Рекорд серии пишется маскоту из галереи и только вверх.
func TestRecordStreakOnlyGrows(t *testing.T) {
	w := newWorld(t)
	col, err := w.app.FindCollectionByNameOrId("mascots")
	require.NoError(t, err)
	m := core.NewRecord(col)
	m.Set("group_id", pair)
	m.Set("mascot_id", "cat")
	m.Set("record_streak", 2)
	require.NoError(t, w.app.Save(m))
	w.set(t, map[string]any{"active_mascot_id": "cat"})

	record := func() int {
		r, err := w.app.FindRecordById("mascots", m.Id)
		require.NoError(t, err)
		return r.GetInt("record_streak")
	}
	both(t, w, "2026-10-10")
	assert.Equal(t, 2, record(), "единица не затирает рекорд")
	both(t, w, "2026-10-11")
	both(t, w, "2026-10-12")
	assert.Equal(t, 3, record())
}

func missRecord(t *testing.T, w *world, uid string) *core.Record {
	t.Helper()
	r, err := w.app.FindFirstRecordByFilter("miss_you", "user_uid = {:u}", map[string]any{"u": uid})
	require.NoError(t, err)
	return r
}

// Нажатия без дня недели копятся под «0» и при выгрузке ложатся на день
// записи; запись без дня — по UTC сервера (воскресенье — 7).
func TestMissYouWeekdayFallback(t *testing.T) {
	w := newWorld(t)
	w.now = time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC) // воскресенье
	_, err := w.svc.MissYou(groupops.MissInput{GroupID: pair, UID: alice})
	require.NoError(t, err)
	assert.JSONEq(t, `{"7":1}`, missRecord(t, w, alice).GetString("by_weekday"))

	res, err := w.svc.MissYou(groupops.MissInput{GroupID: pair, UID: alice, Times: 2})
	require.NoError(t, err)
	require.True(t, res.Buffered)
	w.now = w.now.Add(11 * time.Second)
	res, err = w.svc.MissYou(groupops.MissInput{GroupID: pair, UID: alice, Weekday: 3})
	require.NoError(t, err)
	assert.Equal(t, 4, res.Count)
	assert.JSONEq(t, `{"7":1,"3":3}`, missRecord(t, w, alice).GetString("by_weekday"),
		"хвост без дня — на день этой записи")
}

// Старая пара без карты по типам: весь прежний счёт — «скучаю».
func TestMissYouLegacyVibes(t *testing.T) {
	w := newWorld(t)
	col, err := w.app.FindCollectionByNameOrId("miss_you")
	require.NoError(t, err)
	r := core.NewRecord(col)
	r.Set("group_id", pair)
	r.Set("user_uid", alice)
	r.Set("count", 40)
	require.NoError(t, w.app.Save(r))

	res, err := w.svc.MissYou(groupops.MissInput{GroupID: pair, UID: alice, Vibe: "want_hug", Weekday: 1})
	require.NoError(t, err)
	assert.Equal(t, 41, res.Count)
	assert.JSONEq(t, `{"miss_you":40,"want_hug":1}`, missRecord(t, w, alice).GetString("by_vibe"))
}

// Счёт у каждого свой: нажатия партнёра не попадают в чужую запись и окно.
func TestMissYouPerPerson(t *testing.T) {
	w := newWorld(t)
	_, err := w.svc.MissYou(groupops.MissInput{GroupID: pair, UID: alice})
	require.NoError(t, err)
	res, err := w.svc.MissYou(groupops.MissInput{GroupID: pair, UID: bob})
	require.NoError(t, err)
	assert.False(t, res.Buffered, "окно alice не задерживает bob")
	assert.Equal(t, 1, res.Count)
	assert.Equal(t, 1, missRecord(t, w, alice).GetInt("count"))
}

// Запись не прошла (человека убрали из пары) — копилка сбрасывается, и
// накопленное не уезжает следующей записью, если человека вернули.
func TestMissYouDropsBufferOfStranger(t *testing.T) {
	w := newWorld(t)
	_, err := w.svc.MissYou(groupops.MissInput{GroupID: pair, UID: alice})
	require.NoError(t, err)
	_, err = w.svc.MissYou(groupops.MissInput{GroupID: pair, UID: alice, Times: 5})
	require.NoError(t, err)

	w.set(t, map[string]any{"members": []string{bob}})
	w.now = w.now.Add(11 * time.Second)
	_, err = w.svc.MissYou(groupops.MissInput{GroupID: pair, UID: alice})
	assert.ErrorIs(t, err, groupops.ErrNotMember)

	w.set(t, map[string]any{"members": []string{alice, bob}})
	res, err := w.svc.MissYou(groupops.MissInput{GroupID: pair, UID: alice})
	require.NoError(t, err)
	assert.False(t, res.Buffered, "окно убрано вместе с копилкой")
	assert.Equal(t, 2, res.Count, "1 прежнее + 1 новое, без пяти из копилки")
}
