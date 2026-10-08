-- Reschedule visit: track how many times a visit was moved and when.
ALTER TABLE visits ADD COLUMN IF NOT EXISTS reschedule_count INT NOT NULL DEFAULT 0;
ALTER TABLE visits ADD COLUMN IF NOT EXISTS rescheduled_at TIMESTAMPTZ;