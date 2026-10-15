-- Commission is agreed BEFORE the rental agreement: agent proposes -> tenant accepts -> tenant pays after both sign.
-- So it hangs off the agreement (not the lease, which only exists after signing).
ALTER TABLE lease_commissions ADD COLUMN IF NOT EXISTS agreement_id UUID REFERENCES agreements(id) ON DELETE CASCADE;
ALTER TABLE lease_commissions ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;

UPDATE lease_commissions c SET agreement_id = l.agreement_id
  FROM leases l WHERE l.id = c.lease_id AND c.agreement_id IS NULL;

ALTER TABLE lease_commissions DROP CONSTRAINT IF EXISTS lease_commissions_status_check;
ALTER TABLE lease_commissions ADD CONSTRAINT lease_commissions_status_check
    CHECK (status IN ('requested', 'accepted', 'paid'));
-- rows made by the earlier lease-based version count as accepted
UPDATE lease_commissions SET status = 'accepted', accepted_at = now() WHERE status = 'requested';

ALTER TABLE lease_commissions ALTER COLUMN lease_id DROP NOT NULL;
ALTER TABLE lease_commissions ALTER COLUMN agreement_id SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_lease_commissions_agreement ON lease_commissions(agreement_id);