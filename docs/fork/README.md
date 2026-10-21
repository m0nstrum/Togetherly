# Tethered — форк Togetherly

Self-hosted форк с E2E. Что и зачем делаем — [PLAN.md](PLAN.md), исходные
находки — [AUDIT.md](AUDIT.md), правки чужих файлов — [TOUCHPOINTS.md](TOUCHPOINTS.md).

## Ветки и апстрим

- `main` — стабильная ветка форка. Сюда мёржатся фича-ветки и апстрим.
- Фича-ветки: по одной на сессию плана (`s1-config`, `s2-telemetry`, …) или на
  задачу. В `main` — через PR с зелёным `Fork CI`.
- Апстрим: remote `upstream` = `https://github.com/THET1ME-1/togetherly`.
  Подключить в своём клоне:

  ```sh
  tool/fork/setup_upstream.sh
  ```

- Апстрим **мёржим, а не ребейзим**: история форка публичная, и merge-коммит
  не ломает чужие клоны.

  ```sh
  git fetch upstream
  git switch -c merge-upstream-$(date +%Y%m%d) main
  git merge upstream/main
  # конфликты — по TOUCHPOINTS.md
  flutter test test/fork && flutter analyze --no-fatal-infos
  ```

## Идентичность

| | Апстрим | Форк |
|---|---|---|
| applicationId | `com.togetherly.love` | `io.github.m0nstrum.tethered` |
| Имя в лаунчере | Togetherly | Tethered |
| Схема приглашений | `loveapp://invite/…` | `tethered://invite/…` |
| Иконка | маскот | `tool/fork/gen_icon.py` |

Форк ставится рядом с приложением апстрима и не перехватывает его ссылки.

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
| `MAP_TILEJSON_URL`, `MAP_TILES_FALLBACK` | нет | OpenFreeMap |

Хост App Links Gradle берёт из тех же `--dart-define` (`SITE_URL`, иначе
`PB_URL`). Сборка без них регистрирует `unconfigured.invalid` и чужих ссылок не
перехватывает.

Крашрепорты (`SENTRY_DSN`) уходят только с согласия: вопрос появляется один
раз после первого запуска, переключатель — в настройках, раздел «О приложении».
Без `user.id`, текстов, URL с токенами и координат (`lib/fork/crash_reports.dart`).

`STORE` в сборках форка не задаётся: по умолчанию `fork` — без покупок и
донатов.

`env/test.json` — только для `flutter test`: в нём адреса апстрима, потому что
его тесты сверяют их буквально.

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

`Fork CI` (`.github/workflows/fork-ci.yml`) на каждый push и PR:

- `tool/fork/analyze_check.sh` — падает на любой ошибке и на предупреждении,
  которого нет в `tool/fork/analyze_baseline.txt` (там предупреждения
  апстрима; после мёржа обновить: `tool/fork/analyze_check.sh --update`);
- `flutter test --dart-define-from-file=env/test.json --exclude-tags fork-runtime`,
  включая сторожа `test/fork/no_author_hosts_test.dart` (адреса апстрима в
  `lib/`, `android/`). `env/test.json` возвращает тестам апстрима его адреса и
  платное поведение (`FORK_UPSTREAM_BEHAVIOR`);
- `flutter test test/fork --tags fork-runtime` — поведение настоящей сборки
  форка, без `env/test.json`;
- release APK под arm64 с `env/example.json` (debug-подпись) и проверка
  `applicationId`, имени и хоста App Links в нём.

Воркфлоу апстрима остаются в репозитории, чтобы не конфликтовать при мёржах.
Форку они не нужны, их стоит выключить: **Settings → Actions** или страница
воркфлоу → `…` → **Disable workflow**. Это все `ios-*.yml` и `release-apk.yml`
(публикует в Play/RuStore/App Store и требует секретов автора).
`android-widget-compile.yml` и `android-sound-clip.yml` можно оставить.

## Локальная сборка

```sh
flutter pub get
flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons \
  --dart-define-from-file=env/prod.local.json
flutter test --dart-define-from-file=env/test.json --exclude-tags fork-runtime
flutter test test/fork --tags fork-runtime
```

Нужен Flutter той же версии, что в `fork-ci.yml` (`FLUTTER_VERSION`).

Golden-тесты апстрима ищут шрифт иконок в `$HOME/snap/flutter/common/flutter`
(путь snap-установки у автора). Если Flutter стоит иначе:

```sh
mkdir -p ~/snap/flutter/common
ln -sfn "$(dirname "$(dirname "$(command -v flutter)")")" ~/snap/flutter/common/flutter
```

Без этого 4 снимка (`home_header_test`, `de_layout_test`) падают: иконки
рисуются квадратами.
`google-services.json` форку не нужен: без него Gradle не применяет плагин
Firebase, а клиент получает push через Centrifugo.
