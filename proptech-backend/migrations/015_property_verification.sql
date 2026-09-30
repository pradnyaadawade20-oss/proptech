-- "Verify Now" feature: owner takes a photo from within the app camera,
-- we capture GPS coordinates at the same moment, and store both. This is
-- what actually earns the "Verified" badge — regular gallery photos on
-- the listing itself stay untouched and don't need to prove anything.

CREATE TABLE IF NOT EXISTS property_verifications (
    property_id  UUID PRIMARY KEY REFERENCES properties(id) ON DELETE CASCADE,
    photo_data   BYTEA NOT NULL,
    content_type TEXT NOT NULL,
    latitude     DOUBLE PRECISION NOT NULL,
    longitude    DOUBLE PRECISION NOT NULL,
    captured_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);