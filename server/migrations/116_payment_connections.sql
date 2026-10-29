-- 116: Online tahsilat saglayici baglantisi (site basina tek satir). Sirlar (API anahtari vb.) YALNIZ sifreli saklanir (AES-256-GCM, env PAYMENT_SECRET_KEY).
-- db.js (src/modules/payment_connection_schema.js) ile AYNI DDL; ekleyici ve idempotent; mevcut tablolara (payment_provider_settings dahil) DOKUNMAZ.
-- provider degeri CHECK ile kilitlenmez: gecerli kodlari sunucudaki saglayici kaydi (payment_providers.js) belirler; yeni suruculer migration istemez.
-- last_test_status 'ok' DEGILSE baglanti dogrulanmis sayilmaz; kimlik bilgileri degisince son sinama sifirlanir.
CREATE TABLE IF NOT EXISTS payment_provider_connections (
  site_code BIGINT PRIMARY KEY REFERENCES sites(site_code) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  mode TEXT NOT NULL DEFAULT 'test',
  public_config JSONB NOT NULL DEFAULT '{}'::jsonb,
  secrets_enc TEXT,
  last_test_at TIMESTAMPTZ,
  last_test_status TEXT,
  last_test_message TEXT,
  updated_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_payment_provider_connections_mode CHECK (mode IN ('test', 'live')),
  CONSTRAINT chk_payment_provider_connections_provider CHECK (char_length(provider) BETWEEN 1 AND 40)
);
