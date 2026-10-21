# Точки касания кода апстрима

Каждая правка файла, который пришёл из апстрима (`THET1ME-1/togetherly`), — здесь.
Новые файлы форка (`lib/fork/**`, `test/fork/**`, `tool/fork/**`,
`android/app/src/fork/**`, `docs/fork/**`, `server/**`, `deploy/**`, `env/**`,
`.github/workflows/fork-*.yml`, `.dockerignore`, `dart_test.yaml`) в реестр не
попадают: с апстримом они не конфликтуют.

Отдельный случай — **JS-хуки апстрима** (`pocketbase/pb_hooks`). Форк их не
правит: сервер берёт файлы по списку `server/hooks.allow` как есть, а
недостающий hotpath заменяет внутренним API на Go (`server/internal/handler/compat.go`).
После мёржа апстрима: `server/scripts/sync-hooks.sh` (упадёт, если файл из
списка переименован), `python3 tool/fork/api_inventory.py --missing`, смоук
`server/scripts/smoke.sh`. Новый хук апстрима сам в сервер не попадает — его
надо осознанно добавить в `hooks.allow`.

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

| `lib/services/analytics_service.dart` | S2 | `flush()` и `_add()` выходят по `ForkFlags.analyticsDisabled`, импорт. | Повторить две строки. |
| `lib/services/rewarded_ad_service.dart`, `lib/services/interstitial_ad_service.dart`, `lib/widgets/common/ad_banner.dart` | S2 | Заменены целиком заглушками с прежним публичным API (без SDK). | Брать нашу версию. Если апстрим поменял API (новый геттер, параметр) — добавить его в заглушку. |
| `lib/main.dart` (S2) | S2 | Импорты `google_mobile_ads`/`yandex_mobileads` убраны; тело `_initConsentAndAds` заменено вызовом `ForkCrashReports.askOnceIfNeeded`; перед `SentryFlutter.init` — `ForkCrashReports.load()`, в конце колбэка — `ForkCrashReports.configure(...)`; `Sentry.configureScope(setUser)` убран. | Повторить. Если апстрим правил `_initConsentAndAds` — взять нашу однострочную версию. |
| `lib/services/plus_service.dart` | S2 | `_open` и `canPurchase` учитывают `ForkFlags.allFree`, импорт. | Повторить. |
| `lib/services/coin_store.dart` | S2 | `createCoinStore()` всегда `_DisabledCoinStore`; импорты IAP-сервисов убраны; дефолт `STORE` = `fork`. | Повторить. |
| `lib/services/iap_service.dart`, `lib/services/rustore_iap_service.dart`, `lib/config/rustore_config.dart` | S2 | Удалены (вместе с зависимостями). | Конфликт modify/delete — оставить удалёнными. |
| `pubspec.yaml` | S2 | Убраны `google_sign_in`, `google_mobile_ads`, `yandex_mobileads`, `in_app_purchase`, `flutter_rustore_billing` (на их месте комментарии `fork`). | Не возвращать; новые рекламные/платёжные зависимости апстрима — тоже убрать. `pubspec.lock` — перегенерировать `flutter pub get`. |
| `android/app/build.gradle.kts` (S2) | S2 | Убраны `firebase-bom`, `firebase-messaging`, `play-services-base` и плагин `google-services`. | Не возвращать. |
| `android/app/src/main/AndroidManifest.xml` (S2) | S2 | `AD_ID` с `tools:node="remove"`; AdMob App ID, сервис `.FcmService` и мета-данные Firebase убраны. | Повторить. |
| `android/app/src/main/kotlin/com/togetherly/love/MainActivity.kt` | S2 | Канал `love_app/fcm`: `hasServices` → `false`, `getToken` → `null`; импорты GMS/Firebase убраны. | Повторить. |
| `android/app/src/main/kotlin/com/togetherly/love/FcmService.kt` | S2 | Удалён. | Оставить удалённым. Логику, которую апстрим добавит в него (пуш-события), переносить на путь Centrifugo. |
| `lib/screens/settings_screen.dart` (S2) | S2 | `ForkCrashReportsRow` в разделе «О приложении»; строки Telegram-канала и бота автора под `!ForkFlags.hideUpstreamChannels`. | Повторить. |
| `lib/screens/profile_screen.dart` (S2) | S2 | Донат-карточка под `!ForkFlags.hideUpstreamChannels`, импорт. | Повторить. |
| `lib/services/pocketbase_service.dart` | S6 | Хранилище сессии: `ForkSecureAuthStore.open(_authPrefsKey)` вместо `AsyncAuthStore` на SharedPreferences; импорт `shared_preferences` убран, добавлен `../fork/secure_auth_store.dart`. | Повторить. Если апстрим сменил хранение сессии — перенести его логику в `lib/fork/secure_auth_store.dart`. |
| `lib/services/pocketbase_service.dart` | S5 | В `init()` после `_initialized = true` — `ForkHttpGateway.install()` (перехват `dart:io` на meta gateway), импорт. | Повторить. `init()` зовут все изоляты; если апстрим заведёт изолят без неё — звать `install()` и там. |
| `lib/services/movie_search_service.dart` | S5 | `_token`: без `--dart-define=KINOPOISK_TOKEN` при `ForkFlags.noUpstreamKeys` — пусто, общий ключ автора не используется (запасной путь — ручной ввод), импорт. | Повторить. Если апстрим добавит другие зашитые ключи — под тот же флаг. |
| `lib/services/pb_data_service.dart` | S4 | Запасной список ICE-серверов: вместо STUN Google — пустой (решение 4). | Повторить; сторож `no_author_hosts_test.dart` ловит `stun.l.google.com`. |
| `lib/services/pb_data_service.dart` | S5 | `linkPreview`: при настройке «Ссылки напрямую с устройства» — `ForkLinkPreview.fetch(url)` вместо `/api/link/preview`; импорт `../fork/meta_direct.dart`. | Повторить. Если апстрим поменяет разбор в `link_preview.pb.js` — перенести и в `server/internal/domain/linkpreview`, и в `lib/fork/meta_direct.dart` (общие случаи в тестах обоих). |
| `lib/screens/settings_screen.dart` | S5 | `ForkMetaDirectRow()` после `ForkCrashReportsRow()`, импорт. | Повторить. |
| `lib/widgets/auth_widgets.dart` | S2 | `AuthSocialRow.build` при `ForkFlags.emailOnlyAuth` возвращает пустое место (решение 3), импорт. | Повторить. |
| `lib/screens/home_screen.dart` | S5 | `onWallet` ряда действий — `null` при `ForkFlags.hideUpstreamChannels` (Togetherly Wallet — продукт автора), импорт. | Повторить. |
| `lib/models/help_items.dart` | S2 | Пункты «telegram» и покупки Плюса — под флагами форка, импорт. | Повторить. |
| `test/chest_open_never_hangs_test.dart`, `test/reels_invite_wiring_test.dart`, `test/android_widget_wake_test.dart` | S2 | Убраны проверки удалённого кода (rewarded-SDK, `FcmService.kt`). | Повторить: проверки удалённого кода не возвращать. |
| `test/rewarded_ad_never_hangs_test.dart`, `test/services/rewarded_ad_failure_report_test.dart`, `test/widgets/ad_banner_network_test.dart`, `test/ios_no_purchases_test.dart`, `test/ios_plus_only_purchase_test.dart` | S2 | Удалены: проверяли удалённые реализацию рекламы и IAP. | Оставить удалёнными. |


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
- Монеты, сундуки и кошелёк как игровая механика: остаются до решения в S3
  (решение 1). Покупки монет и донаты скрыты (`STORE=fork`), заработок монет
  за рекламу недоступен (рекламы нет) — его судьбу тоже решаем в S3.
- `in_app_update`: работает только для установок из Google Play; APK форка
  ставится вручную, путь Play не срабатывает.
- `sign_in_with_apple` и OAuth-методы в `pb_auth_service.dart`: остаются в
  коде (нативный вход Apple — только iOS, OAuth вызывается лишь из скрытых
  кнопок). Сервер форка OAuth-провайдеров не настраивает (решение 3).
- Платное поведение апстрима в тестах: `FORK_UPSTREAM_BEHAVIOR=true` из
  `env/test.json` выключает флаги `allFree`/`hideUpstreamChannels`, чтобы тесты
  апстрима проверяли то, для чего написаны. Поведение сборки форка проверяет
  `test/fork/flags_runtime_test.dart` (тег `fork-runtime`, без env/test.json).
- Воркфлоу апстрима в `.github/workflows/`: не правим, лишние выключаем в
  настройках Actions (см. [README.md](README.md)).
