package watchproxy_test

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"

	"github.com/m0nstrum/togetherly/server/internal/domain/watchproxy"
)

func TestPolicy(t *testing.T) {
	p := watchproxy.Policy{Hosts: watchproxy.DefaultHosts}
	for _, ok := range []string{"www.youtube.com", "youtube.com", "rr3---sn-abc.googlevideo.com", "I.YTIMG.COM", "jnn-pa.googleapis.com"} {
		assert.True(t, p.Allowed(ok), ok)
	}
	for _, no := range []string{"evil.com", "youtube.com.evil.com", "notyoutube.com", "googleapis.com", "1.2.3.4", ""} {
		assert.False(t, p.Allowed(no), no)
	}

	got, err := p.Target("www.YouTube.com:443")
	assert.NoError(t, err)
	assert.Equal(t, "www.youtube.com:443", got)
	for _, bad := range []string{"www.youtube.com:80", "www.youtube.com", "evil.com:443", "[::1]:443"} {
		_, err := p.Target(bad)
		assert.ErrorIs(t, err, watchproxy.ErrTarget, bad)
	}
}

func TestQuota(t *testing.T) {
	q := &watchproxy.Quota{Daily: 100}
	day := time.Date(2026, 10, 21, 23, 0, 0, 0, time.UTC)
	assert.Equal(t, int64(100), q.Left("a", day))
	q.Add("a", 70, day)
	assert.Equal(t, int64(30), q.Left("a", day))
	assert.Equal(t, int64(100), q.Left("b", day), "лимит у каждого свой")
	assert.Equal(t, int64(100), q.Left("a", day.Add(2*time.Hour)), "новый день — новый лимит")

	free := &watchproxy.Quota{}
	free.Add("a", 1<<40, day)
	assert.Positive(t, free.Left("a", day))
}
