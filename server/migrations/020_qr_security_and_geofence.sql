-- 020_qr_security_and_geofence.sql
-- Aşama 4, 5, 6, 7: Dinamik QR Güvenliği, Token İptali, Geofence ve Sahte Konum Koruması

-- 1. qr_access_tokens tablosuna iptal ve konum doğrulama sütunları ekle
ALTER TABLE qr_access_tokens
ADD COLUMN IF NOT EXISTS superseded_at TIMESTAMPTZ;

ALTER TABLE qr_access_tokens
ADD COLUMN IF NOT EXISTS request_latitude DOUBLE PRECISION;

ALTER TABLE qr_access_tokens
ADD COLUMN IF NOT EXISTS request_longitude DOUBLE PRECISION;

ALTER TABLE qr_access_tokens
ADD COLUMN IF NOT EXISTS request_accuracy DOUBLE PRECISION;

ALTER TABLE qr_access_tokens
ADD COLUMN IF NOT EXISTS is_mocked BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. Hızlı sorgulama için indeksler
CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_user_door_active
ON qr_access_tokens(user_code, door_id, is_active);

CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_superseded
ON qr_access_tokens(superseded_at)
WHERE superseded_at IS NOT NULL;

