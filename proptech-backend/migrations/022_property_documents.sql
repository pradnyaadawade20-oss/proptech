-- A4: ownership documents. Files live in the database (like property_media) but
-- in their OWN table that no public route reads, so a document can never be
-- reached through a listing URL. Only the uploading owner and admins can fetch it.

CREATE TABLE IF NOT EXISTS property_documents (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    property_id   UUID        NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    uploaded_by   UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    doc_type      TEXT        NOT NULL
                  CHECK (doc_type IN ('sale_deed','property_tax_receipt','electricity_bill',
                                      'allotment_letter','society_noc','other')),
    file_name     TEXT        NOT NULL DEFAULT '',
    content_type  TEXT        NOT NULL CHECK (content_type IN ('application/pdf','image/jpeg','image/png')),
    size_bytes    INTEGER     NOT NULL CHECK (size_bytes > 0),
    sha256        TEXT        NOT NULL,
    data          BYTEA       NOT NULL,
    status        TEXT        NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','approved','rejected')),
    reject_reason TEXT        NOT NULL DEFAULT '',
    reviewed_by   TEXT        NOT NULL DEFAULT '',
    reviewed_at   TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- the same file cannot be uploaded twice for one property
    UNIQUE (property_id, sha256)
);

CREATE INDEX IF NOT EXISTS idx_property_documents_property ON property_documents (property_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_property_documents_status   ON property_documents (status, created_at);