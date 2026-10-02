-- 012_qr_token_expiration.sql
-- Aşama 2: QR erişim tokenlerine süre (expiration) ekleme

ALTER TABLE qr_access_tokens
ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- Eski süresiz kayıtlar için 10 yıl sonrasına ayarla (geriye uyumluluk)
UPDATE qr_access_tokens
SET expires_at = created_at + INTERVAL '10 years'
WHERE expires_at IS NULL;

-- Yeni kayıtlar için varsayılan kural
ALTER TABLE qr_access_tokens
ALTER COLUMN expires_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_expires
ON qr_access_tokens(expires_at);

