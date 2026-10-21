// Сервер Tethered: PocketBase с хуками и роутами форка (docs/fork/PLAN.md, S4).
//
// Без аргументов — `serve` на TETHERED_HTTP_ADDR. `tethered restore` —
// восстановление из зашифрованного бэкапа. Остальное — команды PocketBase как
// есть: `tethered superuser upsert ...`, `tethered migrate`.
package main

import (
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"os"

	"github.com/m0nstrum/togetherly/server/internal/config"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/backup"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/pocketbase"
)

func main() {
	cfg, err := config.Load()
	log := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: parseLevel(cfg.LogLevel)}))
	if err != nil {
		log.Error("конфигурация", "err", err)
		os.Exit(2)
	}
	if len(os.Args) > 1 && os.Args[1] == "restore" {
		// До PocketBase: его команды при старте создают базу в каталоге
		// данных, а восстанавливаем только в пустой.
		if err := restore(os.Args[2:], cfg.DataDir); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	app := pocketbase.New(cfg, log)
	if len(os.Args) == 1 {
		app.RootCmd.SetArgs([]string{"serve", "--http", cfg.HTTPAddr})
	}
	if err := app.Start(); err != nil {
		log.Error("сервер остановился", "err", err)
		os.Exit(1)
	}
}

// restore — `tethered restore --identity key.txt [--data DIR] FILE.age`.
// Сервер в это время стоит, каталог данных пуст.
func restore(args []string, dataDir string) error {
	fs := flag.NewFlagSet("restore", flag.ContinueOnError)
	identity := fs.String("identity", "", "файл с секретным ключом age (AGE-SECRET-KEY-…)")
	fs.StringVar(&dataDir, "data", dataDir, "пустой каталог данных")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *identity == "" || fs.NArg() != 1 {
		return errors.New("использование: tethered restore --identity key.txt [--data DIR] FILE.age")
	}
	if err := backup.Restore(fs.Arg(0), *identity, dataDir); err != nil {
		return err
	}
	fmt.Println("восстановлено в", dataDir)
	return nil
}

func parseLevel(s string) slog.Level {
	var l slog.Level
	if err := l.UnmarshalText([]byte(s)); err != nil {
		return slog.LevelInfo
	}
	return l
}
