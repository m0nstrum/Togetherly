# Точки касания кода апстрима

Каждая правка файла, который пришёл из апстрима (`THET1ME-1/togetherly`), — здесь.
Новые файлы форка (`lib/fork/**`, `test/fork/**`, `tool/fork/**`,
`android/app/src/fork/**`, `docs/fork/**`, `server/**`, `deploy/**`, `env/**`,
`.github/workflows/fork-*.yml`, `.dockerignore`, `dart_test.yaml`) в реестр не
попадают: с апстримом они не конфликтуют.

Отдельный случай — **JS-хуки апстрима** (`pocketbase/pb_hooks`). Форк правит
их только там, где без этого не работает сквозное шифрование (строки ниже с
пометкой E2E-max); сервер берёт файлы по списку `server/hooks.allow`, а
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
| `lib/models/pair_data.dart` | S0, S1, S8 | `inviteDeepLink` → `ForkIdentity.inviteDeepLink(...)`, `inviteLink` → `Endpoints.current.inviteLink(...)`, два импорта. S8: `inviteLink` с фрагментом `ForkE2E.inviteFragment`. | Повторить замену геттеров и импорты. |
| `lib/models/connection.dart` | S0, S1 | То же, что в `pair_data.dart`. | То же. |
| `lib/services/deep_link_service.dart` | S0, S1, S8 | Разбор `loveapp://invite/` → `ForkIdentity.inviteScheme`. S1: https-хосты приглашений → `Endpoints.current.ownHosts`; ветка email-ссылок Firebase убрана, `_handleEmailLink` помечен `ignore: unused_element`. Импорты. S8: фрагмент ссылки приглашения (секрет E2E) → `ForkE2E.rememberFragment`. | Повторить замены. |
| `test/models/invite_link_domain_test.dart` | S0 | Ожидание `loveapp://invite/HQ792S` → `tethered://invite/HQ792S`. | Повторить замену строки. |
| `android/app/build.gradle.kts` (S1) | S1 | В блоке fork: разбор `dart-defines` → `forkInviteHost` → плейсхолдер `inviteHost`. | Часть блока fork, см. строку выше. |
| `android/app/src/main/res/xml/network_security_config.xml` | S1, S9 | Cleartext-исключение для IP Bugsink апстрима убрано, файл переписан целиком. S9: открытый http разрешён только к `127.0.0.1` — локальный прокси расшифровки медиа. | Взять нашу версию. |
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
| `lib/screens/profile_screen.dart`, `lib/screens/setup_screen.dart`, `lib/screens/home/widgets/cycle_consent_sheet.dart` | S1 | Ссылки на политику, условия и лендинг — из `Endpoints.current`. | Повторить. |
| `lib/screens/settings_screen.dart` | S1, S8 | `supportEmail`/`officialEmail` из `SUPPORT_EMAIL`/`OFFICIAL_EMAIL`. S8: `ForkE2EBackupRow` — бэкап ключей шифрования. | Повторить. |
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
| `pubspec.yaml` | S2 | Убраны `google_sign_in`, `google_mobile_ads`, `yandex_mobileads`, `in_app_purchase`, `flutter_rustore_billing` (на их месте комментарии `fork`). S8: `sodium` (E2E) и ассеты `assets/fork/`. | Не возвращать; новые рекламные/платёжные зависимости апстрима — тоже убрать. `pubspec.lock` — перегенерировать `flutter pub get`. |
| `android/app/build.gradle.kts` (S2) | S2 | Убраны `firebase-bom`, `firebase-messaging`, `play-services-base` и плагин `google-services`. | Не возвращать. |
| `android/app/src/main/AndroidManifest.xml` (S10) | S10 | `TransportBackendDiscovery` (datatransport, через который ML Kit шлёт статистику в Google) с `tools:node="remove"` в конце `<application>`. | Повторить. |
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
| `lib/services/pb_push_service.dart` | S5 | В `_startLocked` — подписка `ForkPushRelay.subscribe(myUid, …)` (уведомления хуков через `user:<uid>` вместо APNs/FCM), импорт. | Повторить. |
| `lib/services/reels/reels_invite.dart` | S5 | `ReelsInviteBus.deliver(invite)` — вход для зова не через мост FCM. | Повторить. |
| `lib/screens/settings_screen.dart` | S5 | `ForkMetaDirectRow()` после `ForkCrashReportsRow()`, импорт. | Повторить. |
| `lib/widgets/auth_widgets.dart` | S2 | `AuthSocialRow.build` при `ForkFlags.emailOnlyAuth` возвращает пустое место (решение 3), импорт. | Повторить. |
| `lib/screens/home_screen.dart` | S5, S8 | `onWallet` ряда действий — `null` при `ForkFlags.hideUpstreamChannels` (Togetherly Wallet — продукт автора), импорт. S8: `_updatePartnerPush` подключает `ForkE2E.attach`/`detach` (ключи E2E — только в главном изоляте). | Повторить. |
| `lib/models/help_items.dart` | S2 | Пункты «telegram» и покупки Плюса — под флагами форка, импорт. | Повторить. |
| `lib/models/connections_manager.dart` | S8 | После приёма кода — `ForkE2E.accepted(code, pairId)`: подтверждение приглашения по ссылке (E2E.md §6.2). | Сохранить вызов после проверки `pairId`. |
| `lib/screens/connect_partner_screen.dart` | S8 | Сканер QR отрезает фрагмент ссылки и отдаёт его `ForkE2E.rememberFragment`. | Сохранить: иначе код с фрагментом не пройдёт проверку длины. |
| `lib/services/pb_auth_service.dart` | S8 | `signOut` сбрасывает `ForkE2E`. | Сохранить. |
| `lib/screens/chat_screen.dart` | S8 | Над лентой — `ForkE2EBanner`: «ключи не проверены», «ключ сменился», «возможна подмена», входящая сверка. | Сохранить первым элементом колонки ленты. |
| `lib/services/pocketbase_service.dart` | S9 | `PocketBase(..., httpClientFactory: ForkE2E.httpClient)` — шифрование полей записей на входе и выходе; после `_initialized = true` — `ForkE2E.preload()`. | Сохранить в любом изоляте: иначе очередь уйдёт открытым текстом, а ответы сервера придут шифртекстом. |
| `lib/services/centrifugo_service.dart` | S9 | В `_onPublication` запись дельты проходит `ForkE2E.decodeSync(collection, …)` перед `RecordModel.fromJson`. | Сохранить: иначе живые сообщения чата покажут шифртекст. Если апстрим заведёт второй разбор дельт — обернуть и его. |
| `lib/screens/chat/chat_search_screen.dart` | S9 | Вкладки «Всё» и «Ссылки» у пары с ключом ищут через `ForkChatSearch.search` вместо `searchChat` с фильтром по тексту. | Сохранить: сервер в шифртексте ничего не найдёт. |
| `lib/services/live_location_service.dart` | S9 | Живая точка в `loc:<канал>` уходит через `ForkE2E.sealPoint`, приходит через `ForkE2E.openPoint` (null — подделка, точку не показываем). | Сохранить обе стороны: иначе координаты летят через сервер открыто. |
| `lib/services/pb_media_service.dart` | S9 | `resolveUrlAuthed` отдаёт адрес через `ForkE2E.mediaUrl` — локальный прокси расшифровки файлов пары. | Сохранить: иначе картинки, голосовые и видео пары придут шифром. Новый способ получить адрес файла в апстриме — пропустить через `ForkE2E.mediaUrl` тоже. Загрузка без `uid` берёт вошедшего (правило `media` форка требует автора). |
| `lib/services/canvas_repository.dart` | S9 | Живой штрих: `data` уходит через `ForkE2E.sealLive`, приходит через `ForkE2E.openLive` (не открылся — пакет не показываем). | Сохранить обе стороны. |
| `lib/screens/together/watch_room_screen.dart` | S9, S11 | Встроенная комната (не ленты, не нативное окно): скрипт `forkNativeChatScript` для страницы и `ForkRoomChatOverlay` последним в `Stack`. S11: `ForkWatchProxy.enable()` в `initState`, `disable()` в `dispose`, `onReceivedHttpAuthRequest` → `ForkWatchProxy.answer`. | Сохранить: иначе чат комнаты снова на странице, которую отдаёт сервер, а ролики не идут через прокси. |
| `pocketbase/pb_public/watch/room/room.js` | S9 | `NATIVE_CHAT = !!window.__forkNativeChat`: страница прячет чат, не принимает `chat` (и шифрованные `chat` в браузере), не пересказывает журнал в `state`. | Повторить правку в `onMessage`, ответе на `hello`, `adoptState` и `start()`. |
| `pocketbase/pb_public/watch/pair.js` | S9 | `hello` вкладки браузера несёт `web: true`. | Повторить. |
| `lib/main.dart` (E2E) | E2E-max | После `LocalStore.ensureOwner` — `unawaited(ForkE2E.ensure(uid))`, импорт. | Повторить: без поднятых ключей профиль и записи без пары не уходят вовсе. |
| `lib/services/pb_auth_service.dart` (E2E) | E2E-max | `signUpWithEmail`: в `create` нет `name`/`display_name`. `_ensureProfile`: сначала `ForkE2E.ensure`, затем запись профиля перечитывается (`getOne`) и кладётся в `authStore`. | Повторить: иначе имя уходит открытым при регистрации. |
| `lib/services/pb_data_service.dart` (E2E) | E2E-max | `startDate` пары — `start_date ?? created_at`. `waitingCreate` шлёт имя-заглушку `ForkE2E.waitingNameOnServer`, затем `ForkE2E.sealWaiting`; `waitingUpdate` целиком — `ForkE2E.sealWaiting`. `loadPartnerCard` — через `ForkProfile.partnerCard`. Импорты `fork_e2e.dart`, `profile.dart`. | Повторить. Новые поля карточки партнёра — добавить и в `ForkProfile`. |
| `lib/services/couple_stats_service.dart` | E2E-max | Ответ статистики правится `ForkE2E.patchCoupleStats`: даты пары из расшифрованной записи. Импорт. | Повторить. |
| `lib/services/canvas_repository.dart`, `lib/services/live_location_service.dart` (E2E) | E2E-max | Нет ключа пары — живой штрих и точка не публикуются вовсе (`sealLive`/`sealPoint` вернули null). | Повторить. |
| `pocketbase/pb_hooks/gifts.pb.js`, `pocketbase/pb_hooks/chest.pb.js` | E2E-max | Поля подарка шифром (`e2e1.…`) не режутся и не разбираются: записка, ответ, место, дата, снимок, звук и его meta. | Взять версию апстрима и повторить ветки `sealed(...)`. Новое поле подарка — добавить в `E2EHttpClient._giftRoutes` и `e2eFields['gifts']`. |
| `pocketbase/pb_hooks/groups.pb.js` | E2E-max | `patch-map` пускает ещё `member_birthdays` и `member_cards`. | Повторить список. |
| `pocketbase/pb_hooks/users_guard.pb.js` | E2E-max | Шифрованные имя или аватар профиля в карты пары не копируются (`sealedProfile`). | Повторить: иначе шифр личного ключа затрёт имя под ключом пары. |
| `pocketbase/pb_hooks/invite_web.pb.js` | E2E-max | Шифрованное имя пригласившего на публичную страницу не попадает. | Повторить. |
| `lib/services/chat_service.dart`, `lib/services/presence_service.dart` | E2E-max | «Печатает» и «в сети» уходят `ForkE2E.sealSignal` (нет ключа — не шлём), приём — через `ForkE2E.openSignal`. Импорт. | Повторить: открытые сигналы принимать нельзя — их может подделать сервер. |
| `lib/services/watch_channel_service.dart` | E2E-max | Сигнализация звонка (`voice-*`: SDP с отпечатком DTLS, ICE) — только шифром ключа пары; открытые `voice-*` отбрасываются. Импорт. | Повторить: открытый SDP даёт серверу встать посередине звонка. |
| `lib/services/watch_videos_service.dart` | E2E-max | Ссылки на ролик и обложку — `pb://watch_videos/…`: показ и плеер идут через токен и локальный прокси расшифровки. | Повторить. |
| `lib/services/watch_history_service.dart` | E2E-max | Дубль истории ищется у себя (адрес шифром), а не фильтром `url = …` на сервере. | Повторить. |
| `lib/screens/setup_screen.dart` (пароль), `lib/widgets/settings/change_password_sheet.dart` | Пароль | Пароль аккаунта по правилам пароля бэкапа (`ForkAccountPassword`, `ForkPasswordChecks`): 12 символов, все классы, без утечек и почты. Индикаторы апстрима `_buildPasswordChecks` и импорт `password_rules` убраны. | Повторить. |
| `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/com/togetherly/love/MainActivity.kt`, `android/app/src/main/kotlin/com/togetherly/love/ForkFcmService.kt` | S12 | Канал `love_app/fcm` — по `ForkFcmService`. firebase-messaging снова в зависимостях, плагин google-services — только при `google-services.json`; сервис `.ForkFcmService` вместо `.FcmService` апстрима; канал отвечает по `ForkFcmService.available/token`. | Повторить; `FcmService.kt` апстрима не возвращать. |
| `lib/services/fcm_service.dart` | S12 | Токен — в `/api/fork/push-token` (`ForkPushToken`) вместо `users.fcm_token`; `ready` ещё и при `ForkPushToken.accepted`. | Повторить. |
| `lib/services/centrifugo_service.dart` | S12 | Разбор публикации вынесен в `_dispatch`, `deliver` отдаёт слушателям публикацию из будильника FCM. | Повторить. |
| `lib/services/widget_background_refresh_service.dart`, `lib/models/user_data.dart` | S12 | Задача `fcmWake` диспетчера → `ForkFcmWake.run`; при выходе (`logout`) токен забывается. | Повторить. |
| `lib/services/watch_voice_service.dart` | Ленты UX | Входящий звонок: зов при выключенном микрофоне показывается (`ringingFrom`), `decline` шлёт `voice-decline`; звонящий повторяет зов раз в 4 с и снимает его через 45 с; «вежливая» сторона отвечает зовом. | Повторить. |
| `lib/screens/together/watch_room_screen.dart` (звонок, чат ленты) | Ленты UX | Карточка `ForkIncomingCall`, `onUnanswered`; в ленте флаг `__forkNativeChat` и мост `forkChat` к `ForkReelsChatBridge`. | Повторить. |
| `lib/widgets/reels/reels_start_sheet.dart` | Ленты UX | Строка `ForkReelsAccountRow`: вход в аккаунт площадки. | Повторить. |
| `lib/widgets/mood_pack_selector.dart` | UX W1 | M2: закрытые наборы за деньги скрыты, `buyMoodPack` не ведёт на lava.top при `allFree`. | Повторить. |
| `lib/screens/widget_screen.dart` | UX W1 | M3: рекламная проба фото виджета дней скрыта при `allFree`. | Повторить. |
| `lib/screens/gifts/gift_shop_screen.dart` | UX W1 | M4: при «Бесплатно» нет «Не хватает монет». | Повторить. |
| `lib/screens/gifts/gift_receive_sheet.dart` | UX W1 | M6: отказ «Не сейчас» — `ForkNotice.failure`. | Повторить. |
| `lib/services/chest_service.dart` | UX W1 | M7: `stashOutcome()` (сбой запроса/каталога — `Failed`), `stash()` как раньше. | Повторить. |
| `lib/screens/chest_screen.dart` | UX W1 | M7: `_restoreStash` показывает сбой с «Повторить»; M11: в таблице шансов нет призов Плюса при `allFree`. | Повторить. |
| `lib/screens/profile_screen.dart` (UX W1) | UX W1 | M12: код из бота и «Восстановить покупки» под флагами; N7: нет строки «Смотреть видео»; N14: без паков монет заголовок «Заработать»; N2: настройки уведомлений через `lib/fork/system_settings.dart`; A4: подтверждение выхода через `ForkLogoutGuard.message`; A14: 401 при удалении — `deleteAccountReauth`. | Повторить. |
| `lib/screens/profile/profile_hero.dart` | UX W1 | N4: тап по фото — правка профиля, рамки — отдельная кнопка слева внизу. | Повторить. |
| `test/widgets/profile_hero_tap_test.dart` | UX W1 | N4: тап по аватару — правка фото, рамки — кнопка `filter_frames_rounded`. | Повторить. |
| `pocketbase/pb_public/watch/reels/reels.js`, `pocketbase/pb_public/watch/reels/index.html` | Ленты UX | Кнопка «назад» и в приложении на Android; с `__forkNativeChat` реплики идут мостом `forkChat`, приходят `window.forkChatIn`, открытый `chat` и история `state` игнорируются; версия скрипта в index.html поднята. Замер «ролик не пошёл» (апстрим, обращение 407) без Umami не пингует площадки. | Повторить. |
| `test/chest_open_never_hangs_test.dart`, `test/reels_invite_wiring_test.dart`, `test/android_widget_wake_test.dart` | S2 | Убраны проверки удалённого кода (rewarded-SDK, `FcmService.kt`). | Повторить: проверки удалённого кода не возвращать. |
| `test/rewarded_ad_never_hangs_test.dart`, `test/services/rewarded_ad_failure_report_test.dart`, `test/widgets/ad_banner_network_test.dart`, `test/ios_no_purchases_test.dart`, `test/ios_plus_only_purchase_test.dart` | S2 | Удалены: проверяли удалённые реализацию рекламы и IAP. | Оставить удалёнными. |
| `lib/screens/memory_lane_screen.dart` | UX-W3 | D1/D6: заливка фото через `uploadPhotosConfirmed` (`lib/fork/memories/photo_batch.dart`) — «загружено N из M», повтор или отказ. D2: `_saveNewMemory` возвращает `bool`, форма фото закрывается только по успеху. D5: музыка через `uploadFileWithReason`, при сбое запись не сохраняется. D13: `ForkNotice.error` вместо текста исключения. D10: `_matchesQuery` → `memoryMatchesQuery` (`lib/fork/memories/search.dart`). Удалён неиспользуемый `_uploadMemoryPhoto`. | Повторить помеченные `fork:` места; `_saveNewMemory` должен остаться `Future<bool>`, три `return;` на сбое — `return false`. |
| `lib/screens/memory_photo_form_screen.dart` | UX-W3 | D2: `_save` ждёт `onSave`, закрывает форму после успеха; `MemorySaveAborted` — форма остаётся, любая другая ошибка — `ForkNotice.error`. | Повторить `_save` и три импорта. |
| `lib/screens/memory_lane/media_widgets.dart` | UX-W3 | D7: видеоплеер — индикатор буферизации, ошибка посреди просмотра, кнопка «Повторить» (`_retry`). | Повторить три помеченных куска в `_InAppVideoPlayerPageState`. |
| `lib/screens/draw_screen.dart` | UX-W3 | D3: очистка холста по результату `_canvas.clear` с откатом и `ForkNotice`. D4: картинка/заливка — `uploadFileWithReason` + `showUploadFailure`, заливка ведром не молчит; раскраска в воспоминания бросает `ForkFailureError`. D8: `_inviteToDraw` показывает «Позвали партнёра». | Повторить помеченные `fork:` места. |
| `lib/screens/draw_gallery_screen.dart` | UX-W3 | D9: `_deleteSelected` считает отказы, оставляет их выбранными, показывает `ForkNotice` с повтором. | Повторить блок после подтверждения удаления. |
| `lib/screens/mascot_gallery_screen.dart` | UX-W3 | M10: картинка маскота не загрузилась — правка отменяется с сообщением, пустой холст не открывается. | Повторить `catch` в `_openDrawScreen`. |
| `lib/services/canvas_storage_service.dart` | UX-W3 | D9: `deleteCanvas` возвращает `bool`; для пары сперва удаляет запись на сервере, локально — только по успеху. | Повторить тело `deleteCanvas`. |
| `lib/services/canvas_repository.dart` | UX-W3 | D3/D9: `clear` и `deleteCatalogue` возвращают `bool` вместо `void`, чтобы экран знал итог. | Повторить два возвращаемых типа. |
| `lib/services/pb_data_service.dart` | UX-W3 | D3: в `clearCanvas` удаление штриха с 404 не валит очистку (`try`/`on ClientException`). | Повторить цикл удаления штрихов. |
| `lib/screens/settings_screen.dart` | Волна 2 UX | N1,N6,N8–N10,N14,N15: секция «Шифрование» (`ForkEncryptionSection` из `lib/fork/ui/settings_parts.dart`) вместо строки в «О приложении»; «Аккаунт» вверху и не красный; удаление отдельной группой внизу; Плюс скрыт при `allFree`; «Поддержка»/«Официально» скрыты при пустом адресе; секции переименованы, рисование и боковая кнопка в своей секции. | Повторить: порядок секций, `ForkEncryptionSection` первой, `if (… isNotEmpty) // fork` у почт. |
| `lib/screens/home/home_header.dart` | Волна 2 UX | N5,N13: тап по аватару — профиль (партнёра — `PartnerProfileScreen`, свой — `onOpenTab(3)`), долгое нажатие — фото; пилюля «Не в паре» — `onOpenTab(2)`. Параметр `onOpenTab`. | Повторить; `home_screen.dart` должен передавать `onOpenTab`. |
| `lib/screens/home/home_bottom_nav.dart` | Волна 2 UX | N11: подпись, Tooltip и подсказка долгого нажатия у круглой кнопки. | Повторить. |
| `lib/screens/miss_you_button.dart` | Волна 2 UX | M8,N12: откат счётчика на всю пачку, повтор не больше 2 раз, ошибка через `ForkNotice`; Semantics/Tooltip у счёта и сердца. | Повторить. |
| `lib/screens/miss_you_screen.dart` | Волна 2 UX | M5: вайб — сердечки после ответа, ошибка через `ForkNotice` с «Повторить». | Повторить. |
| `lib/models/optimistic_count.dart` | Волна 2 UX | M8: `failed({count})` снимает всю пачку. | Повторить. |
| `lib/models/password_change.dart` | Волна 2 UX | A15: минимум пароля — `PasswordPolicy.minLength` (12). | Повторить. |
| `lib/screens/wishes_screen.dart` | Волна 2 UX | D11: видимая кнопка «Удалить» у своего желания. | Повторить. |
| `lib/screens/memory_lane/detail.dart` | Волна 2 UX | D11: видимая кнопка удаления у своего комментария. | Повторить. |
| `lib/widgets/draw/draw_tools_panel.dart` | Волна 2 UX | D12: иконка ластика (`backspace`) вместо «палочки». | Повторить. |
| `lib/screens/live_map_screen.dart` | Волна 2 UX | G16: без точек — весь мир, а не Кишинёв; своя строка ошибки «скучаю». | Повторить. |
| `pocketbase/pb_public/watch/room/room.js` | Волна 2 UX | V13,V14: значок и подпись кнопки полного экрана по состоянию; поле ссылки возвращает адрес на `blur`. | Повторить правки в `setCinema` и обработчике `#link`. |
| `pocketbase/pb_public/watch/room/index.html` | Волна 2 UX | Версии скриптов `i18n.js`/`room.js` подняты (`<!-- fork -->`). | Повторить. |
| `pocketbase/pb_public/watch/i18n.js` | Волна 2 UX | V13: ключи `room.cinema`, `room.cinemaExit` (ru, en). | Повторить. |
| `test/models/optimistic_count_test.dart` | Волна 2 UX | Тесты `failed(count)`. | Сохранить. |
| `test/models/password_change_test.dart` | Волна 2 UX | Минимум 12 символов. | Сохранить. |


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
| `lib/screens/login_screen.dart` | UX A1 | В `_signInAllowingTypo` при `ForkFlags.strictLogin` — `rethrow` до перебора «опечаточных» доменов; импорт `fork/flags.dart`. | Повторить строку с `rethrow` и импорт. |
| `lib/services/live_location_service.dart` (UX) | UX G1, G2, G12 | Согласие на показ привязано к партнёру и входу (`LocationConsent` из `lib/fork/location_consent.dart`: `remember` в `setSharingEnabled`, `allows` в `startSharing`); «Выключить» удаляет точку и шлёт в канал шифрованный `{'t': 'stop'}` (`_announceStop`), даже если стрим не стартовал; `_watchPoint` по `stop` или удалению записи сбрасывает точку; уведомление FGS `setOngoing: true`. | Повторить строки с `// fork (UX G…)`. |
| `lib/services/chat_service.dart`, `lib/screens/chat_screen.dart` (UX) | UX C1 | `send` до кэша и очереди проверяет `ForkE2E.canSeal(groupId)`; нет ключа — `false` и `lastSendFailure = ForkFailure.noKey`. Экран при `false` с известной причиной показывает `ForkNotice.failure` вместо общего «не отправилось». Импорт `fork/ui/feedback.dart` в обоих. | Повторить строки с `// fork (UX C1)`. |
| `lib/services/watch_voice_service.dart`, `lib/services/watch_channel_service.dart`, `lib/screens/together/watch_room_screen.dart` (UX звонок) | UX L2–L5, L7, L12 | Сервис: стадии `VoiceStage` и причина `VoiceProblem` (`lib/fork/watch/voice_stage.dart`), `_setStage`, таймер соединения 30 с после отклика, один ICE restart перед «не вышло», «восстанавливаем» при обрыве посреди разговора, `start()` после `failed` начинает заново, `dismissFailure`, `debugStage`. Канал: `send` возвращает `bool`, причина в `lastFailure` (нет ключа / сеть). Экран: `ForkVoiceStatus` (`lib/fork/watch/voice_status.dart`) в Stack, повтор подключения канала через 5 с, «позвонить» без канала и после сбоя не молчит; `onUnanswered` и `voiceNoPermission` больше не дублируют плашку. | Повторить строки с `// fork (UX L…)`; при конфликте сервиса — взять апстрим и вернуть стадии по этой строке. |
| `pocketbase/pb_public/watch/room/room.js`, `pocketbase/pb_public/watch/room/index.html`, `pocketbase/pb_public/watch/i18n.js` (UX) | UX L8, L15 | `setViewers`: приход и уход партнёра (дребезг 4 с) — строкой в чате и плашкой `note`; `joinedAt: -Infinity`. `netBanner` — плашка «нет связи», пока канал не `ready`. Ключ `room.partnerLeft` (ru/en). В index.html подняты версии `i18n.js` и `room.js` с пометкой `<!-- fork -->`. | Повторить строки с `fork (UX L…)`, версии — новее апстримовских. |
| `pocketbase/pb_public/watch/reels/reels.js` (UX) | UX L8, L11, L15 | `onViewers`: приход и уход (дребезг 4 с) — в чат и тостом; `netBanner` при `offline`/`lost`; «▶» (`is-paused`) сверяется с событием плеера «играю» (`S.pausedAt`): сначала повторная пауза, потом верим плееру. Версия в index.html поднята. | Повторить строки с `fork (UX L…)`. |
| `pocketbase/pb_public/watch/room/room.js`, `lib/screens/together/watch_room_screen.dart` (UX видео) | UX V2, V6, V7, V8 | room.js: у YouTube `onError` с причиной (запрет встраивания, удалён, сбой), «Открываем…» до `onReady`, медленный API — словами; свой файл, который не декодируется, — «нужен MP4 или WebM», партнёру уходит только после `loadedmetadata`; пилюля зрителей в полном экране (`cinemaViewers`); `window.forkExitCinema`. Экран: «назад» сначала зовёт `forkExitCinema` (`_onBack`). Ключи `room.opening`, `room.yt*`, `room.badFile` в i18n.js. | Повторить строки с `fork (UX V…)`. |
| `pocketbase/pb_public/watch/reels/reels.js` (UX лента) | UX L9, L10, L13 | `armStall`: через 20 с без роликов — «Площадка не отдаёт ролики» и «Попробовать ещё раз»; «Обновить» говорит, что подбирает, и возвращает запас, если новых нет; свайп ведомого — тост с подсказкой «Листать мне» (не чаще раза в 15 с). Версии в index.html (и i18n.js) подняты. | Повторить строки с `fork (UX L…)`. |
