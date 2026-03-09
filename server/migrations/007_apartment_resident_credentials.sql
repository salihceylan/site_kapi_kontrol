ALTER TABLE apartments
ADD COLUMN IF NOT EXISTS resident_email TEXT;

ALTER TABLE apartments
ADD COLUMN IF NOT EXISTS resident_pin_code TEXT;
