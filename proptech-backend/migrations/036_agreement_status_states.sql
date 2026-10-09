-- 12.5 Agreement status states: expiry deadline + why/who/when for terminal states.
ALTER TABLE agreements
    ADD COLUMN IF NOT EXISTS expires_at        TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS status_reason     TEXT,
    ADD COLUMN IF NOT EXISTS status_changed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS status_changed_at TIMESTAMPTZ;

-- Open agreements get a fresh 7-day window starting now, so nothing that already
-- exists is expired by surprise on first deploy.
UPDATE agreements
   SET expires_at = now() + interval '7 days'
 WHERE expires_at IS NULL
   AND status IN ('requested', 'draft_ready', 'awaiting_signatures', 'signed_by_owner', 'signed_by_tenant');

CREATE INDEX IF NOT EXISTS idx_agreements_expiry
    ON agreements (expires_at)
 WHERE status IN ('requested', 'draft_ready', 'awaiting_signatures', 'signed_by_owner', 'signed_by_tenant');