-- Richer listing details for the Post Property form.
-- All columns are NOT NULL with defaults (except available_from) so
-- existing rows keep working and scans never hit NULLs.

ALTER TABLE properties
    ADD COLUMN IF NOT EXISTS area_sqft            NUMERIC(10, 2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS bathrooms            INT            NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS balconies            INT            NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS floor_number         INT            NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS total_floors         INT            NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS city                 VARCHAR(100)   NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS locality             VARCHAR(150)   NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS society              VARCHAR(150)   NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS pincode              VARCHAR(10)    NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS security_deposit     NUMERIC(12, 2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS maintenance_charges  NUMERIC(12, 2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS preferred_tenants    TEXT[]         NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS available_from       DATE,
    ADD COLUMN IF NOT EXISTS description          TEXT           NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS property_age_years   INT            NOT NULL DEFAULT -1, -- -1 = unknown
    ADD COLUMN IF NOT EXISTS facing               VARCHAR(30)    NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS ownership_type       VARCHAR(30)    NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS is_price_negotiable  BOOLEAN        NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS contact_preference   VARCHAR(10)    NOT NULL DEFAULT 'both'; -- call | chat | both