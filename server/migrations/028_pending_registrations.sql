-- 028: Bekleyen kayıt (pending_registrations)
-- Bireysel self-servis kayıtta `users` satırı, e-posta sahipliği doğru kodla kanıtlanana kadar OLUŞTURULMAZ.
-- Ad ve parola ÖZETİ (bcrypt; düz metin asla) burada bekler; doğrulamada tek işlemde users'a taşınır ve silinir.
-- db.js ensureDbSchema ile aynı DDL; yeni kurulumlarda migration runner ile uygulanabilsin diye eklendi.
-- Tamamen ekleyici (additive) ve idempotent; mevcut tabloları/verileri değiştirmez.
CREATE TABLE IF NOT EXISTS pending_registrations (
  id BIGSERIAL PRIMARY KEY,
  email TEXT NOT NULL,
  full_name TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- E-posta başına tek bekleyen kayıt (büyük/küçük harf duyarsız); upsert (ON CONFLICT ((LOWER(email)))) buna dayanır.
CREATE UNIQUE INDEX IF NOT EXISTS uq_pending_registrations_email
  ON pending_registrations (LOWER(email));

-- Bakım servisi 2 günden eski kayıtları siler (updated_at'e göre).
CREATE INDEX IF NOT EXISTS idx_pending_registrations_updated
  ON pending_registrations (updated_at);
