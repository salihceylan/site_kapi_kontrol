-- 065: Kart odemesi saglayici ayarlari + kamera/plaka baglastiricilari (F6 + T8). Kaynak: src/modules/device_integrations_schema.js (ayni ifadeler, ayni sira).
-- Tamamen ekleyici ve idempotent; mevcut tablolara dokunmaz. Kamera sifresi uygulama katmaninda AES-256-GCM ile sifrelenir (password_enc).

CREATE TABLE IF NOT EXISTS payment_provider_settings (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  provider TEXT NOT NULL,
  commission_info TEXT,
  updated_by INTEGER,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_payment_provider_settings_provider CHECK (provider IN ('iyzico', 'paytr')),
  CONSTRAINT chk_payment_provider_settings_info CHECK (commission_info IS NULL OR char_length(commission_info) <= 300),
  CONSTRAINT uq_payment_provider_settings UNIQUE (site_code, provider)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'payment_provider_settings_site_code_fkey' AND conrelid = 'payment_provider_settings'::regclass) THEN
    ALTER TABLE payment_provider_settings ADD CONSTRAINT payment_provider_settings_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS camera_devices (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  brand TEXT NOT NULL,
  name TEXT NOT NULL,
  host TEXT NOT NULL,
  port INTEGER,
  username TEXT,
  password_enc TEXT,
  token_hash TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  last_event_at TIMESTAMPTZ,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_camera_devices_brand CHECK (brand IN ('hikvision', 'tiandy', 'onvif')),
  CONSTRAINT chk_camera_devices_name CHECK (char_length(name) BETWEEN 1 AND 60),
  CONSTRAINT chk_camera_devices_host CHECK (char_length(host) BETWEEN 1 AND 120),
  CONSTRAINT chk_camera_devices_port CHECK (port IS NULL OR port BETWEEN 1 AND 65535)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'camera_devices_site_code_fkey' AND conrelid = 'camera_devices'::regclass) THEN
    ALTER TABLE camera_devices ADD CONSTRAINT camera_devices_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_camera_devices_site ON camera_devices (site_code, id DESC);

CREATE TABLE IF NOT EXISTS plate_events (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  device_id BIGINT NOT NULL,
  plate TEXT NOT NULL,
  matched BOOLEAN NOT NULL DEFAULT FALSE,
  vehicle_id BIGINT,
  seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_plate_events_plate CHECK (plate ~ '^[A-Z0-9]{5,10}$')
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_events_site_code_fkey' AND conrelid = 'plate_events'::regclass) THEN
    ALTER TABLE plate_events ADD CONSTRAINT plate_events_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_plate_events_site ON plate_events (site_code, id DESC);
