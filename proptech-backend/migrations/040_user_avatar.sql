-- Profile photos are stored in the DB (same approach as property images,
-- see 009_property_image_data.sql) so they survive Render redeploys.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS avatar_data BYTEA,
    ADD COLUMN IF NOT EXISTS avatar_content_type TEXT;