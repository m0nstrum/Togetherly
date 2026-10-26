package handler

import (
	"errors"
	"log/slog"
	"math"
	"net/http"
	"strings"

	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
	"github.com/spf13/cast"

	"github.com/m0nstrum/togetherly/server/internal/usecase/groupops"
)

// Group — атомарные операции над своей парой (бывший groups.pb.js):
//
//	POST /api/group/patch-map       {groupId, field, value}
//	POST /api/group/increment       {groupId, field, by}
//	POST /api/group/leave           {groupId}
//	POST /api/group/record-activity {groupId, today, restore?}
//	POST /api/group/miss-you        {groupId, vibe, text, count, weekday}
//
// `uid` в теле, если прислан, обязан совпасть с вошедшим. Ответы — как у
// хука: клиент при отказе маршрута откатывается на свою правку.
func Group(r *router.Router[*core.RequestEvent], svc *groupops.Service, log *slog.Logger) {
	type req struct {
		e    *core.RequestEvent
		body map[string]any
		gid  string
		uid  string
	}
	route := func(path string, fn func(q req) error) {
		r.POST(path, func(e *core.RequestEvent) error {
			body := map[string]any{}
			_ = e.BindBody(&body)
			q := req{e: e, body: body, gid: strings.TrimSpace(cast.ToString(body["groupId"])), uid: e.Auth.Id}
			switch err := svc.Check(q.gid); {
			case errors.Is(err, groupops.ErrDisbanded):
				return e.JSON(http.StatusForbidden, map[string]any{"ok": false, "error": "pair disbanded"})
			case err != nil:
				return e.JSON(http.StatusNotFound, map[string]any{"ok": false, "error": "not found"})
			}
			if v, ok := body["uid"]; ok && v != nil && strings.TrimSpace(cast.ToString(v)) != q.uid {
				return e.JSON(http.StatusForbidden, map[string]any{"ok": false, "error": "cannot act as another member"})
			}
			return fn(q)
		}).Bind(apis.RequireAuth())
	}
	fail := func(q req, op string, err error) error {
		switch {
		case errors.Is(err, groupops.ErrBadParams):
			return q.e.JSON(http.StatusBadRequest, map[string]any{"ok": false, "error": "bad params"})
		case errors.Is(err, groupops.ErrNotMember):
			return q.e.JSON(http.StatusForbidden, map[string]any{"ok": false, "error": "not a member"})
		case errors.Is(err, groupops.ErrNotFound):
			return q.e.JSON(http.StatusNotFound, map[string]any{"ok": false, "error": "not found"})
		}
		log.ErrorContext(q.e.Request.Context(), op, "group", q.gid, "err", err)
		return q.e.JSON(http.StatusInternalServerError, map[string]any{"ok": false, "error": "tx failed"})
	}
	ok := func(q req, extra map[string]any) error {
		out := map[string]any{"ok": true}
		for k, v := range extra {
			out[k] = v
		}
		return q.e.JSON(http.StatusOK, out)
	}

	route("/api/group/patch-map", func(q req) error {
		field := strings.TrimSpace(cast.ToString(q.body["field"]))
		if err := svc.PatchMap(q.gid, q.uid, field, q.body["value"]); err != nil {
			return fail(q, "patch-map", err)
		}
		return ok(q, nil)
	})

	route("/api/group/increment", func(q req) error {
		by, err := cast.ToFloat64E(q.body["by"])
		if err != nil || math.IsNaN(by) || math.IsInf(by, 0) {
			by = math.NaN()
		}
		field := strings.TrimSpace(cast.ToString(q.body["field"]))
		if math.IsNaN(by) && field != "drawings_count" && field != "memories_count" {
			return fail(q, "increment", groupops.ErrBadParams)
		}
		res, err := svc.Increment(q.gid, q.uid, field, by)
		if err != nil {
			return fail(q, "increment", err)
		}
		if res.Noop {
			return ok(q, map[string]any{"value": 0, "noop": true})
		}
		return ok(q, map[string]any{"value": res.Value})
	})

	route("/api/group/leave", func(q req) error {
		if err := svc.Leave(q.gid, q.uid); err != nil {
			return fail(q, "leave", err)
		}
		return ok(q, nil)
	})

	route("/api/group/record-activity", func(q req) error {
		today := strings.TrimSpace(cast.ToString(q.body["today"]))
		// Возврат сгоревшей серии за ролик идёт этим же адресом (так у апстрима).
		if v, _ := q.body["restore"].(bool); v {
			r, err := svc.RestoreStreak(q.gid, q.uid, today)
			if errors.Is(err, groupops.ErrNothingToRestore) {
				return q.e.JSON(http.StatusConflict, map[string]any{"ok": false, "error": "nothing_to_restore"})
			}
			if err != nil {
				return fail(q, "restore-streak", err)
			}
			return ok(q, map[string]any{"streak": r.Streak, "groupStreak": r.GroupStreak,
				"mascot_streaks": r.MascotStreaks, "streak_days": r.GroupStreak, "streak_last_opened_date": r.LastOpened})
		}
		a, err := svc.RecordActivity(q.gid, q.uid, today)
		switch {
		case err != nil:
			return fail(q, "record-activity", err)
		case a.Already:
			return ok(q, map[string]any{"already": true})
		case a.Pending:
			return ok(q, map[string]any{"pending": true})
		}
		return ok(q, map[string]any{"streak": a.Streak, "mascotStreak": a.MascotStreak})
	})

	route("/api/group/miss-you", func(q req) error {
		res, err := svc.MissYou(groupops.MissInput{
			GroupID: q.gid, UID: q.uid,
			Vibe:    cast.ToString(q.body["vibe"]),
			Text:    cast.ToString(q.body["text"]),
			Times:   cast.ToInt(q.body["count"]),
			Weekday: cast.ToInt(q.body["weekday"]),
		})
		if err != nil {
			return fail(q, "miss-you", err)
		}
		if res.Buffered {
			return ok(q, map[string]any{"count": res.Count, "buffered": true})
		}
		return ok(q, map[string]any{"count": res.Count})
	})
}
