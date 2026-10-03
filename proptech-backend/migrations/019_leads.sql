-- Step 2: leads (buyer -> owner/broker enquiries).
CREATE TABLE IF NOT EXISTS leads (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    owner_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    buyer_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        VARCHAR(255) NOT NULL DEFAULT '',
    phone       VARCHAR(20)  NOT NULL DEFAULT '',
    message     TEXT         NOT NULL DEFAULT '',
    source      VARCHAR(20)  NOT NULL DEFAULT 'contact', -- contact | call | chat | visit
    status      VARCHAR(20)  NOT NULL DEFAULT 'new',     -- new | contacted | visited | closed
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (property_id, buyer_id)                       -- one lead per buyer per property
);

CREATE INDEX IF NOT EXISTS idx_leads_owner  ON leads (owner_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_leads_buyer  ON leads (buyer_id, created_at DESC);