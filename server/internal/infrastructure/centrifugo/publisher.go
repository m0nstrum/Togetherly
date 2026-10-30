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
	signed, err := p.signed(channel, data)
	if err != nil {
		return err
	}
	body, err := json.Marshal(map[string]any{"channel": channel, "data": signed})
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

// Unsubscribe снимает подписку user на channel со всех его подключений.
func (p *Publisher) Unsubscribe(ctx context.Context, user, channel string) error {
	if !p.Enabled() {
		return ErrDisabled
	}
	body, err := json.Marshal(map[string]any{"user": user, "channel": channel})
	if err != nil {
		return fmt.Errorf("centrifugo: тело: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.api+"/unsubscribe", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("centrifugo: запрос: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-API-Key", p.key)
	resp, err := p.client.Do(req)
	if err != nil {
		return fmt.Errorf("centrifugo: unsubscribe %s: %w", channel, err)
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("centrifugo: unsubscribe %s: HTTP %d", channel, resp.StatusCode)
	}
	return nil
}

// Client — подключение в канале: кто и с какой меткой подписки.
type Client struct {
	User string
	// Info — метка подписки (chan_info): {"app":1}, {"auth":1}, {"vouch":1}.
	Info map[string]any
}

// Presence — кто сейчас в канале.
func (p *Publisher) Presence(ctx context.Context, channel string) (map[string]Client, error) {
	if !p.Enabled() {
		return nil, ErrDisabled
	}
	body, _ := json.Marshal(map[string]any{"channel": channel})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.api+"/presence", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("centrifugo: запрос: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-API-Key", p.key)
	resp, err := p.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("centrifugo: presence %s: %w", channel, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return nil, fmt.Errorf("centrifugo: presence %s: HTTP %d", channel, resp.StatusCode)
	}
	var out struct {
		Error  *struct{ Message string } `json:"error"`
		Result struct {
			Presence map[string]struct {
				User     string          `json:"user"`
				ChanInfo json.RawMessage `json:"chan_info"`
			} `json:"presence"`
		} `json:"result"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, fmt.Errorf("centrifugo: presence %s: %w", channel, err)
	}
	if out.Error != nil {
		return nil, fmt.Errorf("centrifugo: presence %s: %s", channel, out.Error.Message)
	}
	clients := make(map[string]Client, len(out.Result.Presence))
	for id, c := range out.Result.Presence {
		clients[id] = Client{User: c.User, Info: chanInfo(c.ChanInfo)}
	}
	return clients, nil
}

// chanInfo — метка подписки: объектом или строкой с JSON, смотря как отдал
// Centrifugo.
func chanInfo(raw json.RawMessage) map[string]any {
	var s string
	if json.Unmarshal(raw, &s) == nil {
		raw = json.RawMessage(s)
	}
	info := map[string]any{}
	if json.Unmarshal(raw, &info) != nil {
		return nil
	}
	return info
}
