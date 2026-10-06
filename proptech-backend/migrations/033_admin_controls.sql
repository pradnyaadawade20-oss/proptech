-- Admin audit log, maker-checker approvals, user suspension, report auto-hide.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS suspended_at     TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS suspended_reason TEXT NOT NULL DEFAULT '';

-- Why a listing is hidden: 'reports' | 'owner_suspended' | 'admin'
ALTER TABLE properties
    ADD COLUMN IF NOT EXISTS hidden_reason TEXT NOT NULL DEFAULT '';

CREATE TABLE IF NOT EXISTS admin_audit_log (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_email TEXT        NOT NULL,              -- WHO ('system' for automatic actions)
    action      TEXT        NOT NULL,              -- WHAT
    entity_type TEXT        NOT NULL,
    entity_id   TEXT        NOT NULL,
    old_value   JSONB,
    new_value   JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW() -- WHEN
);
CREATE INDEX IF NOT EXISTS idx_audit_created ON admin_audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_entity  ON admin_audit_log (entity_type, entity_id);

CREATE TABLE IF NOT EXISTS admin_approvals (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action        TEXT NOT NULL CHECK (action IN ('delete_user', 'delete_property', 'refund_deposit')),
    entity_id     TEXT NOT NULL,
    summary       TEXT NOT NULL DEFAULT '',
    payload       JSONB NOT NULL DEFAULT '{}',
    reason        TEXT NOT NULL DEFAULT '',
    status        TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'approved', 'rejected', 'failed')),
    requested_by  TEXT NOT NULL,
    decided_by    TEXT,
    decision_note TEXT NOT NULL DEFAULT '',
    error         TEXT NOT NULL DEFAULT '',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    decided_at    TIMESTAMPTZ,
    CHECK (decided_by IS NULL OR decided_by <> requested_by)  -- maker != checker
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_admin_approvals_pending
    ON admin_approvals (action, entity_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_admin_approvals_status ON admin_approvals (status, created_at DESC);