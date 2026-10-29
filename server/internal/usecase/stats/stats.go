// Package stats — счётчики пары для экрана статистики (/api/couple/stats; у
// апстрима их считал hotpath поверх Postgres).
//
// Считаются только метаданные, которые сервер и так хранит открыто: кто и
// когда написал, добавил воспоминание или отметил настроение, тип
// воспоминания. Содержимое зашифровано (docs/E2E.md), поэтому разбивки по
// самим настроениям (`mood_daily`, `mood_top`: mood_id — шифр), площадок
// просмотров (`watchKinds`) и имён участников здесь нет — их считает клиент
// из своих расшифрованных данных (BACKLOG T2, B9).
package stats

import (
	"context"
	"errors"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

// Service считает агрегаты по базе PocketBase.
type Service struct{ app core.App }

// New — счётчики над app.
func New(app core.App) *Service { return &Service{app: app} }

// ErrUnknownCol — коллекцию так не считают.
var ErrUnknownCol = errors.New("stats: коллекция не считается")

// countable — что можно посчитать по group_id.
var countable = map[string]bool{"canvas_strokes": true, "canvas_meta": true}

// Count — сколько записей пары в коллекции col (без удалённых, где есть флаг).
func (s *Service) Count(ctx context.Context, col, groupID string) (int, error) {
	if !countable[col] {
		return 0, ErrUnknownCol
	}
	where := "group_id = {:g}"
	if col == "canvas_strokes" {
		where += " AND COALESCE(deleted, 0) = 0"
	}
	return s.one(ctx, "SELECT COUNT(*) AS n FROM "+col+" WHERE "+where, groupID)
}

// Пары «ключ — сколько» в форме hotpath: uid/m/d/h/k и c.
type (
	byUID struct {
		UID string `db:"uid" json:"uid"`
		C   int    `db:"c" json:"c"`
	}
	byMonth struct {
		M string `db:"m" json:"m"`
		C int    `db:"c" json:"c"`
	}
	byDay struct {
		D int `db:"d" json:"d"`
		C int `db:"c" json:"c"`
	}
	byHour struct {
		H int `db:"h" json:"h"`
		C int `db:"c" json:"c"`
	}
	byKind struct {
		K string `db:"k" json:"k"`
		C int    `db:"c" json:"c"`
	}
)

// Время записи в секундах Unix для каждой коллекции: сообщения хранят ts в
// миллисекундах, остальные — дату PocketBase (UTC, «… Z»).
const (
	msgAt  = "CAST(ts / 1000 AS INTEGER)"
	memAt  = "CAST(strftime('%s', created_at) AS INTEGER)"
	moodAt = "CAST(strftime('%s', timestamp) AS INTEGER)"
)

// source — откуда считать ряд: таблица, условие «живая запись пары», время.
type source struct{ table, where, at, author string }

var (
	messages = source{"chat_messages", "group_id = {:g} AND COALESCE(deleted, 0) = 0", msgAt, "user_uid"}
	memories = source{"memories", "group_id = {:g} AND COALESCE(deleted, 0) = 0", memAt, "author_uid"}
	moods    = source{"mood_entries", "group_id = {:g}", moodAt, "user_uid"}
)

// CoupleAgg — ряды чата, ленты и настроений в форме hotpath (их собирает
// CoupleStats). now — отсчёт для «за 30/90 дней» и года по месяцам.
func (s *Service) CoupleAgg(ctx context.Context, groupID string, now time.Time) (map[string]any, error) {
	out := map[string]any{}
	var err error
	unix := now.Unix()
	since := func(days int) int64 { return unix - int64(days)*86400 }
	yearAgo := now.AddDate(-1, 0, 0).Unix()

	total := func(src source) int {
		var n int
		if err == nil {
			n, err = s.one(ctx, "SELECT COUNT(*) AS n FROM "+src.table+" WHERE "+src.where, groupID)
		}
		return n
	}
	recent := func(src source, days int) int {
		var n int
		if err == nil {
			n, err = s.one(ctx, "SELECT COUNT(*) AS n FROM "+src.table+" WHERE "+src.where+
				" AND "+src.at+" >= {:since}", groupID, dbx.Params{"since": since(days)})
		}
		return n
	}
	members := func(src source) []byUID {
		rows := []byUID{}
		if err == nil {
			err = s.all(ctx, &rows, "SELECT "+src.author+" AS uid, COUNT(*) AS c FROM "+src.table+
				" WHERE "+src.where+" GROUP BY uid", groupID)
		}
		return rows
	}
	timeline := func(src source) []byMonth {
		rows := []byMonth{}
		if err == nil {
			err = s.all(ctx, &rows, "SELECT strftime('%Y-%m', "+src.at+", 'unixepoch') AS m, COUNT(*) AS c FROM "+
				src.table+" WHERE "+src.where+" AND "+src.at+" >= {:since} GROUP BY m ORDER BY m",
				groupID, dbx.Params{"since": yearAgo})
		}
		return rows
	}
	weekdays := func(src source) []byDay {
		rows := []byDay{}
		if err == nil {
			err = s.all(ctx, &rows, "SELECT CAST(strftime('%w', "+src.at+", 'unixepoch') AS INTEGER) AS d, COUNT(*) AS c FROM "+
				src.table+" WHERE "+src.where+" GROUP BY d", groupID)
		}
		return rows
	}

	out["messages"] = total(messages)
	out["memories_total"] = total(memories)
	out["moods"] = total(moods)
	out["by_member_messages"] = members(messages)
	out["by_member_memories"] = members(memories)
	out["by_member_moods"] = members(moods)
	out["timeline_messages"] = timeline(messages)
	out["timeline_memories"] = timeline(memories)
	out["timeline_moods"] = timeline(moods)
	out["weekday_messages"] = weekdays(messages)
	out["weekday_memories"] = weekdays(memories)
	out["messages30"], out["messages90"] = recent(messages, 30), recent(messages, 90)
	out["memories30"], out["memories90"] = recent(memories, 30), recent(memories, 90)
	out["moods30"] = recent(moods, 30)

	// Часы — по UTC: клиент поворачивает гистограмму в свой пояс.
	hours := []byHour{}
	if err == nil {
		err = s.all(ctx, &hours, "SELECT CAST(strftime('%H', "+msgAt+", 'unixepoch') AS INTEGER) AS h, COUNT(*) AS c FROM "+
			messages.table+" WHERE "+messages.where+" GROUP BY h", groupID)
	}
	out["hour_messages"] = hours

	kinds := []byKind{}
	if err == nil {
		err = s.all(ctx, &kinds, "SELECT type AS k, COUNT(*) AS c FROM memories WHERE "+memories.where+
			" GROUP BY k ORDER BY c DESC", groupID)
	}
	out["memory_types"] = kinds

	// Дни с любым делом пары за 30 дней — по UTC-суткам.
	if err == nil {
		day := func(src source) string {
			return "SELECT date(" + src.at + ", 'unixepoch') AS d FROM " + src.table +
				" WHERE " + src.where + " AND " + src.at + " >= {:since}"
		}
		var n int
		n, err = s.one(ctx, "SELECT COUNT(DISTINCT d) AS n FROM ("+day(messages)+" UNION "+day(memories)+
			" UNION "+day(moods)+")", groupID, dbx.Params{"since": since(30)})
		out["active_days30_count"] = n
	}
	if err == nil {
		var first struct {
			D string `db:"d"`
		}
		err = s.app.DB().NewQuery("SELECT COALESCE(MIN(created_at), '') AS d FROM memories WHERE " + memories.where).
			WithContext(ctx).Bind(dbx.Params{"g": groupID}).One(&first)
		out["first_memory"] = first.D
	}
	if err == nil {
		var n int
		n, err = s.Count(ctx, "canvas_meta", groupID)
		out["canvases"] = n
	}
	// Отметки настроений по дням и любимые — шифр, их считает клиент.
	out["mood_daily"] = []any{}
	out["mood_top"] = []any{}
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (s *Service) one(ctx context.Context, sql, groupID string, extra ...dbx.Params) (int, error) {
	var row struct {
		N int `db:"n"`
	}
	err := s.app.DB().NewQuery(sql).WithContext(ctx).Bind(params(groupID, extra)).One(&row)
	return row.N, err
}

func (s *Service) all(ctx context.Context, dst any, sql, groupID string, extra ...dbx.Params) error {
	return s.app.DB().NewQuery(sql).WithContext(ctx).Bind(params(groupID, extra)).All(dst)
}

func params(groupID string, extra []dbx.Params) dbx.Params {
	p := dbx.Params{"g": groupID}
	for _, e := range extra {
		for k, v := range e {
			p[k] = v
		}
	}
	return p
}

// videoFile — условие «файл ленты — видео» по расширению.
const videoFile = "(file LIKE '%.mp4' OR file LIKE '%.mov' OR file LIKE '%.webm' OR file LIKE '%.m4v' OR file LIKE '%.3gp' OR file LIKE '%.avi' OR file LIKE '%.mkv')"

// CoupleStats — ответ /api/couple/stats (бывший couple_stats.pb.js): всё для
// экрана «Статистика пары» готовыми числами — тянуть ради графика десятки
// тысяч записей на телефон нельзя. Ряды по чату, ленте и настроениям — из
// CoupleAgg, остальное считается здесь.
func (s *Service) CoupleStats(ctx context.Context, groupID string, now time.Time) (map[string]any, error) {
	agg, err := s.CoupleAgg(ctx, groupID, now)
	if err != nil {
		return nil, err
	}
	n := func(sql string) int {
		var v int
		if err == nil {
			v, err = s.one(ctx, sql, groupID)
		}
		return v
	}
	list := func(dst any, sql string) {
		if err == nil {
			err = s.all(ctx, dst, sql, groupID)
		}
	}

	var couple []struct {
		Created string  `db:"created" json:"created"`
		Start   string  `db:"start" json:"start"`
		Anni    string  `db:"anni" json:"anniversary"`
		Streak  float64 `db:"streak" json:"streak"`
		XP      float64 `db:"xp" json:"xp"`
	}
	list(&couple, `SELECT created_at AS created, start_date AS start, anniversary_date AS anni,
		COALESCE(streak_days, 0) AS streak, COALESCE(xp, 0) AS xp FROM groups WHERE id = {:g}`)
	// Имя участника — шифр (`users.display_name` личным ключом, в паре —
	// `groups.member_names` ключом пары): сервер отдаёт пустое, клиент
	// подставляет расшифрованное (ForkE2E.patchCoupleStats). Шифр в ответе
	// старым сборкам рисовался на экране вместо имени.
	members := []struct {
		UID  string `db:"uid" json:"uid"`
		Name string `db:"name" json:"name"`
	}{}
	list(&members, `SELECT je.value AS uid, '' AS name
		FROM groups gr, json_each(gr.members) je
		WHERE gr.id = {:g} AND json_valid(gr.members)`)

	media := n("SELECT COUNT(*) AS n FROM media WHERE group_id = {:g}")
	videos := n("SELECT COUNT(*) AS n FROM media WHERE group_id = {:g} AND " + videoFile)
	strokes, cerr := s.Count(ctx, "canvas_strokes", groupID)
	if err == nil {
		err = cerr
	}
	totals := map[string]any{
		"memories": agg["memories_total"],
		"comments": n("SELECT COUNT(*) AS n FROM memory_comments WHERE group_id = {:g}"),
		"messages": agg["messages"],
		"moods":    agg["moods"],
		"missYou":  n("SELECT COALESCE(SUM(count), 0) AS n FROM miss_you WHERE group_id = {:g}"),
		"strokes":  strokes,
		"canvases": agg["canvases"],
		"gifts":    n("SELECT COUNT(*) AS n FROM gifts WHERE group_id = {:g}"),
		"watch":    n("SELECT COUNT(*) AS n FROM watch_history WHERE group_id = {:g}"),
		"media":    media,
		"videos":   videos,
		"photos":   media - videos,
		"mascots":  n("SELECT COUNT(*) AS n FROM mascots WHERE group_id = {:g}"),
	}

	missYou, gifts := []byUID{}, []byUID{}
	list(&missYou, "SELECT user_uid AS uid, COALESCE(SUM(count), 0) AS c FROM miss_you WHERE group_id = {:g} GROUP BY uid")
	list(&gifts, "SELECT sender_uid AS uid, COUNT(*) AS c FROM gifts WHERE group_id = {:g} GROUP BY uid")
	giftKinds := []byKind{}
	list(&giftKinds, "SELECT gift_key AS k, COUNT(*) AS c FROM gifts WHERE group_id = {:g} GROUP BY k ORDER BY c DESC LIMIT 10")
	// Площадка просмотра (`watch_history.kind`) — шифр, у каждой записи свой:
	// группировка давала по строке на ролик. Разбивку считает клиент.
	watchKinds := []byKind{}
	missWeek := []struct {
		UID string `db:"uid" json:"uid"`
		W   string `db:"w" json:"w"`
	}{}
	list(&missWeek, "SELECT user_uid AS uid, COALESCE(by_weekday, '') AS w FROM miss_you WHERE group_id = {:g}")
	if err != nil {
		return nil, err
	}

	out := map[string]any{"ok": true, "couple": map[string]any{}, "members": members, "totals": totals}
	if len(couple) > 0 {
		out["couple"] = couple[0]
	}
	out["byMember"] = map[string]any{
		"memories": agg["by_member_memories"], "messages": agg["by_member_messages"],
		"moods": agg["by_member_moods"], "missYou": missYou, "gifts": gifts,
	}
	out["timeline"] = map[string]any{
		"memories": agg["timeline_memories"], "messages": agg["timeline_messages"], "moods": agg["timeline_moods"],
	}
	// %w — 0 = воскресенье; клиент разворачивает под свою неделю.
	out["rhythm"] = map[string]any{
		"weekdayMessages": agg["weekday_messages"], "hourMessages": agg["hour_messages"],
		"weekdayMemories": agg["weekday_memories"],
	}
	out["mood"] = map[string]any{"daily": agg["mood_daily"], "top": agg["mood_top"]}
	out["breakdown"] = map[string]any{
		"memoryTypes": agg["memory_types"], "gifts": giftKinds, "watchKinds": watchKinds, "missYouWeekday": missWeek,
	}
	// Темп последних недель — основа прогноза: годовое среднее для пары,
	// которая только начала, врало бы вдвое.
	out["pace"] = map[string]any{
		"memories30": agg["memories30"], "memories90": agg["memories90"],
		"messages30": agg["messages30"], "messages90": agg["messages90"],
		"moods30": agg["moods30"], "activeDays30": agg["active_days30_count"],
		"firstMemory": agg["first_memory"],
	}
	return out, nil
}
