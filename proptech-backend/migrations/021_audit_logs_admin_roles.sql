-- A3: admin roles + audit log.
--
-- Roles (least -> most privileged):
--   support      read-only: can view users/listings/visits/agreements
--   moderator    support + verify/unverify and delete listings
--   super_admin  everything, incl. deleting users, managing admins, reading the audit log
-- The admin that already exists (seeded in 017) becomes super_admin via the DEFAULT,
-- so nobody is locked out after this migration.

ALTER TABLE admins
    ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'super_admin';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'admins_role_check'
    ) THEN
        ALTER TABLE admins
            ADD CONSTRAINT admins_role_check
            CHECK (role IN ('support', 'moderator', 'super_admin'));
    END IF;
END $$;

-- Append-only record of what admins did. actor_email is plain text (not an FK)
-- on purpose: the log must survive even if the admin account is deleted later.
CREATE TABLE IF NOT EXISTS audit_logs (
    id           BIGSERIAL PRIMARY KEY,
    actor_email  TEXT        NOT NULL,
    actor_role   TEXT        NOT NULL DEFAULT '',
    action       TEXT        NOT NULL,
    target_type  TEXT        NOT NULL DEFAULT '',
    target_id    TEXT        NOT NULL DEFAULT '',
    metadata     JSONB       NOT NULL DEFAULT '{}'::jsonb,
    ip           TEXT        NOT NULL DEFAULT '',
    success      BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at  ON audit_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor       ON audit_logs (actor_email, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action      ON audit_logs (action, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_target      ON audit_logs (target_type, target_id);