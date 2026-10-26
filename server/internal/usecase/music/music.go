// Package music — метаданные трека Яндекс.Музыки (бывший music.pb.js).
//
// Страницу трека Яндекс рисует скриптом: ни og-тегов, ни ld+json, поэтому
// данные берутся из их API `api.music.yandex.net/tracks/<id>` — без ключа.
// За пределами России API отвечает 451, и клиент повторяет запрос сюда.
// Снаружи приходит только номер трека (цифры), хост фиксированный — SSRF тут
// неоткуда взяться.
package music

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"

	"github.com/m0nstrum/togetherly/server/internal/infrastructure/safefetch"
)

// Fetcher — исходящий GET.
type Fetcher interface {
	Get(ctx context.Context, url string, headers map[string]string) (safefetch.Response, error)
}

var (
	// ErrBadTrack — номер трека не цифры.
	ErrBadTrack = errors.New("bad track id")
	// ErrNotFound — Яндекс трека не знает.
	ErrNotFound = errors.New("track not found")
)

// UpstreamError — Яндекс ответил не 200 или не ответил вовсе.
type UpstreamError struct{ Status int }

func (e UpstreamError) Error() string { return fmt.Sprintf("upstream %d", e.Status) }

var trackRe = regexp.MustCompile(`^[0-9]{1,20}$`)

// Artist и Track — та же форма, что отдаёт сам Яндекс: у клиента один разбор
// на прямой ответ и ответ через нас.
type Artist struct {
	Name string `json:"name"`
}

type Track struct {
	ID       string   `json:"id"`
	Title    string   `json:"title"`
	Artists  []Artist `json:"artists"`
	CoverURI string   `json:"coverUri"`
}

type Service struct{ fetch Fetcher }

func New(fetch Fetcher) *Service { return &Service{fetch: fetch} }

// Track — метаданные трека [id].
func (s *Service) Track(ctx context.Context, id string) (Track, error) {
	if !trackRe.MatchString(id) {
		return Track{}, ErrBadTrack
	}
	res, err := s.fetch.Get(ctx, "https://api.music.yandex.net/tracks/"+id, map[string]string{
		"Accept":     "application/json",
		"User-Agent": "TetheredBot/1.0",
	})
	if err != nil {
		return Track{}, UpstreamError{}
	}
	if res.Status != 200 {
		return Track{}, UpstreamError{Status: res.Status}
	}
	var body struct {
		Result []struct {
			ID       json.RawMessage `json:"id"`
			Title    string          `json:"title"`
			Artists  []Artist        `json:"artists"`
			CoverURI string          `json:"coverUri"`
		} `json:"result"`
	}
	if err := json.Unmarshal(res.Body, &body); err != nil || len(body.Result) == 0 {
		return Track{}, ErrNotFound
	}
	t := body.Result[0]
	out := Track{ID: id, Title: t.Title, Artists: t.Artists, CoverURI: t.CoverURI}
	if raw := string(t.ID); raw != "" && raw != "null" {
		var s string
		if json.Unmarshal(t.ID, &s) == nil {
			out.ID = s
		} else {
			out.ID = raw
		}
	}
	if out.Artists == nil {
		out.Artists = []Artist{}
	}
	return out, nil
}
