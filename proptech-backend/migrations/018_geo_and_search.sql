-- Step 1: geo columns + search indexes for server-side filtering.

ALTER TABLE properties
    ADD COLUMN IF NOT EXISTS latitude  DOUBLE PRECISION NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION NOT NULL DEFAULT 0;

-- Backfill from "Verify Now" photos so already-verified listings show on the map.
UPDATE properties p
SET latitude = v.latitude, longitude = v.longitude
FROM property_verifications v
WHERE v.property_id = p.id AND p.latitude = 0 AND p.longitude = 0;

CREATE INDEX IF NOT EXISTS idx_properties_created_at ON properties (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_properties_city       ON properties (LOWER(city));
CREATE INDEX IF NOT EXISTS idx_properties_category   ON properties (LOWER(category));
CREATE INDEX IF NOT EXISTS idx_properties_price      ON properties (price);
CREATE INDEX IF NOT EXISTS idx_properties_status     ON properties (listing_status);
CREATE INDEX IF NOT EXISTS idx_properties_geo        ON properties (latitude, longitude);

-- Fast ILIKE '%text%' search. pg_trgm may not be allowed on every managed
-- Postgres, so failure here must NOT break startup (search still works, just slower).
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_trgm not available, skipping trigram index: %', SQLERRM;
END $$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm') THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_properties_search_trgm ON properties
                 USING gin ((title || '' '' || location || '' '' || city || '' '' || locality || '' '' || society) gin_trgm_ops)';
    END IF;
END $$;