package handler

import (
	"net/http"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
	"github.com/pocketbase/pocketbase/tools/security"

	"github.com/m0nstrum/togetherly/server/internal/domain/realtime"
)

// realtimeTokenTTL — срок токенов Centrifugo: клиент обновляет их сам.
const realtimeTokenTTL = 120 * time.Second

// RealtimeTokens — токены Centrifugo (бывший centrifugo_tokens.pb.js):
//
//	POST /api/centrifugo/connection-token   — подключение;
//	POST /api/centrifugo/subscription-token {channel} — приватный канал после
//	     проверки членства.
//
// Без них приложение не подключится и не подпишется на канал пары: живые
// обновления умирают молча. secret — общий с Centrifugo ключ HMAC.
func RealtimeTokens(r *router.Router[*core.RequestEvent], secret string) {
	notConfigured := func(e *core.RequestEvent) error {
		return e.JSON(http.StatusInternalServerError, map[string]any{"error": "not configured"})
	}
	r.POST("/api/centrifugo/connection-token", func(e *core.RequestEvent) error {
		if secret == "" {
			return notConfigured(e)
		}
		tok, err := security.NewJWT(jwt.MapClaims{"sub": e.Auth.Id}, secret, realtimeTokenTTL)
		if err != nil {
			return e.InternalServerError("", err)
		}
		return e.JSON(http.StatusOK, map[string]any{"token": tok})
	}).Bind(apis.RequireAuth())

	r.POST("/api/centrifugo/subscription-token", func(e *core.RequestEvent) error {
		var body struct {
			Channel string `json:"channel"`
		}
		_ = e.BindBody(&body)
		if body.Channel == "" {
			return e.JSON(http.StatusBadRequest, map[string]any{"error": "channel required"})
		}
		uid := e.Auth.Id
		scope := realtime.SubscribeScope(body.Channel, uid)
		if !canSubscribe(e.App, scope, uid, secret) {
			return e.JSON(http.StatusForbidden, map[string]any{"error": "forbidden"})
		}
		if secret == "" {
			return notConfigured(e)
		}
		claims := jwt.MapClaims{"sub": uid, "channel": body.Channel}
		// Экран комнаты держит своё подключение ради голоса и зрителем не
		// является: без метки страница считала его вторым человеком. `info`
		// уезжает в присутствие, счёт ведёт countViewers в room.js.
		if scope.Kind == "watch" {
			claims["info"] = map[string]any{"app": 1}
		}
		tok, err := security.NewJWT(claims, secret, realtimeTokenTTL)
		if err != nil {
			return e.InternalServerError("", err)
		}
		return e.JSON(http.StatusOK, map[string]any{"token": tok})
	}).Bind(apis.RequireAuth())
}

// canSubscribe — пускает ли канал человека uid. Пары — только действующие.
func canSubscribe(app core.App, s realtime.Scope, uid, secret string) bool {
	live := func(filter string, params dbx.Params) bool {
		rows, err := app.FindRecordsByFilter("groups", filter+" && disbanded = false", "", 1, 0, params)
		return err == nil && len(rows) > 0
	}
	together := func(a, b string) bool {
		return live("members ~ {:a} && members ~ {:b}", dbx.Params{"a": a, "b": b})
	}
	switch s.Kind {
	case "pair":
		return s.Target != "" && live("id = {:g} && members ~ {:u}", dbx.Params{"g": s.Target, "u": uid})
	case "user":
		return s.Target == uid || (s.Target != "" && together(uid, s.Target))
	case "loc":
		return s.A != "" && s.B != "" && together(s.A, s.B)
	case "watch":
		if secret == "" || s.Target == "" {
			return false
		}
		rows, err := app.FindRecordsByFilter("groups", "members ~ {:u} && disbanded = false", "", 20, 0, dbx.Params{"u": uid})
		if err != nil {
			return false
		}
		for _, g := range rows {
			if realtime.RoomCode(g.Id, secret) == s.Target {
				return true
			}
		}
	}
	return false
}
