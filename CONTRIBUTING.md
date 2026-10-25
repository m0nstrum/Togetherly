# Участие в разработке

Спасибо за интерес к Tethered. Приложение открыто под [GPL-3.0](LICENSE).

## Сборка и сервер

- Сборка, конфигурация, тесты и CI — [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
- Свой сервер для разработки — [deploy/README.md](deploy/README.md) или
  `server/scripts/smoke.sh` (поднимает одноразовый сервер локально).

## Правила

- Изменения — через pull request в `main`; `Fork CI` должен быть зелёным.
- Перед PR: `tool/fork/analyze_check.sh`, `python3 tool/fork/repo_check.py`,
  тесты (`docs/DEVELOPMENT.md`, «Локальная сборка»); на сервере — `go test ./...`.
- Новый серверный код — на Go в `server/` (domain / usecase / handler /
  infrastructure), с тестами; JS-хуки не добавляем.
- Всё, что относится к содержимому пары, шифруется на клиенте
  ([docs/E2E.md](docs/E2E.md)). Новое поле с личными данными без шифрования —
  повод для отказа в PR.
- Секреты, ключи подписи, `google-services.json`, `*.local.json` не коммитим.
- Уязвимости — не в issues, а приватно ([SECURITY.md](SECURITY.md)).

*Contributions welcome via pull requests to `main` with a green CI. Build
instructions: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).*
