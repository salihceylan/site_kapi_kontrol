-- 015_qr_single_use.sql
-- Aşama 3: QR kodunu tek kullanımlık yapma ve yarış durumu (race condition) koruması

ALTER TABLE qr_access_tokens
ADD COLUMN IF NOT EXISTS is_used BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE qr_access_tokens
ADD COLUMN IF NOT EXISTS used_door_id INTEGER;

ALTER TABLE qr_access_tokens
ADD COLUMN IF NOT EXISTS used_device_uid VARCHAR(32);

CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_is_used
ON qr_access_tokens(is_used);

CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_used_door_id
ON qr_access_tokens(used_door_id);

