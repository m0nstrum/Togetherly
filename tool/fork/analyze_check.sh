#!/usr/bin/env bash
# flutter analyze для форка (docs/DEVELOPMENT.md, раздел CI).
#
# В апстриме есть свои предупреждения (неиспользуемые импорты и т.п.). Править
# их в чужих файлах — лишние конфликты, поэтому они записаны в
# tool/fork/analyze_baseline.txt (без номеров строк, чтобы правки выше по
# файлу не ломали сверку). Падаем, если:
#   - есть хоть одна ошибка;
#   - появилось предупреждение, которого нет в базовой линии.
# Обновить базовую линию после мёржа апстрима: tool/fork/analyze_check.sh --update
set -euo pipefail

cd "$(dirname "$0")/../.."
baseline=tool/fork/analyze_baseline.txt
out=$(flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1) || {
  echo "$out" | grep -E '^\s*error •' || echo "$out" | tail -20
  echo "flutter analyze: ошибки" >&2
  exit 1
}

current=$(echo "$out" | grep -E '^\s*warning •' | sed -E 's/^\s+//; s/:[0-9]+:[0-9]+ •/ •/' | sort || true)

if [[ "${1:-}" == "--update" ]]; then
  printf '%s\n' "$current" > "$baseline"
  echo "базовая линия обновлена: $(grep -c . "$baseline") предупреждений"
  exit 0
fi

new=$(comm -13 "$baseline" <(printf '%s\n' "$current") | grep . || true)
if [[ -n "$new" ]]; then
  echo "Новые предупреждения анализатора:" >&2
  echo "$new" >&2
  exit 1
fi
echo "analyze: ошибок нет, предупреждения в пределах базовой линии ($(printf '%s\n' "$current" | grep -c .))"
