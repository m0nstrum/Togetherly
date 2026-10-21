package movies

import (
	"context"
	"encoding/json"
	"errors"
	"net/url"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/infrastructure/safefetch"
)

const fixture = "../../../../pocketbase/hotpath/fixtures/wikidata_sample.json"

// fakeFetch — Викиданные и poiskkino по образцу автора, без сети.
type fakeFetch struct {
	mu       sync.Mutex
	entities map[string]json.RawMessage
	calls    []url.Values
	headers  []map[string]string
	wdDown   bool
	pkStatus int
}

func newFake(t *testing.T) *fakeFetch {
	t.Helper()
	raw, err := os.ReadFile(fixture)
	require.NoError(t, err)
	var s struct {
		Entities struct {
			Entities map[string]json.RawMessage `json:"entities"`
		} `json:"entities"`
	}
	require.NoError(t, json.Unmarshal(raw, &s))
	return &fakeFetch{entities: s.Entities.Entities, pkStatus: 200}
}

func (f *fakeFetch) Get(_ context.Context, raw string, h map[string]string) (safefetch.Response, error) {
	u, _ := url.Parse(raw)
	q := u.Query()
	f.mu.Lock()
	f.calls = append(f.calls, q)
	f.headers = append(f.headers, h)
	f.mu.Unlock()
	js := func(v any) (safefetch.Response, error) {
		b, _ := json.Marshal(v)
		return safefetch.Response{Status: 200, ContentType: "application/json", Body: b}, nil
	}
	if strings.Contains(raw, "poiskkino") {
		if f.pkStatus != 200 {
			return safefetch.Response{Status: f.pkStatus}, nil
		}
		return js(map[string]any{"docs": []any{map[string]any{
			"id": 301, "name": "Матрица", "persons": []any{"x"}, "rating": map[string]any{"kp": 8.5, "imdb": 8.7},
		}}})
	}
	if f.wdDown {
		return safefetch.Response{}, errors.New("сеть")
	}
	switch {
	case q.Get("list") == "search":
		if strings.HasPrefix(q.Get("srsearch"), "пусто") {
			return js(map[string]any{"query": map[string]any{"search": []any{}}})
		}
		ids := []string{"Q13417189", "Q50412717", "Q79784"}
		if strings.Contains(q.Get("srsearch"), "*") {
			ids = []string{"Q246283", "Q13417189"}
		}
		var hits []any
		for _, id := range ids {
			hits = append(hits, map[string]string{"title": id})
		}
		return js(map[string]any{"query": map[string]any{"search": hits}})
	case q.Get("action") == "wbgetentities":
		out := map[string]any{}
		for _, id := range strings.Split(q.Get("ids"), "|") {
			if q.Get("props") == "labels" {
				out[id] = map[string]any{"labels": map[string]any{"ru": map[string]string{"value": "США"}}}
			} else if e, ok := f.entities[id]; ok {
				out[id] = e
			}
		}
		return js(map[string]any{"entities": out})
	}
	return safefetch.Response{Status: 400}, nil
}

func (f *fakeFetch) count(pred func(url.Values) bool) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	n := 0
	for _, c := range f.calls {
		if pred(c) {
			n++
		}
	}
	return n
}

type allow struct{ deny bool }

func (a allow) Allow(string, time.Time) bool { return !a.deny }

func names(t *testing.T, r Result) []string {
	t.Helper()
	var docs []struct {
		Name string `json:"name"`
	}
	require.NoError(t, json.Unmarshal(r.Docs, &docs))
	var out []string
	for _, d := range docs {
		out = append(out, d.Name)
	}
	return out
}

