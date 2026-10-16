-- 035: PLATFORM HIZMETLERI (satisa hazirlik): yasal belge onay kayitlari, istemci hata raporlari, bekleyen kayitta onay bilgisi
-- Sozlesme: docs/PLATFORM_SATISA_HAZIRLIK.md (1.1-1.4)
-- db.js ensureDbSchema ile aynı DDL; yeni kurulumlarda migration runner ile uygulanabilsin diye eklendi.
-- Ekleyici (additive) ve idempotent: mevcut satirlari DEGISTIRMEZ, veri yazmaz. Uygulama yapilandirmasi / destek / yasal sirket bilgisi
-- 033'teki platform_settings tablosunda (app.* / support.* / legal.* anahtarlari) tutulur; bu surumde yeni anahtar tohumlanmaz.

-- 1. Kullanici onay kayitlari. Ayni belge + surum bir kullanici icin tek satir (tekrar onay sessizce yok sayilir). Hesap kimliksizlestirilince
-- (satir kalir) kayitlar kalir; kullanici satiri gercekten silinirse (yonetici ham silme) kayitlar da gider.
-- source: 'register' (kayit akisi) | 'site_application' (site basvurusu) | 'in_app' (uygulama icinden sonradan onay).
CREATE TABLE IF NOT EXISTS user_consents (
  id BIGSERIAL PRIMARY KEY,
  user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
  document_id TEXT NOT NULL,
  version TEXT NOT NULL,
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  source TEXT NOT NULL DEFAULT 'in_app',
  CONSTRAINT uq_user_consents_user_document_version UNIQUE (user_code, document_id, version),
  CONSTRAINT chk_user_consents_document_id CHECK (document_id ~ '^[a-z][a-z0-9_]{1,39}$'),
  CONSTRAINT chk_user_consents_version CHECK (char_length(version) BETWEEN 1 AND 40),
  CONSTRAINT chk_user_consents_source CHECK (source ~ '^[a-z][a-z_]{1,39}$')
);

-- 2. Istemci hata raporlari. Metin alanlari sunucuda kisisel veriden TEMIZLENMIS gelir (e-posta, telefon, JWT / Bearer, uzun sayi dizileri);
-- tekrar eden hata parmak izine (sha256, 64 hex) gore tek satirda toplanir (count). Kullanici / cihaz / IP bilgisi SAKLANMAZ.
-- Satirlar first_seen'den 90 gun sonra silinir (client_error_purge.js, tek calisan advisory kilidi).
CREATE TABLE IF NOT EXISTS client_error_reports (
  id BIGSERIAL PRIMARY KEY,
  fingerprint TEXT NOT NULL,
  error_type TEXT NOT NULL,
  message TEXT NOT NULL,
  app_version TEXT NOT NULL,
  build TEXT,
  platform TEXT NOT NULL,
  os_version TEXT,
  route TEXT,
  fatal BOOLEAN NOT NULL DEFAULT FALSE,
  count INTEGER NOT NULL DEFAULT 1,
  first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sample_stack TEXT,
  CONSTRAINT uq_client_error_reports_fingerprint UNIQUE (fingerprint),
  CONSTRAINT chk_client_error_reports_fingerprint CHECK (char_length(fingerprint) = 64),
  CONSTRAINT chk_client_error_reports_platform CHECK (platform IN ('android', 'ios', 'web', 'other')),
  CONSTRAINT chk_client_error_reports_count CHECK (count >= 1),
  CONSTRAINT chk_client_error_reports_sizes CHECK (
    char_length(error_type) <= 100 AND char_length(message) <= 500 AND (sample_stack IS NULL OR char_length(sample_stack) <= 8000)
  )
);
CREATE INDEX IF NOT EXISTS idx_client_error_reports_last_seen ON client_error_reports (last_seen DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_client_error_reports_first_seen ON client_error_reports (first_seen);

-- 3. Bekleyen kayit (028): e-posta kodu girilene dek hesap OLUSMAZ; kullanicinin kayit sirasinda verdigi yasal belge onaylari burada bekler
-- ([{id, version, accepted_at}]) ve hesap GERCEKTEN olusurken ayni islemde user_consents'a yazilir.
ALTER TABLE pending_registrations
  ADD COLUMN IF NOT EXISTS accepted_documents JSONB CHECK (accepted_documents IS NULL OR jsonb_typeof(accepted_documents) = 'array');
