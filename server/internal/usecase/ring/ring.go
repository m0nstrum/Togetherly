// Package ring будит партнёра, которому звонят (UX_AUDIT L6) или которого
// зовут в комнату просмотра (комната как в Rave, 22.10).
//
// Зов звонка живёт в канале комнаты пары и слышен только открытому
// приложению. Чтобы закрытое тоже узнало о звонке, звонящий просит сервер
// положить уведомление в канал `user:<партнёр>` — тот же путь, что у прочих
// уведомлений хуков (`fork_notify`): по сокету фонового сервиса и пушем-
// будильником FCM без содержимого. Ни имён, ни текста сервер не кладёт:
// подпись телефон партнёра рисует сам.
package ring

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"strconv"
	"sync"
	"time"
)

var (
	// ErrNotMember — звонящий не состоит в паре или партнёра нет.
	ErrNotMember = errors.New("ring: не участник пары")
	// ErrTooOften — звонят чаще [Options.Every].
	ErrTooOften = errors.New("ring: слишком часто")
	// ErrBadKind — неизвестный зов.
	ErrBadKind = errors.New("ring: неизвестный зов")
)

// Kind — о чём зов; он же `thread` уведомления.
type Kind string

const (
	// KindCall — звонок.
	KindCall Kind = "call"
	// KindWatch — зовут в комнату совместного просмотра.
	KindWatch Kind = "watch"
)

func (k Kind) valid() bool { return k == KindCall || k == KindWatch }

// Pairs — пары.
type Pairs interface {
	// Partner — второй участник пары [groupID], если [uid] в ней состоит;
	// иначе [ErrNotMember].
	Partner(ctx context.Context, groupID, uid string) (string, error)
}

// Publisher — публикация в канал (с будильником FCM для `user:<uid>`).
type Publisher interface {
	Publish(ctx context.Context, channel string, data any) error
}

// Options — частота.
type Options struct {
	// Every — не чаще одного зова на человека за этот срок.
	Every time.Duration
}

// Service — зов звонка.
type Service struct {
	pairs Pairs
	pub   Publisher
	opt   Options
	now   func() time.Time

	mu   sync.Mutex
	last map[string]time.Time
}

// New — сервис.
func New(pairs Pairs, pub Publisher, opt Options, now func() time.Time) *Service {
	if opt.Every <= 0 {
		opt.Every = 10 * time.Second
	}
	return &Service{pairs: pairs, pub: pub, opt: opt, now: now, last: map[string]time.Time{}}
}

// Ring — [uid] зовёт партнёра в паре [groupID]: тот получает уведомление.
// Срок между зовами считается отдельно для звонка и для комнаты.
func (s *Service) Ring(ctx context.Context, uid, groupID string, kind Kind) error {
	if !kind.valid() {
		return ErrBadKind
	}
	if uid == "" || groupID == "" {
		return ErrNotMember
	}
	partner, err := s.pairs.Partner(ctx, groupID, uid)
	if err != nil {
		return err
	}
	now := s.now()
	if !s.allow(uid+"/"+string(kind), now) {
		return ErrTooOften
	}
	id := make([]byte, 8)
	if _, err := rand.Read(id); err != nil {
		return fmt.Errorf("ring: id: %w", err)
	}
	err = s.pub.Publish(ctx, "user:"+partner, map[string]any{
		"event": "create", "collection": "fork_notify",
		"record": map[string]any{
			"id": hex.EncodeToString(id), "collectionName": "fork_notify",
			"thread": string(kind), "title": "", "body": "",
			"data": map[string]string{
				"group_id": groupID,
				"from":     uid,
				// Пуш может прийти с опозданием: телефон сверит время и не
				// покажет зов, который давно кончился.
				"at": strconv.FormatInt(now.UnixMilli(), 10),
			},
		},
	})
	if err != nil {
		return fmt.Errorf("ring: публикация: %w", err)
	}
	return nil
}

func (s *Service) allow(uid string, now time.Time) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	for k, t := range s.last {
		if now.Sub(t) >= s.opt.Every {
			delete(s.last, k)
		}
	}
	if t, ok := s.last[uid]; ok && now.Sub(t) < s.opt.Every {
		return false
	}
	s.last[uid] = now
	return true
}
