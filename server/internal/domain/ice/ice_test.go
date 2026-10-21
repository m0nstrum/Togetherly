package ice_test

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/domain/ice"
)

func TestServers(t *testing.T) {
	now := time.Unix(1_800_000_000, 0)

	t.Run("без своего coturn серверов нет, чужих тоже", func(t *testing.T) {
		assert.Empty(t, ice.Servers(ice.TURN{}, "u1", now))
	})

	t.Run("без секрета — только свой STUN", func(t *testing.T) {
		got := ice.Servers(ice.TURN{Host: "turn.example.org"}, "u1", now)
		require.Len(t, got, 1)
		assert.Equal(t, []string{"stun:turn.example.org:3478"}, got[0].URLs)
	})

	t.Run("с секретом — временный TURN", func(t *testing.T) {
		got := ice.Servers(ice.TURN{Host: "turn.example.org", Port: 5349, Secret: "s", TTL: time.Hour}, "u1", now)
		require.Len(t, got, 2)
		turn := got[1]
		assert.Equal(t, "1800003600:u1", turn.Username)
		assert.NotEmpty(t, turn.Credential)
		assert.Contains(t, turn.URLs, "turn:turn.example.org:5349?transport=udp")
		for _, s := range got {
			for _, u := range s.URLs {
				assert.False(t, strings.Contains(u, "google"), u)
			}
		}
	})
}

// Ожидаемое значение посчитано независимо (Python hmac/hashlib) по формуле
// coturn: base64(hmac-sha1(secret, username)).
func TestCredentials(t *testing.T) {
	user, pass := ice.Credentials("north", "u1", time.Unix(1_700_000_000, 0))
	assert.Equal(t, "1700000000:u1", user)
	assert.Equal(t, "V5T4+SMzwlCncdLd960W+gxser0=", pass)
}
