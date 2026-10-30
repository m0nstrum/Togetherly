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
$EDITOR .env        # TETHERED_VERSION, почта (SMTP_*), ключ бэкапов, по желанию WATCH_PROXY
docker compose up -d
docker compose exec server /app/tethered superuser upsert admin@example.org 'длинный-пароль'
```

Образ в GHCR после первой публикации приватный. Либо один раз сделайте его
публичным (GitHub → Packages → `tethered-server` → Package settings → Change
visibility), либо войдите на VPS: `docker login ghcr.io` с токеном, у которого
есть право `read:packages`. Свой форк — свой образ: `TETHERED_IMAGE_NAME` в `.env`.

`TETHERED_VERSION` — тег образа `sha-<коммит>`: какой взять — ниже, в
«Обновлении».

## Администрирование PocketBase

Caddy отвечает 404 на `/_/` и API суперпользователя (по имени коллекции
и её id). Команда `superuser upsert` выше работает внутри контейнера.

Для панели временно включите только локальный порт на VPS:

```sh
docker compose -f docker-compose.yml -f docker-compose.admin.yml up -d server
```

На своём компьютере откройте SSH-туннель:

```sh
ssh -N -L 18090:127.0.0.1:8090 user@your-vps
```

Панель: `http://127.0.0.1:18090/_/`. После работы остановите туннель и
верните сервер без локального порта:

```sh
docker compose up -d --force-recreate server
```

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

(`env/<name>.local.json`, см. [docs/DEVELOPMENT.md](../docs/DEVELOPMENT.md)).
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

## История Centrifugo

Каналы `pair:` и `user:` держат историю (`deploy/centrifugo/config.json`):
последние 100 публикаций канала, не дольше 5 минут, `force_recovery`. Телефон,
переподключившись после короткого обрыва, получает пропущенное из истории, и
перечитывать списки с сервера ему не нужно. Обрыв длиннее, переполненная
история или перезапуск Centrifugo — `recovered=false`, и клиент дотягивает
пропущенное запросами, как без истории.

5 минут — не случайно: клиент не принимает подписанные дельты старше 10 минут
(`lib/fork/realtime/verified_delta.dart`). Длиннее 10 минут историю делать
нельзя: Centrifugo ответит «восстановлено», а старые публикации клиент
выбросит молча.

Память — у Centrifugo, в процессе (движок памяти, без Redis). Публикация —
подписанный конверт с шифрованной записью: обычно 1–3 КБ, вложения в неё не
попадают. Худший случай на канал — 100 × 3 КБ ≈ 300 КБ, и только у пары,
которая за последние 5 минут прислала 100 событий (печать в чате, касания).
Каналы без событий за 5 минут истории не держат: остаётся метаинформация
потока (эпоха и номер, десятки байт) на `history_meta_ttl` — по умолчанию
30 дней. Оценка: 1000 пар, активных одновременно, — до ~300 МБ в пике (на деле
меньше: так часто пишут немногие), обычная нагрузка — единицы МБ. Смотреть —
`docker stats` контейнера `centrifugo`. Если тесно — уменьшить `history_size`:
переполнение лишь чаще возвращает к перечитыванию запросами.

## Метрики

Сервер отдаёт `/metrics` (Prometheus) на `server:9100` внутри сети compose;
через Caddy этот адрес не публикуется. Там только сервер: запросы по
шаблонам маршрутов и классам ответа, время ответа, размер базы, бэкапы
(`tethered_backup_last_success_timestamp_seconds` — для алерта «бэкапа не было
сутки»), публикации в Centrifugo, Go-рантайм. Ни uid, ни IP, ни id записей.

## Пуши (по желанию)

Без настройки уведомления доставляет фоновый сервис приложения с сокетом
Centrifugo — Android с энергосбережением его убивает, и уведомления
опаздывают. Надёжнее — FCM своего Firebase-проекта как будильник: сервер
шлёт в Google только `{type: "sync", event: <случайный id>}`, телефон
просыпается, забирает событие у вашего сервера, расшифровывает и рисует
уведомление сам. Ни текста, ни имён, ни id пары Google не видит; событие
лежит на сервере в памяти 10 минут.

