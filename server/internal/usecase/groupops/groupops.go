// Package groupops — атомарные операции участника над своей парой (бывший
// groups.pb.js): правка своего ключа в словаре, счётчик, выход, отметка дня
// для серии и «Скучаю». Клиентский read-modify-write по полям пары терял
// правки при записи с двух устройств; здесь каждая операция — транзакция
// PocketBase, а запись в SQLite идёт одним соединением, так что второй вызов
// читает уже обновлённое значение.
//
// Транзакция обходит правила коллекций, поэтому членство проверяет каждая
// операция сама.
package groupops

import (
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"sync"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	spfcast "github.com/spf13/cast"

	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
)

var (
	// ErrNotFound — пары нет.
	ErrNotFound = errors.New("groupops: пары нет")
	// ErrDisbanded — пара распалась.
	ErrDisbanded = errors.New("groupops: пара распалась")
	// ErrNotMember — человек не в паре.
	ErrNotMember = errors.New("groupops: не участник")
	// ErrBadParams — неверные параметры.
	ErrBadParams = errors.New("groupops: неверные параметры")
)

// Service — операции над парами.
type Service struct {
	app core.App
	now func() time.Time

	mu   sync.Mutex
	miss map[string]*missBuffer
}

// New — сервис над app.
func New(app core.App, now func() time.Time) *Service {
	return &Service{app: app, now: now, miss: map[string]*missBuffer{}}
}

// Check — пара есть и не распалась (до проверки остального, как в хуке).
func (s *Service) Check(groupID string) error {
	g, err := s.app.FindRecordById("groups", groupID)
	if err != nil {
		return ErrNotFound
	}
	if g.GetBool("disbanded") {
		return ErrDisbanded
	}
	return nil
}

// inGroup — транзакция над записью пары участника uid.
func (s *Service) inGroup(groupID, uid string, fn func(tx core.App, g *core.Record) error) error {
	return s.app.RunInTransaction(func(tx core.App) error {
		g, err := tx.FindRecordById("groups", groupID)
		if err != nil {
			return ErrNotFound
		}
		if !slices.Contains(pairs.Members(g), uid) {
			return ErrNotMember
		}
		return fn(tx, g)
	})
}

// patchable — словари, в которых участник правит свой ключ. Дни рождения и
// карточки клиент пишет шифром ключа пары.
var patchable = []string{"member_moods", "member_names", "member_avatars", "member_ailments",
	"member_birthdays", "member_cards"}

// PatchMap ставит value под ключом uid в словаре field; nil — удаляет ключ.
func (s *Service) PatchMap(groupID, uid, field string, value any) error {
	if groupID == "" || uid == "" || !slices.Contains(patchable, field) {
		return ErrBadParams
	}
	return s.inGroup(groupID, uid, func(tx core.App, g *core.Record) error {
		m := jsonMap(g, field)
		if value == nil {
			delete(m, uid)
		} else {
			m[uid] = value
		}
		g.Set(field, m)
		return tx.Save(g)
	})
}

// IncrementResult — ответ счётчика.
type IncrementResult struct {
	Value float64
	Noop  bool
}

// Increment прибавляет by к счётчику пары. Холсты и ленту считает сервер
// (bindCounters): старые сборки ещё зовут их здесь — отвечаем «готово», не
// трогая, иначе счёт задвоится.
func (s *Service) Increment(groupID, uid, field string, by float64) (IncrementResult, error) {
	if field == "drawings_count" || field == "memories_count" {
		return IncrementResult{Noop: true}, nil
	}
	if groupID == "" || field != "xp" {
		return IncrementResult{}, ErrBadParams
	}
	var next float64
	err := s.inGroup(groupID, uid, func(tx core.App, g *core.Record) error {
		next = float64(g.GetInt(field)) + by
		g.Set(field, next)
		return tx.Save(g)
	})
	return IncrementResult{Value: next}, err
}

