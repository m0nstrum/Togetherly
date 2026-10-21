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
| `android/app/src/main/AndroidManifest.xml` | S0 | Все `android:label="Togetherly"` → `${appLabel}`. В фильтре приглашений `scheme="loveapp"` → `${appScheme}`. | Берём файл апстрима, повторяем замену: `sed -i 's/android:label="Togetherly"/android:label="${appLabel}"/'` и правку фильтра приглашений. Новые `android:label="Togetherly"` от апстрима тоже меняем — их ловит `test/fork/identity_test.dart`. |
| `lib/models/pair_data.dart` | S0 | `inviteDeepLink` → `ForkIdentity.inviteDeepLink(...)`, импорт `../fork/identity.dart`. | Повторить замену геттера и импорт. |
| `lib/models/connection.dart` | S0 | То же, что в `pair_data.dart`. | То же. |
| `lib/services/deep_link_service.dart` | S0 | Разбор `loveapp://invite/` → `ForkIdentity.inviteScheme`, импорт. | Повторить замену условия и импорт. |
| `test/models/invite_link_domain_test.dart` | S0 | Ожидание `loveapp://invite/HQ792S` → `tethered://invite/HQ792S`. | Повторить замену строки. |

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
- Воркфлоу апстрима в `.github/workflows/`: не правим, лишние выключаем в
  настройках Actions (см. [README.md](README.md)).
