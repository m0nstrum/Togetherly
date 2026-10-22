package ring_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/usecase/ring"
)

type pairs map[string][2]string

func (p pairs) Partner(_ context.Context, g, uid string) (string, error) {
	m, ok := p[g]
	switch {
	case !ok:
		return "", ring.ErrNotMember
	case m[0] == uid && m[1] != "":
		return m[1], nil
	case m[1] == uid && m[0] != "":
		return m[0], nil
	}
	return "", ring.ErrNotMember
}

type pub struct {
	channel string
	data    any
	err     error
}

func (p *pub) Publish(_ context.Context, ch string, data any) error {
	p.channel, p.data = ch, data
	return p.err
}

func TestRing(t *testing.T) {
	now := time.UnixMilli(1_760_000_000_000)
	clock := func() time.Time { return now }
	p := &pub{}
	svc := ring.New(pairs{"g1": {"a", "b"}}, p, ring.Options{Every: 10 * time.Second}, clock)
	ctx := context.Background()

	t.Run("зов уходит партнёру без текста", func(t *testing.T) {
		require.NoError(t, svc.Ring(ctx, "a", "g1"))
		assert.Equal(t, "user:b", p.channel)
		rec := p.data.(map[string]any)["record"].(map[string]any)
		assert.Equal(t, "call", rec["thread"])
		assert.Empty(t, rec["title"])
		assert.Empty(t, rec["body"])
		assert.Equal(t, map[string]string{"group_id": "g1", "from": "a", "at": "1760000000000"}, rec["data"])
	})

	t.Run("чаще срока — отказ", func(t *testing.T) {
		assert.ErrorIs(t, svc.Ring(ctx, "a", "g1"), ring.ErrTooOften)
		now = now.Add(10 * time.Second)
		assert.NoError(t, svc.Ring(ctx, "a", "g1"))
	})

	t.Run("чужая пара", func(t *testing.T) {
		p.channel = ""
		assert.ErrorIs(t, svc.Ring(ctx, "x", "g1"), ring.ErrNotMember)
		assert.ErrorIs(t, svc.Ring(ctx, "a", "g2"), ring.ErrNotMember)
		assert.ErrorIs(t, svc.Ring(ctx, "a", ""), ring.ErrNotMember)
		assert.Empty(t, p.channel)
	})

	t.Run("сбой публикации виден", func(t *testing.T) {
		p.err = errors.New("centrifugo")
		assert.Error(t, svc.Ring(ctx, "b", "g1"))
	})
}
