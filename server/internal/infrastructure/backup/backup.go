// Package backup — шифрованные бэкапы (PLAN S10).
//
// PocketBase сам снимает zip с pb_data (по cron из настроек или вручную).
// Сразу после этого zip шифруется ключом оператора (age, X25519) в отдельный
// каталог — его и уносят с машины (rclone, restic, что угодно), — а открытая
// копия удаляется. Секретный ключ на сервере не живёт: расшифровать бэкап
// может только тот, у кого он есть, — при восстановлении (Restore).
package backup

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"filippo.io/age"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/archive"
)

// Ext — расширение зашифрованного бэкапа.
const Ext = ".age"

// Options — куда и чем шифровать.
type Options struct {
	// Dir — каталог зашифрованных бэкапов (вне pb_data).
	Dir string
	// Recipients — публичные ключи age (`age1…`) через пробел или запятую.
	Recipients string
	// MaxKeep — сколько последних бэкапов хранить; 0 — все.
	MaxKeep int
}

// ParseRecipients разбирает список публичных ключей.
func ParseRecipients(s string) ([]age.Recipient, error) {
	var out []age.Recipient
	for _, f := range strings.FieldsFunc(s, func(r rune) bool { return r == ',' || r == ' ' || r == '\n' }) {
		r, err := age.ParseX25519Recipient(f)
		if err != nil {
			return nil, fmt.Errorf("backup: ключ %q: %w", f, err)
		}
		out = append(out, r)
	}
	if len(out) == 0 {
		return nil, errors.New("backup: нет ключей получателя")
	}
	return out, nil
}

// Bind шифрует каждый бэкап PocketBase после создания.
func Bind(app core.App, opt Options, log *slog.Logger) error {
	rcpt, err := ParseRecipients(opt.Recipients)
	if err != nil {
		return err
	}
	if opt.Dir == "" {
		return errors.New("backup: не задан каталог зашифрованных бэкапов")
	}
	app.OnBackupCreate().BindFunc(func(e *core.BackupEvent) error {
		if err := e.Next(); err != nil {
			return err
		}
		if err := seal(e.Context, e.App, e.Name, opt, rcpt); err != nil {
			// Открытый zip остаётся: лучше бэкап без шифра, чем никакого.
			log.Error("бэкап не зашифрован", "name", e.Name, "err", err)
			return err
		}
		log.Info("бэкап зашифрован", "name", e.Name+Ext, "dir", opt.Dir)
		return nil
	})
	return nil
}

func seal(ctx context.Context, app core.App, name string, opt Options, rcpt []age.Recipient) error {
	fsys, err := app.NewBackupsFilesystem()
	if err != nil {
		return fmt.Errorf("backup: хранилище: %w", err)
	}
	defer fsys.Close()
	fsys.SetContext(ctx)

	src, err := fsys.GetReader(name)
	if err != nil {
		return fmt.Errorf("backup: чтение %s: %w", name, err)
	}
	defer src.Close()

	if err := os.MkdirAll(opt.Dir, 0o700); err != nil {
		return fmt.Errorf("backup: каталог: %w", err)
	}
	final := filepath.Join(opt.Dir, name+Ext)
	tmp, err := os.CreateTemp(opt.Dir, ".tmp-*")
	if err != nil {
		return fmt.Errorf("backup: файл: %w", err)
	}
	defer os.Remove(tmp.Name())
	if err := Encrypt(tmp, src, rcpt...); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return fmt.Errorf("backup: запись: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("backup: запись: %w", err)
	}
	if err := os.Rename(tmp.Name(), final); err != nil {
		return fmt.Errorf("backup: переименование: %w", err)
	}
	if err := fsys.Delete(name); err != nil {
		return fmt.Errorf("backup: открытая копия не удалена: %w", err)
	}
	return rotate(opt.Dir, opt.MaxKeep)
}

// Encrypt шифрует src в dst для получателей rcpt.
func Encrypt(dst io.Writer, src io.Reader, rcpt ...age.Recipient) error {
	w, err := age.Encrypt(dst, rcpt...)
	if err != nil {
		return fmt.Errorf("backup: шифр: %w", err)
	}
	if _, err := io.Copy(w, src); err != nil {
		return fmt.Errorf("backup: шифр: %w", err)
	}
	if err := w.Close(); err != nil {
		return fmt.Errorf("backup: шифр: %w", err)
	}
	return nil
}

// rotate оставляет keep самых новых бэкапов (имена PocketBase начинаются с
// даты, поэтому порядок имён — порядок времени).
func rotate(dir string, keep int) error {
	if keep <= 0 {
		return nil
	}
	ents, err := os.ReadDir(dir)
	if err != nil {
		return fmt.Errorf("backup: ротация: %w", err)
	}
	var names []string
	for _, e := range ents {
		if !e.IsDir() && strings.HasSuffix(e.Name(), Ext) {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	var errs []error
	for len(names) > keep {
		if err := os.Remove(filepath.Join(dir, names[0])); err != nil {
			errs = append(errs, err)
		}
		names = names[1:]
	}
	return errors.Join(errs...)
}

// Restore расшифровывает бэкап in ключами из identityFile и разворачивает
// его в dataDir. Сервер в это время должен стоять, dataDir — не существовать
// или быть пустым: поверх живой базы не восстанавливаем.
func Restore(in, identityFile, dataDir string) error {
	if ents, err := os.ReadDir(dataDir); err == nil && len(ents) > 0 {
		return fmt.Errorf("backup: %s не пуст — восстанавливаем только в пустой каталог", dataDir)
	}
	keys, err := os.Open(identityFile)
	if err != nil {
		return fmt.Errorf("backup: ключ: %w", err)
	}
	ids, err := age.ParseIdentities(keys)
	keys.Close()
	if err != nil {
		return fmt.Errorf("backup: ключ: %w", err)
	}
	src, err := os.Open(in)
	if err != nil {
		return fmt.Errorf("backup: бэкап: %w", err)
	}
	defer src.Close()
	plain, err := age.Decrypt(src, ids...)
	if err != nil {
		return fmt.Errorf("backup: расшифровка: %w", err)
	}

	tmp, err := os.CreateTemp("", "tethered-restore-*.zip")
	if err != nil {
		return fmt.Errorf("backup: временный файл: %w", err)
	}
	defer os.Remove(tmp.Name())
	if _, err := io.Copy(tmp, plain); err != nil {
		tmp.Close()
		return fmt.Errorf("backup: расшифровка: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("backup: временный файл: %w", err)
	}
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		return fmt.Errorf("backup: каталог данных: %w", err)
	}
	if err := archive.Extract(tmp.Name(), dataDir); err != nil {
		return fmt.Errorf("backup: распаковка: %w", err)
	}
	return nil
}
