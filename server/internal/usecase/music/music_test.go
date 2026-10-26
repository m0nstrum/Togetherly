package music_test

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/infrastructure/safefetch"
	"github.com/m0nstrum/togetherly/server/internal/usecase/music"
)

type fake struct {
	res  safefetch.Response
	urls []string
}

func (f *fake) Get(_ context.Context, url string, _ map[string]string) (safefetch.Response, error) {
	f.urls = append(f.urls, url)
	return f.res, nil
}

func TestTrack(t *testing.T) {
	f := &fake{res: safefetch.Response{Status: 200, Body: []byte(
		`{"result":[{"id":123,"title":"Песня","artists":[{"name":"Группа","extra":1}],"coverUri":"x/%%"}]}`)}}
	tr, err := music.New(f).Track(context.Background(), "123")
	require.NoError(t, err)
	assert.Equal(t, music.Track{ID: "123", Title: "Песня", Artists: []music.Artist{{Name: "Группа"}}, CoverURI: "x/%%"}, tr)
	assert.Equal(t, []string{"https://api.music.yandex.net/tracks/123"}, f.urls)

	_, err = music.New(f).Track(context.Background(), "../etc")
	assert.ErrorIs(t, err, music.ErrBadTrack)
	assert.Len(t, f.urls, 1, "чужой адрес наружу не уходит")

	f.res = safefetch.Response{Status: 451}
	_, err = music.New(f).Track(context.Background(), "1")
	var up music.UpstreamError
	assert.True(t, errors.As(err, &up))
	assert.Equal(t, 451, up.Status)

	f.res = safefetch.Response{Status: 200, Body: []byte(`{"result":[]}`)}
	_, err = music.New(f).Track(context.Background(), "1")
	assert.ErrorIs(t, err, music.ErrNotFound)
}
