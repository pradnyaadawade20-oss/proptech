-- Adds OTP verification before e-sign becomes valid.
ALTER TABLE agreements
    ADD COLUMN IF NOT EXISTS owner_otp_code      TEXT,
    ADD COLUMN IF NOT EXISTS owner_otp_expires_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS owner_otp_verified   BOOLEAN NOT NULL DEFAULT FALSE,

    ADD COLUMN IF NOT EXISTS tenant_otp_code      TEXT,
    ADD COLUMN IF NOT EXISTS tenant_otp_expires_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS tenant_otp_verified   BOOLEAN NOT NULL DEFAULT FALSE;