// Leave убирает uid из пары и из её словарей; ушёл последний — пара
// распалась.
func (s *Service) Leave(groupID, uid string) error {
	if groupID == "" || uid == "" {
		return ErrBadParams
	}
	return s.inGroup(groupID, uid, func(tx core.App, g *core.Record) error {
		members := slices.DeleteFunc(pairs.Members(g), func(m string) bool { return m == uid })
		g.Set("members", members)
		for _, f := range []string{"member_names", "member_avatars", "member_moods", "member_ailments"} {
			m := jsonMap(g, f)
			delete(m, uid)
			g.Set(f, m)
		}
		if len(members) == 0 {
			g.Set("disbanded", true)
			g.Set("disbanded_at", s.now().UTC())
		}
		return tx.Save(g)
	})
}

// Activity — итог отметки дня.
type Activity struct {
	Already      bool
	Pending      bool
	Streak       int
	MascotStreak int
}

// RecordActivity отмечает, что uid зашёл в день today (YYYY-MM-DD, дата
// телефона). Серия растёт, когда за день зашли оба: первый ставит отметку
// ожидания, второй засчитывает день паре и активному маскоту.
//
// Правила — продовые (hotpath апстрима): соседний день тоже общий (у пары из
// разных поясов даты не совпадают никогда); днём серии считается дата того,
// кто отметился первым (партнёр часто заходит после полуночи); ожидание с
// датой уже закрытого дня — остаток, а не отметка; оборванную серию маскот
// помнит три дня, чтобы её можно было вернуть ([RestoreStreak]).
func (s *Service) RecordActivity(groupID, uid, today string) (Activity, error) {
	if groupID == "" || uid == "" || !isDay(today) {
		return Activity{}, ErrBadParams
	}
	// Клиент отмечается на каждом заходе, а день засчитывается один раз:
	// сначала дешёвое чтение, транзакция — только для настоящей отметки.
	if peek, err := s.app.FindRecordById("groups", groupID); err == nil {
		if !slices.Contains(pairs.Members(peek), uid) {
			return Activity{}, ErrNotMember
		}
		if peek.GetString("streak_last_opened_date") == today {
			return Activity{Already: true}, nil
		}
	}
	var out Activity
	var mascot string
	err := s.inGroup(groupID, uid, func(tx core.App, g *core.Record) error {
		last := g.GetString("streak_last_opened_date")
		if last == today {
			out = Activity{Already: true}
			return nil
		}
		pendDate, pendUID := g.GetString("streak_pending_date"), g.GetString("streak_pending_uid")
		if pendDate != "" && last != "" && pendDate <= last {
			pendDate, pendUID = "", ""
		}
		if pendUID == "" || pendUID == uid || !sameDay(today, pendDate) {
			out = Activity{Pending: true}
			if !sameDay(today, pendDate) || pendUID == "" {
				g.Set("streak_pending_date", today)
				g.Set("streak_pending_uid", uid)
				return tx.Save(g)
			}
			return nil
		}

		// Оба были — день засчитан датой первого.
		start := min(today, pendDate)
		groupBefore := g.GetInt("streak_days")
		out.Streak = 1
		if daysBetween(start, last) == 1 {
			out.Streak = groupBefore + 1
		}
		g.Set("streak_days", out.Streak)
		g.Set("streak_last_opened_date", start)
		g.Set("streak_pending_date", "")
		g.Set("streak_pending_uid", "")
		mascot = g.GetString("active_mascot_id")
		if mascot != "" {
			streaks := jsonMap(g, "mascot_streaks")
			prev, _ := streaks[mascot].(map[string]any)
			was := int(toFloat(prev["s"]))
			prevDay, _ := prev["d"].(string)
			inRow := daysBetween(start, prevDay) == 1
			out.MascotStreak = 1
			entry := map[string]any{"d": start}
			if inRow {
				out.MascotStreak = was + 1
				for _, k := range lostKeys {
					if v, ok := prev[k]; ok {
						entry[k] = v
					}
				}
			} else if was >= 2 {
				// Серия оборвалась: прежнее число помним, чтобы пара могла
				// вернуть его за ролик.
				lostGroup := 0
				if out.Streak == 1 {
					lostGroup = groupBefore
				}
				entry["lost"], entry["lost_d"], entry["lost_g"] = was, start, lostGroup
			}
			entry["s"] = out.MascotStreak
			streaks[mascot] = entry
			g.Set("mascot_streaks", streaks)
		}
		return tx.Save(g)
	})
	if err == nil && mascot != "" && out.MascotStreak > 0 {
		s.raiseRecord(groupID, mascot, out.MascotStreak)
	}
	return out, err
}

