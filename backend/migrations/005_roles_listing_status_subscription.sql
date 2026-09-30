-- Matches new frontend features:
--   1. Multi-role accounts (UserSession.activeRoles + currentRole) — a person
--      can be Buyer/Tenant AND Owner AND Broker on one account, switching
--      between them without logging out.
--   2. Property listing status shown on Owner/Broker Dashboard stat pills
--      ("5 Available, 2 Rented, 1 Sold").
--   3. Broker subscription/plan card on Broker Dashboard
--      ("Free Plan, 3 of 3 listings used" + Upgrade).

-- 1. Multi-role support
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS roles TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS active_role VARCHAR(20);

-- Backfill from the existing single `role` column so current rows keep working.
UPDATE users
SET roles = ARRAY[role], active_role = role
WHERE roles = '{}';

-- 2. Listing status
ALTER TABLE properties
    ADD COLUMN IF NOT EXISTS listing_status VARCHAR(20) NOT NULL DEFAULT 'available';
    -- 'available' | 'rented' | 'sold'

-- 3. Broker subscription
CREATE TABLE IF NOT EXISTS broker_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    broker_id UUID REFERENCES users(id) ON DELETE CASCADE UNIQUE,
    plan_name VARCHAR(50) NOT NULL DEFAULT 'Free Plan',
    listings_limit INT NOT NULL DEFAULT 3,
    created_at TIMESTAMP DEFAULT NOW()
);