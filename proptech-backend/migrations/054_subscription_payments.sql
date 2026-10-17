-- Broker subscription is now paid through Cashfree (payment_orders kind = 'subscription').
-- A subscription order has no lease, so lease_id becomes optional.
ALTER TABLE payment_orders ALTER COLUMN lease_id DROP NOT NULL;
ALTER TABLE payment_orders ADD COLUMN IF NOT EXISTS plan_type TEXT NOT NULL DEFAULT '';

ALTER TABLE payment_orders DROP CONSTRAINT IF EXISTS payment_orders_kind_check;
ALTER TABLE payment_orders ADD CONSTRAINT payment_orders_kind_check
    CHECK (kind IN ('rent', 'deposit', 'commission', 'subscription'));

-- Only ONE open subscription order per broker at a time.
CREATE UNIQUE INDEX IF NOT EXISTS uq_open_subscription_order
    ON payment_orders(payer_id) WHERE status = 'created' AND kind = 'subscription';