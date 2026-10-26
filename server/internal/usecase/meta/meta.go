// Package meta — meta gateway (PLAN S5): сервер запрашивает метаданные и
// превью у сторонних сервисов вместо телефона, провайдер видит IP сервера.
package meta

import (
	"context"
	"errors"
	"fmt"
	"mime"
	"net/url"
	"strings"
	"time"

	"github.com/m0nstrum/togetherly/server/internal/domain/linkpreview"
	dmeta "github.com/m0nstrum/togetherly/server/internal/domain/meta"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/safefetch"
)

// Fetcher — безопасный загрузчик (infrastructure/safefetch).
type Fetcher interface {
	Get(ctx context.Context, url string, headers map[string]string) (safefetch.Response, error)
	GetManual(ctx context.Context, url string, headers map[string]string) (safefetch.Response, error)
}

// Response — ответ провайдера, который отдаётся клиенту как есть.
type Response struct {
	Status      int
	ContentType string
	Body        []byte
	// FinalURL — адрес после переходов (заголовок X-Final-URL).
	FinalURL string
	// Location — куда ведёт редирект (только у FetchManual).
	Location string
}

var (
	// ErrNotAllowed — адреса нет в белом списке.
	ErrNotAllowed = errors.New("meta: адрес не разрешён")
	// ErrUpstream — провайдер не ответил или ответил не тем.
	ErrUpstream = errors.New("meta: провайдер не ответил")
)

// Service — gateway с кэшем.
type Service struct {
	fetch Fetcher
	cache *cache
	now   func() time.Time
}

// New — gateway поверх fetch. Кэш до cacheBytes байт.
func New(fetch Fetcher, cacheBytes int, now func() time.Time) *Service {
	return &Service{fetch: fetch, cache: newCache(cacheBytes), now: now}
}

const (
	maxJSON  = 512 << 10
	maxImage = 2 << 20
	// kindAny — адрес не из белого списка: вид решает тип ответа.
	kindAny dmeta.Kind = -1
)

// Fetch запрашивает адрес raw. Адреса из белого списка (dmeta.Allowed) —
// кому угодно; любые другие публичные — только если authed (так клиент
// открывает страницы и картинки по ссылкам, которыми делятся люди), и только
// текст, JSON или картинки.
func (s *Service) Fetch(ctx context.Context, raw string, authed bool) (Response, error) {
	return s.fetch1(ctx, raw, authed, false)
}

// FetchManual — как Fetch, но без перехода по редиректу: 3xx отдаётся с
// Location. Так клиент раскрывает короткие ссылки (link.deezer.com) сам,
// по шагу через gateway, как раньше напрямую.
func (s *Service) FetchManual(ctx context.Context, raw string, authed bool) (Response, error) {
	return s.fetch1(ctx, raw, authed, true)
}

func (s *Service) fetch1(ctx context.Context, raw string, authed, manual bool) (Response, error) {
	kind, ok := dmeta.Allowed(raw)
	if !ok {
		if !authed {
			return Response{}, ErrNotAllowed
		}
		u, err := url.Parse(raw)
		if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" {
			return Response{}, ErrNotAllowed
		}
		kind = kindAny
	}
	key := "f:" + raw
	get := s.fetch.Get
	if manual {
		key, get = "m:"+raw, s.fetch.GetManual
	}
	if r, ok := s.cache.get(key, s.now()); ok {
		return r, nil
	}
	// Nominatim требует узнаваемый User-Agent (политика OSM).
	resp, err := get(ctx, raw, map[string]string{"User-Agent": "Tethered/1.0 (self-hosted)"})
	if err != nil {
		return Response{}, fmt.Errorf("%w: %v", ErrUpstream, err)
	}
	if manual && resp.Status >= 300 && resp.Status < 400 && resp.Location != "" {
		// Тела у редиректа нет смысла отдавать: клиенту нужен только адрес.
		out := Response{Status: resp.Status, ContentType: "text/plain", Location: resp.Location}
		s.cache.put(key, out, time.Hour, s.now())
		return out, nil
	}
	ct, _, _ := mime.ParseMediaType(resp.ContentType)
	switch kind {
	case dmeta.KindTile:
		if len(resp.Body) > 8<<20 || (ct != "application/x-protobuf" && ct != "application/vnd.mapbox-vector-tile" && ct != "application/octet-stream") {
			return Response{}, fmt.Errorf("%w: invalid vector tile", ErrUpstream)
		}
	case dmeta.KindImage:
		if !strings.HasPrefix(ct, "image/") || len(resp.Body) >= maxImage {
			return Response{}, fmt.Errorf("%w: не картинка или слишком большая", ErrUpstream)
		}
	case dmeta.KindJSON:
		if len(resp.Body) >= maxJSON {
			return Response{}, fmt.Errorf("%w: ответ слишком большой", ErrUpstream)
		}
	case kindAny:
		image := strings.HasPrefix(ct, "image/")
		text := strings.HasPrefix(ct, "text/") || strings.Contains(ct, "json") || strings.Contains(ct, "xml")
		if !image && !text {
			return Response{}, fmt.Errorf("%w: тип %q не отдаём", ErrUpstream, ct)
		}
		if (image && len(resp.Body) >= maxImage) || (text && len(resp.Body) >= maxJSON) {
			return Response{}, fmt.Errorf("%w: ответ слишком большой", ErrUpstream)
		}
		kind = dmeta.KindJSON
		if image {
			kind = dmeta.KindImage
		}
	}
	out := Response{Status: resp.Status, ContentType: resp.ContentType, Body: resp.Body, FinalURL: resp.FinalURL}
	if resp.Status == 200 {
		ttl := 6 * time.Hour
		if kind == dmeta.KindImage {
			ttl = 24 * time.Hour
		}
		s.cache.put(key, out, ttl, s.now())
	}
	return out, nil
}

// LinkPreview — карточка товара по ссылке (бывший link_preview.pb.js +
// link_fetcher). ok=false — магазин закрылся от нас, форма даст заполнить
// руками.
func (s *Service) LinkPreview(ctx context.Context, raw string) (linkpreview.Preview, bool, error) {
	u, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" {
		return linkpreview.Preview{}, false, ErrNotAllowed
	}
	key := "p:" + u.String()
	if r, ok := s.cache.get(key, s.now()); ok {
		p := linkpreview.Parse(string(r.Body), r.FinalURL)
		p.URL = r.FinalURL
		return p, true, nil
	}
	resp, err := s.fetch.Get(ctx, u.String(), nil)
	if err != nil || resp.Status != 200 {
		return linkpreview.Preview{}, false, nil
	}
	// В кэше — HTML и итоговый адрес (он нужен для относительных картинок).
	s.cache.put(key, Response{Status: 200, FinalURL: resp.FinalURL, Body: resp.Body}, time.Hour, s.now())
	p := linkpreview.Parse(string(resp.Body), resp.FinalURL)
	p.URL = resp.FinalURL
	return p, true, nil
}
