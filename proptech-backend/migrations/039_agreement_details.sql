-- Agreement draft details filled in by the owner (address, notice period, rent due day).
ALTER TABLE agreements
    ADD COLUMN IF NOT EXISTS property_address   TEXT,
    ADD COLUMN IF NOT EXISTS notice_period_days INT,
    ADD COLUMN IF NOT EXISTS rent_due_day       INT;