-- 116: Sayac tarifesi (birim fiyat): meter_tariffs. Sozlesme: docs/PLATFORM_SAYAC.md (Tarife).
-- db.js ensureDbSchema ile ayni DDL (src/modules/metering_tariff_schema.js METER_TARIFF_DDL; test: birebir esitlik, ayni sira).
-- Tamamen ekleyici (additive) ve idempotent: yeni tablo; mevcut tablolara sutun / indeks EKLEMEZ, defter semasina DOKUNMAZ.
-- Tarife SURELIDIR: [valid_from, valid_to) yari acik aralik; tur basina tek acik (valid_to bos) tarife olur, yeni tarife eskiyi valid_from tarihinde kapatir.
-- Gecmis faturalandirmalar etkilenmez: fiyat meter_billings.params icinde (unit_price_minor, tariff_id) kayit aninda dondurulur.
-- Silme politikasi: site silinince tarifeler CASCADE; kullanici silinince created_by SET NULL.

CREATE TABLE IF NOT EXISTS meter_tariffs (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  kind TEXT NOT NULL,
  unit_price_minor BIGINT NOT NULL,
  valid_from DATE NOT NULL,
  valid_to DATE,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_meter_tariffs_kind CHECK (kind IN ('water', 'electricity', 'heat', 'hot_water')),
  CONSTRAINT chk_meter_tariffs_price CHECK (unit_price_minor > 0),
  CONSTRAINT chk_meter_tariffs_range CHECK (valid_to IS NULL OR valid_to > valid_from)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meter_tariffs_site_code_fkey' AND conrelid = 'meter_tariffs'::regclass
  ) THEN
    ALTER TABLE meter_tariffs ADD CONSTRAINT meter_tariffs_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meter_tariffs_created_by_fkey' AND conrelid = 'meter_tariffs'::regclass
  ) THEN
    ALTER TABLE meter_tariffs ADD CONSTRAINT meter_tariffs_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_meter_tariffs_site_kind_from ON meter_tariffs (site_code, kind, valid_from);
