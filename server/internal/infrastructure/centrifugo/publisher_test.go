package centrifugo_test

import (
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
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
	assert.Equal(t, "pair:g1", got.Data["channel"])
	encoded := got.Data["payload"].(string)
	payload, err := base64.RawURLEncoding.DecodeString(encoded)
	require.NoError(t, err)
	assert.JSONEq(t, `{"event":"create"}`, string(payload))
	key, err := base64.RawURLEncoding.DecodeString(p.PublicKey())
	require.NoError(t, err)
	sig, err := base64.RawURLEncoding.DecodeString(got.Data["sig"].(string))
	require.NoError(t, err)
	message := fmt.Sprintf("tethered-realtime-v1\npair:g1\n%.0f\n%s\n%s", got.Data["at"], got.Data["nonce"], encoded)
	assert.True(t, ed25519.Verify(key, []byte(message), sig))
	assert.False(t, ed25519.Verify(key, []byte(message+"tampered"), sig))
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

func TestSharedSignatureFixture(t *testing.T) {
	raw, err := os.ReadFile("../../../../test/fork/realtime/fixtures/signed_delta.json")
	require.NoError(t, err)
	var fixture struct {
		Key      string `json:"key"`
		Envelope struct {
			Channel string `json:"channel"`
			At      int64  `json:"at"`
			Nonce   string `json:"nonce"`
			Payload string `json:"payload"`
			Sig     string `json:"sig"`
		} `json:"envelope"`
	}
	require.NoError(t, json.Unmarshal(raw, &fixture))
	p := centrifugo.New("http://unused", "fixture-api-key", time.Second)
	require.Equal(t, p.PublicKey(), fixture.Key)
	key, err := base64.RawURLEncoding.DecodeString(fixture.Key)
	require.NoError(t, err)
	sig, err := base64.RawURLEncoding.DecodeString(fixture.Envelope.Sig)
	require.NoError(t, err)
	e := fixture.Envelope
	message := fmt.Sprintf("tethered-realtime-v1\n%s\n%d\n%s\n%s", e.Channel, e.At, e.Nonce, e.Payload)
	require.True(t, ed25519.Verify(key, []byte(message), sig))
}
