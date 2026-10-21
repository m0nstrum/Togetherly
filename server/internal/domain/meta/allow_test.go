package meta_test

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/m0nstrum/togetherly/server/internal/domain/meta"
)

func TestAllowed(t *testing.T) {
	for raw, want := range map[string]meta.Kind{
		"https://www.youtube.com/oembed?url=x&format=json":      meta.KindJSON,
		"https://api.deezer.com/track/123":                      meta.KindJSON,
		"https://openlibrary.org/search.json?q=a":               meta.KindJSON,
		"https://nominatim.openstreetmap.org/search?q=Москва":   meta.KindJSON,
		"https://i.ytimg.com/vi/abc/hqdefault.jpg":              meta.KindImage,
		"https://rutube.ru/api/video/abc/thumbnail/?redirect=1": meta.KindImage,
		"https://rutube.ru/api/video/abc/?format=json":          meta.KindJSON,
	} {
		k, ok := meta.Allowed(raw)
		assert.True(t, ok, raw)
		assert.Equal(t, want, k, raw)
	}
	for _, raw := range []string{
		"http://www.youtube.com/oembed",           // не https
		"https://evil.example.org/oembed",         // чужой хост
		"https://www.youtube.com/watch?v=1",       // чужой путь
		"https://www.youtube.com:8443/oembed",     // порт
		"https://user:pw@api.deezer.com/track/1",  // учётные данные
		"https://api.deezer.com/track/../user/me", // выход из префикса
		"https://www.youtube.com.evil.org/oembed", // похожий хост
		"file:///etc/passwd",
		"",
	} {
		_, ok := meta.Allowed(raw)
		assert.False(t, ok, raw)
	}
}
