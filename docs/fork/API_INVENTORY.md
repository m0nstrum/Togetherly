# Инвентарь API бэкенда (S3)

Снято на коммите апстрима `76ab665` + правки форка S0–S2. Карту роутов
пересобирает `python3 tool/fork/api_inventory.py` (`--missing` — что клиент
зовёт, а сервера нет). Его стоит запускать после каждого мёржа апстрима.

Пометки: **перенос** — логику берём как есть (JS-хук или порт на Go в S4/S5);
**переписать** — нужен другой подход в форке; **выкинуть** — не переносим
(решения 1–5 в [PLAN.md](PLAN.md)).

## 1. Что нашлось нового относительно AUDIT

- **`pocketbase/pb-cgo/main.go`** — прод автора уже работает на PocketBase
  0.39.11, собранном как Go-библиотека (нативный SQLite через CGO, JSVM для
  `pb_hooks`, публикация в Centrifugo и кэш auth-токенов на Go). Это готовый
  каркас для S4: берём его за основу `server/`, а не начинаем с нуля.
- **`pocketbase/link_fetcher/fetcher.py`** в репозитории есть (AUDIT §4
  ошибался). Безопасный загрузчик с ручными редиректами и проверкой IP —
  образец для meta gateway в S5.
- **Android push шёл через FCM** (AUDIT исправлен в S0). FCM-ветка разбирала
  приглашения в совместную ленту (`ReelsInviteBridge.arrived`) и будила
  виджеты. В форке её нет — S5 должен убедиться, что путь Centrifugo
  (`PbPushService`) покрывает оба случая.
- **`/api/account/schedule-delete`** клиент зовёт при удалении аккаунта, а
  реализации в репозитории нет ни в хуках, ни в hotpath. Писать с нуля (S5).
- **Коллекции `custom_moods` и `love_tests`** клиент читает, но в
  `collections_schema.json` их нет: `custom_moods` создан на проде руками,
  `love_tests` живёт только в hotpath (Postgres). Схему восстанавливать по
  Dart-моделям.

## 1a. hotpath внутри хуков (найдено в S4)

Половина отобранных JS-хуков ходит в hotpath по `http://127.0.0.1:8120/internal/*`
(группы у апстрима жили в Postgres): приём приглашения, счётчики, сундук,
подарки, «ожидание». Хуки форк не правит — сервер отвечает на те же пути
поверх PocketBase (`server/internal/handler/compat.go`, слушает только петлю).

| Путь | Статус |
|---|---|
| `POST /internal/pair-accept` | перенесён (S4), ветвление один в один |
| `GET /internal/group-read`, `POST /internal/group-write`, `GET /internal/groups-of` | перенесены (S4) |
| `GET /internal/geo` | пустой ответ: страна нужна только правилам рекламы |
| `POST /internal/{waiting-create,waiting-reset,pair-claim-approve,record,group-sync}`, `GET /internal/{count,couple-agg,online,profiles}` | 501, перенос в S5 |

## 2. Роуты

### Пары, группы, приглашения

| Роут | Где сейчас | Клиент | Решение |
|---|---|---|---|
| `POST /api/invite/accept` | `invite.pb.js` | `pb_data_service` | перенос; здесь же в S8 обмен ключами пары |
| `GET /invite`, `/invite/{code}`, `/.well-known/assetlinks.json` | `invite_web.pb.js` | — (веб) | перенос; `assetlinks.json` под applicationId форка и его ключ подписи |
| `GET /.well-known/apple-app-site-association` | `invite_web.pb.js` | — | выкинуть (iOS) |
| `POST /api/group/{leave,miss-you,patch-map,record-activity,increment}` | `groups.pb.js` + дубль в hotpath | `pb_data_service`, экраны «скучаю» | перенос (одна реализация, без hotpath) |
| `POST/GET /api/waiting/{create,state,update,claim,approve,cancel,reset}` | `waiting.pb.js` | `pb_data_service`, `connections_manager` | перенос |
| `GET /api/user/card` | `user_card.pb.js` + hotpath | `pb_data_service`, `avatar_frames` | перенос |
| `GET /api/couple/stats` | `couple_stats.pb.js` | `couple_stats_service` | перенос |
| `POST /api/draw/invite` | `draw_invite.pb.js` | `pb_data_service` | перенос |
| `POST/GET /api/reels/{invite,active}` | `reels_invite.pb.js` | `reels_invite`, `watch_home_screen` | перенос (решение 4) |

### Аккаунт и вход

