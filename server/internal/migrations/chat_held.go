package migrations

import (
	m "github.com/pocketbase/pocketbase/migrations"
)

// chat_held — отложенные сообщения (deliver_at): до срока их видит только
// автор. Флаг `held` ставит и снимает сервер; поле заводит ApplyRules, правило
// чтения — domain/access.
func init() {
	m.Register(ApplyRules, nil, "1760000022_chat_held.go")
}
