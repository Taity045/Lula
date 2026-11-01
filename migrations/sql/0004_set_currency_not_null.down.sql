BEGIN;

SET LOCAL lock_timeout = '5s';

-- Restore the previous rule before removing NOT NULL.
ALTER TABLE orders
    ADD CONSTRAINT orders_currency_not_null
    CHECK (currency IS NOT NULL);

ALTER TABLE orders
    ALTER COLUMN currency DROP NOT NULL;

COMMIT;