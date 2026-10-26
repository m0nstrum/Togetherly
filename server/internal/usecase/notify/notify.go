// Package notify — уведомления людям пары (бывший apns_push.js форка).
//
// Транспорт — канал `user:<uid>` Centrifugo: телефон рисует уведомление сам,
// из приложения или из фонового сервиса, который держит сокет
// (lib/fork/push_relay.dart). Релеев APNs и FCM у форка нет (решение 2).
//
// Кому не слать: автору, тому, кто сейчас на связи (кроме Force), и тому,
// кто выключил этот вид уведомлений.
package notify

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"regexp"
	"strings"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"

	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
)

// Publisher — публикация в канал Centrifugo.
type Publisher interface {
	Publish(ctx context.Context, channel string, data any) error
}

// onlineWindow — «на связи»: присутствие обновлялось не раньше.
const onlineWindow = 25 * time.Second

// prefField — выключатель вида уведомлений в профиле.
var prefField = map[string]string{
	"chat":    "notif_chat",
	"mood":    "notif_mood",
	"memory":  "notif_new_memory",
	"miss":    "notif_miss_you",
	"comment": "notif_comments",
	"draw":    "notif_draw",
}

// Message — уведомление. Thread — вид (chat, draw, reels…): по нему телефон
// группирует уведомления, а сервер ищет выключатель.
type Message struct {
	Thread, Title, Body string
	Data                map[string]string
	// Force — слать и тому, кто сейчас в приложении: внутри приложения о
	// событии иначе не узнать.
	Force bool
}

// Service рассылает уведомления.
type Service struct {
	app core.App
	pub Publisher
	now func() time.Time
}

// New — рассылка через pub.
func New(app core.App, pub Publisher, now func() time.Time) *Service {
	return &Service{app: app, pub: pub, now: now}
}

// Group — уведомление всем живым участникам пары, кроме автора.
func (s *Service) Group(ctx context.Context, groupID, author string, m Message) {
	g, err := s.app.FindRecordById("groups", groupID)
	if err != nil || g.GetBool("disbanded") {
		return
	}
	for _, uid := range pairs.Members(g) {
		if uid != "" && uid != author {
			s.Send(ctx, uid, m)
		}
	}
}

// Send — уведомление человеку, если оно ему сейчас нужно.
func (s *Service) Send(ctx context.Context, uid string, m Message) {
	u, err := s.app.FindRecordById("users", uid)
	if err != nil {
		return
	}
	if !m.Force && s.online(uid) {
		return
	}
	// Колонки булевы, у нового аккаунта в них ноль: нулю верим, только если
	// телефон уже присылал свои тумблеры (notif_synced_at).
	if f, ok := prefField[m.Thread]; ok && !u.GetBool(f) && u.GetString("notif_synced_at") != "" {
		return
	}
	if err := s.Deliver(ctx, uid, m); err != nil {
		s.app.Logger().Warn("уведомление не доставлено", "uid", uid, "thread", m.Thread, "err", err)
	}
}

// Deliver кладёт уведомление в личный канал без проверок «нужно ли».
func (s *Service) Deliver(ctx context.Context, uid string, m Message) error {
	id := make([]byte, 8)
	_, _ = rand.Read(id)
	data := m.Data
	if data == nil {
		data = map[string]string{}
	}
	return s.pub.Publish(ctx, "user:"+uid, map[string]any{
		"event": "create", "collection": "fork_notify",
		"record": map[string]any{
			"id": hex.EncodeToString(id), "collectionName": "fork_notify",
			"thread": m.Thread, "title": DropSealed(m.Title), "body": DropSealed(m.Body), "data": data,
		},
	})
}

func (s *Service) online(uid string) bool {
	p, err := s.app.FindFirstRecordByFilter("user_presence", "user_uid = {:u}", dbx.Params{"u": uid})
	if err != nil {
		return false
	}
	seen := time.UnixMilli(int64(p.GetFloat("seen_at")))
	if p.GetFloat("seen_at") <= 0 {
		seen = p.GetDateTime("updated").Time()
	}
	return !seen.IsZero() && s.now().Sub(seen) < onlineWindow
}

// sealedToken — шифртекст поля E2E (`e2e1.<keyId>.<nonce>.<ct>`).
var sealedToken = regexp.MustCompile(`e2e1\.[A-Za-z0-9_:.+/=\-]+`)

// DropSealed убирает шифртекст из текста уведомления: имя в профиле — шифр
// личного ключа (docs/E2E.md), серверу его не прочесть.
func DropSealed(s string) string {
	if !strings.Contains(s, "e2e1.") {
		return s
	}
	return strings.Join(strings.Fields(sealedToken.ReplaceAllString(s, "")), " ")
}

// DisplayName — имя для текста уведомления: шифр не показываем, вместо
// пустого — fallback.
func DisplayName(u *core.Record, fallback string) string {
	name := strings.TrimSpace(DropSealed(u.GetString("display_name")))
	if name == "" {
		return fallback
	}
	return name
}
