-- Who viewed a listing: one row per viewer per day (logged-in user id, or the caller's IP when anonymous).
CREATE TABLE IF NOT EXISTS property_views (
    id          BIGSERIAL PRIMARY KEY,
    property_id UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    viewer_key  TEXT NOT NULL,
    view_date   DATE NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (property_id, viewer_key, view_date)
);
CREATE INDEX IF NOT EXISTS idx_property_views_property ON property_views (property_id);