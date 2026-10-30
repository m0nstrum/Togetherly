#!/usr/bin/env bash
# Тест deploy.sh на заглушках docker и curl (настоящий Docker не нужен):
# успешный деплой; провал здоровья → откат; нет образа; отказ на `latest`.
#   bash deploy/deploy.test.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Заглушки пишут вызовы в журнал вместе с версией из .env в этот момент.
# STUB_BAD — версия, которая не здорова; STUB_MISSING — образа нет в GHCR.
mkdir "$work/bin"
cat > "$work/bin/docker" <<'EOF'
#!/usr/bin/env bash
v=$(sed -n 's/^TETHERED_VERSION=//p' .env)
echo "docker $* @$v" >> "$STUB_LOG"
case "$*" in
  "compose pull server") [ "$v" != "${STUB_MISSING:-}" ] ;;
  "compose exec -T server wget"*) [ "$v" != "${STUB_BAD:-}" ] ;;
  *) true ;;
esac
EOF
cat > "$work/bin/curl" <<'EOF'
#!/usr/bin/env bash
v=$(sed -n 's/^TETHERED_VERSION=//p' .env)
echo "curl ${*: -1} @$v" >> "$STUB_LOG"
[ "$v" != "${STUB_BAD:-}" ]
EOF
chmod +x "$work/bin/docker" "$work/bin/curl"

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

# Свежая копия deploy.sh с .env (версия $1) в отдельном каталоге.
setup() {
  dir="$work/case-$RANDOM$RANDOM"
  mkdir "$dir"
  cp "$here/deploy.sh" "$dir/"
  printf 'TETHERED_VERSION=%s\nTETHERED_DOMAIN=tethered.example.org\nCENTRIFUGO_API_KEY=very-secret\n' "$1" > "$dir/.env"
  export STUB_LOG="$dir/calls.log"
  : > "$STUB_LOG"
}

# deploy.sh с заглушками; код выхода — в $code, вывод — в $out.
run() {
  set +e
  out=$(cd "$dir" && PATH="$work/bin:$PATH" DEPLOY_TIMEOUT=0 DEPLOY_INTERVAL=0 \
    STUB_BAD="${STUB_BAD:-}" STUB_MISSING="${STUB_MISSING:-}" ./deploy.sh "$@" 2>&1)
  code=$?
  set -e
}

version() { sed -n 's/^TETHERED_VERSION=//p' "$dir/.env"; }

expect() { # описание, ожидаемое, фактическое
  [ "$2" = "$3" ] || fail "$1: ждали «$2», получили «$3»"
}

expect_log() { grep -qF -- "$1" "$STUB_LOG" || fail "нет вызова «$1»; журнал:
$(cat "$STUB_LOG")"; }

no_secrets() { case "$out" in *very-secret*) fail "секрет в выводе" ;; esac; }

# 1. Успешный деплой: новая версия в .env, образ скачан, здоровье проверено.
setup sha-aaaaaaa
STUB_BAD= STUB_MISSING= run sha-bbbbbbb
expect "успех: код" 0 "$code"
expect "успех: версия" sha-bbbbbbb "$(version)"
expect_log "docker compose pull server @sha-bbbbbbb"
expect_log "docker compose up -d @sha-bbbbbbb"
expect_log "curl https://tethered.example.org/api/health @sha-bbbbbbb"
expect_log "docker compose exec -T server wget -qO /dev/null http://centrifugo:8000/health @sha-bbbbbbb"
no_secrets

# 2. Новая версия не здорова: откат на прежнюю, ненулевой код.
setup sha-aaaaaaa
STUB_BAD=sha-bbbbbbb run sha-bbbbbbb
expect "откат: код" 1 "$code"
expect "откат: версия" sha-aaaaaaa "$(version)"
expect_log "docker compose up -d @sha-bbbbbbb"
expect_log "docker compose up -d @sha-aaaaaaa"
expect_log "curl https://tethered.example.org/api/health @sha-aaaaaaa"
case "$out" in *"откат удался"*) ;; *) fail "откат: нет сообщения; вывод: $out" ;; esac
no_secrets

# 3. И прежняя версия не здорова: код 2.
setup sha-aaaaaaa
STUB_BAD=sha-aaaaaaa run sha-aaaaaaa
expect "откат не помог: код" 2 "$code"

# 4. Образа нет: compose не трогаем, .env как был.
setup sha-aaaaaaa
STUB_MISSING=sha-ccccccc run sha-ccccccc
expect "нет образа: код" 1 "$code"
expect "нет образа: версия" sha-aaaaaaa "$(version)"
if grep -q "up -d" "$STUB_LOG"; then fail "нет образа: compose up вызван"; fi

# 5. Отказ на latest, пустом аргументе и чужих тегах — ничего не вызвано.
for bad in latest "" v1.2.3 sha-XYZ sha-123 "sha-aaaaaaa;rm"; do
  setup sha-aaaaaaa
  run $bad
  expect "отказ «$bad»: код" 1 "$code"
  expect "отказ «$bad»: версия" sha-aaaaaaa "$(version)"
  [ -s "$STUB_LOG" ] && fail "отказ «$bad»: были вызовы: $(cat "$STUB_LOG")"
done

# 6. Без прежней sha-… провал здоровья не откатывается, но и не молчит.
setup latest
STUB_BAD=sha-bbbbbbb run sha-bbbbbbb
expect "без прежней: код" 1 "$code"
case "$out" in *"откатываться некуда"*) ;; *) fail "без прежней: нет сообщения; вывод: $out" ;; esac

if ((failures)); then
  echo "deploy.test.sh: провалов: $failures" >&2
  exit 1
fi
echo "ok: deploy.sh — успех, откат, нет образа, отказ на latest"
