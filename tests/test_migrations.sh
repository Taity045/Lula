#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DB_URL:?Set DB_URL to an empty test database}"

query() {
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 -Atc "$1"
}

assert_equal() {
  if [[ "$1" != "$2" ]]; then
    echo "FAIL: $3 — expected $2, got $1"
    exit 1
  fi
  echo "PASS: $3"
}

# Refuse to run against a database containing application data.
assert_equal \
  "$(query "SELECT to_regclass('public.orders') IS NULL")" \
  "t" "test database is empty of orders"

psql "$DB_URL" -X -v ON_ERROR_STOP=1 -f schema.sql
migrate -path migrations/sql -database "$DB_URL" up 1

assert_equal \
  "$(query "SELECT COUNT(*) FROM orders WHERE currency IS NULL")" \
  "20" "existing orders await backfill"

# Commit the first five rows.
psql "$DB_URL" -X -v ON_ERROR_STOP=1 -v batch_size=5 \
  -f migrations/sql/backfill_currency.sql

# Reuse the actual batch SQL, injecting an error before COMMIT.
# ON_ERROR_STOP closes the connection; its transaction rolls back.
if awk '
  /^COMMIT;/ { print "SELECT 1 / 0;" }
  { print }
' migrations/sql/backfill_currency.sql |
  psql "$DB_URL" -X -v ON_ERROR_STOP=1 -v batch_size=5; then
  echo "FAIL: the injected error unexpectedly succeeded"
  exit 1
fi

assert_equal \
  "$(query "SELECT COUNT(*) FROM orders WHERE currency IS NULL")" \
  "15" "failed batch rolled back"

assert_equal \
  "$(query "SELECT COUNT(*) FROM orders WHERE currency = 'ZAR'")" \
  "5" "previously committed batch survived"

# Resume through the real deployment script.
BATCH_SIZE=5 bash scripts/migrate.sh

assert_equal \
  "$(query "SELECT COUNT(*) FROM orders")" \
  "20" "order count preserved"

assert_equal \
  "$(query "SELECT COUNT(*) FROM orders WHERE currency = 'ZAR'")" \
  "20" "all orders backfilled"

assert_equal \
  "$(query "SELECT version FROM schema_migrations WHERE NOT dirty")" \
  "4" "schema migrations completed"

assert_equal \
  "$(query "SELECT is_nullable FROM information_schema.columns
           WHERE table_schema = 'public'
             AND table_name = 'orders'
             AND column_name = 'currency'")" \
  "NO" "currency is required"

echo "Migration tests passed."