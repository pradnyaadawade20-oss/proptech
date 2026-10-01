-- Admin panel logins. Only a bcrypt hash is stored, never the password.
CREATE TABLE IF NOT EXISTS admins (
    email         TEXT PRIMARY KEY,
    password_hash TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO admins (email, password_hash)
VALUES ('admin@proptech.in', '$2a$12$7ta9WZgT1l.m6xMVnxfDO.VFl8faItUc7EG.x9n/AlTYcXUxK.6b6')
ON CONFLICT (email) DO NOTHING;