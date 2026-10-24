#!/usr/bin/env bash
# Disposable broker using the actual deployment namespaces; no production data.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
name="tethered-realtime-test-$$"
port=${BROKER_TEST_PORT:-18100}
cleanup() { docker rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT
docker create --name "$name" -p "127.0.0.1:$port:8000" \
  -e CENTRIFUGO_CLIENT_TOKEN_HMAC_SECRET_KEY=h3-test-secret \
  -e CENTRIFUGO_HTTP_API_KEY=h3-test-api \
  centrifugo/centrifugo:v6 centrifugo --config=/tmp/config.json >/dev/null
docker cp "$here/../../deploy/centrifugo/config.json" "$name:/tmp/config.json"
docker start "$name" >/dev/null
for _ in $(seq 1 50); do
  if curl -fsS "http://127.0.0.1:$port/health" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
BROKER_URL="http://127.0.0.1:$port" node "$here/realtime-broker.test.cjs"