1. [console.firebase.google.com](https://console.firebase.google.com) →
   новый проект (Google Analytics — выключить).
2. Добавить Android-приложение `io.github.m0nstrum.tethered` (SHA-1 не
   нужен) и скачать `google-services.json` — его содержимое в секрет
   `GOOGLE_SERVICES_JSON` репозитория (docs/DEVELOPMENT.md), пересобрать APK.
3. Project settings → Service accounts → Generate new private key: файл
   положить в `deploy/secrets/fcm-service-account.json`, в `.env` —
   `FCM_CREDENTIALS_FILE=/secrets/fcm-service-account.json`,
   `docker compose up -d`.

Нужны оба шага: телефон гасит фоновый сокет, только когда сервер ответил,
что умеет слать FCM. Телефоны без сервисов Google остаются на сокете.

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

## Приглашения по ссылке

Ссылка `https://<домен>/invite/<код>` открывает страницу с кодом и сразу
пробует приложение (`tethered://invite/<код>`). Куда вести тех, у кого
приложения нет, задают `INVITE_PLAY_URL`, `INVITE_RUSTORE_URL`,
`INVITE_APK_URL` в `.env` — пустые кнопки не показываются. Чтобы ссылка
открывала приложение без страницы (App Links), укажите отпечатки подписи APK
в `INVITE_ANDROID_FINGERPRINTS` (через запятую, `keytool -list -v -keystore …`);
для iOS — `INVITE_IOS_APP_ID` вида `TeamID.BundleID`. Без них файлы
`/.well-known/assetlinks.json` и `apple-app-site-association` не раздаются.

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

Сервер закреплён на версии: `TETHERED_VERSION=sha-<коммит>` в `.env`.
Образ с таким тегом публикует `fork-server-image.yml` только после зелёного
Fork CI на `main` (с проверенной серверной частью) — есть тег, значит коммит
прошёл тесты. `latest` тоже есть, но в `.env` его не ставьте: он едет на VPS
при любом `pull` без вашего решения.

Какую версию взять: страница пакета `tethered-server` в GitHub (Packages) —
свежий тег `sha-…` рядом с `latest`; или последний зелёный запуск
**Actions → Fork server image**, шаг «теги». Проверить, что тег есть:

```sh
docker manifest inspect ghcr.io/m0nstrum/tethered-server:sha-1a2b3c4 >/dev/null && echo есть
```

Обновиться:

```sh
git pull                 # если менялись compose, Caddyfile или конфиг Centrifugo
grep TETHERED_VERSION .env   # запишите текущую — это точка отката
sed -i 's/^TETHERED_VERSION=.*/TETHERED_VERSION=sha-1a2b3c4/' .env
docker compose pull server && docker compose up -d
docker compose logs --tail=50 server   # миграции и старт без ошибок
```

Откатиться — вернуть прежний тег и пересоздать сервер:

```sh
sed -i 's/^TETHERED_VERSION=.*/TETHERED_VERSION=sha-<прежний>/' .env
docker compose up -d server
```

Миграции применяются при старте сервера и обратно не откатываются. Если
между версиями менялась схема (`server/internal/migrations`), старый сервер
может не понять новую базу — перед обновлением такой версии убедитесь, что
свежий бэкап есть («Бэкапы»: `docker compose exec server ls -l /backups`),
и откатывайтесь вместе с восстановлением из него.

Переход со старого `.env` (`TETHERED_IMAGE=…:latest`): строку
`TETHERED_IMAGE` удалите (свой форк — `TETHERED_IMAGE_NAME` без тега) и
добавьте `TETHERED_VERSION`. Без неё `docker compose` откажется стартовать
и подскажет, что вписать.

Своя сборка образа на машине (нужно ~2 ГБ памяти):
`docker compose -f docker-compose.yml -f docker-compose.build.yml up -d --build`.

### Деплой скриптом

То же самое с проверкой и откатом делает `deploy.sh`:

```sh
git pull                 # если менялись compose, Caddyfile или конфиг Centrifugo
./deploy.sh sha-1a2b3c4
```

Скрипт принимает только `sha-…` (`latest` и прочие теги — отказ),
запоминает текущий `TETHERED_VERSION`, вписывает новый в `.env`, делает
`docker compose pull server` и `docker compose up -d`, затем до 120 с ждёт
здоровья: `https://<домен>/api/health` через свой Caddy (curl резолвит домен
в `127.0.0.1`, DNS не нужен) и `/health` Centrifugo изнутри сети compose.

- Здоров — код 0, в выводе прежняя версия: это точка отката.
- Образ не скачался (нет тега, нет доступа к GHCR) — `.env` возвращается как
  был, контейнеры не трогаются, код 1.
- Не дождался — прежний `sha-…` обратно в `.env`, `docker compose up -d`,
  снова проверка: откат здоров — код 1, нет — код 2, разбираться руками
  (`docker compose logs --tail=100 server centrifugo`).

Откатиться вручную на конкретную версию — тот же скрипт с прежним тегом:
`./deploy.sh sha-<прежний>`. Миграции он назад не откатывает — про схему и
бэкап см. выше. Ожидание и адрес проверки меняются переменными
`DEPLOY_TIMEOUT`, `DEPLOY_INTERVAL`, `DEPLOY_HEALTH_URL`, `DEPLOY_RESOLVE`
(описаны в начале `deploy.sh`). Тест скрипта на заглушках —
`bash deploy/deploy.test.sh`, гоняется в CI.

### Обновление realtime (H3)

Сервер подписывает публикации pair/loc/user ключом Ed25519, производным
от CENTRIFUGO_API_KEY с отдельным доменом. Клиент получает только публичный
ключ через авторизованный HTTPS `/api/fork/realtime-key`, кэширует минуту
и проверяет точные байты пакета, канал, срок (10 минут, допуск часов +30 с),
nonce. Для срока используется время из HTTPS-ответа ключа и монотонный
таймер, поэтому ручная смена часов телефона не ломает доставку.
Повторные/неподписанные дельты не применяются. Wake-ответы идут через
авторизованный HTTPS inbox и остаются доверенным отдельным путём доставки.

Клиентские pair/loc сигналы физически идут в signal/locsignal. Логические
каналы в E2E AAD сохранены, шифрование не меняется. draw/watch — отдельные
эфемерные протоколы, они не применяются как дельты записей.

При переходе с прежней сборки обновите сервер, приложение и этот конфиг
Centrifugo согласованно: старые клиенты не разбирают подписанный конверт.
**Смените CENTRIFUGO_TOKEN_HMAC и пересоздайте PocketBase/Centrifugo**,
чтобы закрыть старые соединения и погасить уже выданные суточные JWT.
Это также пересоздаёт коды комнат просмотра; новые ссылки выдаёт приложение.
Не меняйте только конфиг без рестарта брокера. Новый API ключ менять для
этого не требуется; его ротация меняет публичный ключ подписи.

Новые авторизованные connection/subscription JWT живут 120 секунд.
При refresh сервер снова проверяет действующее членство. После расставания
новые подписки/обновления запрещены; ранее выданная новая подписка может
читать до истечения своего JWT (окно до двух минут, плюс grace брокера).
Старый токен не даёт публиковать в серверные namespace. Браузерные гостевые
watch-билеты ограничены только своим watch-каналом и не дают права на дельты.

Проверки: `server/scripts/realtime-security.test.py` через SMOKE_AFTER;
`server/scripts/realtime-broker-check.sh` поднимает и удаляет отдельный брокер
с этим конфигом и запускает `realtime-broker.test.cjs`; для готового брокера
BROKER_URL/BROKER_TEST_SECRET/BROKER_TEST_API_KEY — тестовые параметры.

Регрессы апстрима в parity.sh адаптируются только во временной копии: H3-конверт
проверяется Ed25519 перед передачей исходным проверкам payload. Нужны Python
пакеты websockets и cryptography; файлы тестов апстрима остаются неизменными.
