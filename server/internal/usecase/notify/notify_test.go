package notify_test

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/m0nstrum/togetherly/server/internal/usecase/notify"
)

// Имя из профиля — шифр личного ключа: в уведомление он не попадает.
func TestDropSealed(t *testing.T) {
	assert.Equal(t, "Аня зовёт рисовать", notify.DropSealed("Аня зовёт рисовать"))
	assert.Equal(t, "зовёт рисовать", notify.DropSealed("e2e1.alice:0.bm9uY2U.Y3Q= зовёт рисовать"))
	assert.Equal(t, "", notify.DropSealed("e2e1.k:1.n.c"))
}
