-- Direct UPI rent/deposit payments: owner UPI id, payment proof (screenshot), owner-confirm reminder.

ALTER TABLE users ADD COLUMN IF NOT EXISTS upi_id TEXT;

-- One proof screenshot per rent month (kind='rent', target_id = rent_payment id)
-- or per deposit (kind='deposit', target_id = lease id). Re-submitting replaces it.
CREATE TABLE IF NOT EXISTS payment_proofs (
    kind         TEXT NOT NULL CHECK (kind IN ('rent', 'deposit')),
    target_id    UUID NOT NULL,
    lease_id     UUID NOT NULL REFERENCES leases(id) ON DELETE CASCADE,
    uploader_id  UUID NOT NULL REFERENCES users(id),
    content_type TEXT NOT NULL,
    data         BYTEA NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (kind, target_id)
);

-- Set when the owner was reminded (24h after the tenant submitted) so it is sent only once.
ALTER TABLE rent_payments  ADD COLUMN IF NOT EXISTS confirm_reminded_at TIMESTAMPTZ;
ALTER TABLE lease_deposits ADD COLUMN IF NOT EXISTS confirm_reminded_at TIMESTAMPTZ;