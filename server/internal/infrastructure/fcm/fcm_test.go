package fcm_test

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/infrastructure/fcm"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/wake"
)

func TestSender(t *testing.T) {
	g := testutil.NewFakeFCM(t)
	s, err := fcm.New(fcm.Options{Credentials: g.Credentials, Endpoint: g.URL, TTL: 10 * time.Minute})
	require.NoError(t, err)
	ctx := context.Background()

	require.NoError(t, s.Send(ctx, "phone", map[string]string{"type": "sync", "event": "abc"}))
	require.NoError(t, s.Send(ctx, "phone", map[string]string{"type": "sync", "event": "def"}))
	assert.Equal(t, 1, g.TokenRequests(), "токен OAuth кешируется")

	msgs := g.Messages()
	require.Len(t, msgs, 2)
	m := msgs[0]
	assert.ElementsMatch(t, []string{"token", "data", "android"}, keysOf(m), "ни notification, ни чего-то ещё")
	assert.Equal(t, map[string]any{"type": "sync", "event": "abc"}, m["data"])
	assert.Equal(t, map[string]any{"priority": "HIGH", "ttl": "600s"}, m["android"])

	g.Dead["gone"] = true
	assert.ErrorIs(t, s.Send(ctx, "gone", map[string]string{"type": "sync"}), wake.ErrUnregistered)
}

func TestSenderOff(t *testing.T) {
	s, err := fcm.New(fcm.Options{})
	require.NoError(t, err)
	assert.Nil(t, s, "без ключа — выключен")
	_, err = fcm.New(fcm.Options{Credentials: `{"project_id":"x"}`})
	assert.Error(t, err)
}

func keysOf(m map[string]any) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
