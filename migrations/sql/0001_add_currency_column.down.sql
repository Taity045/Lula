BEGIN;

SET LOCAL lock_timeout = '5s';

ALTER TABLE orders
    DROP COLUMN currency;

COMMIT;