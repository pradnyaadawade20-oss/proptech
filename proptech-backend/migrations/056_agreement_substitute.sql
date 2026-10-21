-- Substitute payer written into the agreement: filled by the tenant before
-- signing. If the tenant is unavailable, this person pays the rent.
ALTER TABLE agreements ADD COLUMN IF NOT EXISTS substitute_name     TEXT;
ALTER TABLE agreements ADD COLUMN IF NOT EXISTS substitute_phone    TEXT;
ALTER TABLE agreements ADD COLUMN IF NOT EXISTS substitute_relation TEXT;