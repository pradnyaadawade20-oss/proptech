-- A5: reports + auto-hide, user bans, broker listing limit enforced in the DB.

-- ---- bans ----
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS banned_at  TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS ban_reason TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS banned_by  TEXT NOT NULL DEFAULT '';

-- ---- hidden listings (by reports, by admin, or because the owner is banned) ----
ALTER TABLE properties
    ADD COLUMN IF NOT EXISTS is_hidden     BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS hidden_reason TEXT    NOT NULL DEFAULT '',   -- reports | admin | owner_banned
    ADD COLUMN IF NOT EXISTS hidden_at     TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_properties_hidden ON properties (is_hidden) WHERE is_hidden;
CREATE INDEX IF NOT EXISTS idx_properties_owner_posted_by ON properties (owner_id, posted_by);

-- ---- reports ----
CREATE TABLE IF NOT EXISTS reports (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_type     TEXT NOT NULL CHECK (target_type IN ('property','user')),
    property_id     UUID REFERENCES properties(id) ON DELETE CASCADE,
    target_user_id  UUID REFERENCES users(id) ON DELETE CASCADE,
    reason          TEXT NOT NULL CHECK (reason IN
                      ('spam','fake_listing','wrong_info','scam','offensive','already_rented','other')),
    details         TEXT NOT NULL DEFAULT '',
    status          TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','dismissed','actioned')),
    resolved_by     TEXT NOT NULL DEFAULT '',
    resolution_note TEXT NOT NULL DEFAULT '',
    resolved_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (
        (target_type = 'property' AND property_id IS NOT NULL AND target_user_id IS NULL) OR
        (target_type = 'user'     AND target_user_id IS NOT NULL AND property_id IS NULL)
    ),
    -- one report per reporter per target (NULLs never collide, so each key only
    -- constrains its own target type)
    UNIQUE (reporter_id, property_id),
    UNIQUE (reporter_id, target_user_id)
);

CREATE INDEX IF NOT EXISTS idx_reports_status_created ON reports (status, created_at);
CREATE INDEX IF NOT EXISTS idx_reports_property ON reports (property_id) WHERE property_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_reports_target_user ON reports (target_user_id) WHERE target_user_id IS NOT NULL;

-- ---- broker listing limit, enforced where it cannot be bypassed ----
-- Counts only broker listings. A user whose active role is 'broker' is treated
-- as posting a broker listing even if the client says posted_by='owner'.
-- The advisory lock makes check+insert atomic for one broker, so two requests
-- at the same moment cannot both squeeze under the limit.
CREATE OR REPLACE FUNCTION enforce_broker_listing_limit() RETURNS trigger AS $$
DECLARE
    lim      INT;
    used     INT;
    role_now TEXT;
BEGIN
    IF NEW.owner_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.posted_by IS DISTINCT FROM 'broker' THEN
        SELECT COALESCE(active_role, role) INTO role_now FROM users WHERE id = NEW.owner_id;
        IF role_now = 'broker' THEN
            NEW.posted_by := 'broker';
        END IF;
    END IF;

    IF NEW.posted_by IS DISTINCT FROM 'broker' THEN
        RETURN NEW;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('broker_listing_limit:' || NEW.owner_id::text, 0));

    SELECT listings_limit INTO lim FROM broker_subscriptions WHERE broker_id = NEW.owner_id;
    IF NOT FOUND THEN
        lim := 3;  -- same default as the Free Plan row
    END IF;

    SELECT count(*) INTO used FROM properties WHERE owner_id = NEW.owner_id AND posted_by = 'broker';
    IF used >= lim THEN
        RAISE EXCEPTION 'BROKER_LIMIT_REACHED used=% limit=%', used, lim USING ERRCODE = 'PB001';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_broker_listing_limit ON properties;
CREATE TRIGGER trg_broker_listing_limit
    BEFORE INSERT ON properties
    FOR EACH ROW EXECUTE FUNCTION enforce_broker_listing_limit();