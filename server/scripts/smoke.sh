#!/usr/bin/env bash
# Смоук сервера: настоящий бинарник, JS-хуки по hooks.allow, пустая база.
# Проверяет критерий S4: регистрация и вход, пара по коду приглашения,
# сообщение в чат, которое видит партнёр, токен Centrifugo.
#
#   server/scripts/smoke.sh                                  # свой бинарник
#   SMOKE_BASE=https://tethered.example.org server/scripts/smoke.sh  # живой инстанс
#
# На живом инстансе заводятся два пользователя smoke-<время>@example.org.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
port=${SMOKE_PORT:-18090}
base=${SMOKE_BASE:-"http://127.0.0.1:$port"}
cleanup() {
  if [ -n "${pid:-}" ]; then kill "$pid" 2>/dev/null || true; fi
  if [ -n "${SMOKE_LOG:-}" ]; then cp "$work/server.log" "$SMOKE_LOG"; fi
  rm -rf "$work"
}
trap cleanup EXIT

touch "$work/server.log"
if [ -z "${SMOKE_BASE:-}" ]; then
(cd "$here" && go build -o "$work/tethered" ./cmd/tethered)
"$here/scripts/sync-hooks.sh" "$work/pb_hooks" >/dev/null

TETHERED_HTTP_ADDR="127.0.0.1:$port" \
TETHERED_DATA_DIR="$work/pb_data" \
TETHERED_HOOKS_DIR="$work/pb_hooks" \
TETHERED_RATE_LIMITS=false \
TETHERED_PUBLIC_DIR="$here/../pocketbase/pb_public" \
CENTRIFUGO_TOKEN_HMAC="smoke-secret" \
  "$work/tethered" >"$work/server.log" 2>&1 &
pid=$!
fi

curl() { command curl ${SMOKE_INSECURE:+-k} "$@"; }

for _ in $(seq 1 100); do
  curl -fsS "$base/api/health" >/dev/null 2>&1 && break
  sleep 0.2
done
curl -fsS "$base/api/health" >/dev/null || { cat "$work/server.log"; echo "сервер не поднялся" >&2; exit 1; }

json() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1], {'d': d}))" "$1"; }
fail() { echo "FAIL: $*" >&2; tail -40 "$work/server.log" >&2; exit 1; }

post() { # url token body
  curl -sS -X POST "$base$1" -H 'Content-Type: application/json' ${2:+-H "Authorization: $2"} -d "$3"
}
get() { # url token
  curl -sS "$base$1" ${2:+-H "Authorization: $2"}
}

tag=${SMOKE_BASE:+-$(date +%s)}
for who in alice bob; do
  post /api/collections/users/records "" \
    "{\"email\":\"$who$tag@example.org\",\"password\":\"password123\",\"passwordConfirm\":\"password123\",\"display_name\":\"$who\"}" \
    | json "d['id']" >/dev/null || fail "регистрация $who"
done

login() {
  post /api/collections/users/auth-with-password "" "{\"identity\":\"$1$tag@example.org\",\"password\":\"password123\"}"
}
alice=$(login alice); bob=$(login bob)
atok=$(echo "$alice" | json "d['token']"); aid=$(echo "$alice" | json "d['record']['id']")
btok=$(echo "$bob" | json "d['token']"); bid=$(echo "$bob" | json "d['record']['id']")
echo "ok: регистрация и вход"

code=$(python3 -c "import random; print(''.join(random.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(6)))")
post /api/collections/invite_codes/records "$atok" "{\"code\":\"$code\",\"owner_uid\":\"$aid\"}" \
  | json "d['id']" >/dev/null || fail "код приглашения"
accept=$(post /api/invite/accept "$btok" "{\"code\":\"$(echo "$code" | tr 'A-Z' 'a-z')\"}")
pair=$(echo "$accept" | json "d['pairId']") || fail "приём кода: $accept"
echo "ok: пара $pair"

get "/api/collections/groups/records/$pair" "$btok" | json "d['id']" >/dev/null || fail "партнёр не видит пару"
get "/api/collections/groups/records/$pair" "$atok" | json "d['id']" >/dev/null || fail "приглашающий не видит пару"

post /api/collections/chat_messages/records "$atok" \
  "{\"group_id\":\"$pair\",\"user_uid\":\"$aid\",\"text\":\"привет\",\"ts\":1}" | json "d['id']" >/dev/null \
  || fail "сообщение в чат"
n=$(get "/api/collections/chat_messages/records?filter=group_id%3D%22$pair%22" "$btok" | json "d['totalItems']")
[ "$n" = "1" ] || fail "партнёр видит $n сообщений вместо 1"
echo "ok: чат"

post /api/centrifugo/connection-token "$btok" '{}' | json "d['token']" >/dev/null || fail "токен Centrifugo"
echo "ok: токен Centrifugo"

ice=$(get /api/watch/rtc "$btok")
echo "$ice" | json "d['success']" | grep -q True || fail "watch/rtc: $ice"
echo "ok: watch/rtc"

# Доп. проверка поверх готовой пары (например, обмен ключами E2E клиента:
# test/fork/e2e/live_test.dart). Команда получает адрес, токены и пару.
if [ -n "${SMOKE_AFTER:-}" ]; then
  SMOKE_BASE_URL="$base" SMOKE_PAIR="$pair" SMOKE_AID="$aid" SMOKE_BID="$bid" \
  SMOKE_ATOK="$atok" SMOKE_BTOK="$btok" sh -c "$SMOKE_AFTER" || fail "SMOKE_AFTER: $SMOKE_AFTER"
  echo "ok: $SMOKE_AFTER"
fi

if grep -q '"level":"ERROR"' "$work/server.log"; then
  grep '"level":"ERROR"' "$work/server.log" >&2
  fail "ошибки в журнале сервера"
fi
echo "смоук пройден"
