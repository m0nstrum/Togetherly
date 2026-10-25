package migrations

import (
	m "github.com/pocketbase/pocketbase/migrations"
)

// held_write — придержанное сообщение партнёр не правит и не удаляет: ответ
// на PATCH отдавал запись целиком мимо правила чтения (domain/access).
func init() {
	m.Register(ApplyRules, nil, "1760000023_held_write.go")
}
