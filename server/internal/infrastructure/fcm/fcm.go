// Package fcm шлёт data-сообщения через FCM HTTP v1 сервисным аккаунтом
// Firebase-проекта оператора (PLAN S12).
//
// В сообщении только то, что дал вызывающий (`type`, `event`), высокий
// приоритет и срок жизни. Ни notification-блока, ни collapse-ключей с
// данными пары.
package fcm

import (
	"bytes"
	"context"
	"crypto/rsa"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"github.com/m0nstrum/togetherly/server/internal/usecase/wake"
)

const scope = "https://www.googleapis.com/auth/firebase.messaging"

// account — нужные поля JSON сервисного аккаунта.
type account struct {
	ProjectID   string `json:"project_id"`
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
	TokenURI    string `json:"token_uri"`
}

// Sender — отправитель FCM.
type Sender struct {
	email    string
	key      *rsa.PrivateKey
	tokenURI string
	sendURL  string
	ttl      time.Duration
	client   *http.Client
	now      func() time.Time

	mu     sync.Mutex
	access string
	until  time.Time
}

// Options — откуда ключ и как слать.
type Options struct {
	// Credentials — JSON сервисного аккаунта; CredentialsFile — путь к нему.
	Credentials     string
	CredentialsFile string
	// TTL — срок жизни сообщения в FCM.
	TTL     time.Duration
	Timeout time.Duration
	// Endpoint — подмена адреса FCM в тестах.
	Endpoint string
}

// New — отправитель или nil, если ключ не задан (FCM выключен).
func New(o Options) (*Sender, error) {
	raw := []byte(o.Credentials)
	if len(raw) == 0 && o.CredentialsFile != "" {
		b, err := os.ReadFile(o.CredentialsFile)
		if err != nil {
			return nil, fmt.Errorf("fcm: ключ: %w", err)
		}
		raw = b
	}
	if len(raw) == 0 {
		return nil, nil
	}
	var a account
	if err := json.Unmarshal(raw, &a); err != nil {
		return nil, fmt.Errorf("fcm: ключ не JSON: %w", err)
	}
	if a.ProjectID == "" || a.ClientEmail == "" || a.PrivateKey == "" {
		return nil, errors.New("fcm: в ключе нет project_id, client_email или private_key")
	}
	key, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(a.PrivateKey))
	if err != nil {
		return nil, fmt.Errorf("fcm: закрытый ключ: %w", err)
	}
	if a.TokenURI == "" {
		a.TokenURI = "https://oauth2.googleapis.com/token"
	}
	endpoint := o.Endpoint
	if endpoint == "" {
		endpoint = "https://fcm.googleapis.com"
	}
	if o.Timeout <= 0 {
		o.Timeout = 10 * time.Second
	}
	return &Sender{
		email:    a.ClientEmail,
		key:      key,
		tokenURI: a.TokenURI,
		sendURL:  endpoint + "/v1/projects/" + url.PathEscape(a.ProjectID) + "/messages:send",
		ttl:      o.TTL,
		client:   &http.Client{Timeout: o.Timeout},
		now:      time.Now,
	}, nil
}

// Send доставляет [data] на устройство [token].
func (s *Sender) Send(ctx context.Context, token string, data map[string]string) error {
	access, err := s.accessToken(ctx)
	if err != nil {
		return err
	}
	android := map[string]any{"priority": "HIGH"}
	if s.ttl > 0 {
		android["ttl"] = fmt.Sprintf("%ds", int(s.ttl.Seconds()))
	}
	body, err := json.Marshal(map[string]any{"message": map[string]any{
		"token": token, "data": data, "android": android,
	}})
	if err != nil {
		return fmt.Errorf("fcm: тело: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.sendURL, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("fcm: запрос: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+access)
	resp, err := s.client.Do(req)
	if err != nil {
		return fmt.Errorf("fcm: отправка: %w", err)
	}
	defer resp.Body.Close()
	msg, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	switch {
	case resp.StatusCode/100 == 2:
		return nil
	case resp.StatusCode == http.StatusNotFound,
		resp.StatusCode == http.StatusBadRequest && strings.Contains(string(msg), "registration token"):
		// UNREGISTERED или негодный токен: устройство его больше не держит.
		return wake.ErrUnregistered
	case resp.StatusCode == http.StatusUnauthorized:
		s.mu.Lock()
		s.access = ""
		s.mu.Unlock()
	}
	return fmt.Errorf("fcm: HTTP %d", resp.StatusCode)
}

// accessToken — OAuth2-токен по JWT сервисного аккаунта (RFC 7523), с
// запасом минута до истечения.
func (s *Sender) accessToken(ctx context.Context) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now()
	if s.access != "" && now.Before(s.until) {
		return s.access, nil
	}
	assertion, err := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"iss": s.email, "scope": scope, "aud": s.tokenURI,
		"iat": now.Unix(), "exp": now.Add(time.Hour).Unix(),
	}).SignedString(s.key)
	if err != nil {
		return "", fmt.Errorf("fcm: подпись: %w", err)
	}
	form := url.Values{
		"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"},
		"assertion":  {assertion},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.tokenURI, strings.NewReader(form.Encode()))
	if err != nil {
		return "", fmt.Errorf("fcm: запрос токена: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := s.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("fcm: токен: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return "", fmt.Errorf("fcm: токен: HTTP %d", resp.StatusCode)
	}
	var out struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil || out.AccessToken == "" {
		return "", errors.Join(errors.New("fcm: пустой токен"), err)
	}
	s.access = out.AccessToken
	s.until = now.Add(time.Duration(out.ExpiresIn)*time.Second - time.Minute)
	return s.access, nil
}
