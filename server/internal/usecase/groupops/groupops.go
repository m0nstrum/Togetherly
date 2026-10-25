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
func (s *Service) RecordActivity(groupID, uid, today string) (Activity, error) {
	if groupID == "" || uid == "" {
		return Activity{}, ErrBadParams
	}
	if _, err := time.Parse(time.DateOnly, today); err != nil || len(today) != 10 {
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
	err := s.inGroup(groupID, uid, func(tx core.App, g *core.Record) error {
		last := g.GetString("streak_last_opened_date")
		if last == today {
			out = Activity{Already: true}
			return nil
		}
		pendUID, pendDate := g.GetString("streak_pending_uid"), g.GetString("streak_pending_date")
		if pendDate == today && pendUID != "" && pendUID != uid {
			out.Streak = 1
			if consecutive(last, today) {
				out.Streak = g.GetInt("streak_days") + 1
			}
			g.Set("streak_days", out.Streak)
			g.Set("streak_last_opened_date", today)
			// Своя серия у каждого маскота, по его последнему общему дню:
			// пропуск — снова с единицы.
			mascot := g.GetString("active_mascot_id")
			if mascot != "" {
				streaks := jsonMap(g, "mascot_streaks")
				prev, _ := streaks[mascot].(map[string]any)
				out.MascotStreak = 1
				if d, _ := prev["d"].(string); consecutive(d, today) {
					out.MascotStreak = int(toFloat(prev["s"])) + 1
				}
				streaks[mascot] = map[string]any{"s": out.MascotStreak, "d": today}
				g.Set("mascot_streaks", streaks)
			}
			if err := tx.Save(g); err != nil {
				return err
			}
			if mascot != "" {
				// Рекорд — только у сохранённых маскотов; каталожных нет в базе.
				m, err := tx.FindFirstRecordByFilter("mascots", "group_id = {:g} && mascot_id = {:m}",
					dbx.Params{"g": groupID, "m": mascot})
				if err == nil && m.GetInt("record_streak") < out.MascotStreak {
					m.Set("record_streak", out.MascotStreak)
					if err := tx.Save(m); err != nil {
						return err
					}
				}
			}
			return nil
		}
		out = Activity{Pending: true}
		if pendDate != today || pendUID == "" {
			g.Set("streak_pending_date", today)
			g.Set("streak_pending_uid", uid)
			return tx.Save(g)
		}
		return nil
	})
	return out, err
}

func consecutive(prev, today string) bool {
	a, err1 := time.Parse(time.DateOnly, today)
	b, err2 := time.Parse(time.DateOnly, prev)
	return err1 == nil && err2 == nil && a.Sub(b) == 24*time.Hour
}

func jsonMap(g *core.Record, field string) map[string]any {
	m := map[string]any{}
	if err := g.UnmarshalJSONField(field, &m); err != nil || m == nil {
		return map[string]any{}
	}
	return m
}

func toFloat(v any) float64 {
	switch x := v.(type) {
	case float64:
		return x
	case string:
		f, _ := strconv.ParseFloat(x, 64)
		return f
	}
	return 0
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
