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

- `flutter analyze --no-fatal-infos` — падает на warning и error;
- `flutter test`;
- release APK под arm64 (debug-подпись) и проверка `applicationId`/имени в нём.

Воркфлоу апстрима остаются в репозитории, чтобы не конфликтовать при мёржах.
Форку они не нужны, их стоит выключить: **Settings → Actions** или страница
воркфлоу → `…` → **Disable workflow**. Это все `ios-*.yml` и `release-apk.yml`
(публикует в Play/RuStore/App Store и требует секретов автора).
`android-widget-compile.yml` и `android-sound-clip.yml` можно оставить.

## Локальная сборка

```sh
flutter pub get
flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons
```

Нужен Flutter той же версии, что в `fork-ci.yml` (`FLUTTER_VERSION`).
`google-services.json` форку не нужен: без него Gradle не применяет плагин
Firebase, а клиент получает push через Centrifugo.
