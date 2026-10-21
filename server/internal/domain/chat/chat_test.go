package chat

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestMessageTime(t *testing.T) {
	const srv = int64(1_800_000_000_000)
	const min = int64(60_000)
	cases := []struct {
		name            string
		own, sent, want int64
	}{
		{"нет своего времени", 0, 0, srv},
		{"старая сборка, часы верны", srv - 30_000, 0, srv - 30_000},
		{"старая сборка, часы сбиты", srv - 10*min, 0, srv},
		{"офлайн: встаёт на время написания", srv - 105*min, srv, srv - 105*min},
		{"часы спешат на час, офлайн 10 минут", srv + 50*min, srv + 60*min, srv - 10*min},
		{"из будущего — время сервера", srv + min, srv, srv},
		{"старше недели — время сервера", srv - 8*24*60*min, srv, srv},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			assert.Equal(t, c.want, MessageTime(c.own, srv, c.sent))
		})
	}
}
