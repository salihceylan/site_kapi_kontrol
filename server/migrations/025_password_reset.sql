-- 025_password_reset.sql: Kullanıcı şifre sıfırlama (şifremi unuttum) token ve süre alanları
ALTER TABLE users
ADD COLUMN IF NOT EXISTS password_reset_token_hash TEXT,
ADD COLUMN IF NOT EXISTS password_reset_expires_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_users_password_reset_token
ON users (password_reset_token_hash)
WHERE password_reset_token_hash IS NOT NULL;

