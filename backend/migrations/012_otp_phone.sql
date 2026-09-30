-- Phone number is collected at signup again (email + password + phone).
-- The number waits in email_otps next to the pending name/password until
-- the OTP is verified (or skipped in testing), then it is saved on users.
ALTER TABLE email_otps ADD COLUMN IF NOT EXISTS phone TEXT NOT NULL DEFAULT '';