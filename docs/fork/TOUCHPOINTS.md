# Точки касания кода апстрима

Каждая правка файла, который пришёл из апстрима (`THET1ME-1/togetherly`), — здесь.
Новые файлы форка (`lib/fork/**`, `test/fork/**`, `tool/fork/**`,
`android/app/src/fork/**`, `docs/fork/**`, `server/**`, `deploy/**`,
`.github/workflows/fork-*.yml`) в реестр не попадают: с апстримом они не
конфликтуют.

Правки в чужих файлах помечены комментарием `fork` (`// fork`, `<!-- fork -->`),
поэтому их можно найти так: `git grep -n "fork:\|// fork"`.

**Как пользоваться при мёрже апстрима:** пройти таблицу сверху вниз. Если файл
конфликтует, взять версию апстрима и заново применить правку из колонки «Что
сделано». После мёржа — `flutter test test/fork` и `Fork CI`.

| Файл | Сессия | Что сделано | Как разрешать конфликт |
|---|---|---|---|
| `android/app/build.gradle.kts` | S0 | Блок `── fork: Tethered ──` после `plugins`: `forkApplicationId`, `forkManifestPlaceholders` (`appLabel`, `appScheme`), условное применение `google-services`. В `plugins` у `google-services` стоит `apply false`. `applicationId = forkApplicationId`, `manifestPlaceholders += …` в `defaultConfig`. Перед `flutter {}` к build-type source set'ам подключён `src/fork/res`. | Берём файл апстрима, возвращаем четыре куска с пометкой `fork`. `namespace` не трогаем. |
| `android/app/src/main/AndroidManifest.xml` | S0, S1 | Все `android:label="Togetherly"` → `${appLabel}`. В фильтре приглашений `scheme="loveapp"` → `${appScheme}`. S1: три https-фильтра приглашений (togetherly.day, duckdns, web.app) заменены одним с `android:host="${inviteHost}"`. | Берём файл апстрима, повторяем замену: `sed -i 's/android:label="Togetherly"/android:label="${appLabel}"/'` и правку фильтра приглашений. Новые `android:label="Togetherly"` от апстрима тоже меняем — их ловит `test/fork/identity_test.dart`. Новые хосты апстрима ловит `test/fork/no_author_hosts_test.dart`. |
| `lib/models/pair_data.dart` | S0, S1 | `inviteDeepLink` → `ForkIdentity.inviteDeepLink(...)`, `inviteLink` → `Endpoints.current.inviteLink(...)`, два импорта. | Повторить замену геттеров и импорты. |
| `lib/models/connection.dart` | S0, S1 | То же, что в `pair_data.dart`. | То же. |
| `lib/services/deep_link_service.dart` | S0, S1 | Разбор `loveapp://invite/` → `ForkIdentity.inviteScheme`. S1: https-хосты приглашений → `Endpoints.current.ownHosts`; ветка email-ссылок Firebase убрана, `_handleEmailLink` помечен `ignore: unused_element`. Импорты. | Повторить замены. |
| `test/models/invite_link_domain_test.dart` | S0 | Ожидание `loveapp://invite/HQ792S` → `tethered://invite/HQ792S`. | Повторить замену строки. |
| `android/app/build.gradle.kts` (S1) | S1 | В блоке fork: разбор `dart-defines` → `forkInviteHost` → плейсхолдер `inviteHost`. | Часть блока fork, см. строку выше. |
| `android/app/src/main/res/xml/network_security_config.xml` | S1 | Cleartext-исключение для IP Bugsink апстрима убрано, файл переписан целиком. | Взять нашу версию. |
| `.gitignore` | S1 | Строка `env/*.local.json`. | Дописать строку. |
| `lib/main.dart` | S1 | Первая строка `main()`: `Endpoints.ensureConfigured();`, импорт. | Повторить. |
| `lib/services/pocketbase_service.dart` | S1 | `baseUrl = Endpoints.pbUrl` (без дефолта на апстрим). | Повторить. |
| `lib/services/centrifugo_service.dart` | S1 | `_wsUrl = Endpoints.current.centrifugoUrl` (`static final`). | Повторить. |
| `lib/services/music_meta_service.dart` | S1 | `pbBaseUrl = Endpoints.pbUrl`. | Повторить. |
| `lib/services/watch_room_service.dart` | S1 | `gamesUrl`, `siteHost` — геттеры из `Endpoints.current`. | Повторить. |
| `lib/services/reels/reels_proxy.dart` | S1 | `_url` из `REELS_PROXY_URL`; пустой — `enable()` ничего не делает. | Повторить. |
| `lib/services/map/map_tiles.dart` | S1 | `_tileJson`, `_fallback` из конфига; User-Agent форка. | Повторить. |
| `lib/models/pb_media_ref.dart` | S1 | `kPbFileHosts = Endpoints.current.ownHosts` (`final` вместо `const`). | Повторить. |
| `lib/models/memory_sticker.dart` | S1 | Разрешённые префиксы картинок наклеек строятся из `ownHosts`. | Повторить. |
| `lib/config/sentry_config.dart` | S1 | `dsn = String.fromEnvironment('SENTRY_DSN')`. В S2 сюда же придёт opt-in. | Повторить. |
| `lib/screens/profile_screen.dart`, `setup_screen.dart`, `home/widgets/cycle_consent_sheet.dart` | S1 | Ссылки на политику, условия и лендинг — из `Endpoints.current`. | Повторить. |
| `lib/screens/settings_screen.dart` | S1 | `supportEmail`/`officialEmail` из `SUPPORT_EMAIL`/`OFFICIAL_EMAIL`. | Повторить. |
| `lib/screens/force_update_screen.dart` | S1 | Ссылка на релизы — `RELEASES_URL`. | Повторить. |
| `lib/screens/memory_book_form_screen.dart` | S1 | User-Agent запросов к Open Library без домена апстрима. | Повторить. |
| `lib/widgets/chest/chest_share_card.dart`, `lib/widgets/mood/vessel_story_card.dart` | S1 | Подпись `togetherly.day` на карточках «поделиться» → `Endpoints.current.siteHost`. | Повторить. |
| `lib/widgets/together/watch_home_blocks.dart` | S1 | `WatchBento.games` необязательный, раскладка без игр (`_gamesAndComputer`). | Повторить; если апстрим перекроил раскладку — заново сделать `games` nullable. |
| `lib/screens/together/watch_home_screen.dart` | S1 | `games: null` при пустом `GAMES_URL`. | Повторить. |