| Роут | Где сейчас | Клиент | Решение |
|---|---|---|---|
| `POST /api/auth/password-reset` | `email_case.pb.js` | `pb_auth_service` | перенос + лимит попыток (решение 3) |
| `POST /api/account/email-change/{request,confirm}` | `email_change.pb.js` | `email_change_service` | перенос, письма через свой SMTP |
| `POST /api/account/schedule-delete` | **нет** | `user_data.dart` | **написать** (S5) |
| `POST /api/migrate/verify-password` | `migrate_bridge.pb.js` | `pb_auth_service` | выкинуть: мост Firebase → PB, у форка нет старой базы |
| `POST /api/apple/native`, `POST /api/apple/notifications` | `apple_*.pb.js` | `pb_auth_service` (iOS) | выкинуть (решения 2, 3) |
| `/api/oauth2-redirect` | встроенный PB | `pb_auth_service` | не настраиваем провайдеров (решение 3) |

### Realtime и push

| Роут | Где сейчас | Клиент | Решение |
|---|---|---|---|
| `POST /api/centrifugo/{connection,subscription}-token` | `centrifugo_tokens.pb.js` (+ старый `centrifugo.pb.js`, hotpath) | `centrifugo_service` | перенос, одна реализация на Go; проверка членства в канале |
| `POST /api/apns/test`, `POST /api/fcm/test` | `push_apns.pb.js` | — | выкинуть |

### Чат, медиа, виджеты

| Роут | Где сейчас | Клиент | Решение |
|---|---|---|---|
| `GET /api/note/export` | hotpath | `note_export_service` | переписать на Go (hotpath не переносим) |
| `POST /api/widget/anim/prepare`, `GET /api/widget/anim/sheet` | `widget_anim.pb.js` + `tools/widget_anim.py` | `widget_anim_service` | перенос; до E2E — серверная обработка, после S9 — на клиент |
| `GET /api/filecheck` | `filecheck.pb.js` | — (nginx `auth_request`) | переписать: в compose раздача файлов через PB или Caddy `forward_auth` |
| `GET /api/watch/rtc` | `watch_rtc.pb.js` | `pb_data_service` | перенос; креды своего coturn (решение 4) |
| `POST /api/watch/{room,new,token}` | `watch.pb.js` | `watch_room_service`, `pb_public/watch` | перенос (решение 4) |

### Метаданные внешних сервисов (meta gateway, S5)

| Роут | Где сейчас | Клиент | Решение |
|---|---|---|---|
| `GET /api/link/preview` | `link_preview.pb.js` → `link_fetcher` | `pb_data_service` | перенос в gateway, fetcher — образец |
| `GET /api/music/yandex` | `music.pb.js` | `music_meta_service` | перенос в gateway |
| `GET /api/movies/search` | hotpath (`movies.py`: poiskkino, Wikidata) | `movie_search_service` | переписать в gateway; ключ poiskkino — свой или без него |
| — | — | клиент сам ходит в Deezer, iTunes, Open Library, Vimeo oEmbed, noembed, YouTube-превью | перевести на gateway (§6) |

### Монеты, сундуки, подарки

Решение 1 оставляет монеты и сундуки, если без них ломается UI. Без них
ломается: монеты тратятся на темы, иконки и рамки, фото в виджете, фоны чата
(`purchase-theme/icon/feature`, `spend`), а Плюс эти траты не покрывает.
**Рекомендация (подтвердить):** монеты и сундуки — игровая механика без денег.
Заработок: ежедневный бонус, задания, серия настроений, приглашение партнёра,
сундук. Всё, что связано с деньгами и рекламой, — выкинуть.

