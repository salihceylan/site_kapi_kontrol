-- 070: Sayac okuma fotograflari (gorevli sahada fotografla okur; Drive bagli degilse fotograf sunucuda bu tabloda tutulur).
-- db.js ensureDbSchema ile AYNI DDL (src/modules/metering_field_schema.js). Tamamen ekleyici ve idempotent.

CREATE TABLE IF NOT EXISTS meter_reading_photos (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  meter_id BIGINT NOT NULL,
  reading_id BIGINT NOT NULL,
  name TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  sha256 TEXT NOT NULL,
  data BYTEA NOT NULL,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_meter_reading_photos_size CHECK (size_bytes > 0 AND size_bytes <= 1048576)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'meter_reading_photos_site_code_fkey' AND conrelid = 'meter_reading_photos'::regclass) THEN
    ALTER TABLE meter_reading_photos ADD CONSTRAINT meter_reading_photos_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'meter_reading_photos_reading_id_fkey' AND conrelid = 'meter_reading_photos'::regclass) THEN
    ALTER TABLE meter_reading_photos ADD CONSTRAINT meter_reading_photos_reading_id_fkey FOREIGN KEY (reading_id) REFERENCES meter_readings(id) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_meter_reading_photos_site ON meter_reading_photos (site_code, reading_id);
