-- 027: users.updated_at, LOWER(email) indeksi, join_requests.notes ve doğrulama kodu arama indeksi
-- (db.js ensureDbSchema ile aynı DDL; yeni kurulumlarda migration runner ile uygulanabilsin diye eklendi).
-- Tamamen ekleyici (additive) ve idempotent.
ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
CREATE INDEX IF NOT EXISTS idx_users_email_lower ON users (LOWER(email));
ALTER TABLE join_requests ADD COLUMN IF NOT EXISTS notes TEXT;
CREATE INDEX IF NOT EXISTS idx_email_verifications_email_created
  ON email_verifications (LOWER(email), created_at DESC);
