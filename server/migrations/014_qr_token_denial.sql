-- 014_qr_token_denial.sql
-- QR kodun yetkisiz/başka kapıya okutulması veya reddedilme durumlarını takip eden sütunlar

ALTER TABLE qr_access_tokens
ADD COLUMN IF NOT EXISTS last_denial_reason TEXT;

ALTER TABLE qr_access_tokens
ADD COLUMN IF NOT EXISTS last_denied_at TIMESTAMPTZ;

ALTER TABLE qr_access_tokens
ADD COLUMN IF NOT EXISTS denied_door_name TEXT;

