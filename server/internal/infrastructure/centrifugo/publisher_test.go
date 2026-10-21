package centrifugo_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/infrastructure/centrifugo"
)

func TestPublish(t *testing.T) {
	var got struct {
		Channel string         `json:"channel"`
		Data    map[string]any `json:"data"`
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, "/api/publish", r.URL.Path)
		assert.Equal(t, "secret", r.Header.Get("X-API-Key"))
		require.NoError(t, json.NewDecoder(r.Body).Decode(&got))
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	p := centrifugo.New(srv.URL+"/api", "secret", time.Second)
	require.True(t, p.Enabled())
	require.NoError(t, p.Publish(context.Background(), "pair:g1", map[string]any{"event": "create"}))
	assert.Equal(t, "pair:g1", got.Channel)
	assert.Equal(t, "create", got.Data["event"])
}

func TestPublishErrors(t *testing.T) {
	t.Run("выключен", func(t *testing.T) {
		err := centrifugo.New("", "", time.Second).Publish(context.Background(), "x", nil)
		assert.ErrorIs(t, err, centrifugo.ErrDisabled)
	})
	t.Run("ответ не 2xx", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusUnauthorized)
		}))
		defer srv.Close()
		err := centrifugo.New(srv.URL, "k", time.Second).Publish(context.Background(), "x", nil)
		assert.ErrorContains(t, err, "HTTP 401")
	})
}