| Роут | Где сейчас | Решение |
|---|---|---|
| `POST /api/coins/{daily-bonus,task-reward,mood-streak,memory-reward,partner-invite}` | `coins.pb.js` | перенос (заработок) |
| `POST /api/coins/{purchase-theme,purchase-icon,purchase-feature,spend}` | `coins.pb.js` | перенос (траты) |
| `GET/POST /api/chest/{state,open,keep,sell,give}` | `chest.pb.js` | перенос; открытие без ролика (сейчас «за ролик») |
| `POST /api/gifts/{send,react,decline}`, `GET/POST /api/frames/{gift-quote,give}` | `gifts.pb.js`, `frame_gift.pb.js` | перенос |
| `POST /api/coins/{ad-grant,ad-reward}` | `coins.pb.js` | выкинуть (рекламы нет); копилка пары `pair_jar` копится от роликов — выкинуть вместе с ними |
| `POST /api/coins/{iap-purchase,redeem,donation-bind,donation-credit,plus-monthly}` | `coins.pb.js`, `redeem.pb.js`, `donations.pb.js` | выкинуть |
| `POST /api/coins/dev-coins` | `coins.pb.js` | выкинуть (отладка автора) |
| `POST /api/lava/{checkout,webhook}`, `GET /api/lava/gift`, `POST /api/plus/activate`, `GET /plus` | `lava*.pb.js`, `plus_web.pb.js` | выкинуть |
| `GET/POST /api/wallet/waitlist` | `wallet_waitlist.pb.js` | выкинуть; тизер Wallet в клиенте скрыть (без роута клиент молча получает пусто, но тизер остаётся) |
| `GET /modapi/income` | `income.pb.js` | выкинуть (админка доходов) |

### Прочее

| Роут | Где сейчас | Решение |
|---|---|---|
| `GET /api/profile/web` | `profile_web.pb.js` | выкинуть: публичный профиль пары наружу (имена, даты) — против целей форка |
| `POST /api/stats/collect` | `tools/stats_collector.py` | выкинуть (аналитика выключена в S2) |
| `GET /healthz` | hotpath | свой healthcheck в `server/` |

## 3. Хуки без роутов

| Хук | Что делает | Решение |
|---|---|---|
| `centrifugo.pb.js` (+ `pb-cgo` на Go) | публикует create/update/delete 24 коллекций целиком в `pair:`/`user:`/`loc:` | перенос; после E2E публикуются шифртекст и метаданные |
| `chat_guard`, `groups_guard`, `wishes_guard`, `users_guard` | запрет менять чужое / денежные поля | перенос (на Go, правила в одном месте) |
| `groups_membership` | ведёт `users.group_ids` | перенос; здесь же разобрать расхождение `apply_acl.py` и схемы |
| `birthdays` | зеркалит `users.birth_date` в `groups.member_birthdays` | перенос |
| `counters`, `comments_count` | счётчики достижений и комментариев | перенос |
| `email_case` | вход и сброс без учёта регистра почты | перенос |
| `gmail_mailer` + `mail_relay/` | все письма через Gmail-релей автора | переписать: свой SMTP из env |
| `push_apns` + `apns_push.js`, `apns/`, `fcm/` | пуши iPhone и FCM, текст сообщения в payload | выкинуть (решение 2) |
| `widget_plus` | признак Плюса в `widget_data` | переписать: всегда «открыто» |
| `plus_pending` | выдача оплаченного Плюса при регистрации | выкинуть |
| `income`, `lava_checkout` (cron) | доход, счета | выкинуть |
| `widget_anim` (cron) | чистка анимаций | перенос |

## 4. Коллекции

36 коллекций в `collections_schema.json` плюс две, которых там нет. Таблицы
hotpath (`pocketbase/hotpath/*.sql`) повторяют коллекции PB, кроме кэшей.

| Коллекция | Решение | Заметки |
|---|---|---|
| `users` | перенос | убрать денежные поля из схемы форка позже, в S4 оставить для совместимости клиента; `fcm_token`, `apns_*` не нужны |
| `groups`, `invite_codes`, `user_presence` | перенос | `user_presence` — только члены пары (S6) |
| `chat_messages`, `chat_reads`, `chat_typing` | перенос | E2E в S9 |
| `memories`, `memory_comments`, `media` | перенос | E2E в S9; `media` avatar/banner — только пара (S6) |
| `mood_entries`, `miss_you`, `cycle_entries`, `wishes`, `wish_categories`, `wish_reservations` | перенос | |
| `mascots`, `love_tests`*, `custom_moods`* | перенос | *нет в схеме — восстановить по моделям |
| `canvas_strokes`, `canvas_meta`, `canvas_live`, `canvas_catalogue` | перенос | |
| `live_location` | перенос | исправить `createRule`/`viewRule` (S6) |
| `live_sessions`, `live_session_presence`, `live_session_chat`, `watch_history`, `watch_videos` | перенос | |
| `widget_data` | перенос | |
| `catalog_items`, `app_config` | перенос | каталог наклеек/рамок — данные; `app_config.min_build` для force-update |
| `chest_opens` | перенос | |
| `gifts` | перенос | |
| `pair_jars` | выкинуть | копилка от роликов |
| `iap_purchases`, `redeem_codes`, `wallet_waitlist` | выкинуть | |
| `migration_flags` | выкинуть | мост Firebase |
| hotpath: `movie_query_cache`, `wd_cache` | переписать | кэш meta gateway |
| hotpath: `miss_you_events` | перенос | история импульсов «Скучаю» (каждый тап — строка, живёт 3 суток), отдаётся ответом `/api/group/miss-you`; в форке — коллекция PB с чисткой по cron |

