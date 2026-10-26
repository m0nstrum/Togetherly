package stats_test

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/stats"
)

func save(t *testing.T, app core.App, col string, fields map[string]any) {
	t.Helper()
	c, err := app.FindCollectionByNameOrId(col)
	require.NoError(t, err)
	r := core.NewRecord(c)
	for k, v := range fields {
		r.Set(k, v)
	}
	require.NoError(t, app.Save(r))
}

// T2: счётчики пары по метаданным, без содержимого и без чужой пары.
func TestCoupleAgg(t *testing.T) {
	app := testutil.NewApp(t)
	now := time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC) // воскресенье
	ms := func(d time.Time) int64 { return d.UnixMilli() }
	day := 24 * time.Hour

	save(t, app, "chat_messages", map[string]any{"group_id": "g1", "user_uid": "a", "text": "e2e1.x", "ts": ms(now.Add(-time.Hour))})
	save(t, app, "chat_messages", map[string]any{"group_id": "g1", "user_uid": "b", "text": "e2e1.y", "ts": ms(now.Add(-40 * day))})
	save(t, app, "chat_messages", map[string]any{"group_id": "g1", "user_uid": "a", "ts": ms(now.Add(-2 * time.Hour)), "deleted": true})
	save(t, app, "chat_messages", map[string]any{"group_id": "g2", "user_uid": "c", "ts": ms(now)})
	save(t, app, "memories", map[string]any{"group_id": "g1", "author_uid": "a", "type": "photo", "created_at": now.Add(-3 * day)})
	save(t, app, "memories", map[string]any{"group_id": "g1", "author_uid": "b", "type": "photo", "created_at": now.Add(-400 * day)})
	save(t, app, "memories", map[string]any{"group_id": "g1", "author_uid": "b", "type": "note", "created_at": now.Add(-1 * day)})
	save(t, app, "mood_entries", map[string]any{"group_id": "g1", "user_uid": "b", "mood_id": "e2e1.z", "timestamp": now.Add(-5 * day)})

	out, err := stats.New(app).CoupleAgg(context.Background(), "g1", now)
	require.NoError(t, err)
	raw, _ := json.Marshal(out)
	var got map[string]any
	require.NoError(t, json.Unmarshal(raw, &got))

	assert.EqualValues(t, 2, got["messages"], "удалённое и чужая пара не считаются")
	assert.EqualValues(t, 3, got["memories_total"])
	assert.EqualValues(t, 1, got["moods"])
	assert.EqualValues(t, 1, got["messages30"])
	assert.EqualValues(t, 2, got["messages90"])
	assert.EqualValues(t, 2, got["memories30"])
	assert.EqualValues(t, 1, got["moods30"])
	assert.EqualValues(t, 4, got["active_days30_count"], "сегодня, −1, −3, −5 дней")
	assert.ElementsMatch(t, []any{
		map[string]any{"uid": "a", "c": 1.0}, map[string]any{"uid": "b", "c": 1.0},
	}, got["by_member_messages"])
	assert.Equal(t, []any{
		map[string]any{"k": "photo", "c": 2.0}, map[string]any{"k": "note", "c": 1.0},
	}, got["memory_types"])
	assert.Equal(t, []any{
		map[string]any{"m": "2026-09", "c": 1.0}, map[string]any{"m": "2026-10", "c": 1.0},
	}, got["timeline_messages"])
	assert.Len(t, got["timeline_memories"], 1, "воспоминание старше года — вне ряда")
	assert.Contains(t, got["weekday_messages"], map[string]any{"d": 0.0, "c": 1.0}, "воскресенье = 0")
	assert.Contains(t, got["hour_messages"], map[string]any{"h": 11.0, "c": 1.0}, "часы по UTC")
	assert.Contains(t, got["first_memory"], "2025-09-20")
	assert.Equal(t, []any{}, got["mood_top"], "настроения — шифр, их считает клиент")
	assert.NotContains(t, string(raw), "e2e1.", "содержимое не выходит")

	n, err := stats.New(app).Count(context.Background(), "canvas_strokes", "g1")
	require.NoError(t, err)
	assert.Equal(t, 0, n)
	_, err = stats.New(app).Count(context.Background(), "users", "g1")
	assert.ErrorIs(t, err, stats.ErrUnknownCol)
}