## Что сознательно не трогали

- `namespace = "com.togetherly.love"` и пакет Kotlin-кода. Это внутреннее имя;
  на устройстве приложения различаются по `applicationId`.
- Внутренняя схема виджетов `loveapp://…` (Kotlin-провайдеры и `home_screen.dart`).
  Интенты виджетов явные (`MainActivity::class.java`), поэтому наружу схема не
  регистрируется и с приложением апстрима не спорит.
- Тематические иконки `ic_launcher_<тема>`: остаются апстримовскими. Перекрыта
  только основная `launcher_icon*` (через `android/app/src/fork/res`).
- Упоминания «Togetherly» в текстах интерфейса и локализациях. Ребрендинг
  текстов — сотни строк в чужих файлах, при каждом мёрже это были бы конфликты.
  Вернёмся к этому отдельно, если понадобится.
- `ios/`: по решению 2 не собираем.
- Тесты апстрима, которые буквально проверяют адреса `togetherly.day`: им в CI
  подаётся `env/test.json` с теми же значениями. Логику конфига форка
  проверяют `test/fork/endpoints_test.dart` и сторож `no_author_hosts_test.dart`.
- Предупреждения анализатора в коде апстрима: записаны в
  `tool/fork/analyze_baseline.txt`, CI валится только на новых.
- `PLUS_URL` (lava.top) и прочая монетизация — S2.
- Воркфлоу апстрима в `.github/workflows/`: не правим, лишние выключаем в
  настройках Actions (см. [README.md](README.md)).
