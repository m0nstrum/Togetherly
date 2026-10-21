#!/usr/bin/env sh
# Собирает каталог JS-хуков из pocketbase/pb_hooks по server/hooks.allow.
#   scripts/sync-hooks.sh [куда]   (по умолчанию server/pb_hooks)
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
src="$here/../pocketbase/pb_hooks"
dst="${1:-$here/pb_hooks}"

rm -rf "$dst"
mkdir -p "$dst"
grep -vE '^[[:space:]]*(#|$)' "$here/hooks.allow" | while read -r name; do
  if [ ! -f "$src/$name" ]; then
    echo "нет хука $name в pocketbase/pb_hooks (апстрим переименовал?)" >&2
    exit 1
  fi
  cp "$src/$name" "$dst/$name"
done
echo "хуки: $(ls "$dst" | wc -l) → $dst"
