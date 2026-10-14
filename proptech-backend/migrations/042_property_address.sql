-- Full street address of a listing, shown under "About this property".
ALTER TABLE properties
    ADD COLUMN IF NOT EXISTS address TEXT NOT NULL DEFAULT '';