#!/usr/bin/env sh
# Собирает статику сервера: страницы апстрима по server/public.allow, затем
# свои страницы форка из server/public поверх.
#   scripts/sync-public.sh [куда]   (по умолчанию server/pb_public)
#
# Правки страниц апстрима — правилами ниже, а не в его файлах (мёржи):
#   - скрипт аналитики автора (analytics.togetherly.day) удаляется;
#   - WebSocket комнаты «Смотрим вместе» — на хост, с которого открыта
#     страница (Caddy форка ведёт /connection/websocket в Centrifugo);
#   - почта поддержки и ссылки на скачивание приложения автора убираются.
# В конце — проверка: адресов инфраструктуры апстрима в коде страниц нет.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
src="$here/../pocketbase/pb_public"
dst="${1:-$here/pb_public}"

rm -rf "$dst"
mkdir -p "$dst"
grep -vE '^[[:space:]]*(#|$)' "$here/public.allow" | while read -r name; do
  if [ ! -e "$src/$name" ]; then
    echo "нет $name в pocketbase/pb_public (апстрим переименовал?)" >&2
    exit 1
  fi
  cp -R "$src/$name" "$dst/$name"
done
# Тесты страниц апстрима в раздачу не нужны.
find "$dst" -type d -name tests -prune -exec rm -rf {} +

find "$dst" -type f \( -name '*.html' -o -name '*.js' \) | while read -r f; do
  sed -i \
    -e '/analytics\.togetherly\.day\/script\.js/d' \
    -e "s#'wss://togetherly\.day/connection/websocket'#'wss://' + location.host + '/connection/websocket'#g" \
    -e '/wss:\/\/rt\.togetherly\.day:8443/d' \
    -e 's#<a href="mailto:support@togetherly\.day">support@togetherly\.day</a>##g' \
    -e '\#play\.google\.com/store/apps/details?id=com\.togetherly\.love#d' \
    -e '\#github\.com/THET1ME-1/togetherly/releases#d' \
    "$f"
done

cp -R "$here/public/." "$dst/"

# Сторож: в коде страниц (не в комментариях JS) нет адресов апстрима.
left=$(find "$dst" -type f \( -name '*.html' -o -name '*.js' \) \
  -exec grep -HnE 'togetherly\.(day|app)|duckdns|web\.app|com\.togetherly\.love|THET1ME-1' {} + \
  | grep -vE ':[0-9]+:[[:space:]]*//' || true)
if [ -n "$left" ]; then
  echo "в статике остались адреса апстрима — добавьте правило в sync-public.sh:" >&2
  echo "$left" >&2
  exit 1
fi
echo "статика: $(find "$dst" -type f | wc -l) файлов → $dst"
