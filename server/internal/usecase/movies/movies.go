// Package movies — поиск фильмов для приложения (бывший /api/movies/search
// в hotpath апстрима): Викиданные первыми, poiskkino — запасным, только если
// оператор задал свой ключ. Общий ключ автора форк не использует.
package movies

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strings"
	"sync"
	"time"

	dm "github.com/m0nstrum/togetherly/server/internal/domain/movies"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/safefetch"
)

// Fetcher — безопасный загрузчик (infrastructure/safefetch).
type Fetcher interface {
	Get(ctx context.Context, url string, headers map[string]string) (safefetch.Response, error)
}

// Limiter — сколько поисков можно человеку (handler.IPLimiter по uid).
type Limiter interface {
	Allow(key string, now time.Time) bool
}

var (
	// ErrRateLimited — человек ищет слишком часто (клиент: 429).
	ErrRateLimited = errors.New("movies: слишком часто")
	// ErrUnavailable — источники не ответили (клиент: 503).
	ErrUnavailable = errors.New("movies: источники не ответили")
	// ErrQuota — Викиданные не ответили, а у ключа poiskkino кончился
	// суточный лимит (клиент: 503 с reason=quota).
	ErrQuota = errors.New("movies: лимит poiskkino")
)

// Result — ответ в форме poiskkino.
type Result struct {
	Docs   json.RawMessage `json:"docs"`
	Source string          `json:"source"`
}

// Options — настройки поиска.
type Options struct {
	// WikidataAPI — адрес api.php (подмена в тестах).
	WikidataAPI string
	// PoiskkinoAPI — адрес /v1.4/movie/search; ключ пуст — не ходим.
	PoiskkinoAPI string
	PoiskkinoKey string
	// UserAgent — Викиданные требуют узнаваемый (политика Wikimedia).
	UserAgent string
}

const (
	queryTTL      = 3 * 24 * time.Hour // новые фильмы появляются не сразу
	emptyTTL      = 6 * time.Hour      // пустой ответ помним недолго
	entityTTL     = 14 * 24 * time.Hour
	searchTimeout = 20 * time.Second
	resultLimit   = 10
)

// Service — поиск с кэшем запросов и записей Викиданных (в памяти).
type Service struct {
	fetch    Fetcher
	limit    Limiter
	opt      Options
	now      func() time.Time
	queries  *ttlCache[Result]
	entities *ttlCache[dm.Compact]
	gate     chan struct{}
}

// New — поиск поверх fetch.
func New(fetch Fetcher, limit Limiter, opt Options, now func() time.Time) *Service {
	if opt.WikidataAPI == "" {
		opt.WikidataAPI = "https://www.wikidata.org/w/api.php"
	}
	if opt.PoiskkinoAPI == "" {
		opt.PoiskkinoAPI = "https://api.poiskkino.dev/v1.4/movie/search"
	}
	if opt.UserAgent == "" {
		opt.UserAgent = "Tethered/1.0 (self-hosted; https://github.com/m0nstrum/togetherly)"
	}
	return &Service{
		fetch: fetch, limit: limit, opt: opt, now: now,
		queries:  newTTLCache[Result](5000),
		entities: newTTLCache[dm.Compact](20000),
		gate:     make(chan struct{}, 6),
	}
}

