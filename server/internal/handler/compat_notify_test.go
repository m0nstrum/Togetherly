package handler_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/handler"
)

type fakePub struct {
	channel string
	data    any
}

func (p *fakePub) Publish(_ context.Context, ch string, data any) error {
	p.channel, p.data = ch, data
	return nil
}

func TestCompatNotify(t *testing.T) {
	pub := &fakePub{}
	h := handler.Compat(nil, nil, nil, pub, nil)
	do := func(body string) int {
		req := httptest.NewRequest(http.MethodPost, "/internal/notify", strings.NewReader(body))
		req.RemoteAddr = "127.0.0.1:5555"
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		return rec.Code
	}

	require.Equal(t, http.StatusOK, do(`{"uid":"u2","thread":"reels","title":"T","body":"B","data":{"feed":"shorts"}}`))
	assert.Equal(t, "user:u2", pub.channel)
	msg := pub.data.(map[string]any)
	assert.Equal(t, "fork_notify", msg["collection"])
	rec := msg["record"].(map[string]any)
	assert.Equal(t, "reels", rec["thread"])
	assert.Equal(t, map[string]string{"feed": "shorts"}, rec["data"])
	assert.NotEmpty(t, rec["id"])

	assert.Equal(t, http.StatusBadRequest, do(`{"thread":"reels"}`), "без адресата")
}
