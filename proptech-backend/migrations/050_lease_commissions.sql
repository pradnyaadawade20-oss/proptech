-- Agent (broker) commission, paid by the tenant through Cashfree once the lease exists.
CREATE TABLE IF NOT EXISTS lease_commissions (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lease_id       UUID NOT NULL UNIQUE REFERENCES leases(id) ON DELETE CASCADE,
    agent_id       UUID NOT NULL REFERENCES users(id),
    tenant_id      UUID NOT NULL REFERENCES users(id),
    amount         NUMERIC(12,2) NOT NULL CHECK (amount >= 1),
    note           TEXT NOT NULL DEFAULT '',
    status         TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested', 'paid')),
    payment_method TEXT NOT NULL DEFAULT '',
    reference      TEXT NOT NULL DEFAULT '',
    receipt_no     TEXT NOT NULL DEFAULT '',
    paid_at        TIMESTAMPTZ,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_lease_commissions_agent ON lease_commissions(agent_id, created_at DESC);

-- Cashfree orders can now also be for a commission.
ALTER TABLE payment_orders DROP CONSTRAINT IF EXISTS payment_orders_kind_check;
ALTER TABLE payment_orders ADD CONSTRAINT payment_orders_kind_check CHECK (kind IN ('rent', 'deposit', 'commission'));
CREATE UNIQUE INDEX IF NOT EXISTS uq_open_commission_order
    ON payment_orders(lease_id) WHERE status = 'created' AND kind = 'commission';