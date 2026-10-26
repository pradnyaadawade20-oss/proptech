-- Deposit refund through Cashfree (back to the tenant's original payment method).
ALTER TABLE lease_deposits ADD COLUMN IF NOT EXISTS cf_refund_id     TEXT NOT NULL DEFAULT '';
ALTER TABLE lease_deposits ADD COLUMN IF NOT EXISTS cf_refund_status TEXT NOT NULL DEFAULT '';  -- SUCCESS | PENDING | ONHOLD | CANCELLED | FAILED