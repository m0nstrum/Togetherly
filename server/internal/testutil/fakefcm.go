package testutil

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"

	"github.com/stretchr/testify/require"
)

// FakeFCM — Google OAuth и FCM HTTP v1 в одном тестовом сервере.
type FakeFCM struct {
	URL string
	// Credentials — JSON сервисного аккаунта, указывающий на этот сервер.
	Credentials string
	// Dead — токены, на которые FCM отвечает UNREGISTERED.
	Dead map[string]bool

	mu       sync.Mutex
	messages []map[string]any
	tokens   int
}

// NewFakeFCM поднимает сервер; закрывается в t.Cleanup.
func NewFakeFCM(t testing.TB) *FakeFCM {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	require.NoError(t, err)
	der, err := x509.MarshalPKCS8PrivateKey(key)
	require.NoError(t, err)
	f := &FakeFCM{Dead: map[string]bool{}}
	srv := httptest.NewServer(http.HandlerFunc(f.serve))
	t.Cleanup(srv.Close)
	f.URL = srv.URL
	creds, err := json.Marshal(map[string]string{
		"type": "service_account", "project_id": "tethered-test",
		"client_email": "fcm@tethered-test.iam.gserviceaccount.com",
		"private_key":  string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})),
		"token_uri":    srv.URL + "/token",
	})
	require.NoError(t, err)
	f.Credentials = string(creds)
	return f
}

func (f *FakeFCM) serve(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	switch {
	case r.URL.Path == "/token":
		if !strings.Contains(string(body), "jwt-bearer") {
			http.Error(w, "grant", http.StatusBadRequest)
			return
		}
		f.mu.Lock()
		f.tokens++
		f.mu.Unlock()
		_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "ya29.test", "expires_in": 3600})
	case r.URL.Path == "/v1/projects/tethered-test/messages:send":
		if r.Header.Get("Authorization") != "Bearer ya29.test" {
			http.Error(w, "auth", http.StatusUnauthorized)
			return
		}
		var m map[string]any
		_ = json.Unmarshal(body, &m)
		msg, _ := m["message"].(map[string]any)
		if tok, _ := msg["token"].(string); f.Dead[tok] {
			http.Error(w, `{"error":{"status":"NOT_FOUND","message":"Requested entity was not found."}}`, http.StatusNotFound)
			return
		}
		f.mu.Lock()
		f.messages = append(f.messages, msg)
		f.mu.Unlock()
		_, _ = w.Write([]byte(`{"name":"projects/tethered-test/messages/1"}`))
	default:
		http.NotFound(w, r)
	}
}

// Messages — принятые сообщения (поле message запроса).
func (f *FakeFCM) Messages() []map[string]any {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]map[string]any(nil), f.messages...)
}

// TokenRequests — сколько раз выдавался OAuth-токен.
func (f *FakeFCM) TokenRequests() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.tokens
}
