BEGIN;

SET LOCAL lock_timeout = '5s';

UPDATE orders
SET currency = 'ZAR'
WHERE id IN (
    SELECT id
    FROM orders
    WHERE currency IS NULL
    ORDER BY id
    LIMIT :batch_size
)
RETURNING id, currency;

COMMIT;