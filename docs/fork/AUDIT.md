# Аудит апстрима (база форка)

Снято с апстрима на коммите `76ab665`. Это стартовый контекст для каждой рабочей
сессии форка: что нашли, где это в коде и насколько вывод проверен.

Метки: **[код]** — видно прямо в коде; **[гипотеза]** — выведено из правил или
схемы, вживую не проверялось.

## 1. Шифрование

- Сквозного шифрования нет. Сервер, Centrifugo и бэкапы видят всё в открытом виде. [код]
- Офлайн-кэш зашифрован AES-256-GCM, ключ лежит в Keystore/Keychain
  (`lib/services/offline/cache_cipher.dart`, `cache_key_store.dart`). Сделано нормально. [код]
- Токен сессии PocketBase лежит в SharedPreferences открытым
  (`lib/services/pocketbase_service.dart:51`). [код]
- «Секретные воспоминания» — это флаг `isSecret` в `memories.data` и PIN, хешированный
  SHA-256, в SharedPreferences (`lib/services/secret_pin_service.dart`). Контент на
  сервере и у партнёра открыт. [код]
- Капсула времени: дата открытия проверяется только на клиенте
  (`lib/models/memory.dart:173`), сервер отдаёт `data` сразу. [код]
- Push: текст сообщения (до 120 символов) уходит в APNs
  (`pocketbase/pb_hooks/push_apns.pb.js:93`). [код]
- Centrifugo публикует запись целиком (`record: rec`) по 24 коллекциям
  (`pocketbase/pb_hooks/centrifugo.pb.js`). [код]
- Серверная логика, которой нужен открытый текст:
  - поиск по чату: `hotpath.py`, `searchable: {"text"}`;
  - текст в push;
  - `link_preview` (сервер ходит по ссылке);
  - `memory_thumbs.py` (пишет в `memories.data`);
  - `profile_web.pb.js`;
  - веб-страницы `pb_public/watch`.

## 2. Безопасность сервера

- `live_location.createRule` не ограничивает `channel`, поэтому любой пользователь,
  скорее всего, может вбросить точку в канал чужой пары, а Centrifugo её разошлёт
  в `loc:<channel>`. [гипотеза]
- `live_location.viewRule` проверяет `channel ~ auth.id`, то есть ищет id по подстроке. [код]
- `pocketbase/apply_acl.py` (правила на `groups.members ?~`) расходится с
  `collections_schema.json` (правила на `@request.auth.group_ids`). Какой из вариантов
  стоит на проде, неизвестно. [код]
- `user_presence` читают все залогиненные. Медиа с `kind=avatar/banner` тоже
  читают все залогиненные. [код]
- Брошенные домены в App Links: `togetherly.duckdns.org`, `togetherly-d4856.web.app`
  (`android/app/src/main/AndroidManifest.xml:124-147`, `ios/Runner/Runner.entitlements:28-30`).
  Их можно перехватить и через них увести инвайты. [код]
- Реальная почта пользователя лежит в `tools/grant_coins.py` (docstring). [код]
- Возможности оператора: `tools/make_reset_token.py` (сброс пароля любому пользователю),
  `hotpath/probe_*` (запросы от лица живого пользователя). [код]

## 3. Телеметрия и привязка к автору

- Bugsink/Sentry: DSN зашит константой (`lib/config/sentry_config.dart:15`) и в
  release-сборке включён всегда. В событие пишется `user.id` = uid (`lib/main.dart:379`). [код]
- Собственная аналитика `lib/services/analytics_service.dart` → `/api/stats/collect`:
  экраны, время на них, действия, uid открытым текстом. Отключить нельзя. Хеширует uid
  сервер (`tools/stats_collector.py`). [код]
- AdMob и Yandex Mobile Ads (`pubspec.yaml:114-115`), RuStore SDK
  (`lib/config/rustore_config.dart`, appId автора). [код]
- Адреса автора, которые не задаются через `--dart-define`:
  - `lib/services/reels/reels_proxy.dart:18`: `http://169.58.6.158:8899`, прокси
    на весь WebView;
  - `lib/services/watch_room_service.dart:24,93`: `games.togetherly.day`, `togetherly.day`;
  - ссылки инвайтов `https://togetherly.day/invite/` (`lib/models/pair_data.dart:79`,
    `lib/models/connection.dart:253`);
  - белый список медиа-хостов (`lib/models/pb_media_ref.dart:16`,
    `lib/models/memory_sticker.dart:128`);
  - legal-URL (`lib/screens/profile_screen.dart:149`, `lib/screens/setup_screen.dart`,
    `cycle_consent_sheet.dart`);
  - релизы (`lib/screens/force_update_screen.dart:19`);
  - `lib/services/deep_link_service.dart`.
- Через `--dart-define`, но по умолчанию прод автора: `PB_URL`, `CENTRIFUGO_WS`,
  URL в `music_meta_service.dart:47`. [код]
- Внешние сервисы, к которым клиент ходит напрямую:
  - `tiles.openfreemap.org` (видит, где пользователь);
  - `noembed.com` (видит ссылки);
  - `api.deezer.com`, `api.music.yandex.net`, `itunes.apple.com`;
  - `openlibrary.org`, `vimeo.com/api/oembed`, `i.ytimg.com`. [код]
- Внешние сервисы, к которым ходит сервер: `api.poiskkino.dev` и Wikidata (поиск фильмов
  в `hotpath`), Gmail (почта). [код]
- Android push: основной путь — FCM (нативный `FcmService.kt`, токен в
  `users.fcm_token`, `firebase-messaging` в `android/app/build.gradle.kts`).
  Где сервисов Google или токена нет, foreground-сервис держит WebSocket к
  Centrifugo (`lib/services/pb_push_service.dart`, `lib/services/fcm_service.dart`).
  Для форка остаётся только второй путь; в S0 плагин `google-services`
  применяется лишь при наличии `google-services.json`, и без него клиент сам
  уходит на сокет. (Уточнено в S0; в первой версии аудита FCM пропущен.) [код]

## 4. Как устроен прод автора на самом деле

Прод — это не только `pocketbase/pb_hooks`:

- Caddy раскидывает маршруты. Caddyfile в репозитории нет, есть только
  `pocketbase/hotpath/caddy_add_routes.py`.
- `pocketbase/hotpath/hotpath.py` (~4.8k строк) — PB-совместимый API для «горячих»
  коллекций поверх Postgres (Supabase). Подпись токенов PB проверяет сам, читая
  `tokenKey` прямо из SQLite PB. Появился потому, что PB упирался примерно в 6
  записей в секунду на нагрузке автора.
- Сопутствующие сервисы:
  - `tools/stats_collector.py` (:8098);
  - `link_fetcher` (:8110), исходников в репозитории нет;
  - Bugsink в Docker;
  - tinyproxy на втором VPS;
  - Cloudflare Worker `workers/downloads-badge`.
- Закрытая админка `admin.togetherly.day/modapi/*` (`pb_hooks/income.pb.js`, воркер).
- Деплой: скрипты под `root@77.91.95.34`, `/opt/...`, systemd. Compose нет.
- Хвосты старых бэкендов: `functions/` (Firebase), `firestore.rules`, `supabase/`,
  `.wrangler`.

Масштаб: клиент — около 255 тыс. строк Dart, 144 сервиса. В схеме 36 коллекций.
В хуках 81 роут.
