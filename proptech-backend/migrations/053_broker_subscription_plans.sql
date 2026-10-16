-- Broker paid plans: first 3 listings are free, after that a monthly / yearly
-- subscription is required (enforced in POST /api/properties for posted_by=broker).

ALTER TABLE broker_subscriptions
    ADD COLUMN IF NOT EXISTS plan_type   VARCHAR(10) NOT NULL DEFAULT 'free',
    ADD COLUMN IF NOT EXISTS started_at  TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS expires_at  TIMESTAMPTZ;

ALTER TABLE broker_subscriptions
    DROP CONSTRAINT IF EXISTS broker_subscriptions_plan_type_check;
ALTER TABLE broker_subscriptions
    ADD CONSTRAINT broker_subscriptions_plan_type_check
    CHECK (plan_type IN ('free', 'monthly', 'yearly'));

-- One row per purchase / renewal.
CREATE TABLE IF NOT EXISTS broker_subscription_history (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    broker_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_type   VARCHAR(10) NOT NULL CHECK (plan_type IN ('monthly', 'yearly')),
    amount      NUMERIC(10,2) NOT NULL,
    starts_at   TIMESTAMPTZ NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    payment_ref TEXT NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_broker_sub_history_broker
    ON broker_subscription_history (broker_id, created_at DESC);