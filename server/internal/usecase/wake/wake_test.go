package wake_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/usecase/wake"
)

type sent struct {
	token string
	data  map[string]string
}

type fakeSender struct {
	sent []sent
	dead map[string]bool
}

func (f *fakeSender) Send(_ context.Context, token string, data map[string]string) error {
	if f.dead[token] {
		return wake.ErrUnregistered
	}
	f.sent = append(f.sent, sent{token, data})
	return nil
}

type fakeTokens struct {
	by        map[string][]string
	forgotten []string
}

func (f *fakeTokens) Tokens(_ context.Context, uid string) ([]string, error) { return f.by[uid], nil }
func (f *fakeTokens) Forget(_ context.Context, token string) error {
	f.forgotten = append(f.forgotten, token)
	return nil
}

func TestWake(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	clock := func() time.Time { return now }
	send := &fakeSender{dead: map[string]bool{"old": true}}
	tokens := &fakeTokens{by: map[string][]string{"bob": {"phone", "old"}}}
	svc := wake.New(send, tokens, wake.Options{TTL: time.Minute}, clock)
	ctx := context.Background()

	t.Run("в Google — только type и event", func(t *testing.T) {
		require.NoError(t, svc.Wake(ctx, "bob", "pair:g1", map[string]any{"record": "шифр"}))
		require.Len(t, send.sent, 1)
		assert.Equal(t, "phone", send.sent[0].token)
		assert.Equal(t, []string{"event", "type"}, keys(send.sent[0].data))
		assert.Equal(t, "sync", send.sent[0].data["type"])
		assert.Equal(t, []string{"old"}, tokens.forgotten, "мёртвый токен забыт")
	})
	id := send.sent[0].data["event"]

	t.Run("событие забирает только адресат", func(t *testing.T) {
		e, ok := svc.Fetch("bob", id)
		require.True(t, ok)
		assert.Equal(t, "pair:g1", e.Channel)
		_, ok = svc.Fetch("alice", id)
		assert.False(t, ok, "чужое")
		_, ok = svc.Fetch("bob", "nope")
		assert.False(t, ok)
	})

	t.Run("после срока событие уходит", func(t *testing.T) {
		now = now.Add(2 * time.Minute)
		_, ok := svc.Fetch("bob", id)
		assert.False(t, ok)
	})

	t.Run("без токенов — ни пуша, ни записи в ящик", func(t *testing.T) {
		send.sent = nil
		require.NoError(t, svc.Wake(ctx, "carol", "pair:g1", 1))
		assert.Empty(t, send.sent)
	})

	t.Run("без FCM выключен", func(t *testing.T) {
		off := wake.New(nil, tokens, wake.Options{}, clock)
		assert.False(t, off.Enabled())
		assert.NoError(t, off.Wake(ctx, "bob", "pair:g1", 1))
	})
}

func TestWakeBoxIsBounded(t *testing.T) {
	now := time.Unix(1_700_000_000, 0)
	send := &fakeSender{}
	svc := wake.New(send, &fakeTokens{by: map[string][]string{"bob": {"phone"}}}, wake.Options{TTL: time.Hour, Max: 3}, func() time.Time { return now })
	for range 5 {
		require.NoError(t, svc.Wake(context.Background(), "bob", "c", 1))
	}
	_, ok := svc.Fetch("bob", send.sent[0].data["event"])
	assert.False(t, ok, "старое вытеснено")
	_, ok = svc.Fetch("bob", send.sent[4].data["event"])
	assert.True(t, ok)
}

func TestWakeSendErrorsJoined(t *testing.T) {
	svc := wake.New(errSender{}, &fakeTokens{by: map[string][]string{"bob": {"a", "b"}}}, wake.Options{}, time.Now)
	err := svc.Wake(context.Background(), "bob", "c", 1)
	assert.ErrorContains(t, err, "сеть")
}

type errSender struct{}

func (errSender) Send(context.Context, string, map[string]string) error {
	return errors.New("сеть")
}

func keys(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for _, k := range []string{"event", "type"} {
		if _, ok := m[k]; ok {
			out = append(out, k)
		}
	}
	if len(out) != len(m) {
		return nil
	}
	return out
}
