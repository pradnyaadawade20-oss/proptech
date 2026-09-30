-- Adds fields required by the frontend Property model:
-- category: 'Residential' | 'Commercial' | 'Plot/Land'
-- amenities: list of amenity keys (wifi, parking, lift, power_backup, etc.)

ALTER TABLE properties
    ADD COLUMN IF NOT EXISTS category VARCHAR(50) NOT NULL DEFAULT 'Residential',
    ADD COLUMN IF NOT EXISTS amenities TEXT[] NOT NULL DEFAULT '{}';