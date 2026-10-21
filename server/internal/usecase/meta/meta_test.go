package meta_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/infrastructure/safefetch"
	"github.com/m0nstrum/togetherly/server/internal/usecase/meta"
)

type fakeFetch struct {
	calls int
	resp  safefetch.Response
	err   error
}

func (f *fakeFetch) Get(context.Context, string, map[string]string) (safefetch.Response, error) {
	f.calls++
	return f.resp, f.err
}

func TestFetch(t *testing.T) {
	ctx := context.Background()
	now := time.Unix(0, 0)
	f := &fakeFetch{resp: safefetch.Response{Status: 200, ContentType: "application/json", Body: []byte(`{"title":"x"}`)}}
	svc := meta.New(f, 1<<20, func() time.Time { return now })

	_, err := svc.Fetch(ctx, "https://evil.example.org/x", false)
	assert.ErrorIs(t, err, meta.ErrNotAllowed)
	assert.Zero(t, f.calls)

	r, err := svc.Fetch(ctx, "https://www.youtube.com/oembed?url=a", false)
	require.NoError(t, err)
	assert.JSONEq(t, `{"title":"x"}`, string(r.Body))
	_, _ = svc.Fetch(ctx, "https://www.youtube.com/oembed?url=a", false)
	assert.Equal(t, 1, f.calls, "второй раз — из кэша")

	now = now.Add(7 * time.Hour)
	_, _ = svc.Fetch(ctx, "https://www.youtube.com/oembed?url=a", false)
	assert.Equal(t, 2, f.calls, "кэш истёк")

	f.resp = safefetch.Response{Status: 200, ContentType: "text/html", Body: []byte("<html>")}
	_, err = svc.Fetch(ctx, "https://i.ytimg.com/vi/a/hqdefault.jpg", false)
	assert.ErrorIs(t, err, meta.ErrUpstream, "вместо картинки HTML")

	f.err = errors.New("сеть")
	_, err = svc.Fetch(ctx, "https://api.deezer.com/track/1", false)
	assert.ErrorIs(t, err, meta.ErrUpstream)
}

func TestFetchAnyAuthed(t *testing.T) {
	ctx := context.Background()
	f := &fakeFetch{resp: safefetch.Response{Status: 200, ContentType: "text/html; charset=utf-8", FinalURL: "https://open.spotify.com/track/1", Body: []byte("<title>x</title>")}}
	svc := meta.New(f, 1<<20, time.Now)

	_, err := svc.Fetch(ctx, "https://open.spotify.com/track/1", false)
	assert.ErrorIs(t, err, meta.ErrNotAllowed, "без входа — только белый список")

	r, err := svc.Fetch(ctx, "https://open.spotify.com/track/1", true)
	require.NoError(t, err)
	assert.Equal(t, "https://open.spotify.com/track/1", r.FinalURL)

	f.resp = safefetch.Response{Status: 200, ContentType: "application/octet-stream", Body: []byte{1}}
	_, err = svc.Fetch(ctx, "https://files.example.org/a.apk", true)
	assert.ErrorIs(t, err, meta.ErrUpstream, "бинарники не отдаём")

	_, err = svc.Fetch(ctx, "ftp://files.example.org/a", true)
	assert.ErrorIs(t, err, meta.ErrNotAllowed)
}

func TestLinkPreview(t *testing.T) {
	f := &fakeFetch{resp: safefetch.Response{Status: 200, FinalURL: "https://shop.example.org/p", Body: []byte(`<meta property="og:title" content="Кружка"><meta property="og:image" content="/a.jpg">`)}}
	svc := meta.New(f, 1<<20, time.Now)

	p, ok, err := svc.LinkPreview(context.Background(), "https://shop.example.org/p")
	require.NoError(t, err)
	require.True(t, ok)
	assert.Equal(t, "Кружка", p.Title)
	assert.Equal(t, "https://shop.example.org/a.jpg", p.Image)

	_, _, _ = svc.LinkPreview(context.Background(), "https://shop.example.org/p")
	assert.Equal(t, 1, f.calls, "кэш")

	_, _, err = svc.LinkPreview(context.Background(), "javascript:alert(1)")
	assert.ErrorIs(t, err, meta.ErrNotAllowed)

	f.err = errors.New("антибот")
	_, ok, err = svc.LinkPreview(context.Background(), "https://other.example.org/")
	require.NoError(t, err)
	assert.False(t, ok)
}
