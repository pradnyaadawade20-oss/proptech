-- Email + password + email-OTP login (replaces phone-number OTP login).

-- Phone is no longer collected at signup. Keep the column (existing rows,
-- "call owner" feature) but allow NULL. UNIQUE still holds for non-NULL values.
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS password_hash  TEXT,
    ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE;

-- One pending OTP per email. Stored in the DB (not memory) so it survives
-- restarts / Render free-tier sleep. Only a hash of the OTP is stored.
-- For a brand-new signup, name + password_hash wait here until the OTP is
-- verified; the users row is only created after verification.
CREATE TABLE IF NOT EXISTS email_otps (
    email         TEXT PRIMARY KEY,
    otp_hash      TEXT        NOT NULL,
    name          TEXT        NOT NULL DEFAULT '',
    password_hash TEXT        NOT NULL DEFAULT '',
    attempts      INT         NOT NULL DEFAULT 0,
    expires_at    TIMESTAMPTZ NOT NULL,
    last_sent_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);