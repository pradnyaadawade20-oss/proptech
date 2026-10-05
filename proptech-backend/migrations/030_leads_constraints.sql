-- B2: lead values lock (019_leads.sql created the table).
-- NOT VALID = only new/updated rows are checked, so old rows can't break the deploy.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'leads_status_chk') THEN
        ALTER TABLE leads ADD CONSTRAINT leads_status_chk
            CHECK (status IN ('new', 'contacted', 'visited', 'closed')) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'leads_source_chk') THEN
        ALTER TABLE leads ADD CONSTRAINT leads_source_chk
            CHECK (source IN ('contact', 'call', 'chat', 'visit')) NOT VALID;
    END IF;
END $$;