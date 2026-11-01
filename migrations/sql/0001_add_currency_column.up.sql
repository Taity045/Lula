BEGIN;

SET LOCAL lock_timeout = '5s';

ALTER TABLE orders
    ADD COLUMN currency CHAR(3);

ALTER TABLE orders
    ALTER COLUMN currency SET DEFAULT 'ZAR';

COMMIT;