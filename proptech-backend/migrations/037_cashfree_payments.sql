-- Cashfree (sandbox) online payments: owner bank onboarding, payment orders,
-- webhook log (idempotency), settlement tracking, deposit receipts.

CREATE TABLE IF NOT EXISTS owner_bank_accounts (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id         UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    account_holder   TEXT NOT NULL,
    account_number   TEXT NOT NULL,            -- AES-GCM encrypted, never returned by the API
    account_last4    TEXT NOT NULL,
    ifsc             TEXT NOT NULL,
    vendor_id        TEXT NOT NULL UNIQUE,     -- Cashfree Easy Split vendor id
    status           TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'active', 'verification_failed', 'inactive')),
    status_detail    TEXT NOT NULL DEFAULT '',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payment_orders (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id              TEXT NOT NULL UNIQUE,            -- id we send to Cashfree
    kind                  TEXT NOT NULL CHECK (kind IN ('rent', 'deposit')),
    lease_id              UUID NOT NULL REFERENCES leases(id) ON DELETE CASCADE,
    rent_payment_id       UUID REFERENCES rent_payments(id) ON DELETE CASCADE,
    payer_id              UUID NOT NULL REFERENCES users(id),
    owner_id              UUID NOT NULL REFERENCES users(id),
    vendor_id             TEXT NOT NULL DEFAULT '',
    amount                NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    rent_amount           NUMERIC(12,2) NOT NULL DEFAULT 0,
    late_days             INT NOT NULL DEFAULT 0,
    late_fee              NUMERIC(12,2) NOT NULL DEFAULT 0,
    platform_fee          NUMERIC(12,2) NOT NULL DEFAULT 0,
    owner_amount          NUMERIC(12,2) NOT NULL DEFAULT 0,
    status                TEXT NOT NULL DEFAULT 'created'
                          CHECK (status IN ('created', 'paid', 'expired', 'cancelled', 'superseded', 'duplicate')),
    cf_order_id           TEXT NOT NULL DEFAULT '',
    payment_session_id    TEXT NOT NULL DEFAULT '',
    cf_payment_id         TEXT NOT NULL DEFAULT '',
    payment_method        TEXT NOT NULL DEFAULT '',
    attempts              INT NOT NULL DEFAULT 0,
    failure_reason        TEXT NOT NULL DEFAULT '',
    last_failed_at        TIMESTAMPTZ,
    expires_at            TIMESTAMPTZ NOT NULL,
    paid_at               TIMESTAMPTZ,
    settlement_status     TEXT NOT NULL DEFAULT 'pending'
                          CHECK (settlement_status IN ('pending', 'settled', 'failed')),
    settlement_id         TEXT NOT NULL DEFAULT '',
    settlement_utr        TEXT NOT NULL DEFAULT '',
    settlement_amount     NUMERIC(12,2),
    settled_at            TIMESTAMPTZ,
    settlement_checked_at TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((kind = 'rent') = (rent_payment_id IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS idx_payment_orders_lease  ON payment_orders(lease_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_orders_owner  ON payment_orders(owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_orders_open   ON payment_orders(status, expires_at);
-- Only ONE open order per rent month / per deposit at a time.
CREATE UNIQUE INDEX IF NOT EXISTS uq_open_rent_order
    ON payment_orders(rent_payment_id) WHERE status = 'created' AND rent_payment_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_open_deposit_order
    ON payment_orders(lease_id) WHERE status = 'created' AND kind = 'deposit';

-- Every webhook is stored once; a repeat (Cashfree retries) is ignored.
CREATE TABLE IF NOT EXISTS payment_webhook_events (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_key   TEXT NOT NULL UNIQUE,
    event_type  TEXT NOT NULL,
    order_id    TEXT NOT NULL DEFAULT '',
    payload     JSONB NOT NULL,
    result      TEXT NOT NULL DEFAULT '',
    received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE lease_deposits ADD COLUMN IF NOT EXISTS receipt_no TEXT;