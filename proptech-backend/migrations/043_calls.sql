-- In-app peer-to-peer audio calls (WebRTC). The server only does signaling;
-- this table is the call log / state machine.
CREATE TABLE IF NOT EXISTS calls (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id     UUID NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
    caller_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    callee_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status      VARCHAR(12) NOT NULL DEFAULT 'ringing'
                CHECK (status IN ('ringing', 'active', 'ended', 'rejected', 'missed')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    answered_at TIMESTAMPTZ,
    ended_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_calls_caller ON calls (caller_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_calls_callee ON calls (callee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_calls_open   ON calls (status) WHERE status IN ('ringing', 'active');