## 5. Centrifugo

| Канал | Что идёт | Кто подписывается |
|---|---|---|
| `pair:<groupId>` | все парные коллекции, `groups` | члены пары (проверка в subscription-token) |
| `user:<uid>` | `user_presence`, изменения своих групп | сам пользователь |
| `loc:<channel>` | `live_location`, `channel = pair_<uidA>_<uidB>` | участники пары; канал привязать к группе автора записи (S6) |

Сообщение: `{event, collection, record}`, запись целиком. Коллекции в
публикации: `chat_messages, mood_entries, memories, memory_comments, mascots,
miss_you, gifts, user_presence, live_sessions, live_session_presence,
live_session_chat, live_location, canvas_strokes, canvas_meta, canvas_live,
canvas_catalogue, widget_data, chat_typing, chat_reads, groups, watch_history,
cycle_entries, wishes, wish_categories, custom_moods`.

Android-уведомления формирует клиент из этих событий (`PbPushService` в
foreground-сервисе), сервер текстов уведомлений не собирает.

## 6. Внешние сервисы

| Сервис | Кто зовёт | Что видит | Решение |
|---|---|---|---|
| OpenFreeMap (тайлы) | клиент | где пользователь смотрит карту | пока исключение (PLAN), адрес в конфиге (S1) |
| noembed.com, Vimeo oEmbed, `i.ytimg.com`, Rutube API | клиент | ссылки на видео | gateway (S5) |
| Deezer, iTunes, `api.music.yandex.net` | клиент / `music.pb.js` | треки | gateway |
| Open Library (поиск и обложки) | клиент | книги | gateway |
| poiskkino, Wikidata | hotpath | фильмы | gateway |
| страницы магазинов (превью ссылок) | `link_fetcher` | ссылки | gateway, настройка «напрямую с устройства» |
| TikTok, YouTube, Rutube и др. (встраивание) | клиент (WebView) | просмотр | осознанное исключение (решение 4), прокси TikTok — `REELS_PROXY_URL` |
| Gmail | `mail_relay` | все письма | свой SMTP |
| ML Kit (`mobile_scanner`) | клиент | возможно, статистика использования Google | проверить трафиком (S2) |

## 7. Игры: контракт встраивания (решение 4)

Клиент открывает `GAMES_URL` во внешнем браузере (`watch_home_screen.dart`,
`_openGames`, `LaunchMode.externalApplication`). Ни сессии, ни кода пары, ни
параметров не передаётся: игры апстрима «на одном телефоне», без сервера. Значит
контракт минимальный: **любой статический сайт по HTTPS**. Пустой `GAMES_URL`
скрывает плитку (S1). Если позже понадобятся игры по сети, их стоит строить
как комнаты «Смотрим вместе» (`/api/watch/room` + токен), а не придумывать
второй механизм.

## 8. Вспомогательные сервисы прод-сервера

| Сервис | Решение |
|---|---|
| `hotpath/` (FastAPI поверх Postgres) | выкинуть (решение 5); `note/export`, `movies/search` — на Go |
| `link_fetcher/` | основа fetcher'а meta gateway |
| `mail_relay/` | выкинуть, свой SMTP |
| `apns/`, `fcm/` | выкинуть |
| `donation_worker/`, `tools/stats_collector.py`, `workers/downloads-badge` | выкинуть |
| `memory_thumbs.py`, `tools/thumb_cache.py`, `tools/widget_anim.py` | перенос до E2E; после S9 превью делает клиент |
| `season_chest.py`, `chest_morning_push.py` | разобрать в S5 вместе с сундуком |
| `pb-cgo/` | основа `server/` (S4) |
| `pb_public/` | перенос: `watch/`, `invite`, `privacy-policy`, `terms`, `reset`, `delete-account`; выкинуть `club`, `wallet-*`, баннеры и рекламные `app-ads.txt` |

## 9. Решения, нужные от владельца

1. **Монеты и сундуки** — оставить игровой механикой без денег (рекомендация
   выше) или убрать вместе с тратами и сделать всё «купленным»?
2. **Публичный профиль пары** (`profile_web`) — выкидываем (рекомендация)?
