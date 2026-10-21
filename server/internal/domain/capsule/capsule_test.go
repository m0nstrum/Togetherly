package capsule_test

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"

	"github.com/m0nstrum/togetherly/server/internal/domain/capsule"
)

var now = time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC)

func sealedData() map[string]any {
	return map[string]any{
		"type": "photo", "authorUid": "alice", "sealed": true,
		"openAt": "2027-01-01T00:00:00.000Z", "imageUrl": "pb://media/x/y.webp",
		"description": "секрет", "latitude": 55.75, "reactions": map[string]any{"bob": "❤"},
	}
}

func TestSealed(t *testing.T) {
	d := sealedData()
	assert.True(t, capsule.Sealed(d, now))
	assert.False(t, capsule.Sealed(d, time.Date(2027, 1, 1, 0, 0, 1, 0, time.UTC)))
	d["sealed"] = false
	assert.False(t, capsule.Sealed(d, now))
	assert.False(t, capsule.Sealed(map[string]any{"sealed": true, "openAt": "когда-нибудь"}, now))
	assert.False(t, capsule.Sealed(nil, now))
}

func TestRedact(t *testing.T) {
	r := capsule.Redact(sealedData())
	assert.Equal(t, "photo", r["type"])
	assert.Equal(t, "2027-01-01T00:00:00.000Z", r["openAt"])
	assert.Contains(t, r, "reactions")
	for _, hidden := range []string{"imageUrl", "description", "latitude"} {
		assert.NotContains(t, r, hidden)
	}
}

func TestMergeUpdate(t *testing.T) {
	stored := sealedData()

	t.Run("обрезанная копия не стирает содержимое", func(t *testing.T) {
		in := capsule.Redact(stored)
		in["reactions"] = map[string]any{"bob": "😂"}
		out := capsule.MergeUpdate(stored, in, false)
		assert.Equal(t, "секрет", out["description"])
		assert.Equal(t, map[string]any{"bob": "😂"}, out["reactions"])
	})

	t.Run("подмена содержимого не проходит", func(t *testing.T) {
		in := sealedData()
		in["description"] = "подмена"
		assert.Equal(t, "секрет", capsule.MergeUpdate(stored, in, true)["description"])
	})

	t.Run("партнёр не распечатывает раньше срока", func(t *testing.T) {
		in := capsule.Redact(stored)
		in["sealed"] = false
		in["openAt"] = "2026-01-01T00:00:00.000Z"
		out := capsule.MergeUpdate(stored, in, false)
		assert.Equal(t, true, out["sealed"])
		assert.Equal(t, "2027-01-01T00:00:00.000Z", out["openAt"])
	})

	t.Run("автор меняет дату", func(t *testing.T) {
		in := capsule.Redact(stored)
		in["openAt"] = "2026-12-01T00:00:00.000Z"
		assert.Equal(t, "2026-12-01T00:00:00.000Z", capsule.MergeUpdate(stored, in, true)["openAt"])
	})

	t.Run("отметку открытия ставит только сервер", func(t *testing.T) {
		in := capsule.Redact(stored)
		in[capsule.OpenedMark] = true
		assert.NotContains(t, capsule.MergeUpdate(stored, in, true), capsule.OpenedMark)
	})
}

// После E2E (S9) содержимое лежит шифром в ключе `e2e` — его капсула прячет
// так же, как открытое содержимое раньше.
func TestRedactHidesCiphertext(t *testing.T) {
	d := map[string]any{"sealed": true, "openAt": "2027-01-01T00:00:00.000Z", "e2e": "e2e1.g:1.n.c"}
	assert.NotContains(t, capsule.Redact(d), "e2e")
	in := capsule.Redact(d)
	in["e2e"] = "e2e1.g:1.n.подмена"
	assert.Equal(t, "e2e1.g:1.n.c", capsule.MergeUpdate(d, in, true)["e2e"])
}
