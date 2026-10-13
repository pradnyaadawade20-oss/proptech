-- Phase 1: broker listings are linked to the REAL owner (landlord), so agreements
-- and rent/deposit go to the owner, while the broker stays on record as the agent.

-- The real owner of a broker-posted property (NULL = not linked yet).
ALTER TABLE properties
    ADD COLUMN IF NOT EXISTS landlord_id UUID REFERENCES users(id) ON DELETE SET NULL;

-- The broker who introduced the deal (shown on the agreement as "Agent").
ALTER TABLE agreements
    ADD COLUMN IF NOT EXISTS agent_id UUID REFERENCES users(id) ON DELETE SET NULL;

-- Broker -> owner invitations. The owner accepts from their own account
-- (after Aadhaar KYC + their own UPI ID), which sets properties.landlord_id.
CREATE TABLE IF NOT EXISTS landlord_invites (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id      UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    broker_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code             TEXT NOT NULL UNIQUE,
    landlord_name    TEXT NOT NULL,
    landlord_phone   TEXT,
    landlord_email   TEXT,
    landlord_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    status           TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'accepted', 'declined', 'cancelled')),
    expires_at       TIMESTAMPTZ NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at     TIMESTAMPTZ
);

-- Only one open invite per property at a time.
CREATE UNIQUE INDEX IF NOT EXISTS landlord_invites_one_pending
    ON landlord_invites (property_id) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS landlord_invites_broker_idx ON landlord_invites (broker_id);