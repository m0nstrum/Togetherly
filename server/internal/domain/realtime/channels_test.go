package realtime_test

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/m0nstrum/togetherly/server/internal/domain/realtime"
)

type rec struct {
	col, id string
	fields  map[string]string
	members []string
}

func (r rec) CollectionName() string  { return r.col }
func (r rec) RecordID() string        { return r.id }
func (r rec) String(f string) string  { return r.fields[f] }
func (r rec) Strings(string) []string { return r.members }

func TestChannels(t *testing.T) {
	cases := []struct {
		name string
		rec  rec
		want []string
	}{
		{"чат идёт в канал пары", rec{col: "chat_messages", fields: map[string]string{"group_id": "g1"}}, []string{"pair:g1"}},
		{"присутствие — в личный", rec{col: "user_presence", fields: map[string]string{"user_uid": "u1"}}, []string{"user:u1"}},
		{"геопозиция — в loc", rec{col: "live_location", fields: map[string]string{"channel": "pair_a_b"}}, []string{"loc:pair_a_b"}},
		{"сессия — по своему id", rec{col: "live_sessions", id: "s1"}, []string{"pair:s1"}},
		{"чат сессии — по pair_id", rec{col: "live_session_chat", fields: map[string]string{"pair_id": "s1"}}, []string{"pair:s1"}},
		{"группа — пара и участники", rec{col: "groups", id: "g1", members: []string{"u1", "", "u2"}}, []string{"pair:g1", "user:u1", "user:u2"}},
		{"шаг сверки ключей — в канал пары", rec{col: "e2e_handshake", fields: map[string]string{"group_id": "g1"}}, []string{"pair:g1"}},
		{"бэкап ключей не рассылается", rec{col: "e2e_backups", fields: map[string]string{"user_uid": "u1"}}, nil},
		{"без группы некуда", rec{col: "memories"}, nil},
		{"не рассылаемая коллекция", rec{col: "invite_codes", fields: map[string]string{"group_id": "g1"}}, nil},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			assert.Equal(t, tc.want, realtime.Channels(tc.rec))
		})
	}
	assert.Nil(t, realtime.Channels(nil))
}

// D11: удалил свою точку — снимаем его подписки на геоканал и сигналы.
func TestRevoked(t *testing.T) {
	user, chs := realtime.Revoked(rec{col: "live_location", fields: map[string]string{"channel": "pair_a_b", "user_uid": "a"}})
	assert.Equal(t, "a", user)
	assert.Equal(t, []string{"loc:pair_a_b", "locsignal:pair_a_b"}, chs)

	for name, r := range map[string]rec{
		"другая коллекция": {col: "chat_messages", fields: map[string]string{"group_id": "g1", "user_uid": "a"}},
		"без автора":       {col: "live_location", fields: map[string]string{"channel": "pair_a_b"}},
		"без канала":       {col: "live_location", fields: map[string]string{"user_uid": "a"}},
	} {
		t.Run(name, func(t *testing.T) {
			user, chs := realtime.Revoked(r)
			assert.Empty(t, user)
			assert.Nil(t, chs)
		})
	}
	user, chs = realtime.Revoked(nil)
	assert.Empty(t, user)
	assert.Nil(t, chs)
}
