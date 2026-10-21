#!/usr/bin/env bash
# Первый .env инстанса: домен и случайные секреты (deploy/README.md).
#   ./init-env.sh tethered.example.org
# Существующий .env не трогает.
set -euo pipefail
cd "$(dirname "$0")"

domain=${1:-}
if [[ ! "$domain" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
  echo "использование: $0 <домен>, например $0 tethered.example.org" >&2
  exit 1
fi
if [ -e .env ]; then
  echo ".env уже есть — правьте его руками" >&2
  exit 1
fi

secret() { openssl rand -hex 32; }

sed -e "s/^TETHERED_DOMAIN=.*/TETHERED_DOMAIN=$domain/" \
  -e "s/^CENTRIFUGO_TOKEN_HMAC=$/CENTRIFUGO_TOKEN_HMAC=$(secret)/" \
  -e "s/^CENTRIFUGO_API_KEY=$/CENTRIFUGO_API_KEY=$(secret)/" \
  -e "s/^TURN_SECRET=$/TURN_SECRET=$(secret)/" \
  -e "s/^BUGSINK_SECRET_KEY=$/BUGSINK_SECRET_KEY=$(secret)/" \
  .env.example > .env
chmod 600 .env
echo "готово: .env для $domain. Почту (SMTP_*) и ключ бэкапов (BACKUP_AGE_RECIPIENTS) впишите сами."
