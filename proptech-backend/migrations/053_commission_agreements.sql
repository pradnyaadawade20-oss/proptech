-- Commission agreement between the broker and the tenant, signed BEFORE the rental agreement.
-- The tenant can request the rental agreement for a broker listing only after signing this,
-- and pays the commission (through Cashfree) once the rental agreement is completed.
CREATE TABLE IF NOT EXISTS commission_agreements (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agreement_number TEXT NOT NULL DEFAULT '',
    property_id      UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    agent_id         UUID NOT NULL REFERENCES users(id),
    tenant_id        UUID NOT NULL REFERENCES users(id),
    amount           NUMERIC(12,2) NOT NULL CHECK (amount >= 1),
    note             TEXT NOT NULL DEFAULT '',
    status           TEXT NOT NULL DEFAULT 'sent' CHECK (status IN ('sent', 'signed', 'declined', 'cancelled')),
    agent_sign_type  TEXT NOT NULL DEFAULT '',
    agent_sign_data  TEXT NOT NULL DEFAULT '',
    agent_signed_at  TIMESTAMPTZ,
    tenant_sign_type TEXT NOT NULL DEFAULT '',
    tenant_sign_data TEXT NOT NULL DEFAULT '',
    tenant_signed_at TIMESTAMPTZ,
    pay_status       TEXT NOT NULL DEFAULT 'unpaid' CHECK (pay_status IN ('unpaid', 'paid')),
    payment_method   TEXT NOT NULL DEFAULT '',
    reference        TEXT NOT NULL DEFAULT '',
    receipt_no       TEXT NOT NULL DEFAULT '',
    paid_at          TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- only one live commission agreement per property + tenant
CREATE UNIQUE INDEX IF NOT EXISTS uq_commission_active
    ON commission_agreements(property_id, tenant_id) WHERE status IN ('sent', 'signed');
CREATE INDEX IF NOT EXISTS idx_commission_agent ON commission_agreements(agent_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_commission_tenant ON commission_agreements(tenant_id, created_at DESC);