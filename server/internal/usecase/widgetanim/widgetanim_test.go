package widgetanim

import (
	"bytes"
	"image"
	"image/color/palette"
	"image/gif"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Длительность — из заголовков кадров, без распаковки: та же сумма, что
// дал бы gif.DecodeAll, нулевая задержка — 100 мс.
func TestGifDuration(t *testing.T) {
	g := &gif.GIF{}
	for _, d := range []int{5, 0, 12, 7} {
		g.Image = append(g.Image, image.NewPaletted(image.Rect(0, 0, 4, 4), palette.Plan9))
		g.Delay = append(g.Delay, d)
	}
	var buf bytes.Buffer
	require.NoError(t, gif.EncodeAll(&buf, g))
	dir := t.TempDir()
	write := func(name string, b []byte) string {
		p := filepath.Join(dir, name)
		require.NoError(t, os.WriteFile(p, b, 0o644))
		return p
	}

	assert.Equal(t, (5+10+12+7)*10, gifDuration(write("a.gif", buf.Bytes())))
	assert.Zero(t, gifDuration(write("cut.gif", buf.Bytes()[:buf.Len()-8])), "обрезанный файл")
	assert.Zero(t, gifDuration(write("x.webp", []byte("RIFF\x00\x00\x00\x00WEBP"))), "не гифка")
}
