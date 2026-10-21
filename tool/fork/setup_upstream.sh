#!/usr/bin/env sh
# Подключает апстрим Togetherly как remote `upstream` (docs/fork/README.md).
# Повторный запуск безопасен: адрес просто обновится.
set -eu

URL="https://github.com/THET1ME-1/togetherly"

if git remote get-url upstream >/dev/null 2>&1; then
  git remote set-url upstream "$URL"
else
  git remote add upstream "$URL"
fi
# Пушить в апстрим форку незачем: закрываем случайный push.
git remote set-url --push upstream DISABLED
git fetch upstream
echo "upstream: $URL"
