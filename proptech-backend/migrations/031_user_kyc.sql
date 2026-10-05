
-- B3: server-side KYC (Aadhaar OTP). One row per user.
-- The full Aadhaar number is NEVER stored: only the last 4 digits (for display)
-- and an HMAC-SHA256 of the number (keyed with KYC_HASH_SECRET) so the same
-- Aadhaar can't be verified on two accounts.
CREATE TABLE IF NOT EXISTS user_kyc (
    user_id         UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'verified', 'rejected')),
    aadhaar_last4   CHAR(4) NOT NULL,
    aadhaar_hash    TEXT NOT NULL,
    provider        TEXT NOT NULL,
    provider_ref    TEXT,                       -- provider's OTP transaction id; cleared once verified
    attempts        INT NOT NULL DEFAULT 0,     -- wrong-OTP counter for the current OTP
    otp_sent_at     TIMESTAMPTZ,
    verified_at     TIMESTAMPTZ,
    rejected_reason TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One verified Aadhaar <-> one account.
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_kyc_verified_hash
    ON user_kyc (aadhaar_hash) WHERE status = 'verified';