// lostKeys — память обрыва в записи маскота: сколько было, когда оборвалось,
// сколько потеряла пара.
var lostKeys = []string{"lost", "lost_d", "lost_g"}

// restoreWindow — сколько дней после обрыва серию ещё можно вернуть.
const restoreWindow = 3

// Restored — серия после возврата и поля пары для кэша приложения.
type Restored struct {
	Streak, GroupStreak int
	MascotStreaks       map[string]any
	LastOpened          string
}

// ErrNothingToRestore — возвращать нечего или срок вышел.
var ErrNothingToRestore = errors.New("groupops: нечего возвращать")

// RestoreStreak возвращает сгоревшую серию активного маскота (ролик смотрит
// клиент). Обрыв бывает двух видов: пара уже вернулась и зачёт сбросил серию
// в единицу — прежнее число лежит в `lost`, его прибавляем; пара ещё не
// вернулась — пропуск закрываем вчерашним днём, и сегодняшний общий день
// продолжит серию.
func (s *Service) RestoreStreak(groupID, uid, today string) (Restored, error) {
	if groupID == "" || !isDay(today) {
		return Restored{}, ErrBadParams
	}
	var out Restored
	var mascot string
	err := s.inGroup(groupID, uid, func(tx core.App, g *core.Record) error {
		mascot = g.GetString("active_mascot_id")
		streaks := jsonMap(g, "mascot_streaks")
		entry, _ := streaks[mascot].(map[string]any)
		if mascot == "" || entry == nil {
			return ErrNothingToRestore
		}
		group, last := g.GetInt("streak_days"), g.GetString("streak_last_opened_date")
		next := map[string]any{}
		lost, lostDay := int(toFloat(entry["lost"])), str(entry["lost_d"])
		was, day := int(toFloat(entry["s"])), str(entry["d"])
		switch {
		case lost >= 2 && lostDay != "" && between(daysBetween(today, lostDay), 0, restoreWindow):
			for k, v := range entry {
				if !slices.Contains(lostKeys, k) {
					next[k] = v
				}
			}
			next["s"] = was + lost
			group += int(toFloat(entry["lost_g"]))
		case was >= 2 && day != "" && between(daysBetween(today, day), 2, restoreWindow+1):
			for k, v := range entry {
				next[k] = v
			}
			yesterday := addDays(today, -1)
			next["d"] = yesterday
			if last != "" && between(daysBetween(today, last), 2, restoreWindow+1) {
				last = yesterday
			}
		default:
			return ErrNothingToRestore
		}
		streaks[mascot] = next
		g.Set("mascot_streaks", streaks)
		g.Set("streak_days", group)
		g.Set("streak_last_opened_date", last)
		out = Restored{Streak: int(toFloat(next["s"])), GroupStreak: group, MascotStreaks: streaks, LastOpened: last}
		return tx.Save(g)
	})
	if err == nil {
		s.raiseRecord(groupID, mascot, out.Streak)
	}
	return out, err
}

