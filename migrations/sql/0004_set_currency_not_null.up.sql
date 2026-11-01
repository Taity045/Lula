BEGIN;

SET LOCAL lock_timeout = '5s';

ALTER TABLE orders
    ALTER COLUMN currency SET NOT NULL;

ALTER TABLE orders
    DROP CONSTRAINT orders_currency_not_null;

COMMIT;