// Search ищет q для человека uid; lang — язык названий.
func (s *Service) Search(ctx context.Context, uid, q, lang string) (Result, error) {
	q, lang = dm.NormQuery(q), dm.Lang(lang)
	if q == "" {
		return Result{Docs: json.RawMessage("[]"), Source: "empty"}, nil
	}
	key := lang + "|" + q
	if r, ok := s.queries.get(key, s.now()); ok {
		r.Source = "cache"
		return r, nil
	}
	if !s.limit.Allow(uid, s.now()) {
		return Result{}, ErrRateLimited
	}

	var docs []json.RawMessage
	source, wdErr := "wikidata", s.wikidata(ctx, q, lang, &docs)
	quota := false
	if len(docs) == 0 && len([]rune(q)) >= 3 && s.opt.PoiskkinoKey != "" {
		pdocs, err := s.poiskkino(ctx, q)
		if err == nil {
			docs, source = pdocs, "poiskkino"
		}
		quota = errors.Is(err, ErrQuota)
	}
	if len(docs) == 0 && wdErr != nil {
		if quota {
			return Result{}, fmt.Errorf("%w: %v", ErrQuota, wdErr)
		}
		return Result{}, fmt.Errorf("%w: %v", ErrUnavailable, wdErr)
	}
	if len(docs) == 0 {
		source = "none"
	}
	raw, err := json.Marshal(nonNil(docs))
	if err != nil {
		return Result{}, fmt.Errorf("movies: ответ: %w", err)
	}
	res := Result{Docs: raw, Source: source}
	ttl := queryTTL
	if len(docs) == 0 {
		ttl = emptyTTL
	}
	s.queries.put(key, res, ttl, s.now())
	return res, nil
}

func nonNil(d []json.RawMessage) []json.RawMessage {
	if d == nil {
		return []json.RawMessage{}
	}
	return d
}

// wikidata — два поиска (точный и со звёздочкой), записи фильмов, страны.
func (s *Service) wikidata(ctx context.Context, q, lang string, out *[]json.RawMessage) error {
	select {
	case s.gate <- struct{}{}:
		defer func() { <-s.gate }()
	case <-ctx.Done():
		return ctx.Err()
	}
	ctx, cancel := context.WithTimeout(ctx, searchTimeout)
	defer cancel()

	jobs := []map[string]string{dm.SearchParams(q, false, 8)}
	if dm.Wildcard(q) {
		jobs = append(jobs, dm.SearchParams(q, true, 8))
	}
	answers := make([][]byte, len(jobs))
	errs := make([]error, len(jobs))
	var wg sync.WaitGroup
	for i, p := range jobs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			answers[i], errs[i] = s.wdGet(ctx, p)
		}()
	}
	wg.Wait()
	failed := 0
	var ids []string
	for i, a := range answers {
		if errs[i] != nil {
			failed++
			continue
		}
		for _, id := range dm.SearchIDs(a) {
			if !contains(ids, id) {
				ids = append(ids, id)
			}
		}
	}
	if failed == len(jobs) {
		return errs[0]
	}
	if len(ids) > resultLimit {
		ids = ids[:resultLimit]
	}
	if len(ids) == 0 {
		return nil
	}

	films, err := s.entitiesOf(ctx, ids, "labels|claims")
	if err != nil {
		return err
	}
	var list []dm.Compact
	var countryIDs []string
	for _, id := range ids {
		c, ok := films[id]
		if !ok || c.Kind == "" || c.Adult {
			continue
		}
		list = append(list, c)
		if c.Country != "" && !contains(countryIDs, c.Country) {
			countryIDs = append(countryIDs, c.Country)
		}
	}
	countries := map[string]map[string]string{}
	if len(countryIDs) > 0 {
		// Без названий стран карточки всё равно годятся.
		if cs, err := s.entitiesOf(ctx, countryIDs, "labels"); err == nil {
			for id, c := range cs {
				countries[id] = c.Labels
			}
		}
	}
	for _, c := range list {
		d := dm.DocFromCompact(c, lang, countries)
		if d.Name == "" {
			continue
		}
		raw, err := json.Marshal(d)
		if err != nil {
			return fmt.Errorf("movies: карточка: %w", err)
		}
		*out = append(*out, raw)
	}
	return nil
}