// raiseRecord поднимает рекорд серии маскота. Каталожных маскотов в базе нет
// — им рекорд не пишется.
func (s *Service) raiseRecord(groupID, mascot string, streak int) {
	m, err := s.app.FindFirstRecordByFilter("mascots", "group_id = {:g} && mascot_id = {:m}",
		dbx.Params{"g": groupID, "m": mascot})
	if err != nil || m.GetInt("record_streak") >= streak {
		return
	}
	m.Set("record_streak", streak)
	if err := s.app.Save(m); err != nil {
		s.app.Logger().Warn("рекорд серии не записан", "group", groupID, "err", err)
	}
}

func isDay(s string) bool {
	_, err := time.Parse(time.DateOnly, s)
	return err == nil && len(s) == 10
}

// daysBetween — сколько дней от earlier до later; не даты — очень много.
func daysBetween(later, earlier string) int {
	a, err1 := time.Parse(time.DateOnly, later)
	b, err2 := time.Parse(time.DateOnly, earlier)
	if err1 != nil || err2 != nil {
		return 1 << 20
	}
	return int(a.Sub(b).Hours() / 24)
}

// sameDay — отметка партнёра того же общего дня: та же дата или соседняя.
func sameDay(today, pending string) bool {
	d := daysBetween(today, pending)
	return pending != "" && (d == 0 || d == 1 || d == -1)
}

func addDays(day string, n int) string {
	t, _ := time.Parse(time.DateOnly, day)
	return t.AddDate(0, 0, n).Format(time.DateOnly)
}

func between(v, lo, hi int) bool { return v >= lo && v <= hi }

func str(v any) string {
	s, _ := v.(string)
	return s
}

func jsonMap(g *core.Record, field string) map[string]any {
	m := map[string]any{}
	if err := g.UnmarshalJSONField(field, &m); err != nil || m == nil {
		return map[string]any{}
	}
	return m
}

func toFloat(v any) float64 {
	f, _ := spfcast.ToFloat64E(v)
	return f
}

// ── «Скучаю» ───────────────────────────────────────────────────────────────

// missWindow — как часто нажатия одного человека доходят до базы. Вечерами
// «Скучаю» жали десятки раз в секунду (игра «кто больше»), и каждая запись
// занимала соединение записи. Первое нажатие серии уходит сразу — партнёр
// получает зов без задержки, — а хвост копится в памяти и доезжает суммой
// со следующим нажатием после окна.
const missWindow = 10 * time.Second

var vibes = []string{"miss_you", "thinking_of_you", "want_hug", "custom"}

type missBuffer struct {
	at    time.Time
	n     int
	week  map[string]int // "0" — день не прислан, берётся у следующей записи
	vibes map[string]int
	base  int
}

// MissInput — нажатия «Скучаю».
type MissInput struct {
	GroupID, UID string
	Vibe, Text   string
	Times        int // 1…20, остальное — 1
	Weekday      int // 1=пн … 7=вс по часам телефона; иначе — по UTC
}

// MissResult — счёт человека после нажатий.
type MissResult struct {
	Count    int
	Buffered bool
}

