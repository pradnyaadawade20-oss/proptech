-- Rental/Sale agreements with e-signature (draw or type, no OTP)
CREATE TABLE IF NOT EXISTS agreements (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id     UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    owner_id        UUID NOT NULL REFERENCES users(id),
    tenant_id       UUID NOT NULL REFERENCES users(id),

    status          TEXT NOT NULL DEFAULT 'requested',
    -- requested -> draft_ready -> awaiting_signatures -> signed_by_owner
    -- -> signed_by_tenant -> completed | rejected | cancelled

    monthly_rent    NUMERIC(12,2),
    security_deposit NUMERIC(12,2),
    start_date      DATE,
    duration_months INT,
    terms           TEXT, -- generated draft text, editable before signing

    owner_signature_type   TEXT, -- 'draw' | 'type'
    owner_signature_data   TEXT, -- base64 PNG (draw) or typed name string (type)
    owner_signed_at        TIMESTAMPTZ,

    tenant_signature_type  TEXT,
    tenant_signature_data  TEXT,
    tenant_signed_at       TIMESTAMPTZ,

    final_pdf_url   TEXT, -- generated once both parties have signed

    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_agreements_property ON agreements(property_id);
CREATE INDEX IF NOT EXISTS idx_agreements_owner ON agreements(owner_id);
CREATE INDEX IF NOT EXISTS idx_agreements_tenant ON agreements(tenant_id);