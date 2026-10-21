-- 061: Sayac Okuma ve Faturalandirma: meters, meter_readings, meter_billings, meter_billing_lines
-- Sozlesme: docs/PLATFORM_SAYAC.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/metering_schema.js METERING_DDL; test: metering_schema birebir esitlik, ayni sira).
-- Tamamen ekleyici (additive) ve idempotent: mevcut tablolara sutun / indeks EKLEMEZ, defter semasina DOKUNMAZ, hicbir satiri DEGISTIRMEZ / SILMEZ.
-- Tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumali bir ALTER TABLE'dir (ifade basina tek ust tablo).
-- Silme politikasi: site silinince tum sayac kayitlari CASCADE; daire silinince sayaclari ve okumalari CASCADE; kullanici silinince created_by / posted_by SET NULL.
-- Faturalandirma satirlarinin ledger_entry_id alani FK'siz (defter degismez ve sicak tablo; baglanti yalniz bilgi icin).

CREATE TABLE IF NOT EXISTS meters (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  kind TEXT NOT NULL,
  serial_no TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_meters_kind CHECK (kind IN ('water', 'electricity', 'heat', 'hot_water')),
  CONSTRAINT chk_meters_serial_length CHECK (char_length(serial_no) BETWEEN 1 AND 40)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meters_site_code_fkey' AND conrelid = 'meters'::regclass
  ) THEN
    ALTER TABLE meters ADD CONSTRAINT meters_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meters_apartment_id_fkey' AND conrelid = 'meters'::regclass
  ) THEN
    ALTER TABLE meters ADD CONSTRAINT meters_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meters_created_by_fkey' AND conrelid = 'meters'::regclass
  ) THEN
    ALTER TABLE meters ADD CONSTRAINT meters_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_meters_site_kind_serial ON meters (site_code, kind, lower(serial_no));

CREATE INDEX IF NOT EXISTS idx_meters_apartment ON meters (apartment_id);

CREATE TABLE IF NOT EXISTS meter_readings (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  meter_id BIGINT NOT NULL,
  reading_date DATE NOT NULL,
  value NUMERIC(14,3) NOT NULL,
  source TEXT NOT NULL DEFAULT 'manual',
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_meter_readings_value CHECK (value >= 0),
  CONSTRAINT chk_meter_readings_source CHECK (source IN ('manual', 'file'))
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meter_readings_site_code_fkey' AND conrelid = 'meter_readings'::regclass
  ) THEN
    ALTER TABLE meter_readings ADD CONSTRAINT meter_readings_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meter_readings_meter_id_fkey' AND conrelid = 'meter_readings'::regclass
  ) THEN
    ALTER TABLE meter_readings ADD CONSTRAINT meter_readings_meter_id_fkey FOREIGN KEY (meter_id) REFERENCES meters(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meter_readings_created_by_fkey' AND conrelid = 'meter_readings'::regclass
  ) THEN
    ALTER TABLE meter_readings ADD CONSTRAINT meter_readings_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_meter_readings_meter_date ON meter_readings (meter_id, reading_date);

CREATE TABLE IF NOT EXISTS meter_billings (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  kind TEXT NOT NULL,
  method TEXT NOT NULL,
  period_from DATE NOT NULL,
  period_to DATE NOT NULL,
  total_minor BIGINT NOT NULL,
  apartment_count INTEGER NOT NULL,
  params JSONB NOT NULL DEFAULT '{}'::JSONB,
  preview_hash TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  posted_by INTEGER,
  posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_meter_billings_kind CHECK (kind IN ('water', 'electricity', 'heat', 'hot_water')),
  CONSTRAINT chk_meter_billings_method CHECK (method IN ('unit_price', 'invoice', 'heat')),
  CONSTRAINT chk_meter_billings_period CHECK (period_to > period_from),
  CONSTRAINT chk_meter_billings_total CHECK (total_minor > 0 AND apartment_count > 0)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meter_billings_site_code_fkey' AND conrelid = 'meter_billings'::regclass
  ) THEN
    ALTER TABLE meter_billings ADD CONSTRAINT meter_billings_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meter_billings_posted_by_fkey' AND conrelid = 'meter_billings'::regclass
  ) THEN
    ALTER TABLE meter_billings ADD CONSTRAINT meter_billings_posted_by_fkey FOREIGN KEY (posted_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_meter_billings_key ON meter_billings (site_code, idempotency_key);

CREATE INDEX IF NOT EXISTS idx_meter_billings_site_kind ON meter_billings (site_code, kind, period_to);

CREATE TABLE IF NOT EXISTS meter_billing_lines (
  id BIGSERIAL PRIMARY KEY,
  billing_id BIGINT NOT NULL,
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  consumption NUMERIC(14,3) NOT NULL,
  amount_minor BIGINT NOT NULL,
  account_party TEXT NOT NULL,
  ledger_entry_id BIGINT,
  CONSTRAINT chk_meter_billing_lines_amount CHECK (amount_minor > 0),
  CONSTRAINT chk_meter_billing_lines_account CHECK (account_party IN ('owner', 'tenant'))
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meter_billing_lines_billing_id_fkey' AND conrelid = 'meter_billing_lines'::regclass
  ) THEN
    ALTER TABLE meter_billing_lines ADD CONSTRAINT meter_billing_lines_billing_id_fkey FOREIGN KEY (billing_id) REFERENCES meter_billings(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meter_billing_lines_site_code_fkey' AND conrelid = 'meter_billing_lines'::regclass
  ) THEN
    ALTER TABLE meter_billing_lines ADD CONSTRAINT meter_billing_lines_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_meter_billing_lines_billing ON meter_billing_lines (billing_id);
