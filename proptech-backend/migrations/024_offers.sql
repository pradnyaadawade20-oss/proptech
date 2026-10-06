-- Phase 1: Buy offers (buyer -> owner, owner counter, one accepted per property)
CREATE TABLE IF NOT EXISTS offers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id     UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    buyer_id        UUID NOT NULL REFERENCES users(id),
    initiated_by    TEXT NOT NULL CHECK (initiated_by IN ('buyer', 'owner')),
    amount          NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
    status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN
                        ('pending', 'countered', 'accepted', 'rejected',
                         'expired', 'superseded', 'withdrawn')),
    expires_at      TIMESTAMPTZ NOT NULL,
    parent_offer_id UUID REFERENCES offers(id),
    root_offer_id   UUID REFERENCES offers(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Ek property par sirf ek accepted offer
CREATE UNIQUE INDEX IF NOT EXISTS one_accepted_offer_per_property
    ON offers (property_id) WHERE status = 'accepted';

CREATE INDEX IF NOT EXISTS idx_offers_property ON offers (property_id);
CREATE INDEX IF NOT EXISTS idx_offers_buyer    ON offers (buyer_id);
CREATE INDEX IF NOT EXISTS idx_offers_root     ON offers (root_offer_id);