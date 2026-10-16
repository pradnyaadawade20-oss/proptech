-- Share-link flow: the broker sends the owner a link (WhatsApp / SMS) that opens the app.
-- The old short invite code is replaced by a long, unguessable token carried in the link.

ALTER TABLE landlord_invites ADD COLUMN IF NOT EXISTS token TEXT;

UPDATE landlord_invites
   SET token = replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')
 WHERE token IS NULL;

ALTER TABLE landlord_invites ALTER COLUMN token SET NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS landlord_invites_token_key ON landlord_invites (token);

ALTER TABLE landlord_invites DROP COLUMN IF EXISTS code;

-- A broker listing is public only after the owner approves (properties.landlord_id gets set).
CREATE INDEX IF NOT EXISTS idx_properties_live ON properties (posted_by, landlord_id);