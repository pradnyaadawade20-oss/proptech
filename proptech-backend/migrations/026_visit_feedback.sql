-- Visit feedback: after a visit is completed the visitor says how it went.
ALTER TABLE visits ADD COLUMN IF NOT EXISTS feedback_interest VARCHAR(20)
    CHECK (feedback_interest IN ('interested', 'maybe', 'not_interested'));
ALTER TABLE visits ADD COLUMN IF NOT EXISTS feedback_note TEXT NOT NULL DEFAULT '';
ALTER TABLE visits ADD COLUMN IF NOT EXISTS feedback_at TIMESTAMPTZ;