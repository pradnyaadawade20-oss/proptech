-- Forgot password: one pending reset code per email (only a hash is stored).
CREATE TABLE IF NOT EXISTS password_resets (
    email        TEXT PRIMARY KEY,
    otp_hash     TEXT        NOT NULL,
    attempts     INT         NOT NULL DEFAULT 0,
    expires_at   TIMESTAMPTZ NOT NULL,
    last_sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);