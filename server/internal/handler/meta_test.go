package handler_test

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"

	"github.com/m0nstrum/togetherly/server/internal/handler"
)

func TestIPLimiter(t *testing.T) {
	l := &handler.IPLimiter{Max: 2, Window: time.Minute}
	now := time.Unix(0, 0)
	assert.True(t, l.Allow("1.1.1.1", now))
	assert.True(t, l.Allow("1.1.1.1", now))
	assert.False(t, l.Allow("1.1.1.1", now))
	assert.True(t, l.Allow("2.2.2.2", now), "другой IP")
	assert.True(t, l.Allow("1.1.1.1", now.Add(2*time.Minute)), "новое окно")
}
