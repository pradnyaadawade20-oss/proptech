-- Rate limiting + temporary blocks (OTP etc.), and relay call requests.

CREATE TABLE IF NOT EXISTS rate_limits (
    key           TEXT PRIMARY KEY,
    count         INT         NOT NULL DEFAULT 0,
    window_start  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    blocked_until TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_rate_limits_window ON rate_limits (window_start);

-- Buyer asked to reach an owner through the relay. No phone numbers stored here.
CREATE TABLE IF NOT EXISTS contact_requests (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id     UUID NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
    requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    mode        TEXT NOT NULL,                       -- relay | callback
    status      TEXT NOT NULL DEFAULT 'requested',   -- requested | connected | failed
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_contact_requests_lead ON contact_requests (lead_id, created_at DESC);