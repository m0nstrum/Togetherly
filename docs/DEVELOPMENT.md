# Разработка Tethered

Tethered — приложение для пар с E2E-шифрованием и своим сервером. Начиналось
как форк [Togetherly](https://github.com/THET1ME-1/togetherly) (GPL-3.0), с
24.10.2026 развивается самостоятельно: апстрим больше не мёржим.

Документы:

- [ROADMAP.md](ROADMAP.md) — куда идём, этапы;
- [BACKLOG.md](BACKLOG.md) — баги и доработки;
- [AUDIT_2026-10.md](AUDIT_2026-10.md) — аудит состояния проекта 29.10.2026;
- [E2E.md](E2E.md) — модель угроз и шифрование;
- [TESTING.md](TESTING.md) — ручная проверка на телефонах;
- [../deploy/README.md](../deploy/README.md) — развёртывание сервера;
- [history/](history/) — архив этапа форка (план S0–S12, аудиты, реестр правок
  файлов апстрима). Не обновляется.

## Ветки

- `main` — стабильная ветка. Рабочие ветки попадают в неё через PR с зелёным
  `Fork CI`.
- Push в рабочую ветку CI не запускает — его запускает PR.

## Идентичность

| | |
|---|---|
| applicationId | `io.github.m0nstrum.tethered` |
| Имя в лаунчере | Tethered |
| Схема приглашений | `tethered://invite/…` |
| Иконка | `tool/fork/gen_icon.py` |

Внутренние имена ещё от Togetherly (Kotlin-пакет `com.togetherly.love`,
Dart-пакет `love_app`) — переименование в ROADMAP, этап 1.

## Конфигурация сервера

Все адреса клиента — в `lib/fork/config/endpoints.dart` и задаются при сборке
файлом:

```sh
cp env/example.json env/prod.local.json   # *.local.json в .gitignore
flutter build apk --release --dart-define-from-file=env/prod.local.json
```

| Ключ | Обязателен | Пусто означает |
|---|---|---|
| `PB_URL` | да | приложение не стартует (`Endpoints.ensureConfigured`) |
| `CENTRIFUGO_WS` | нет | `wss://<хост PB_URL>/connection/websocket` |
| `SITE_URL` | нет | = `PB_URL`; отсюда приглашения, политика, условия, хост App Links |
| `LEGACY_HOSTS` | нет | старых доменов нет (через запятую, если есть) |
| `GAMES_URL` | нет | плитка игр скрыта |
| `REELS_PROXY_URL` | нет | TikTok без прокси |
| `RELEASES_URL` | нет | ссылки на свежий APK нет |
| `SUPPORT_EMAIL`, `OFFICIAL_EMAIL` | нет | адрес поддержки пустой |
| `SENTRY_DSN` | нет | крашрепорты выключены |
| `MAP_TILEJSON_URL`, `MAP_TILES_FALLBACK` | нет | `/api/fork/map/tilejson` и `/api/fork/map/tiles/latest/…` на PB_URL; переопределения только на свои хосты |

Хост App Links Gradle берёт из тех же `--dart-define` (`SITE_URL`, иначе
`PB_URL`). Сборка без них регистрирует `unconfigured.invalid` и чужих ссылок не
перехватывает.

Крашрепорты (`SENTRY_DSN`) уходят только с согласия: вопрос появляется один
раз после первого запуска, переключатель — в настройках, раздел «О приложении».
Без `user.id`, текстов, URL с токенами и координат (`lib/fork/crash_reports.dart`).

`STORE` в наших сборках не задаётся: по умолчанию `fork` — без покупок и
донатов.

`env/test.json` — только для `flutter test`: в нём адреса Togetherly, потому
что унаследованные тесты сверяют их буквально. Платного поведения апстрима
(переключатель `FORK_UPSTREAM_BEHAVIOR`) больше нет: тесты проверяют то же,
что делает сборка. Переводы на скрытые языки тесты включают
`LocaleService.allLanguagesForTests`.

## Ключ подписи

Ключ хранится вне репозитория. Gradle берёт его из `android/key.properties`
(в `.gitignore`), формат как у апстрима:

```properties
storeFile=/абсолютный/путь/tethered-release.jks
storePassword=…
keyAlias=tethered
keyPassword=…
```

Создать ключ:

```sh
keytool -genkeypair -v -keystore tethered-release.jks -alias tethered \
  -keyalg RSA -keysize 4096 -validity 10000
```

Без `key.properties` release-сборка подписывается debug-ключом — так работает CI.
Потерянный ключ означает, что обновить установленное приложение будет нельзя,
только переустановить с потерей локальных данных. Храните копию отдельно.

## CI

`Fork CI` (`.github/workflows/fork-ci.yml`) запускается на push в `main`, на PR
и вручную. Правки только в `docs/` и `*.md` его не запускают. Задача «что
менялось» решает, какие части нужны:

| Часть | Когда | Что |
|---|---|---|
| `analyze + test` | клиент или сервер | `tool/fork/analyze_check.sh` (ошибки и предупреждения сверх `tool/fork/analyze_baseline.txt`; обновить базовую линию — `--update`), `tool/fork/repo_check.py`, `flutter test --dart-define-from-file=env/test.json --exclude-tags fork-runtime`, `flutter test test/fork --tags fork-runtime` (поведение боевой сборки), живой E2E клиента против сервера |
| `server (Go)` | сервер, хуки, `deploy/` | `go test -race`, смоуки с настоящими JS-хуками, паритет |
| `build APK` | клиент | release APK под arm64 с `env/example.json`, проверка `applicationId`, имени, хоста App Links |

Остальные воркфлоу:

| Файл | Когда |
|---|---|
| `fork-release.yml` | вручную — боевой APK, см. ниже |
| `fork-server-image.yml` | после зелёного Fork CI на `main`, если в нём прошла часть `server (Go)` — образ сервера `sha-…` и `latest` (deploy/README.md, «Обновление») |
| `android-widget-compile.yml`, `android-sound-clip.yml` | PR и `main`, только при правках своих файлов |
| `ios-runner-compile.yml`, `ios-widget-*.yml`, `ios-sound-clip.yml` | PR и `main`, только при правках `ios/` — macOS-раннеры дорогие |

## Сборка в GitHub

`Fork release APK` (`.github/workflows/fork-release.yml`) собирает боевой APK
под свой сервер. Запуск вручную: **Actions → Fork release APK → Run workflow**,
галочка `publish` кладёт APK в GitHub Releases, без неё он лежит артефактом
запуска 30 дней.

Что задать в **Settings → Secrets and variables → Actions**:

| Где | Имя | Что |
|---|---|---|
| Variables | `TETHERED_URL` | обязательно: `https://<домен сервера>` без `/` в конце, становится `PB_URL` и хостом App Links |
| Variables | `TETHERED_SITE_URL` | не нужно, если сайт на том же домене |
| Variables | `TETHERED_CENTRIFUGO_WS` | не нужно при стандартном `deploy/` |
| Variables | `TETHERED_SUPPORT_EMAIL` | адрес поддержки в приложении |
| Variables | `TETHERED_SENTRY_DSN` | DSN проекта в Bugsink, если он поднят |
| Variables | `TETHERED_RELEASES_URL` | по умолчанию `https://github.com/<репо>/releases/latest` |
| Secrets | `ANDROID_KEYSTORE_BASE64` | `base64 -w0 tethered-release.jks` |
| Secrets | `ANDROID_KEYSTORE_PASSWORD` | пароль хранилища |
| Secrets | `ANDROID_KEY_ALIAS` | `tethered` |
| Secrets | `ANDROID_KEY_PASSWORD` | пароль ключа; пусто — тот же, что у хранилища |
| Secrets | `GOOGLE_SERVICES_JSON` | необязательно: содержимое `google-services.json` своего Firebase-проекта — пуши-будильник FCM (deploy/README.md, «Пуши»); пусто — сборка без FCM |

Без ключа подписи воркфлоу падает намеренно: debug-ключ у каждого раннера
свой, и следующая сборка не встала бы поверх установленной. Номер сборки —
номер из `pubspec.yaml` плюс номер запуска, поэтому каждая новая ставится
поверх прежней. Проверки после сборки: `applicationId`, хост App Links равен
домену из `TETHERED_URL`, подпись не debug (SHA-256 сертификата — в логе).

В публичном репозитории релизы видны всем, а с ними и адрес сервера. Адрес
не секрет (он есть в каждой установленной копии), но если не хочется
светить — собирайте без `publish` и берите APK из артефакта.

## Локальная сборка

```sh
flutter pub get
flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons \
  --dart-define-from-file=env/prod.local.json
flutter test --dart-define-from-file=env/test.json --exclude-tags fork-runtime
flutter test test/fork --tags fork-runtime
```

Нужен Flutter той же версии, что в `fork-ci.yml` (`FLUTTER_VERSION`).

Унаследованные golden-тесты ищут шрифт иконок в `$HOME/snap/flutter/common/flutter`
(путь snap-установки автора Togetherly). Если Flutter стоит иначе:

```sh
mkdir -p ~/snap/flutter/common
ln -sfn "$(dirname "$(dirname "$(command -v flutter)")")" ~/snap/flutter/common/flutter
```

Без этого 4 снимка (`home_header_test`, `de_layout_test`) падают: иконки
рисуются квадратами.
`google-services.json` необязателен: без него Gradle не применяет плагин
Firebase, а клиент получает push через Centrifugo.

Карта (M10): телефон обращается к своему `/api/fork/map/*`. Сервер получает
TileJSON и PBF OpenFreeMap, переписывает источник на свой маршрут, кэширует
ответы в ограниченном LRU (64 МиБ, 6 часов), ограничивает координаты z≤14
и частоту запросов (600/мин/IP). Заголовки входа и IP телефона провайдеру
не передаются. Это прокси, собственная генерация планеты не требуется.
Старые внешние MAP_* в env нужно убрать; пустые значения включают прокси.
