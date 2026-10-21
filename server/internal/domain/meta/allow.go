// Package meta — какие внешние адреса сервер готов запросить за клиента
// (meta gateway, PLAN S5). Провайдер видит IP сервера, а не человека.
//
// Белый список по хосту и пути: без него эндпоинт стал бы открытым прокси.
package meta

import (
	"net/url"
	"strings"
)

// Kind — что за ответ: от этого зависят лимит размера и срок кэша.
type Kind int

const (
	// KindJSON — метаданные (oEmbed, поиск).
	KindJSON Kind = iota + 1
	// KindImage — превью и обложки.
	KindImage
)

type rule struct {
	host   string
	prefix string // путь начинается с
	kind   Kind
}

var rules = []rule{
	// oEmbed видео и музыки
	{"www.youtube.com", "/oembed", KindJSON},
	{"vimeo.com", "/api/oembed.json", KindJSON},
	{"www.dailymotion.com", "/services/oembed", KindJSON},
	{"www.tiktok.com", "/oembed", KindJSON},
	{"noembed.com", "/embed", KindJSON},
	{"rutube.ru", "/api/video/", KindJSON},
	// Музыка
	{"api.deezer.com", "/track/", KindJSON},
	{"itunes.apple.com", "/lookup", KindJSON},
	{"itunes.apple.com", "/search", KindJSON},
	{"api.music.yandex.net", "/tracks/", KindJSON},
	// Книги и фильмы
	{"openlibrary.org", "/search.json", KindJSON},
	{"api.poiskkino.dev", "/v1.4/movie/search", KindJSON},
	// Поиск мест на карте
	{"nominatim.openstreetmap.org", "/search", KindJSON},
	{"nominatim.openstreetmap.org", "/reverse", KindJSON},
	// Картинки
	{"i.ytimg.com", "/vi/", KindImage},
	{"covers.openlibrary.org", "/b/", KindImage},
}

// Allowed — можно ли запросить raw и что ждать в ответ. Только https, без
// учётных данных и нестандартных портов.
func Allowed(raw string) (Kind, bool) {
	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "https" || u.User != nil || u.Port() != "" {
		return 0, false
	}
	host := strings.ToLower(u.Hostname())
	// Rutube отдаёт превью по /api/video/<id>/thumbnail/ — это картинка.
	if host == "rutube.ru" && strings.HasPrefix(u.Path, "/api/video/") && strings.Contains(u.Path, "/thumbnail") {
		return KindImage, true
	}
	for _, r := range rules {
		if host == r.host && strings.HasPrefix(u.EscapedPath(), r.prefix) && !strings.Contains(u.Path, "..") {
			return r.kind, true
		}
	}
	return 0, false
}
