// Package widgetanim — живое фото для парного виджета (бывшие
// widget_anim.pb.js и tools/widget_anim.py апстрима): из видео или гифки
// сервер делает одну картинку-раскадровку, телефоны только скачивают её.
//
// `ImageView` в виджете не проигрывает ни видео, ни анимацию — кадры
// покадрово толкает приложение. Разбирать видео на телефоне партнёра дорого
// (100–200 мс на кадр), поэтому кадры готовит сервер: 18 кадров сеткой 6×3 в
// одном webp, около 300 КБ, и манифест рядом. Файлы `widget_anim` — открытые
// (docs/E2E.md, исключение), иначе серверу нечего было бы резать.
//
// Режет ffmpeg: без него в PATH Prepare отвечает ErrUnavailable.
package widgetanim

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
)

const (
	cols, rows = 6, 3 // 18 кадров: столько влезает в 300 КБ и хватает глазу
	cell       = 300  // сторона кадра: плитка виджета крупнее не бывает
	frames     = cols * rows
	videoSpan  = 1500 // мс: первые полторы секунды видео
	// Шаг анимации: ниже 90 мс лончер не успевает перерисовать виджет, выше
	// 200 движение распадается на отдельные картинки.
	minStep, maxStep = 90, 200
	quality          = 74
)

var (
	// ErrUnavailable — на сервере нет ffmpeg.
	ErrUnavailable = errors.New("widgetanim: ffmpeg не найден")
	// ErrUnsupported — файл не видео и не гифка, или не разобрался.
	ErrUnsupported = errors.New("widgetanim: файл не подходит")
)

var (
	videoExt = []string{".mp4", ".mov", ".m4v", ".webm", ".3gp"}
	animExt  = []string{".gif", ".webp"}
)

// Manifest — как раскадровка разложена; читает WidgetAnimManifest клиента.
type Manifest struct {
	Cols   int    `json:"cols"`
	Rows   int    `json:"rows"`
	Cell   int    `json:"cell"`
	Frames int    `json:"frames"`
	StepMS int    `json:"step_ms"`
	Source string `json:"source"`
}

// Service готовит и хранит раскадровки в <pb_data>/widget_anim.
type Service struct {
	app    core.App
	dir    string
	ffmpeg string
	// Одна нарезка за раз: ffmpeg съедает ядро, а виджеты подождут.
	slot chan struct{}
}

// New — сервис над app. ffmpeg ищется в PATH.
func New(app core.App) *Service {
	bin, _ := exec.LookPath("ffmpeg")
	return &Service{app: app, dir: filepath.Join(app.DataDir(), "widget_anim"), ffmpeg: bin, slot: make(chan struct{}, 1)}
}

// SheetPath — где лежит раскадровка записи media id.
func (s *Service) SheetPath(id string) string { return filepath.Join(s.dir, id+".webp") }

func (s *Service) manifestPath(id string) string { return filepath.Join(s.dir, id+".json") }

// badPath — метка файла, который ffmpeg не разобрал: добор раз в десять
// минут не гоняет его снова, а клиент сразу получает «не подходит».
func (s *Service) badPath(id string) string { return filepath.Join(s.dir, id+".bad") }

// Ready — манифест готовой раскадровки, если она есть.
func (s *Service) Ready(id string) (*Manifest, bool) {
	raw, err := os.ReadFile(s.manifestPath(id))
	if err != nil {
		return nil, false
	}
	var m Manifest
	if json.Unmarshal(raw, &m) != nil {
		return nil, false
	}
	if st, err := os.Stat(s.SheetPath(id)); err != nil || st.Size() == 0 {
		return nil, false
	}
	return &m, true
}

// Prepare делает раскадровку записи media (идемпотентно: готовую отдаёт
// сразу — клиент зовёт повторно после обрыва сети).
func (s *Service) Prepare(ctx context.Context, rec *core.Record) (*Manifest, error) {
	if m, ok := s.Ready(rec.Id); ok {
		return m, nil
	}
	if s.ffmpeg == "" {
		return nil, ErrUnavailable
	}
	if _, err := os.Stat(s.badPath(rec.Id)); err == nil {
		return nil, ErrUnsupported
	}
	name := rec.GetString("file")
	ext := strings.ToLower(filepath.Ext(name))
	isVideo, isAnim := contains(videoExt, ext), contains(animExt, ext)
	if name == "" || (!isVideo && !isAnim) {
		return nil, ErrUnsupported
	}
	select {
	case s.slot <- struct{}{}:
		defer func() { <-s.slot }()
	case <-ctx.Done():
		return nil, ctx.Err()
	}
	if m, ok := s.Ready(rec.Id); ok {
		return m, nil
	}

	work, err := os.MkdirTemp("", "wanim_")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(work)
	src := filepath.Join(work, "src"+ext)
	if err := s.download(rec, name, src); err != nil {
		return nil, err
	}

	span, step := videoSpan, videoSpan/frames
	source := "video"
	if isAnim {
		source = "animation"
		// Шаг — из самой анимации: у гифки своя скорость, и показ по 83 мс
		// гнал бы её втрое быстрее. Длинную режем по первым трём секундам.
		span, step = videoSpan, 100
		if total := gifDuration(src); total > 0 {
			span = min(total, 3000)
			step = max(minStep, min(maxStep, (span+frames/2)/frames))
		}
	}
	if err := os.MkdirAll(s.dir, 0o755); err != nil {
		return nil, err
	}
	part := s.SheetPath(rec.Id) + ".part"
	// Кадров бывает меньше, чем клеток (короткое видео): tpad добирает
	// последним, чтобы в атласе не осталось чёрных дыр.
	filter := fmt.Sprintf("tpad=stop_mode=clone:stop_duration=%.3f,fps=%.4f,"+
		"scale=%d:%d:force_original_aspect_ratio=increase,crop=%d:%d,tile=%dx%d",
		float64(frames*step)/1000, 1000/float64(step), cell, cell, cell, cell, cols, rows)
	cctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	cmd := exec.CommandContext(cctx, s.ffmpeg, "-y", "-loglevel", "error",
		"-t", fmt.Sprintf("%.3f", float64(span)/1000), "-i", src,
		"-vf", filter, "-frames:v", "1", "-an",
		"-c:v", "libwebp", "-quality", fmt.Sprint(quality), "-f", "webp", part)
	if out, err := cmd.CombinedOutput(); err != nil {
		_ = os.Remove(part)
		s.app.Logger().Warn("widget_anim: ffmpeg", "media", rec.Id, "err", err, "out", strings.TrimSpace(string(out)))
		// Оборванная нарезка (таймаут, отмена) — не приговор файлу.
		if cctx.Err() == nil {
			_ = os.WriteFile(s.badPath(rec.Id), nil, 0o644)
		}
		return nil, ErrUnsupported
	}
	if err := os.Rename(part, s.SheetPath(rec.Id)); err != nil {
		return nil, err
	}
	m := Manifest{Cols: cols, Rows: rows, Cell: cell, Frames: frames, StepMS: step, Source: source}
	raw, _ := json.Marshal(m)
	if err := os.WriteFile(s.manifestPath(rec.Id), raw, 0o644); err != nil {
		return nil, err
	}
	return &m, nil
}

