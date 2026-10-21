-- Visit OTP: buyer sees a 6-digit code in the app once the owner confirms the
-- visit; the buyer tells it to the owner at the visit and the owner enters it
-- to prove this is the same buyer. Verifying completes the visit.
ALTER TABLE visits ADD COLUMN IF NOT EXISTS otp_code        TEXT;
ALTER TABLE visits ADD COLUMN IF NOT EXISTS otp_expires_at  TIMESTAMPTZ;
ALTER TABLE visits ADD COLUMN IF NOT EXISTS otp_attempts    INT NOT NULL DEFAULT 0;
ALTER TABLE visits ADD COLUMN IF NOT EXISTS otp_verified_at TIMESTAMPTZ;