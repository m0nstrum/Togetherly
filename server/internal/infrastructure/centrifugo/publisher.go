// Package centrifugo публикует изменения в Centrifugo через его HTTP API.
package centrifugo

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Publisher шлёт сообщения в каналы Centrifugo.
type Publisher struct {
	api    string
	key    string
	client *http.Client
}

// New — публикатор для HTTP API (`http://centrifugo:8000/api`) с ключом
// `X-API-Key`. Пустой api или key — публикатор выключен.
func New(api, key string, timeout time.Duration) *Publisher {
	return &Publisher{api: api, key: key, client: &http.Client{Timeout: timeout}}
}

// Enabled — настроен ли адрес и ключ.
func (p *Publisher) Enabled() bool { return p != nil && p.api != "" && p.key != "" }

// ErrDisabled — публикатор не настроен.
var ErrDisabled = errors.New("centrifugo: публикатор не настроен")

// Publish отправляет data в channel.
func (p *Publisher) Publish(ctx context.Context, channel string, data any) error {
	if !p.Enabled() {
		return ErrDisabled
	}
	body, err := json.Marshal(map[string]any{"channel": channel, "data": data})
	if err != nil {
		return fmt.Errorf("centrifugo: тело: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.api+"/publish", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("centrifugo: запрос: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-API-Key", p.key)
	resp, err := p.client.Do(req)
	if err != nil {
		return fmt.Errorf("centrifugo: publish %s: %w", channel, err)
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("centrifugo: publish %s: HTTP %d", channel, resp.StatusCode)
	}
	return nil
}
