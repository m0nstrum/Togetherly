package centrifugo

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

func (p *Publisher) signingKey() ed25519.PrivateKey {
	seed := sha256.Sum256([]byte("tethered-realtime-key-v1\x00" + p.key))
	return ed25519.NewKeyFromSeed(seed[:])
}

// PublicKey is fetched over the application's authenticated HTTPS origin.
func (p *Publisher) PublicKey() string {
	return base64.RawURLEncoding.EncodeToString(p.signingKey().Public().(ed25519.PublicKey))
}

func serverChannel(channel string) bool {
	return strings.HasPrefix(channel, "pair:") || strings.HasPrefix(channel, "user:") || strings.HasPrefix(channel, "loc:")
}

func (p *Publisher) signed(channel string, data any) (any, error) {
	if !serverChannel(channel) {
		return data, nil
	}
	payload, err := json.Marshal(data)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, 16)
	if _, err = rand.Read(nonce); err != nil {
		return nil, err
	}
	encoded := base64.RawURLEncoding.EncodeToString(payload)
	id := hex.EncodeToString(nonce)
	at := time.Now().UnixMilli()
	message := fmt.Sprintf("tethered-realtime-v1\n%s\n%d\n%s\n%s", channel, at, id, encoded)
	sig := ed25519.Sign(p.signingKey(), []byte(message))
	return map[string]any{"v": 1, "channel": channel, "at": at, "nonce": id, "payload": encoded, "sig": base64.RawURLEncoding.EncodeToString(sig)}, nil
}
