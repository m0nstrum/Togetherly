package handler

import (
	"net/http"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
	"github.com/spf13/cast"

	"github.com/m0nstrum/togetherly/server/internal/usecase/notify"
)

// Зовы партнёру: «пойдём порисовать» и «смотрим ленту вместе» (бывшие
// draw_invite.pb.js и reels_invite.pb.js). Отметки частоты и живой зов в
// ленту живут в памяти процесса: перезапуск их теряет, и это не беда —
// позовут снова при следующем входе.

const (
	// drawGap — молчим после зова порисовать: за вечер в раскраску заходят
	// десяток раз, и без паузы партнёр получил бы десяток уведомлений.
	drawGap = 30 * time.Minute
	// reelsGap — зов в ленту при входе; reelsManualGap — кнопкой «Позвать».
	reelsGap       = 10 * time.Minute
	reelsManualGap = time.Minute
	// reelsActive — столько зов в ленту считается живым: партнёр входит по
	// плитке, не дожидаясь нового уведомления.
	reelsActive = 3 * time.Hour
)

// reelsFeeds — площадки ленты: те же ключи, что ReelsSource.key в приложении.
var reelsFeeds = map[string]string{
	"shorts": "YouTube Shorts",
	"tiktok": "TikTok",
	"rutube": "Rutube",
	"vk":     "ВК Клипы",
	"dzen":   "Дзен",
}

// mayCall — прошла ли пауза после прошлого зова. Отметка из будущего
// (часы ушли назад) зов не запирает.
func mayCall(last, now time.Time, gap time.Duration) bool {
	return last.IsZero() || last.After(now) || now.Sub(last) >= gap
}

type reelsSession struct {
	by, name, feed string
	at             time.Time
	stopped        bool
}

