-- BUG FIX: the DB trigger blocked the 4th listing even when the broker had an
-- active paid plan (it only looked at listings_limit). Now an active
-- monthly/yearly plan (expires_at in the future) means unlimited.
CREATE OR REPLACE FUNCTION enforce_broker_listing_limit() RETURNS trigger AS $$
DECLARE
    lim      INT;
    used     INT;
    role_now TEXT;
    p_type   TEXT;
    p_exp    TIMESTAMPTZ;
BEGIN
    IF NEW.owner_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.posted_by IS DISTINCT FROM 'broker' THEN
        SELECT COALESCE(active_role, role) INTO role_now FROM users WHERE id = NEW.owner_id;
        IF role_now = 'broker' THEN
            NEW.posted_by := 'broker';
        END IF;
    END IF;

    IF NEW.posted_by IS DISTINCT FROM 'broker' THEN
        RETURN NEW;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('broker_listing_limit:' || NEW.owner_id::text, 0));

    SELECT listings_limit, plan_type, expires_at INTO lim, p_type, p_exp
    FROM broker_subscriptions WHERE broker_id = NEW.owner_id;
    IF NOT FOUND THEN
        lim := 3;
    END IF;

    -- active paid plan = unlimited
    IF p_type IS NOT NULL AND p_type <> 'free' AND p_exp IS NOT NULL AND p_exp > now() THEN
        RETURN NEW;
    END IF;

    SELECT count(*) INTO used FROM properties WHERE owner_id = NEW.owner_id AND posted_by = 'broker';
    IF used >= lim THEN
        RAISE EXCEPTION 'BROKER_LIMIT_REACHED used=% limit=%', used, lim USING ERRCODE = 'PB001';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;