// MissYou прибавляет нажатия к записи miss_you человека: общий счёт, карта
// по дням недели и по типу зова.
func (s *Service) MissYou(in MissInput) (MissResult, error) {
	if in.GroupID == "" || in.UID == "" {
		return MissResult{}, ErrBadParams
	}
	if in.Times < 1 || in.Times > 20 {
		in.Times = 1
	}
	if in.Vibe == "" {
		in.Vibe = "miss_you"
	}
	vibeKey := in.Vibe
	if !slices.Contains(vibes, vibeKey) {
		vibeKey = "miss_you"
	}
	key := in.GroupID + ":" + in.UID
	now := s.now()

	s.mu.Lock()
	buf := s.miss[key]
	if buf != nil && now.Sub(buf.at) < missWindow {
		wk := "0"
		if in.Weekday >= 1 && in.Weekday <= 7 {
			wk = strconv.Itoa(in.Weekday)
		}
		buf.n += in.Times
		buf.week[wk] += in.Times
		buf.vibes[vibeKey] += in.Times
		count := buf.base + buf.n
		s.mu.Unlock()
		return MissResult{Count: count, Buffered: true}, nil
	}
	carry := &missBuffer{week: map[string]int{}, vibes: map[string]int{}}
	if buf != nil {
		carry = buf
	}
	// Окно закрыто: накопленное уезжает этой записью. Пока она идёт, новые
	// нажатия копятся в свежем окне — счёт не теряется.
	s.miss[key] = &missBuffer{at: now, week: map[string]int{}, vibes: map[string]int{}}
	s.sweepMiss(now)
	s.mu.Unlock()

	weekday := in.Weekday
	if weekday < 1 || weekday > 7 {
		weekday = int(now.UTC().Weekday())
		if weekday == 0 {
			weekday = 7
		}
	}
	day := strconv.Itoa(weekday)
	var count int
	err := s.inGroup(in.GroupID, in.UID, func(tx core.App, _ *core.Record) error {
		rec, err := tx.FindFirstRecordByFilter("miss_you", "group_id = {:g} && user_uid = {:u}",
			dbx.Params{"g": in.GroupID, "u": in.UID})
		if err != nil {
			col, err := tx.FindCollectionByNameOrId("miss_you")
			if err != nil {
				return err
			}
			rec = core.NewRecord(col)
			rec.Set("group_id", in.GroupID)
			rec.Set("user_uid", in.UID)
		}
		before := rec.GetInt("count")
		week := textMap(rec, "by_weekday")
		week[day] += in.Times
		for k, n := range carry.week {
			if k == "0" {
				k = day
			}
			week[k] += n
		}
		byVibe := textMap(rec, "by_vibe")
		// Первая карта у старой пары: весь прежний счёт был «скучаю» — так его
		// показывает и клиент, пока карты нет.
		if len(byVibe) == 0 && before > 0 {
			byVibe["miss_you"] = before
		}
		byVibe[vibeKey] += in.Times
		for k, n := range carry.vibes {
			byVibe[k] += n
		}
		count = before + in.Times + carry.n
		rec.Set("count", count)
		rec.Set("by_weekday", mustJSON(week))
		rec.Set("by_vibe", mustJSON(byVibe))
		rec.Set("updated_at", now.UTC())
		rec.Set("last_vibe", in.Vibe)
		rec.Set("last_vibe_text", in.Text)
		return tx.Save(rec)
	})

	s.mu.Lock()
	defer s.mu.Unlock()
	cur := s.miss[key]
	if err != nil {
		// Запись не прошла: возвращаем унесённое в копилку, чтобы не пропало.
		if cur != nil {
			cur.n += carry.n
			for k, n := range carry.week {
				cur.week[k] += n
			}
			for k, n := range carry.vibes {
				cur.vibes[k] += n
			}
			if errors.Is(err, ErrNotMember) || errors.Is(err, ErrNotFound) {
				delete(s.miss, key)
			}
		}
		return MissResult{}, err
	}
	if cur != nil {
		cur.base = count
	}
	return MissResult{Count: count}, nil
}

// sweepMiss убирает давно закрытые пустые окна. Окна с нажатиями держим:
// их сумма уедет со следующим нажатием.
func (s *Service) sweepMiss(now time.Time) {
	if len(s.miss) < 1024 {
		return
	}
	for k, b := range s.miss {
		if b.n == 0 && now.Sub(b.at) > missWindow {
			delete(s.miss, k)
		}
	}
}

// textMap — карта «ключ → число» из текстового поля с JSON.
func textMap(r *core.Record, field string) map[string]int {
	raw := map[string]any{}
	_ = json.Unmarshal([]byte(r.GetString(field)), &raw)
	out := map[string]int{}
	for k, v := range raw {
		out[k] = int(toFloat(v))
	}
	return out
}

func mustJSON(v any) string {
	b, err := json.Marshal(v)
	if err != nil {
		panic(fmt.Sprintf("groupops: %v", err))
	}
	return string(b)
}
