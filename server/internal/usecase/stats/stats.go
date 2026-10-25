// Package stats — счётчики пары для экрана статистики (/internal/couple-agg и
// /internal/count, которые у апстрима держал hotpath поверх Postgres).
//
// Считаются только метаданные, которые сервер и так хранит открыто: кто и
// когда написал, добавил воспоминание или отметил настроение, тип
// воспоминания. Содержимое зашифровано (docs/E2E.md), поэтому разбивки по
// самим настроениям (`mood_daily`, `mood_top`: mood_id — шифр) здесь нет —
// их считает клиент из своих расшифрованных данных (BACKLOG T2).
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

// ErrUnknownCol — коллекцию нельзя считать через /internal/count.
var ErrUnknownCol = errors.New("stats: коллекция не считается")

// countable — что можно посчитать по group_id через /internal/count.
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

// CoupleAgg — ответ в форме hotpath `/internal/couple-agg` (его читает
// couple_stats.pb.js). now — отсчёт для «за 30/90 дней» и года по месяцам.
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
