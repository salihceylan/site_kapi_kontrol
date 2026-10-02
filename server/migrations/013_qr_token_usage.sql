-- 013_qr_token_usage.sql
-- QR tokenin kapıda GM60 tarafından kullanılıp kullanılmadığını takip eden sütunlar

ALTER TABLE qr_access_tokens
ADD COLUMN IF NOT EXISTS used_at TIMESTAMPTZ;

ALTER TABLE qr_access_tokens
ADD COLUMN IF NOT EXISTS use_count INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_used_at
ON qr_access_tokens(used_at);