// entitiesOf — ужатые записи: из кэша, недостающие — одним запросом.
func (s *Service) entitiesOf(ctx context.Context, ids []string, props string) (map[string]dm.Compact, error) {
	now := s.now()
	have := map[string]dm.Compact{}
	var need []string
	for _, id := range ids {
		if c, ok := s.entities.get(props+":"+id, now); ok {
			have[id] = c
		} else {
			need = append(need, id)
		}
	}
	if len(need) == 0 {
		return have, nil
	}
	raw, err := s.wdGet(ctx, map[string]string{
		"action": "wbgetentities", "format": "json", "ids": strings.Join(need, "|"),
		"props": props, "languages": dm.FetchLanguages(),
	})
	if err != nil {
		return nil, err
	}
	var payload struct {
		Entities map[string]dm.Entity `json:"entities"`
	}
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil, fmt.Errorf("movies: викиданные: %w", err)
	}
	for qid, e := range payload.Entities {
		if e.ID == "" {
			e.ID = qid
		}
		var c dm.Compact
		if props == "labels" {
			c = dm.Compact{QID: qid, Labels: e.LabelMap()}
		} else {
			var ok bool
			if c, ok = dm.CompactEntity(e); !ok {
				continue
			}
		}
		have[qid] = c
		s.entities.put(props+":"+qid, c, entityTTL, now)
	}
	return have, nil
}

func (s *Service) wdGet(ctx context.Context, params map[string]string) ([]byte, error) {
	v := url.Values{}
	for k, x := range params {
		v.Set(k, x)
	}
	resp, err := s.fetch.Get(ctx, s.opt.WikidataAPI+"?"+v.Encode(), map[string]string{"User-Agent": s.opt.UserAgent})
	if err != nil {
		return nil, fmt.Errorf("викиданные: %w", err)
	}
	if resp.Status != 200 {
		return nil, fmt.Errorf("викиданные: HTTP %d", resp.Status)
	}
	var e struct {
		Error json.RawMessage `json:"error"`
	}
	if json.Unmarshal(resp.Body, &e) == nil && len(e.Error) > 0 {
		return nil, fmt.Errorf("викиданные: %s", e.Error)
	}
	return resp.Body, nil
}

// poiskkinoKeep — поля, которые читает клиент; актёры и трейлеры не нужны.
var poiskkinoKeep = []string{"id", "name", "alternativeName", "enName", "year", "releaseYears",
	"poster", "genres", "countries", "rating", "description", "shortDescription", "type"}

func (s *Service) poiskkino(ctx context.Context, q string) ([]json.RawMessage, error) {
	v := url.Values{"page": {"1"}, "limit": {"25"}, "query": {q}}
	resp, err := s.fetch.Get(ctx, s.opt.PoiskkinoAPI+"?"+v.Encode(),
		map[string]string{"X-API-KEY": s.opt.PoiskkinoKey, "Accept": "application/json"})
	if err != nil {
		return nil, fmt.Errorf("poiskkino: %w", err)
	}
	switch resp.Status {
	case 200:
	case 403: // у poiskkino это суточный лимит, а не ключ
		return nil, ErrQuota
	default:
		return nil, fmt.Errorf("poiskkino: HTTP %d", resp.Status)
	}
	return TrimPoiskkino(resp.Body, 25), nil
}

// TrimPoiskkino — ответ poiskkino без тяжёлого; у рейтинга — только kp.
func TrimPoiskkino(body []byte, limit int) []json.RawMessage {
	var p struct {
		Docs []map[string]json.RawMessage `json:"docs"`
	}
	if json.Unmarshal(body, &p) != nil {
		return nil
	}
	if len(p.Docs) > limit {
		p.Docs = p.Docs[:limit]
	}
	var out []json.RawMessage
	for _, d := range p.Docs {
		t := map[string]json.RawMessage{}
		for _, k := range poiskkinoKeep {
			if x, ok := d[k]; ok {
				t[k] = x
			}
		}
		var r map[string]json.RawMessage
		if json.Unmarshal(d["rating"], &r) == nil && r != nil {
			kp := r["kp"]
			if kp == nil {
				kp = json.RawMessage("null")
			}
			t["rating"], _ = json.Marshal(map[string]json.RawMessage{"kp": kp})
		}
		raw, err := json.Marshal(t)
		if err == nil {
			out = append(out, raw)
		}
	}
	return out
}

func contains(xs []string, x string) bool {
	for _, y := range xs {
		if y == x {
			return true
		}
	}
	return false
}