func TestSearch(t *testing.T) {
	ctx := context.Background()
	now := func() time.Time { return time.Unix(1_800_000_000, 0) }

	t.Run("точное выше звёздочки, без повторов и порно", func(t *testing.T) {
		svc := New(newFake(t), allow{}, Options{}, now)
		r, err := svc.Search(ctx, "u1", "Интерстеллар", "ru")
		require.NoError(t, err)
		got := names(t, r)
		assert.Equal(t, "wikidata", r.Source)
		assert.Equal(t, "Интерстеллар", got[0])
		assert.Equal(t, 1, strings.Count(strings.Join(got, "|"), "Интерстеллар"))
		assert.Contains(t, got, "Холодное сердце")
		assert.Contains(t, got, "Друзья")
		assert.Len(t, got, 3, "порнофильм выброшен")
	})

	t.Run("повтор — из кэша запросов, записи — из кэша записей", func(t *testing.T) {
		f := newFake(t)
		svc := New(f, allow{}, Options{}, now)
		_, err := svc.Search(ctx, "u1", "интерстеллар", "ru")
		require.NoError(t, err)
		r, err := svc.Search(ctx, "u1", "«Интерстеллар»", "ru")
		require.NoError(t, err)
		assert.Equal(t, "cache", r.Source)

		heavy := func(q url.Values) bool { return q.Get("props") == "labels|claims" }
		before := f.count(heavy)
		_, err = svc.Search(ctx, "u1", "интерстеллар", "en")
		require.NoError(t, err)
		assert.Equal(t, before, f.count(heavy), "тяжёлые записи второй раз не тянем")
	})

	t.Run("короткое слово без звёздочки", func(t *testing.T) {
		f := newFake(t)
		_, err := New(f, allow{}, Options{}, now).Search(ctx, "u1", "оно", "ru")
		require.NoError(t, err)
		assert.Zero(t, f.count(func(q url.Values) bool {
			return strings.Contains(strings.Split(q.Get("srsearch"), " haswbstatement")[0], "*")
		}))
	})

	t.Run("узнаваемый User-Agent", func(t *testing.T) {
		f := newFake(t)
		_, err := New(f, allow{}, Options{}, now).Search(ctx, "u1", "оно", "ru")
		require.NoError(t, err)
		assert.Contains(t, f.headers[0]["User-Agent"], "Tethered")
	})

	t.Run("пустой поиск", func(t *testing.T) {
		r, err := New(newFake(t), allow{}, Options{}, now).Search(ctx, "u1", "пусто совсем", "ru")
		require.NoError(t, err)
		assert.JSONEq(t, `[]`, string(r.Docs))
		assert.Equal(t, "none", r.Source)
		r, err = New(newFake(t), allow{}, Options{}, now).Search(ctx, "u1", "а", "ru")
		require.NoError(t, err)
		assert.Equal(t, "empty", r.Source)
	})

	t.Run("лимит на человека", func(t *testing.T) {
		_, err := New(newFake(t), allow{deny: true}, Options{}, now).Search(ctx, "u1", "оно", "ru")
		assert.ErrorIs(t, err, ErrRateLimited)
	})

	t.Run("без ключа poiskkino не трогаем", func(t *testing.T) {
		f := newFake(t)
		f.wdDown = true
		_, err := New(f, allow{}, Options{}, now).Search(ctx, "u1", "матрица", "ru")
		assert.ErrorIs(t, err, ErrUnavailable)
		assert.Zero(t, f.count(func(q url.Values) bool { return q.Get("query") != "" }))
	})

	t.Run("ключ оператора — запасной путь", func(t *testing.T) {
		f := newFake(t)
		f.wdDown = true
		r, err := New(f, allow{}, Options{PoiskkinoKey: "k"}, now).Search(ctx, "u1", "матрица", "ru")
		require.NoError(t, err)
		assert.Equal(t, "poiskkino", r.Source)
		assert.JSONEq(t, `[{"id":301,"name":"Матрица","rating":{"kp":8.5}}]`, string(r.Docs))

		f.pkStatus = 403
		_, err = New(f, allow{}, Options{PoiskkinoKey: "k"}, now).Search(ctx, "u1", "матрица", "ru")
		assert.ErrorIs(t, err, ErrQuota)
	})
}
