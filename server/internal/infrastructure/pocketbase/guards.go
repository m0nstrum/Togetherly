package pocketbase

import (
	"net/http"
	"strings"
	"time"

	validation "github.com/pocketbase/ozzo-validation/v4"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
	"github.com/spf13/cast"

	"github.com/m0nstrum/togetherly/server/internal/domain/chat"
	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
)

// bindGuards — проверки записи, которые не выразить правилом PocketBase (S6).
func bindGuards(app core.App) {
	bindDuplicateID(app)

	// Новую группу создаёшь только с собой: правило `members ?~ auth.id`
	// пускало вписать в неё кого угодно. Второй участник появляется только
	// через приём приглашения на сервере.
	app.OnRecordCreateRequest("groups").BindFunc(func(e *core.RecordRequestEvent) error {
		if e.HasSuperuserAuth() || e.Auth == nil {
			return e.Next()
		}
		// Запись с таким id уже есть: пусть PocketBase ответит «не уникально»,
		// клиент на этом переходит к правке (PbDataService._upsertById).
		if e.Record.Id != "" {
			if _, err := e.App.FindRecordById("groups", e.Record.Id); err == nil {
				return e.Next()
			}
		}
		m := pairs.Members(e.Record)
		if len(m) != 1 || m[0] != e.Auth.Id {
			return router.NewApiError(http.StatusForbidden, "Группу можно создать только с собой в составе.", nil)
		}
		return e.Next()
	})

	// Канал геопозиции вида pair_<a>_<b>: автор — один из двоих, и у них есть
	// общая живая пара. Канал-id группы проверяет правило коллекции.
	guardLocation := func(e *core.RecordRequestEvent) error {
		if e.HasSuperuserAuth() || e.Auth == nil {
			return e.Next()
		}
		ch := e.Record.GetString("channel")
		if !strings.HasPrefix(ch, "pair_") {
			return e.Next()
		}
		a, b, ok := strings.Cut(strings.TrimPrefix(ch, "pair_"), "_")
		if !ok || a == "" || b == "" || (e.Auth.Id != a && e.Auth.Id != b) || !sharePair(e.App, a, b) {
			return router.NewApiError(http.StatusForbidden, "Чужой канал геопозиции.", nil)
		}
		return e.Next()
	}
	app.OnRecordCreateRequest("live_location").BindFunc(guardLocation)
	app.OnRecordUpdateRequest("live_location").BindFunc(guardLocation)

	// Время сообщения ставит сервер: сбитые часы телефона не перемешивают
	// переписку, а сообщение из офлайна встаёт на время написания
	// (domain/chat). `sent_at` в коллекции нет — читается из тела запроса.
	app.OnRecordCreateRequest("chat_messages").BindFunc(func(e *core.RecordRequestEvent) error {
		var sent int64
		if info, err := e.RequestInfo(); err == nil {
			sent = cast.ToInt64(info.Body["sent_at"])
		}
		now := time.Now().UnixMilli()
		e.Record.Set("ts", chat.MessageTime(int64(e.Record.GetFloat("ts")), now, sent))
		return e.Next()
	})
}

// sharePair — есть ли у a и b общая живая пара.
func sharePair(app core.App, a, b string) bool {
	groups, err := pairs.New(app).GroupsOfUser(a, true)
	if err != nil {
		return false
	}
	for _, g := range groups {
		for _, m := range pairs.Members(g) {
			if m == b {
				return true
			}
		}
	}
	return false
}

// bindDuplicateID отвечает на создание записи с уже занятым id так же, как
// hotpath апстрима: `validation_not_unique` / «Value must be unique.».
// PocketBase отвечает `validation_pk_invalid`, а клиент (alreadyExists в
// pb_data_service.dart) узнаёт дубль только по тексту hotpath и на нём
// переходит от создания к правке.
func bindDuplicateID(app core.App) {
	app.OnRecordCreateRequest().BindFunc(func(e *core.RecordRequestEvent) error {
		if e.Record.Id == "" {
			return e.Next()
		}
		if _, err := e.App.FindRecordById(e.Collection, e.Record.Id); err != nil {
			return e.Next()
		}
		return router.NewBadRequestError("Failed to create record.", validation.Errors{
			"id": validation.NewError("validation_not_unique", "Value must be unique."),
		})
	})
}
