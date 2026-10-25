package pocketbase

import (
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
)

// Shared mutations are explicit; possessing a pair's token never grants authorship.
func bindAuthorship(app core.App) {
	for name, policy := range map[string]struct {
		author string
		shared map[string]bool
	}{
		"chat_messages":     {"user_uid", map[string]bool{"reactions": true, "voice_heard_at": true}},
		"live_session_chat": {"uid", map[string]bool{"reactions": true}},
		// `enc` — шифр переехавших полей (дата отметки среди них): без него
		// партнёр не отметил бы сбывшимся. `also` и `pos` — «я тоже хочу» и
		// общий порядок карточек.
		"wishes": {"author_uid", map[string]bool{"done": true, "done_at": true, "done_by": true, "done_note": true,
			"enc": true, "also": true, "pos": true}},
	} {
		app.OnRecordUpdateRequest(name).BindFunc(func(e *core.RecordRequestEvent) error {
			if e.HasSuperuserAuth() || e.Auth == nil {
				return e.Next()
			}
			original := e.Record.Original()
			if original.GetString(policy.author) == e.Auth.Id {
				return e.Next()
			}
			info, err := e.RequestInfo()
			if err != nil {
				return err
			}
			for field := range info.Body {
				if field != "id" && !policy.shared[field] {
					return router.NewForbiddenError("Only the author can edit this record.", nil)
				}
			}
			return e.Next()
		})
		app.OnRecordDeleteRequest(name).BindFunc(func(e *core.RecordRequestEvent) error {
			if !e.HasSuperuserAuth() && e.Auth != nil && e.Record.GetString(policy.author) != e.Auth.Id {
				return router.NewForbiddenError("Only the author can delete this record.", nil)
			}
			return e.Next()
		})
	}
}
