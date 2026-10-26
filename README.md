# Tethered

Приложение для пар: общий чат, воспоминания, настроения, карта, рисунки,
совместный просмотр и виджеты рабочего стола. Всё личное шифруется на
телефонах (E2E): сервер хранит шифр и не может прочитать переписку, фото,
геопозицию или настроения. Сервер свой — поднимается на одном VPS.

*An app for couples with end-to-end encryption and a self-hosted server.
English summary below.*

## Что внутри

- 💬 **Чат** — сообщения, голосовые, кружки, реакции; шифруется на телефоне.
- 📸 **Воспоминания** — фото, видео, места, музыка, фильмы; капсула времени.
- 😊 **Настроения**, «скучаю», прикосновение, заряд телефона партнёра.
- 🗺️ **Карта «Где мы»** — геопозиция в реальном времени, шифром.
- 🎬 **Смотрим вместе** — комната с синхронным плеером и голосом, общая лента роликов, «Что посмотрим».
- 🎨 **Рисунки** вдвоём, маскот пары, темы, виджеты Android и iOS.
- 🔐 **Безопасность** — сверка ключей эмодзи или QR, бэкап ключей фразой, замок приложения.

## Как устроено

| Часть | Где | Что |
|---|---|---|
| Приложение | `lib/`, `android/`, `ios/` | Flutter; E2E — `lib/fork/e2e/` |
| Сервер | `server/` | Go + PocketBase как библиотека |
| Живые обновления | `deploy/centrifugo/` | Centrifugo, дельты подписаны сервером |
| Развёртывание | `deploy/` | Docker Compose: сервер, Centrifugo, Caddy, coturn |

## Документы

- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — сборка, конфигурация, CI;
- [deploy/README.md](deploy/README.md) — свой сервер;
- [docs/E2E.md](docs/E2E.md) — модель угроз и шифрование;
- [docs/ROADMAP.md](docs/ROADMAP.md), [docs/BACKLOG.md](docs/BACKLOG.md) — планы;
- [docs/TESTING.md](docs/TESTING.md) — проверка на телефонах.

## Сборка

```sh
cp env/example.json env/prod.local.json   # вписать PB_URL своего сервера
flutter pub get
flutter build apk --release --dart-define-from-file=env/prod.local.json
```

Подробно — [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Происхождение и лицензия

Tethered начинался как форк [Togetherly](https://github.com/THET1ME-1/togetherly)
(© THET1ME-1) и с октября 2026 развивается самостоятельно. Приложение
распространяется под [GPL-3.0](LICENSE), как и исходный проект: исходники
открыты, производные обязаны оставаться под той же лицензией.

---

## English

**Tethered** is a private space for couples: chat, memories, moods, live map,
drawing, watch-together and home-screen widgets. Personal data is end-to-end
encrypted on the phones; the self-hosted server only stores ciphertext.

Build: see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Server: see
[deploy/README.md](deploy/README.md).

Tethered started as a fork of [Togetherly](https://github.com/THET1ME-1/togetherly)
and is now developed independently. The app is licensed under
[GPL-3.0](LICENSE).
