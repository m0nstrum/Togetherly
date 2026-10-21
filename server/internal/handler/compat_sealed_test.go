package handler

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

// Имя из профиля — шифр личного ключа: в уведомление он не попадает.
func TestDropSealed(t *testing.T) {
	assert.Equal(t, "Аня зовёт рисовать", dropSealed("Аня зовёт рисовать"))
	assert.Equal(t, "зовёт рисовать", dropSealed("e2e1.alice:0.bm9uY2U.Y3Q= зовёт рисовать"))
	assert.Equal(t, "", dropSealed("e2e1.k:1.n.c"))
}
