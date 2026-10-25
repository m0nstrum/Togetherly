package handler

import (
	"context"
	"crypto/rand"
	"net/http"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
	"github.com/pocketbase/pocketbase/tools/security"

	"github.com/m0nstrum/togetherly/server/internal/domain/realtime"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/centrifugo"
)

// Presence — кто сейчас в канале Centrifugo.
type Presence interface {
	Presence(ctx context.Context, channel string) (map[string]centrifugo.Client, error)
}

// watchPassTTL — пропуск в комнату на вечер: дольше комнате не нужно.
const watchPassTTL = 6 * time.Hour

var (
	watchRoomChars = regexp.MustCompile(`[^a-z0-9]`)
	watchGuest     = regexp.MustCompile(`^g[a-z0-9]{14}$`)
)

// WatchRooms — комнаты совместного просмотра (бывший watch.pb.js). Сервер не
// хранит ни комнат, ни ссылок, ни переписки: комната — канал `watch:<код>`
// Centrifugo, пока в нём есть соединения. Подписка — только по пропуску.
//
//	POST /api/watch/room  {groupId} — код комнаты пары (HMAC от group_id):
//	                                  оба телефона молча попадают в одну;
//	POST /api/watch/new             — код новой открытой комнаты из браузера;
//	POST /api/watch/token {room, guest?} — пропуск в комнату.
//
// В открытую комнату пускают по ссылке кого угодно. В комнату пары —
// участников; выпущенные сборки открывают её во встроенном браузере без
// сессии, и для них есть поручительство: экран комнаты в приложении держит
// своё подключение с меткой `app` (его выдаёт RealtimeTokens только
// участнику), и каждое такое подключение пускает одну страницу без входа.
func WatchRooms(r *router.Router[*core.RequestEvent], secret string, presence Presence) {
	notConfigured := func(e *core.RequestEvent) error {
		return e.JSON(http.StatusInternalServerError, map[string]any{"ok": false, "error": "not_configured"})
	}
	// Участие — по users.group_ids; он догоняет состав с задержкой, поэтому
	// запасной путь — сам состав пар.
	pairsOf := func(e *core.RequestEvent) []string {
		ids := e.Auth.GetStringSlice("group_ids")
		rows, err := e.App.FindRecordsByFilter("groups", "members ~ {:u}", "", 50, 0, dbx.Params{"u": e.Auth.Id})
		if err == nil {
			for _, g := range rows {
				if !slices.Contains(ids, g.Id) {
					ids = append(ids, g.Id)
				}
			}
		}
		return ids
	}

	r.POST("/api/watch/room", func(e *core.RequestEvent) error {
		if e.Auth == nil {
			return e.JSON(http.StatusUnauthorized, map[string]any{"ok": false, "error": "unauthorized"})
		}
		var body struct {
			GroupID string `json:"groupId"`
		}
		_ = e.BindBody(&body)
		if body.GroupID == "" {
			return e.JSON(http.StatusBadRequest, map[string]any{"ok": false, "error": "no_group"})
		}
		if !slices.Contains(pairsOf(e), body.GroupID) {
			return e.JSON(http.StatusForbidden, map[string]any{"ok": false, "error": "not_member"})
		}
		if secret == "" {
			return notConfigured(e)
		}
		return e.JSON(http.StatusOK, map[string]any{"ok": true, "room": realtime.RoomCode(body.GroupID, secret)})
	})

	// Код придумывает сервер, а не страница: раньше пропуск выдавался на
	// любой набранный код, и тем же путём к паре заходили посторонние.
	r.POST("/api/watch/new", func(e *core.RequestEvent) error {
		if secret == "" {
			return notConfigured(e)
		}
		random := make([]byte, 6)
		_, _ = rand.Read(random)
		return e.JSON(http.StatusOK, map[string]any{"ok": true, "room": realtime.NewOpenRoom(random, secret)})
	})

	r.POST("/api/watch/token", func(e *core.RequestEvent) error {
		var body struct {
			Room  string `json:"room"`
			Guest string `json:"guest"`
		}
		_ = e.BindBody(&body)
		// Только буквы и цифры: иначе через имя канала можно уехать в чужое
		// пространство имён.
		room := watchRoomChars.ReplaceAllString(strings.ToLower(body.Room), "")
		if len(room) < 4 || len(room) > 12 {
			return e.JSON(http.StatusBadRequest, map[string]any{"ok": false, "error": "bad_room"})
		}
		if secret == "" {
			return notConfigured(e)
		}
		// У гостя — случайное имя: сайт анонимный. Прежнее браузер присылает
		// обратно, иначе перезагрузка вкладки выглядела бы вторым зрителем.
		guest := body.Guest
		if !watchGuest.MatchString(guest) {
			guest = "g" + strings.ToLower(security.RandomString(14))
		}
		channel := "watch:" + room

		kind := ""
		switch {
		case realtime.IsOpenRoom(room, secret):
			kind = "open"
		case realtime.LooksLikePairRoom(room):
			if e.Auth != nil {
				for _, g := range pairsOf(e) {
					if realtime.RoomCode(g, secret) == room {
						kind = "member"
						break
					}
				}
			}
			if kind == "" && vouched(e.Request.Context(), presence, channel, guest) {
				kind = "vouch"
			}
			if kind == "" {
				uid := ""
				if e.Auth != nil {
					uid = e.Auth.Id
				}
				e.App.Logger().Warn("watch: в комнату пары не пустили", "room", room, "auth", uid, "ip", e.RealIP())
				if e.Auth != nil {
					return e.JSON(http.StatusForbidden, map[string]any{"ok": false, "error": "not_member"})
				}
				return e.JSON(http.StatusUnauthorized, map[string]any{"ok": false, "error": "auth_required"})
			}
		default:
			e.App.Logger().Warn("watch: комнаты нет", "room", room, "ip", e.RealIP())
			return e.JSON(http.StatusNotFound, map[string]any{"ok": false, "error": "not_found"})
		}

		claims := jwt.MapClaims{"sub": guest, "channel": channel}
		switch kind {
		case "member":
			claims["info"] = map[string]any{"auth": 1}
		case "vouch":
			claims["info"] = map[string]any{"vouch": 1}
		}
		conn, err := security.NewJWT(jwt.MapClaims{"sub": guest}, secret, watchPassTTL)
		if err != nil {
			return e.InternalServerError("", err)
		}
		sub, err := security.NewJWT(claims, secret, watchPassTTL)
		if err != nil {
			return e.InternalServerError("", err)
		}
		return e.JSON(http.StatusOK, map[string]any{
			"ok": true, "kind": kind, "userId": guest, "channel": channel,
			"connectionToken": conn, "subscriptionToken": sub,
		})
	})
}

// vouched — есть ли в комнате пары свободное поручительство: подключений
// приложения (метка app) больше, чем уже пущенных страниц без входа. Место
// занимает любая страница без входа; вошедшие своим аккаунтом не в счёт.
func vouched(ctx context.Context, presence Presence, channel, guest string) bool {
	if presence == nil {
		return false
	}
	clients, err := presence.Presence(ctx, channel)
	if err != nil {
		return false
	}
	apps, pages := map[string]bool{}, map[string]bool{}
	for _, c := range clients {
		switch {
		case c.Info["app"] != nil:
			apps[c.User] = true
		case c.Info["auth"] == nil && c.User != guest:
			pages[c.User] = true
		}
	}
	return len(apps) > 0 && len(pages) < len(apps)
}
