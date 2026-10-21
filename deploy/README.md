# Развёртывание Tethered

Один хост с Docker. Поднимает сервер (PocketBase + JS-хуки апстрима + Go),
Centrifugo (живые обновления и push через WebSocket), Caddy (HTTPS), coturn
(голос в «Смотрим вместе») и по желанию Bugsink (крашрепорты).

## Запуск

```sh
cd deploy
cp .env.example .env
$EDITOR .env        # домен, секреты: openssl rand -hex 32
docker compose up -d
docker compose exec server /app/tethered superuser upsert admin@example.org 'длинный-пароль'
```

Нужно открыть порты: 80/443 TCP и 443 UDP (Caddy), 3478 TCP/UDP и
49160–49200 UDP (coturn).

Клиент собирается под этот домен:

```json
{ "PB_URL": "https://tethered.example.org" }
```

(`env/<name>.local.json`, см. [docs/fork/README.md](../docs/fork/README.md)).
`CENTRIFUGO_WS` по умолчанию — `wss://<домен>/connection/websocket`, как и
маршрутизирует Caddy.

## Что где

| Сервис | Внутри | Наружу |
|---|---|---|
| server | `:8090`, внутренний API хуков `127.0.0.1:8120` | через Caddy |
| centrifugo | `:8000` (WebSocket и HTTP API `/api`) | только `/connection/websocket` через Caddy |
| caddy | — | 80, 443 |
| coturn | сеть хоста | 3478, 49160–49200/udp |
| bugsink | `:8000` | профиль `crash`; маршрут в Caddy добавить вручную |

Данные — в томе `server-data` (`/data`): база SQLite и файлы. Бэкапы
PocketBase пишет туда же, в `backups/` (`BACKUP_CRON`, `BACKUP_MAX_KEEP`).
Шифрование бэкапов и вынос на другую машину — S10.

## Проверка

```sh
SMOKE_BASE=https://tethered.example.org server/scripts/smoke.sh
```

Регистрирует двух тестовых пользователей, собирает из них пару по коду
приглашения и проверяет чат, токен Centrifugo и `/api/watch/rtc`.

## Обновление

```sh
git pull
docker compose build server && docker compose up -d
```

Миграции применяются при старте сервера.
