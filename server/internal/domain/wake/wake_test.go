package wake_test

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/m0nstrum/togetherly/server/internal/domain/wake"
)

type rec struct {
	col    string
	fields map[string]string
}

func (r rec) CollectionName() string     { return r.col }
func (r rec) String(field string) string { return r.fields[field] }

func TestTargets(t *testing.T) {
	pair := []string{"a", "b"}
	cases := []struct {
		name  string
		event string
		r     rec
		want  []string
	}{
		{"сообщение будит партнёра", "create", rec{"chat_messages", map[string]string{"user_uid": "a"}}, []string{"b"}},
		{"правка сообщения не будит", "update", rec{"chat_messages", map[string]string{"user_uid": "a"}}, nil},
		{"настроение — и правка", "update", rec{"mood_entries", map[string]string{"user_uid": "b"}}, []string{"a"}},
		{"скучаю", "update", rec{"miss_you", map[string]string{"user_uid": "a"}}, []string{"b"}},
		{"воспоминание — по автору", "create", rec{"memories", map[string]string{"author_uid": "a"}}, []string{"b"}},
		{"подарок — получателю", "create", rec{"gifts", map[string]string{"recipient_uid": "a", "state": "sent"}}, []string{"a"}},
		{"отклик на подарок не будит", "update", rec{"gifts", map[string]string{"recipient_uid": "a", "state": "reacted"}}, nil},
		{"штрих рисунка не будит", "create", rec{"canvas_strokes", map[string]string{"user_uid": "a"}}, nil},
		{"удаление не будит", "delete", rec{"chat_messages", map[string]string{"user_uid": "a"}}, nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			assert.Equal(t, c.want, wake.Targets(c.event, c.r, pair))
		})
	}
	assert.False(t, wake.NeedsMembers("create", rec{"gifts", nil}), "подарку пара не нужна")
	assert.True(t, wake.NeedsMembers("create", rec{"chat_messages", nil}))
}