// download копирует файл записи из хранилища PocketBase (диск или S3).
func (s *Service) download(rec *core.Record, name, dst string) error {
	fsys, err := s.app.NewFilesystem()
	if err != nil {
		return err
	}
	defer fsys.Close()
	r, err := fsys.GetReader(rec.BaseFilesPath() + "/" + name)
	if err != nil {
		return ErrUnsupported
	}
	defer r.Close()
	f, err := os.Create(dst)
	if err != nil {
		return err
	}
	if _, err := io.Copy(f, r); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}

// Sweep — добор: свежие записи `widget_anim` без раскадровки (клиент мог не
// дозваться до Prepare).
func (s *Service) Sweep(ctx context.Context) {
	if s.ffmpeg == "" {
		return
	}
	recs, err := s.app.FindRecordsByFilter("media", "kind = 'widget_anim'", "-created", 200, 0, dbx.Params{})
	if err != nil {
		return
	}
	for _, r := range recs {
		if ctx.Err() != nil {
			return
		}
		if _, ok := s.Ready(r.Id); ok {
			continue
		}
		if _, err := s.Prepare(ctx, r); err != nil && !errors.Is(err, ErrUnsupported) {
			s.app.Logger().Warn("widget_anim: добор", "media", r.Id, "err", err)
		}
	}
}

// gifDuration — длительность гифки в мс (0 — не гифка или не разобралась).
// Кадр без задержки считается за 100 мс, как в браузерах.
//
// Файл присылает человек, поэтому кадры не распаковываем: gif.DecodeAll
// держит в памяти каждый, и гифка в пару мегабайт разворачивается в
// гигабайты. Задержки лежат в заголовках кадров — проходим блоки, пропуская
// данные картинок.
func gifDuration(path string) int {
	f, err := os.Open(path)
	if err != nil {
		return 0
	}
	defer f.Close()
	r := bufio.NewReader(f)
	head := make([]byte, 13)
	if _, err := io.ReadFull(r, head); err != nil || string(head[:3]) != "GIF" {
		return 0
	}
	skipTable := func(flags byte) bool {
		if flags&0x80 == 0 {
			return true
		}
		_, err := r.Discard(3 << ((flags & 7) + 1))
		return err == nil
	}
	skipBlocks := func() bool {
		for {
			n, err := r.ReadByte()
			if err != nil {
				return false
			}
			if n == 0 {
				return true
			}
			if _, err := r.Discard(int(n)); err != nil {
				return false
			}
		}
	}
	if !skipTable(head[10]) {
		return 0
	}
	total, delay := 0, 0
	for {
		kind, err := r.ReadByte()
		if err != nil {
			return 0
		}
		switch kind {
		case 0x3B: // конец файла
			return total
		case 0x21: // расширение; 0xF9 — управление кадром с задержкой
			label, err := r.ReadByte()
			if err != nil {
				return 0
			}
			if label == 0xF9 {
				gce := make([]byte, 5)
				if _, err := io.ReadFull(r, gce); err != nil || gce[0] < 4 {
					return 0
				}
				delay = int(gce[2]) | int(gce[3])<<8
				if _, err := r.Discard(int(gce[0]) - 4); err != nil {
					return 0
				}
			}
			if !skipBlocks() {
				return 0
			}
		case 0x2C: // кадр
			desc := make([]byte, 9)
			if _, err := io.ReadFull(r, desc); err != nil || !skipTable(desc[8]) {
				return 0
			}
			if _, err := r.ReadByte(); err != nil { // размер кода LZW
				return 0
			}
			if !skipBlocks() {
				return 0
			}
			if delay <= 0 {
				delay = 10
			}
			total += delay * 10
			delay = 0
		default:
			return 0
		}
	}
}

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}
