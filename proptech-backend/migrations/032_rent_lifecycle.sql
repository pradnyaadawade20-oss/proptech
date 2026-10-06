-- Rent lifecycle: lease, monthly rent schedule, deposit, move-in/out photos,
-- renewal, maintenance tickets and an audit trail.

ALTER TABLE agreements ADD COLUMN IF NOT EXISTS renewal_of_lease_id UUID;

CREATE TABLE IF NOT EXISTS leases (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agreement_id          UUID NOT NULL UNIQUE REFERENCES agreements(id) ON DELETE CASCADE,
    property_id           UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    owner_id              UUID NOT NULL REFERENCES users(id),
    tenant_id             UUID NOT NULL REFERENCES users(id),
    monthly_rent          NUMERIC(12,2) NOT NULL,
    security_deposit      NUMERIC(12,2) NOT NULL DEFAULT 0,
    start_date            DATE NOT NULL,
    end_date              DATE NOT NULL,
    grace_days            INT NOT NULL DEFAULT 5,
    late_fee_per_day      NUMERIC(10,2) NOT NULL DEFAULT 0,
    status                TEXT NOT NULL DEFAULT 'active'
                          CHECK (status IN ('active', 'notice_given', 'moved_out', 'renewed')),
    renewal_status        TEXT NOT NULL DEFAULT 'none'
                          CHECK (renewal_status IN ('none', 'renew_requested', 'renew_accepted', 'renew_declined', 'vacate')),
    renewal_prompt_stage  INT NOT NULL DEFAULT 0,
    renewed_agreement_id  UUID,
    previous_lease_id     UUID,
    move_out_date         DATE,
    moved_out_at          TIMESTAMPTZ,
    move_in_confirmed_at  TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_leases_owner    ON leases(owner_id);
CREATE INDEX IF NOT EXISTS idx_leases_tenant   ON leases(tenant_id);
CREATE INDEX IF NOT EXISTS idx_leases_property ON leases(property_id);
CREATE INDEX IF NOT EXISTS idx_leases_status   ON leases(status, end_date);

CREATE TABLE IF NOT EXISTS rent_payments (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lease_id           UUID NOT NULL REFERENCES leases(id) ON DELETE CASCADE,
    period_no          INT NOT NULL,
    due_date           DATE NOT NULL,
    amount             NUMERIC(12,2) NOT NULL,
    status             TEXT NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending', 'submitted', 'paid')),
    late_days          INT NOT NULL DEFAULT 0,
    late_fee           NUMERIC(12,2) NOT NULL DEFAULT 0,
    payment_method     TEXT,
    reference          TEXT,
    submitted_at       TIMESTAMPTZ,
    paid_at            TIMESTAMPTZ,
    receipt_no         TEXT,
    reject_reason      TEXT,
    remind_3d_at       TIMESTAMPTZ,
    remind_due_at      TIMESTAMPTZ,
    remind_overdue_at  TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (lease_id, period_no)
);
CREATE INDEX IF NOT EXISTS idx_rent_payments_due ON rent_payments(status, due_date);

CREATE TABLE IF NOT EXISTS lease_deposits (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lease_id          UUID NOT NULL UNIQUE REFERENCES leases(id) ON DELETE CASCADE,
    amount            NUMERIC(12,2) NOT NULL,
    status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'submitted', 'held', 'inspection', 'settlement',
                                        'disputed', 'refund_due', 'refunded', 'carried_forward')),
    payment_method    TEXT,
    reference         TEXT,
    submitted_at      TIMESTAMPTZ,
    received_at       TIMESTAMPTZ,
    total_deductions  NUMERIC(12,2) NOT NULL DEFAULT 0,
    refund_amount     NUMERIC(12,2) NOT NULL DEFAULT 0,
    tenant_owes       NUMERIC(12,2) NOT NULL DEFAULT 0,
    tenant_note       TEXT,
    admin_note        TEXT,
    refund_method     TEXT,
    refund_reference  TEXT,
    settlement_at     TIMESTAMPTZ,
    responded_at      TIMESTAMPTZ,
    refunded_at       TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS deposit_deductions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deposit_id  UUID NOT NULL REFERENCES lease_deposits(id) ON DELETE CASCADE,
    category    TEXT NOT NULL CHECK (category IN ('damage', 'unpaid_rent', 'cleaning', 'other')),
    reason      TEXT NOT NULL,
    amount      NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    created_by  UUID,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_deductions_deposit ON deposit_deductions(deposit_id);

CREATE TABLE IF NOT EXISTS maintenance_tickets (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lease_id     UUID NOT NULL REFERENCES leases(id) ON DELETE CASCADE,
    property_id  UUID NOT NULL REFERENCES properties(id) ON DELETE CASCADE,
    tenant_id    UUID NOT NULL REFERENCES users(id),
    owner_id     UUID NOT NULL REFERENCES users(id),
    title        TEXT NOT NULL,
    description  TEXT NOT NULL DEFAULT '',
    category     TEXT NOT NULL DEFAULT 'other'
                 CHECK (category IN ('plumbing', 'electrical', 'appliance', 'structural', 'pest', 'other')),
    priority     TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'urgent')),
    status       TEXT NOT NULL DEFAULT 'reported'
                 CHECK (status IN ('reported', 'in_progress', 'resolved')),
    resolved_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tickets_lease  ON maintenance_tickets(lease_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tickets_status ON maintenance_tickets(status, priority);

CREATE TABLE IF NOT EXISTS maintenance_updates (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id  UUID NOT NULL REFERENCES maintenance_tickets(id) ON DELETE CASCADE,
    actor_id   UUID NOT NULL,
    status     TEXT NOT NULL,
    note       TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ticket_updates ON maintenance_updates(ticket_id, created_at);

-- One table for every photo in the lease: move-in, move-out, damage proof
-- (deposit deductions) and maintenance issues.
CREATE TABLE IF NOT EXISTS lease_photos (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lease_id      UUID NOT NULL REFERENCES leases(id) ON DELETE CASCADE,
    uploader_id   UUID NOT NULL REFERENCES users(id),
    kind          TEXT NOT NULL CHECK (kind IN ('move_in', 'move_out', 'damage', 'maintenance')),
    room          TEXT NOT NULL DEFAULT 'Other',
    caption       TEXT NOT NULL DEFAULT '',
    deduction_id  UUID REFERENCES deposit_deductions(id) ON DELETE CASCADE,
    ticket_id     UUID REFERENCES maintenance_tickets(id) ON DELETE CASCADE,
    content_type  TEXT NOT NULL,
    data          BYTEA NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_lease_photos_lease ON lease_photos(lease_id, kind);

-- Audit trail: who did what and when (used for disputes / admin review).
CREATE TABLE IF NOT EXISTS lease_events (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lease_id   UUID NOT NULL REFERENCES leases(id) ON DELETE CASCADE,
    actor_id   TEXT NOT NULL,            -- user uuid, 'system' or 'admin'
    event      TEXT NOT NULL,
    detail     TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_lease_events ON lease_events(lease_id, created_at);