#!/usr/bin/env bash
# Обновление сервера на версию sha-… с проверкой здоровья и откатом
# (deploy/README.md, «Деплой скриптом»).
#   ./deploy.sh sha-1a2b3c4
#
# Запоминает текущий TETHERED_VERSION из .env, вписывает новый, тянет образ,
# поднимает compose и ждёт здоровья: сервер — /api/health через Caddy,
# Centrifugo — /health изнутри сети compose. Не дождались — возвращает
# прежний sha-… в .env, поднимает снова и выходит с ошибкой.
#
# Настройки (переменные окружения):
#   DEPLOY_TIMEOUT        сколько секунд ждать здоровья (120)
#   DEPLOY_INTERVAL       пауза между проверками, секунды (5)
#   DEPLOY_HEALTH_URL     адрес здоровья сервера (https://<домен>/api/health)
#   DEPLOY_RESOLVE        куда curl резолвит домен (<домен>:443:127.0.0.1 —
#                         к своему Caddy, мимо DNS); пусто — обычный DNS
#
# Коды выхода: 0 — обновлено; 1 — не обновлено (версия отклонена, образа
# нет, здоровья не дождались и откат удался); 2 — откат тоже не здоров.
set -euo pipefail
cd "$(dirname "$0")"

timeout=${DEPLOY_TIMEOUT:-120}
interval=${DEPLOY_INTERVAL:-5}

say() { echo "deploy: $*"; }
die() { echo "deploy: $*" >&2; exit 1; }

target=${1:-}
if [[ ! "$target" =~ ^sha-[0-9a-f]{7,40}$ ]]; then
  die "использование: $0 sha-<коммит>, например $0 sha-1a2b3c4. Только sha-…: \`latest\` и другие теги не принимаются (deploy/README.md, «Обновление»)"
fi
[ -f .env ] || die "нет .env рядом со скриптом — сначала ./init-env.sh <домен>"

# Значение KEY из .env без кавычек; секреты не читаем и не печатаем.
env_get() { sed -n "s/^$1=//p" .env | tail -n1 | tr -d "\"'"; }

set_version() {
  if grep -q '^TETHERED_VERSION=' .env; then
    sed -i "s/^TETHERED_VERSION=.*/TETHERED_VERSION=$1/" .env
  else
    echo "TETHERED_VERSION=$1" >> .env
  fi
}

original=$(env_get TETHERED_VERSION)
previous=$original
domain=$(env_get TETHERED_DOMAIN)
[ -n "$domain" ] || [ -n "${DEPLOY_HEALTH_URL:-}" ] || die "в .env нет TETHERED_DOMAIN — не знаю, где проверять здоровье"
health_url=${DEPLOY_HEALTH_URL:-https://$domain/api/health}
resolve=${DEPLOY_RESOLVE-$domain:443:127.0.0.1}

if [[ ! "$previous" =~ ^sha-[0-9a-f]{7,40}$ ]]; then
  previous=""
  say "внимание: в .env нет прежней версии sha-… — откатываться будет некуда"
else
  say "сейчас: $previous"
fi
say "ставлю: $target"

healthy_once() {
  local args=(-fsS -o /dev/null --max-time 5)
  [ -n "$resolve" ] && args+=(--resolve "$resolve")
  curl "${args[@]}" "$health_url" || return 1
  # Порт Centrifugo наружу не опубликован: спрашиваем из контейнера сервера.
  docker compose exec -T server wget -qO /dev/null http://centrifugo:8000/health || return 1
}

wait_healthy() {
  local deadline=$((SECONDS + timeout))
  while true; do
    if healthy_once >/dev/null 2>&1; then return 0; fi
    if ((SECONDS >= deadline)); then return 1; fi
    sleep "$interval"
  done
}

set_version "$target"
if ! docker compose pull server; then
  set_version "$original"
  die "образ $target не скачался (нет такого тега или нет доступа к GHCR) — ничего не менял, .env вернул как было"
fi
if docker compose up -d; then
  say "жду здоровья сервера и Centrifugo до ${timeout} с…"
  if wait_healthy; then
    say "готово: $target здоров. Точка отката — ${previous:-нет}"
    exit 0
  fi
  say "ОШИБКА: $target не стал здоровым за ${timeout} с" >&2
else
  say "ОШИБКА: docker compose up -d с $target не прошёл" >&2
fi
say "журнал: docker compose logs --tail=100 server centrifugo" >&2
if [ -z "$previous" ]; then
  die "откатываться некуда: прежней версии sha-… не было. В .env остался $target"
fi

say "откат на $previous…" >&2
set_version "$previous"
if docker compose up -d && wait_healthy; then
  say "откат удался: работает $previous. Миграции новой версии назад не откатываются — если менялась схема, смотрите «Обновление» в deploy/README.md" >&2
  exit 1
fi
say "ОШИБКА: и после отката на $previous сервис не здоров — нужна ручная проверка" >&2
exit 2
