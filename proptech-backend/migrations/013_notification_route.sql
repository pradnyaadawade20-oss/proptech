-- Screen the app should open when a notification is tapped (e.g. /agreement/<id>/status)
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS route TEXT NOT NULL DEFAULT '';