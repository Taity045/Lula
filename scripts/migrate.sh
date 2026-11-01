#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root, regardless of where we started.
cd "$(dirname "$0")/.."

: "${DB_URL:?Set DB_URL to the target database}"
BATCH_SIZE="${BATCH_SIZE:-1000}"

if ! [[ "$BATCH_SIZE" =~ ^[1-9][0-9]*$ ]]; then
  echo "BATCH_SIZE must be a positive whole number."
  exit 1
fi

query() {
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 -Atc "$1"
}

# The baseline schema must already exist.
if [[ "$(query "SELECT to_regclass('public.orders') IS NOT NULL")" != "t" ]]; then
  echo "The orders table is missing. Initialize the baseline first."
  exit 1
fi

version=0

if [[ "$(query "SELECT to_regclass('public.schema_migrations') IS NOT NULL")" == "t" ]]; then
  if [[ "$(query "SELECT EXISTS (
      SELECT 1 FROM public.schema_migrations WHERE dirty
  )")" == "t" ]]; then
    echo "Migration state is dirty. Inspect and resolve it before retrying."
    exit 1
  fi

  version="$(query "SELECT COALESCE(
      (SELECT version FROM public.schema_migrations LIMIT 1), 0
  )")"
fi

case "$version" in
  0)
    migrate -path migrations/sql -database "$DB_URL" goto 1
    ;;
  1|2|3|4)
    echo "Current schema version: $version"
    ;;
  *)
    echo "Unexpected schema version: $version"
    exit 1
    ;;
esac

while true; do
  remaining="$(query "SELECT COUNT(*) FROM orders WHERE currency IS NULL")"
  echo "Orders still missing currency: $remaining"

  if [[ "$remaining" == "0" ]]; then
    break
  fi

  psql "$DB_URL" -X \
    -v ON_ERROR_STOP=1 \
    -v batch_size="$BATCH_SIZE" \
    -f migrations/sql/backfill_currency.sql
done

migrate -path migrations/sql -database "$DB_URL" up
migrate -path migrations/sql -database "$DB_URL" version