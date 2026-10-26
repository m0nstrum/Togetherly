package handler_test

import (
	"encoding/json"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/filesystem"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/widgetanim"
)

// Видео и гифка режутся в атлас 6×3 по 300 px; чужой паре файл не отдаётся.
func TestWidgetAnim(t *testing.T) {
	ffmpeg, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("нет ffmpeg")
	}
	app := testutil.NewApp(t)
	svc := widgetanim.New(app)
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.WidgetAnim(e.Router, svc)
		return e.Next()
	})
	testutil.Group(t, app, "animpairaaaaaaa", "animalice000001")
	_, alice := testutil.User(t, app, "animalice000001", "animpairaaaaaaa")
	_, eve := testutil.User(t, app, "animeve00000001")

	dir := t.TempDir()
	make := func(name string, args ...string) string {
		p := filepath.Join(dir, name)
		out, err := exec.Command(ffmpeg, append(append([]string{"-y", "-loglevel", "error"}, args...), p)...).CombinedOutput()
		require.NoError(t, err, string(out))
		return p
	}
	video := make("clip.mp4", "-f", "lavfi", "-i", "testsrc=duration=0.6:size=320x240:rate=25", "-pix_fmt", "yuv420p")
	anim := make("loop.gif", "-f", "lavfi", "-i", "testsrc=duration=2:size=200x200:rate=5")

	col, err := app.FindCollectionByNameOrId("media")
	require.NoError(t, err)
	upload := func(path string) string {
		f, err := filesystem.NewFileFromPath(path)
		require.NoError(t, err)
		r := core.NewRecord(col)
		r.Set("uid", "animalice000001")
		r.Set("group_id", "animpairaaaaaaa")
		r.Set("kind", "widget_anim")
		r.Set("file", f)
		require.NoError(t, app.Save(r))
		return r.Id
	}
	for _, tc := range []struct {
		path, source string
		step         int
	}{{video, "video", 83}, {anim, "animation", 111}} {
		id := upload(tc.path)
		code, body := testutil.Do(t, app, http.MethodPost, "/api/widget/anim/prepare", alice, `{"mediaId":"`+id+`"}`)
		require.Equal(t, http.StatusOK, code, body)
		var res struct {
			Manifest widgetanim.Manifest
		}
		require.NoError(t, json.Unmarshal([]byte(body), &res))
		assert.Equal(t, widgetanim.Manifest{Cols: 6, Rows: 3, Cell: 300, Frames: 18, StepMS: tc.step, Source: tc.source}, res.Manifest)

		code, sheet := testutil.Do(t, app, http.MethodGet, "/api/widget/anim/sheet?id="+id, alice, "")
		require.Equal(t, http.StatusOK, code)
		require.Greater(t, len(sheet), 12)
		assert.Equal(t, "WEBP", sheet[8:12])
		probe, err := exec.Command(filepath.Join(filepath.Dir(ffmpeg), "ffprobe"), "-v", "error", "-show_entries", "stream=width,height",
			"-of", "csv=p=0", svc.SheetPath(id)).Output()
		if err == nil {
			assert.Equal(t, "1800,900", string(probe[:len(probe)-1]))
		}

		code, _ = testutil.Do(t, app, http.MethodGet, "/api/widget/anim/sheet?id="+id, eve, "")
		assert.Equal(t, http.StatusForbidden, code)
	}
	code, _ := testutil.Do(t, app, http.MethodPost, "/api/widget/anim/prepare", alice, `{"mediaId":"nope"}`)
	assert.Equal(t, http.StatusNotFound, code)

	// Битый файл ffmpeg не берёт — метка, и добор его больше не гоняет.
	junk := filepath.Join(dir, "junk.mp4")
	require.NoError(t, os.WriteFile(junk, []byte("not a video"), 0o644))
	id := upload(junk)
	for range 2 {
		code, _ = testutil.Do(t, app, http.MethodPost, "/api/widget/anim/prepare", alice, `{"mediaId":"`+id+`"}`)
		assert.Equal(t, http.StatusUnprocessableEntity, code)
	}
	assert.FileExists(t, filepath.Join(filepath.Dir(svc.SheetPath(id)), id+".bad"))
}
