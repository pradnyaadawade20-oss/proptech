-- B2: lock down lead values (019_leads.sql created the table, nothing wrote to it yet).
ALTER TABLE leads
    ADD CONSTRAINT leads_status_chk CHECK (status IN ('new', 'contacted', 'visited', 'closed')),
    ADD CONSTRAINT leads_source_chk CHECK (source IN ('contact', 'call', 'chat', 'visit'));