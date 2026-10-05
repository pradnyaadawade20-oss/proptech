-- Step 3: admin approval, report listing, duplicate detection.

-- 1. Approval workflow. New listings default to 'pending'; the admin approves
--    or rejects. Listings that already exist stay live (backfilled below).
ALTER TABLE properties
    ADD COLUMN IF NOT EXISTS approval_status  VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending | approved | rejected
    ADD COLUMN IF NOT EXISTS rejection_reason TEXT        NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS duplicate_of     UUID REFERENCES properties(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS reviewed_at      TIMESTAMPTZ;

UPDATE properties SET approval_status = 'approved', reviewed_at = NOW();

CREATE INDEX IF NOT EXISTS idx_properties_approval ON properties (approval_status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_properties_dupcheck ON properties (LOWER(city), LOWER(bhk), floor_number);

-- 2. Reports (buyer -> admin). One report per user per listing.
CREATE TABLE IF NOT EXISTS property_reports (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    reporter_id UUID NOT NULL REFERENCES users(id)      ON DELETE CASCADE,
    reason      VARCHAR(30) NOT NULL,   -- spam | fake_listing | wrong_info | already_rented_sold | duplicate | inappropriate | other
    details     TEXT        NOT NULL DEFAULT '',
    status      VARCHAR(20) NOT NULL DEFAULT 'open',  -- open | dismissed | resolved
    admin_note  TEXT        NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ,
    UNIQUE (property_id, reporter_id)
);

CREATE INDEX IF NOT EXISTS idx_reports_status   ON property_reports (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_property ON property_reports (property_id);