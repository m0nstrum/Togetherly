package memory_test

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"

	"github.com/m0nstrum/togetherly/server/internal/domain/memory"
)

func TestClampFuture(t *testing.T) {
	now := time.Date(2026, 10, 12, 12, 0, 0, 0, time.UTC)
	var zero time.Time
	day := 24 * time.Hour

	c, a := memory.ClampFuture(now.Add(7*day), zero, now)
	assert.Equal(t, now, c, "дата из будущего — сегодня")
	assert.True(t, a.IsZero())

	// Часы спешат на сутки: «два дня назад» по ним — два дня назад по нашим.
	c, a = memory.ClampFuture(now.Add(-day), now.Add(day), now)
	assert.Equal(t, now.Add(-2*day), c)
	assert.Equal(t, now, a)

	c, _ = memory.ClampFuture(now.Add(-30*day), zero, now)
	assert.Equal(t, now.Add(-30*day), c, "прошлое не трогаем")
	c, _ = memory.ClampFuture(now.Add(time.Minute), zero, now)
	assert.Equal(t, now.Add(time.Minute), c, "в пределах допуска")
}

func TestParseDate(t *testing.T) {
	want := time.Date(2026, 10, 19, 8, 30, 0, 123000000, time.UTC)
	for _, s := range []string{"2026-10-19T08:30:00.123Z", "2026-10-19 08:30:00.123Z", "2026-10-19T11:30:00.123+03:00", "2026-10-19T08:30:00.123"} {
		assert.Equal(t, want, memory.ParseDate(s), s)
	}
	assert.True(t, memory.ParseDate("nope").IsZero())
	assert.Equal(t, "2026-10-19T08:30:00.123000Z", memory.FormatDate(want))
}
