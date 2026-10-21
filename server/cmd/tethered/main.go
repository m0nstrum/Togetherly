// Сервер Tethered: PocketBase с хуками и роутами форка (docs/fork/PLAN.md, S4).
//
// Без аргументов — `serve` на TETHERED_HTTP_ADDR. С аргументами — команды
// PocketBase как есть: `tethered superuser upsert ...`, `tethered migrate`.
package main

import (
	"log/slog"
	"os"

	"github.com/m0nstrum/togetherly/server/internal/config"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/pocketbase"
)

func main() {
	cfg, err := config.Load()
	log := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: parseLevel(cfg.LogLevel)}))
	if err != nil {
		log.Error("конфигурация", "err", err)
		os.Exit(2)
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

func parseLevel(s string) slog.Level {
	var l slog.Level
	if err := l.UnmarshalText([]byte(s)); err != nil {
		return slog.LevelInfo
	}
	return l
}
