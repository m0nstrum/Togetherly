# Мёрж апстрима

Апстрим — `THET1ME-1/togetherly`, remote `upstream` (`tool/fork/setup_upstream.sh`).
Мёржим, не ребейзим: история форка публичная.

## 1. Слить

```sh
git fetch upstream
git switch -c merge-upstream-$(date +%Y%m%d) main
git merge upstream/main
```

Конфликты — по [TOUCHPOINTS.md](TOUCHPOINTS.md): берём версию апстрима и
заново применяем правку из колонки «Что сделано». Файлы форка (`lib/fork`,
`server`, `deploy`, `docs/fork`, …) с апстримом не конфликтуют.

## 2. Быстрые проверки

```sh
python3 tool/fork/merge_check.py
```

| Проверка | Что значит провал |
|---|---|
| маркеры конфликтов | конфликт закоммичен неразрешённым |
| правки форка на месте | файл из реестра без пометки `fork` — при разрешении взяли версию апстрима и не вернули правку; удалённый форком файл (`FcmService.kt`, IAP) вернулся; пометка `fork` в файле не из реестра |
| убранные зависимости | в `pubspec.yaml` вернулась реклама, IAP, Firebase или OAuth |
| роуты клиента | апстрим зовёт новый `/api/...`, которого нет ни в Go, ни в хуках из `server/hooks.allow` — перенести или записать с причиной в `tool/fork/api_absent.txt` |
| состав апстрима | новые/пропавшие хуки, живые тесты, страницы `pb_public` — решить про `server/hooks.allow`, `server/parity.allow`, `server/public.allow`, затем `merge_check.py --update` |
| хуки и статика | хук из списка переименован; в страницах появился адрес автора — правило в `server/scripts/sync-public.sh` |

Те же проверки гоняет `Fork CI`.

## 3. Что проверить глазами

- Новые адреса автора: `test/fork/no_author_hosts_test.dart` (в CI) — новый
  хост в коде клиента нужно вынести в `Endpoints` или в исключения сторожа.
- Новые предупреждения анализатора — правка апстрима: `tool/fork/analyze_check.sh --update`.
- Новые платные развилки (`PlusService`, реклама, `kStore`) — под `ForkFlags`.
- Новые пуши через `apns_push.js` — у форка свой модуль (`server/hooks/apns_push.js`),
  API должен совпадать: новая функция апстрима — добавить и туда.
- Изменения схемы (`pocketbase/collections_schema.json`) — `cd server && go generate ./...`,
  новые коллекции — правила в `server/internal/domain/access/rules.go`.
- Разбор превью (`link_preview.pb.js`) — в `server/internal/domain/linkpreview`
  и `lib/fork/meta_direct.dart`; поиск фильмов (`hotpath/movies.py`) — в
  `server/internal/domain/movies` (жанры: `go generate`).

## 4. Полный прогон

```sh
python3 tool/fork/merge_check.py --full
```

Анализатор, тесты клиента (с `env/test.json` и `fork-runtime`), `go test`,
смоук и паритет (тесты автора против нашего сервера, нужен Docker). После —
PR в `main` с зелёным `Fork CI`.
