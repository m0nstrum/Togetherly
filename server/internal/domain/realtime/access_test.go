package realtime_test

import (
	"testing"

	"github.com/pocketbase/pocketbase/tools/security"
	"github.com/stretchr/testify/assert"

	"github.com/m0nstrum/togetherly/server/internal/domain/realtime"
)

func TestSubscribeScope(t *testing.T) {
	for channel, want := range map[string]realtime.Scope{
		"pair:g1":              {Kind: "pair", Target: "g1"},
		"signal:g1":            {Kind: "pair", Target: "g1"},
		"draw:g1":              {Kind: "pair", Target: "g1"},
		"user:u2":              {Kind: "user", Target: "u2"},
		"loc:pair_u1_u2":       {Kind: "loc", A: "u1", B: "u2"},
		"locsignal:pair_u2_u1": {Kind: "loc", A: "u2", B: "u1"},
		"loc:pair_u2_u3":       {},
		"loc:u1_u2":            {},
		"watch:abcdefgh":       {Kind: "watch", Target: "abcdefgh"},
		"server:x":             {},
		"pair":                 {},
	} {
		assert.Equal(t, want, realtime.SubscribeScope(channel, "u1"), channel)
	}
}

// Код комнаты обязан совпадать с тем, что считают JS-хуки и страница.
func TestRoomCode(t *testing.T) {
	const abc = "abcdefghjkmnpqrstuvwxyz23456789"
	digest := security.HS256("grp123456789012", "s3cret")
	want := ""
	for i := range 8 {
		want += string(abc[int(digest[i])%len(abc)])
	}
	assert.Equal(t, want, realtime.RoomCode("grp123456789012", "s3cret"))
	assert.Len(t, want, 8)
	assert.NotEqual(t, want, realtime.RoomCode("grp123456789012", "other"))
}
