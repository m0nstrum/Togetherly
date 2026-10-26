#!/usr/bin/env bash
# Паритет с апстримом (PLAN S5): тесты автора против нашего сервера.
#
#   - JS-тесты хуков из server/pb_hooks (*.test.js);
#   - живые регрессы pocketbase/*.test.py из parity.allow: они бьют в прод
#     автора, поэтому адреса подменяются во временной копии, их файлы не
#     трогаем;
#   - свои сценарии форка из scripts/e2e.
#
# Поднимает свой бинарник и Centrifugo в Docker (нужен регрессу инвайтов).
#   server/scripts/parity.sh
#   CENTRIFUGO_IMAGE=mirror.gcr.io/centrifugo/centrifugo:v6 server/scripts/parity.sh
# Нужны go, node, python3 с пакетами websockets и cryptography, docker.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
up="$here/../pocketbase"
work=$(mktemp -d)
port=${PARITY_PORT:-18190}
cf_port=${PARITY_CENTRIFUGO_PORT:-18100}
cf_name="tethered-parity-$$"
cleanup() {
  if [ -n "${pid:-}" ]; then kill "$pid" 2>/dev/null || true; fi
  docker rm -f "$cf_name" >/dev/null 2>&1 || true
  if [ -n "${PARITY_LOG:-}" ]; then cp "$work/server.log" "$PARITY_LOG"; fi
  rm -rf "$work"
}
trap cleanup EXIT

failed=0
run() { # имя, команда...
  local name=$1; shift
  if "$@" >"$work/out.txt" 2>&1; then
    echo "ok: $name ($(tail -1 "$work/out.txt"))"
  else
    echo "FAIL: $name" >&2
    cat "$work/out.txt" >&2
    failed=1
  fi
}

# 1. Тесты хуков: чистая логика, сервер не нужен.
for t in "$here"/pb_hooks/*.test.js; do
  [ -e "$t" ] || continue
  run "hook $(basename "$t" .test.js)" node "$t"
done

# 2. Живые регрессы.
secret="parity-$$"
docker run -d --name "$cf_name" -p "127.0.0.1:$cf_port:8000" \
  -v "$here/../deploy/centrifugo:/centrifugo:ro" \
  -e CENTRIFUGO_CLIENT_TOKEN_HMAC_SECRET_KEY="$secret" \
  -e CENTRIFUGO_HTTP_API_KEY="$secret" \
  -e CENTRIFUGO_CLIENT_ALLOWED_ORIGINS='*' \
  "${CENTRIFUGO_IMAGE:-centrifugo/centrifugo:v6}" centrifugo --config=/centrifugo/config.json >/dev/null

(cd "$here" && go build -o "$work/tethered" ./cmd/tethered)
TETHERED_HTTP_ADDR="127.0.0.1:$port" \
TETHERED_DATA_DIR="$work/pb_data" \
TETHERED_HOOKS_DIR="$here/pb_hooks" \
TETHERED_RATE_LIMITS=false \
TETHERED_CENTRIFUGO__API="http://127.0.0.1:$cf_port/api" \
TETHERED_CENTRIFUGO__API_KEY="$secret" \
CENTRIFUGO_TOKEN_HMAC="$secret" \
  "$work/tethered" >"$work/server.log" 2>&1 &
pid=$!

for _ in $(seq 1 100); do
  curl -fsS "http://127.0.0.1:$port/api/health" >/dev/null 2>&1 \
    && curl -fsS "http://127.0.0.1:$cf_port/health" >/dev/null 2>&1 && break
  sleep 0.2
done
curl -fsS "http://127.0.0.1:$port/api/health" >/dev/null || { cat "$work/server.log"; echo "сервер не поднялся" >&2; exit 1; }

grep -vE '^[[:space:]]*(#|$)' "$here/parity.allow" | while read -r name; do
  src="$up/$name"
  [ -f "$src" ] || { echo "нет $name в pocketbase/ (апстрим переименовал?)" >&2; exit 1; }
  sed -e "s#^BASE = .*#BASE = \"http://127.0.0.1:$port\"#" \
      -e "s#^WS = .*#WS = \"ws://127.0.0.1:$cf_port/connection/websocket\"#" \
      -e 's#ssl=ssl.create_default_context(), ##' \
      "$src" >"$work/$name"
  # Verify/unwrap H3 transport only in the disposable test copy.
  python3 "$here/scripts/adapt-realtime-test.py" "$work/$name" "$work/$name"
  # Сторож: в копии не осталось адресов автора.
  if grep -nE 'togetherly\.(day|app)' "$work/$name" | grep -vE ':[0-9]+:[[:space:]]*#' >&2; then
    echo "FAIL: $name — адрес автора не подменён" >&2
    exit 1
  fi
  (cd "$work" && PARITY_API_KEY="$secret" timeout 180 python3 -I "$name") >"$work/out.txt" 2>&1 && status=0 || status=$?
  if [ "$status" = 0 ]; then
    echo "ok: $name ($(tail -1 "$work/out.txt"))"
  else
    echo "FAIL: $name" >&2
    cat "$work/out.txt" >&2
    exit 1
  fi
done || failed=1

# 3. Свои сценарии форка поверх того же стека (scripts/e2e).
for t in "$here"/scripts/e2e/*.test.py; do
  adapted="$work/$(basename "$t")"
  python3 "$here/scripts/adapt-realtime-test.py" "$t" "$adapted"
  run "$(basename "$t")" env PARITY_API_KEY="$secret" BASE="http://127.0.0.1:$port" \
    WS="ws://127.0.0.1:$cf_port/connection/websocket" timeout 180 python3 -I "$adapted"
done

exit "$failed"
