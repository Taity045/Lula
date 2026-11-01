# Orders API — DevOps assessment

A small orders API with Docker, GitHub Actions, database migrations and an Azure Terraform sketch.

The main change adds currency to existing orders without breaking the app's current reads and writes.

## Run locally

You need Docker Compose. To run migrations from your terminal, also install PostgreSQL's `psql` client and `golang-migrate` (CI uses v4.20.1).

From the repository root:

```bash
docker compose up -d --build
curl --fail --retry 10 --retry-connrefused --retry-delay 2 http://localhost:8001/health
curl --fail http://localhost:8001/orders
```

Open http://localhost:8001/docs to try the API. The app runs as a non-root user. Its health check tests database connectivity.

On a fresh database, Compose loads `schema.sql` and creates 20 sample orders. It does not run the migrations automatically.

```bash
export DB_URL="postgres://app:app@localhost:5432/app?sslmode=disable"
BATCH_SIZE=5 bash scripts/migrate.sh
```

These credentials are for local development. If you already changed this database manually, use a fresh test database rather than applying migration 0001 again.

## How the migration works

Assumption: the existing amounts are in ZAR. In production, confirm that with the data owner before filling anything in.

| Step | Change | Why |
| --- | --- | --- |
| 0001 | Add an optional currency column and set a default of ZAR. | Existing rows stay unchanged. Old app inserts that omit currency receive ZAR. |
| Backfill | Fill only rows where currency is NULL, in small batches. | Each batch commits separately, so work can resume after a failure. |
| 0002 | Add a not-null check using NOT VALID. | Reject new NULL values without scanning all historical rows in this step. |
| 0003 | Validate the check against existing rows. | Confirm the backfill is complete before tightening the column. |
| 0004 | Set NOT NULL and remove the temporary check. | Make currency mandatory, using the validated check to avoid another table scan. |

This is expand, backfill, then contract: add something compatible, fill the old data, then enforce the final rule.

The current API still omits currency when writing orders. Keeping the default preserves that behaviour. There is no second, currency-aware app version in this submission.

Each forward migration uses a transaction and a five-second lock timeout. This limits how long it waits for a lock; it does not make the migration lock-free or limit total execution time. In production I would run one migration job per database and watch order errors, latency and database locks.

The numbered `.up.sql` and `.down.sql` files follow [golang-migrate's naming convention](https://github.com/golang-migrate/migrate/blob/master/MIGRATIONS.md). The backfill is separate because it needs repeated, independently committed batches. `scripts/migrate.sh` runs them in the right order.

## If it fails

Start by checking what actually happened:

```bash
psql "$DB_URL" -c "SELECT version, dirty FROM schema_migrations;"
psql "$DB_URL" -c '\d public.orders'
```

Once the currency column exists, check progress:

```bash
psql "$DB_URL" -c "SELECT COUNT(*) AS remaining FROM orders WHERE currency IS NULL;"
```

**Backfill failure:** committed batches remain. An unfinished transaction rolls back when the connection closes. Fix the cause and rerun `scripts/migrate.sh`; rows already filled are skipped. The backfill runs through psql, so its failure does not set golang-migrate's dirty flag.

**Numbered migration failure:** the script stops if the migration history is dirty. Read the error, inspect the table and compare it with the relevant SQL file. After confirming which version the database actually matches, use `migrate force <confirmed-version>` with the same path and database options to correct the history, then rerun. Force changes the recorded version only; it does not repair the schema. Never clear dirty just to make the pipeline green.

## Rollback

Prefer rolling back the app while keeping the compatible column and default.

To rehearse one schema step backwards on a disposable database at version 4:

```bash
migrate -path migrations/sql -database "$DB_URL" down 1
```

That restores the temporary check and removes the column's NOT NULL setting. Currency is still required by the check. Run `bash scripts/migrate.sh` to move forward again.

Migration 0003's down file intentionally does nothing: validation only checked existing data. Migration 0002's down removes the check. Migration 0001's down drops the column and all currency values. A full rollback is therefore destructive. Backfilled values are not reset to NULL. Review schema rollback locks before using it on a busy database.

## Tests and CI

To test failure and recovery locally, use a new disposable database:

```bash
docker compose exec -T db createdb -U app assessment_test
DB_URL="postgres://app:app@localhost:5432/assessment_test?sslmode=disable" \
  bash tests/test_migrations.sh
```

Use another database name if it already exists.

The test commits five rows, deliberately fails the next batch, checks that the first batch survived, then resumes and checks the final schema and data.

GitHub Actions also builds the image, reruns the completed migration, checks the non-root user, tests the API and checks metrics and JSON logs. Its PostgreSQL service is the deployment target for this exercise. Terraform is formatted and validated; nothing is deployed to Azure.

Limit: CI checks the API after migration. It does not yet prove API behaviour under concurrent traffic during a partial backfill.

## Observability

`/metrics` exposes request counts by method, route and status. JSON request logs include status and duration so slow or failed requests can be investigated.

- **Alert I would set:** sustained 5xx errors on order requests, with a minimum request volume. A starting point is more than 2% failures over five minutes with at least 100 requests; tune this to real traffic.
- **Alert I would not set:** missing currency greater than zero during backfill. That is expected progress, not an incident. Remaining rows must reach zero before the script proceeds to the final constraints.

These are proposed alerts; no Prometheus server or alert rules are deployed here.

## Azure

[The Terraform README](terraform/README.md) explains Container Apps, private PostgreSQL, Key Vault, costs and protecting state. Database setup and the app secret must be ready before enabling the app.
