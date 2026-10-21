# Развёртывание Tethered

Один хост с Docker. Поднимает сервер (PocketBase + JS-хуки апстрима + Go),
Centrifugo (живые обновления и push через WebSocket), Caddy (HTTPS), coturn
(голос в «Смотрим вместе») и по желанию Bugsink (крашрепорты).

## Что нужно

- VPS: 1 vCPU, 1 ГБ памяти (на 512 МБ работает со swap), x86-64 или ARM64,
  10 ГБ диска плюс место под фото и видео пары. Linux с Docker и плагином
  compose. Образ сервера собирает GitHub (`fork-server-image.yml`), VPS его
  только скачивает.
- Домен с A-записью (и AAAA, если есть IPv6) на адрес VPS — с него Caddy
  получает сертификат Let's Encrypt. Подойдёт и поддомен бесплатного DNS.
- Открытые порты (ниже).

## Запуск

```sh
git clone <репозиторий> tethered && cd tethered/deploy
./init-env.sh tethered.example.org   # домен и случайные секреты в .env
$EDITOR .env        # почта (SMTP_*), ключ бэкапов, по желанию WATCH_PROXY
docker compose up -d
docker compose exec server /app/tethered superuser upsert admin@example.org 'длинный-пароль'
```

Образ в GHCR после первой публикации приватный. Либо один раз сделайте его
публичным (GitHub → Packages → `tethered-server` → Package settings → Change
visibility), либо войдите на VPS: `docker login ghcr.io` с токеном, у которого
есть право `read:packages`. Свой форк — свой образ: `TETHERED_IMAGE` в `.env`.

## Порты

| Порт | Кто | Зачем |
|---|---|---|
| 443/tcp+udp | Caddy | всё HTTP: API, файлы, сайт, WebSocket Centrifugo, сертификат (TLS-ALPN-01); udp — HTTP/3 |
| 3478/tcp+udp | coturn | голос в «Смотрим вместе» |
| 8443/tcp | сервер | только с прокси роликов (`WATCH_PROXY_LISTEN=0.0.0.0`) |

Порт 80 не нужен: Let's Encrypt проверяет домен на 443. Голос идёт напрямую
между телефонами, а где не выходит — через TURN. Оба телефона получают relay
на этом сервере, и ICE находит пару relay↔relay: два relay на одной машине
говорят друг с другом локально, поэтому диапазон ретранслятора 49160–49200
наружу не открывается. Если у VPS нет публичного адреса на интерфейсе (1:1
NAT облака) — допишите coturn `--external-ip` и откройте диапазон.

Прокси роликов и TURN на 443 не сажаются: это не HTTP, а Caddy без
плагина layer4 не умеет делить порт по SNI.

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
| caddy | — | 443 |
| coturn | сеть хоста | 3478 |
| bugsink | `:8000` | профиль `crash`; маршрут в Caddy добавить вручную |

Данные — в томе `server-data` (`/data`): база SQLite и файлы.

## Метрики

Сервер отдаёт `/metrics` (Prometheus) на `server:9100` внутри сети compose;
через Caddy этот адрес не публикуется. Там только сервер: запросы по
шаблонам маршрутов и классам ответа, время ответа, размер базы, бэкапы
(`tethered_backup_last_success_timestamp_seconds` — для алерта «бэкапа не было
сутки»), публикации в Centrifugo, Go-рантайм. Ни uid, ни IP, ни id записей.

## Прокси роликов (по желанию)

YouTube в РФ режется по SNI, поэтому Smart DNS не помогает. Приложение умеет
пускать плеер комнаты «Смотрим вместе» через ваш сервер: `WATCH_PROXY=true`
и `WATCH_PROXY_LISTEN=0.0.0.0` в `.env`, порт `8443` открыт наружу. Это TLS-прокси (CONNECT) на сертификате
Caddy: пускает только по входу в приложение и только к площадкам из списка
(YouTube, Vimeo и их CDN), TLS до площадки сквозной — сервер видит домены, а
не ролики. Лимит — `WATCH_PROXY_DAILY_MB` на человека в сутки. В метриках —
число соединений по исходу и байты, без доменов и людей.

Учтите: трафик роликов идёт через ваш VPS, а в РФ это может подпадать под
запрет средств обхода блокировок (149-ФЗ, ст. 15.8). По умолчанию выключено.
Проверьте на деле, отдаёт ли YouTube ролики IP вашего дата-центра.

## Бэкапы

PocketBase снимает бэкап по `BACKUP_CRON`. С ключом `BACKUP_AGE_RECIPIENTS`
каждый сразу шифруется (age) в том `server-backups` (`/backups`), открытая
копия удаляется, хранятся последние `BACKUP_MAX_KEEP`. Без ключа бэкапы
лежат открытыми в `server-data` (`backups/`), сервер пишет об этом в журнал.

Ключ — пара: публичная половина в `.env`, секретная — **не на сервере**
(менеджер паролей, бумага, вторая машина):

```sh
age-keygen -o tethered-backup-key.txt   # строка «public key: age1…» → BACKUP_AGE_RECIPIENTS
```

Уносить с машины — содержимое тома, например
`rclone sync /var/lib/docker/volumes/deploy_server-backups/_data remote:tethered`.

Восстановление (проверено на деле: бэкап по cron → новый том → вход тем же
паролем):

```sh
docker compose stop server
docker volume rm deploy_server-data          # или сохраните его под другим именем
docker compose run --rm -v ./tethered-backup-key.txt:/key.txt:ro server \
  restore --identity /key.txt /backups/<имя>.zip.age
docker compose up -d server
```

`restore` пишет только в пустой каталог данных — поверх живой базы откажет.

Вход, сброс пароля и регистрация ограничены по IP клиента (10 попыток входа в
минуту, 10 регистраций в час). Адрес клиента сервер берёт из
`X-Forwarded-For`, который ставит Caddy (`TETHERED_TRUSTED_PROXY_HEADER`), —
поэтому порт сервера наружу не открывать: заголовок можно подделать.

## Проверка

```sh
SMOKE_BASE=https://tethered.example.org server/scripts/smoke.sh
```

Регистрирует двух тестовых пользователей, собирает из них пару по коду
приглашения и проверяет чат, токен Centrifugo и `/api/watch/rtc`. Две
регистрации за прогон укладываются в лимит; паритет (`server/scripts/parity.sh`)
гоняется только против своего бинарника.

## Обновление

```sh
git pull                 # если менялись compose, Caddyfile или конфиг Centrifugo
docker compose pull && docker compose up -d
```

Своя сборка образа на машине (нужно ~2 ГБ памяти):
`docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build`.

Миграции применяются при старте сервера.