// Calls — POST /api/draw/invite, POST /api/reels/invite, GET /api/reels/active.
func Calls(r *router.Router[*core.RequestEvent], push *notify.Service, now func() time.Time) {
	var mu sync.Mutex
	drawn := map[string]time.Time{} // uid → последний зов порисовать
	called := map[string]time.Time{} // uid → последний зов в ленту
	reels := map[string]*reelsSession{}

	// Членство — по users.group_ids, как в правилах парных коллекций.
	member := func(e *core.RequestEvent, gid string) bool {
		return gid != "" && slices.Contains(e.Auth.GetStringSlice("group_ids"), gid)
	}
	body := func(e *core.RequestEvent) map[string]any {
		b := map[string]any{}
		_ = e.BindBody(&b)
		return b
	}

	// Зов уходит, когда человек открыл раскраску. Хук на запись холста стоил
	// бы сотни вызовов в секунду ради одного уведомления, поэтому — роут.
	// Партнёру, который сейчас в приложении, не шлём: он и так видит холст.
	r.POST("/api/draw/invite", func(e *core.RequestEvent) error {
		me := e.Auth.Id
		gid := strings.TrimSpace(cast.ToString(body(e)["group_id"]))
		if gid == "" {
			return e.JSON(http.StatusBadRequest, map[string]any{"ok": false, "error": "no group_id"})
		}
		if !member(e, gid) {
			return e.JSON(http.StatusForbidden, map[string]any{"ok": false, "error": "not your group"})
		}
		g, err := e.App.FindRecordById("groups", gid)
		if err != nil {
			return e.JSON(http.StatusNotFound, map[string]any{"ok": false, "error": "no group"})
		}
		if g.GetBool("disbanded") {
			return e.JSON(http.StatusOK, map[string]any{"ok": true, "sent": false, "why": "disbanded"})
		}
		at := now()
		mu.Lock()
		if !mayCall(drawn[me], at, drawGap) {
			mu.Unlock()
			return e.JSON(http.StatusOK, map[string]any{"ok": true, "sent": false, "why": "too soon"})
		}
		drawn[me] = at
		mu.Unlock()
		name := notify.DisplayName(e.Auth, "Партнёр")
		push.Group(e.Request.Context(), gid, me, notify.Message{
			Thread: "draw", Title: name + " зовёт порисовать", Body: "Открыл раскраску — заходите рисовать вместе",
		})
		return e.JSON(http.StatusOK, map[string]any{"ok": true, "sent": true})
	}).Bind(apis.RequireAuth())

	//	{group_id, feed}              — запустил ленту, позвать
	//	{group_id, feed, again: true} — кнопка «Позвать» в ленте
	//	{group_id, stop: true}        — вышел из ленты
	// Уведомление уходит и тому, кто в приложении: внутри о зове не узнать.
	// Плюса не спрашиваем: в Tethered всё открыто.
	r.POST("/api/reels/invite", func(e *core.RequestEvent) error {
		me := e.Auth.Id
		b := body(e)
		gid := strings.TrimSpace(cast.ToString(b["group_id"]))
		if gid == "" {
			return e.JSON(http.StatusBadRequest, map[string]any{"ok": false, "error": "no group_id"})
		}
		if !member(e, gid) {
			return e.JSON(http.StatusForbidden, map[string]any{"ok": false, "error": "not your group"})
		}
		if cast.ToBool(b["stop"]) {
			mu.Lock()
			if s := reels[gid]; s != nil && s.by == me {
				s.stopped = true
			}
			mu.Unlock()
			return e.JSON(http.StatusOK, map[string]any{"ok": true})
		}
		g, err := e.App.FindRecordById("groups", gid)
		if err != nil {
			return e.JSON(http.StatusNotFound, map[string]any{"ok": false, "error": "no group"})
		}
		if g.GetBool("disbanded") {
			return e.JSON(http.StatusOK, map[string]any{"ok": true, "sent": false, "why": "disbanded"})
		}
		feed := strings.ToLower(strings.TrimSpace(cast.ToString(b["feed"])))
		if _, ok := reelsFeeds[feed]; !ok {
			feed = "shorts"
		}
		name := notify.DisplayName(e.Auth, "")
		at := now()
		gap := reelsGap
		if v, _ := b["again"].(bool); v {
			gap = reelsManualGap
		}
		mu.Lock()
		reels[gid] = &reelsSession{by: me, name: name, feed: feed, at: at}
		if !mayCall(called[me], at, gap) {
			mu.Unlock()
			return e.JSON(http.StatusOK, map[string]any{"ok": true, "sent": false, "why": "too soon"})
		}
		called[me] = at
		mu.Unlock()
		who := name
		if who == "" {
			who = "Партнёр"
		}
		// Ключ `from` в данных уведомления Firebase держит за собой — поэтому `by`.
		push.Group(e.Request.Context(), gid, me, notify.Message{
			Thread: "reels", Force: true,
			Title: who + " зовёт смотреть " + reelsFeeds[feed],
			Body:  "Совместная лента: ролики из ваших лент по очереди, чат и звонок",
			Data:  map[string]string{"feed": feed, "group": gid, "by": me, "name": name},
		})
		return e.JSON(http.StatusOK, map[string]any{"ok": true, "sent": true})
	}).Bind(apis.RequireAuth())

	r.GET("/api/reels/active", func(e *core.RequestEvent) error {
		gid := strings.TrimSpace(e.Request.URL.Query().Get("group_id"))
		if !member(e, gid) {
			return e.JSON(http.StatusForbidden, map[string]any{"ok": false, "error": "not your group"})
		}
		mu.Lock()
		s := reels[gid]
		var cp reelsSession
		if s != nil {
			cp = *s
		}
		mu.Unlock()
		age := now().Sub(cp.at)
		if s == nil || cp.by == e.Auth.Id || cp.stopped || age < 0 || age >= reelsActive {
			return e.JSON(http.StatusOK, map[string]any{"ok": true, "active": false})
		}
		return e.JSON(http.StatusOK, map[string]any{"ok": true, "active": true,
			"feed": cp.feed, "name": cp.name, "by": cp.by, "at": cp.at.UnixMilli()})
	}).Bind(apis.RequireAuth())
}
