// Package wake будит телефоны пушем FCM без содержимого (PLAN S12).
//
// Событие (та же публикация, что ушла в Centrifugo) кладётся в короткий ящик
// в памяти под случайным id, в Google уходит только этот id. Телефон
// просыпается и забирает событие с нашего сервера, уже со своим входом.
package wake

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"sync"
	"time"
)

// ErrUnregistered — токен больше не действует (приложение удалено,
// переустановлено): его надо забыть.
var ErrUnregistered = errors.New("wake: токен устройства не действует")

// Sender доставляет данные на устройство (FCM HTTP v1).
type Sender interface {
	Send(ctx context.Context, token string, data map[string]string) error
}

// Tokens — токены устройств человека.
type Tokens interface {
	Tokens(ctx context.Context, uid string) ([]string, error)
	Forget(ctx context.Context, token string) error
}

// Entry — событие в ящике.
type Entry struct {
	UID     string `json:"-"`
	Channel string `json:"channel"`
	Data    any    `json:"data"`
	at      time.Time
}

// Options — сроки и размеры ящика.
type Options struct {
	// TTL — сколько событие ждёт телефона. FCM держит сообщение столько же.
	TTL time.Duration
	// Max — предел событий в памяти; старые вытесняются.
	Max int
}

// Service — ящик и рассылка.
type Service struct {
	send   Sender
	tokens Tokens
	opt    Options
	now    func() time.Time

	mu    sync.Mutex
	box   map[string]*Entry
	order []string
}

// New — сервис. Пустой [send] — будильник выключен (нет Firebase).
func New(send Sender, tokens Tokens, opt Options, now func() time.Time) *Service {
	if opt.TTL <= 0 {
		opt.TTL = 10 * time.Minute
	}
	if opt.Max <= 0 {
		opt.Max = 10000
	}
	return &Service{send: send, tokens: tokens, opt: opt, now: now, box: map[string]*Entry{}}
}

// Enabled — настроен ли FCM.
func (s *Service) Enabled() bool { return s != nil && s.send != nil }

// TTL — срок жизни события; его же получает FCM.
func (s *Service) TTL() time.Duration { return s.opt.TTL }

// Wake кладёт событие [data] канала [channel] для [uid] и будит его
// устройства. Без токенов в ящик ничего не кладётся.
func (s *Service) Wake(ctx context.Context, uid, channel string, data any) error {
	if !s.Enabled() || uid == "" {
		return nil
	}
	tokens, err := s.tokens.Tokens(ctx, uid)
	if err != nil {
		return err
	}
	if len(tokens) == 0 {
		return nil
	}
	id, err := s.put(&Entry{UID: uid, Channel: channel, Data: data})
	if err != nil {
		return err
	}
	var errs []error
	for _, t := range tokens {
		err := s.send.Send(ctx, t, map[string]string{"type": "sync", "event": id})
		switch {
		case errors.Is(err, ErrUnregistered):
			if ferr := s.tokens.Forget(ctx, t); ferr != nil {
				errs = append(errs, ferr)
			}
		case err != nil:
			errs = append(errs, err)
		}
	}
	return errors.Join(errs...)
}

// Fetch — событие [id] для [uid]. Чужое и просроченное не отдаётся.
// Повторный запрос того же события разрешён: телефон мог не успеть.
func (s *Service) Fetch(uid, id string) (Entry, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, ok := s.box[id]
	if !ok || e.UID != uid || s.now().Sub(e.at) > s.opt.TTL {
		return Entry{}, false
	}
	return *e, true
}

func (s *Service) put(e *Entry) (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	id := hex.EncodeToString(b)
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now()
	e.at = now
	// Порядок вставки = порядок старения: просроченные и лишние — с головы.
	for len(s.order) > 0 {
		head := s.box[s.order[0]]
		if head != nil && now.Sub(head.at) <= s.opt.TTL && len(s.order) < s.opt.Max {
			break
		}
		delete(s.box, s.order[0])
		s.order = s.order[1:]
	}
	s.box[id] = e
	s.order = append(s.order, id)
	return id, nil
}
