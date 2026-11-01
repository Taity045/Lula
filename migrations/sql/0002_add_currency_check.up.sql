BEGIN;

SET LOCAL lock_timeout = '5s';

ALTER TABLE orders
    ADD CONSTRAINT orders_currency_not_null
    CHECK (currency IS NOT NULL) NOT VALID;

COMMIT;