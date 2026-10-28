-- 097: Drive dosya kaydinin kaynak kayda baglanmasi (P1-11). Ekleyici, idempotent; mevcut satirlara dokunmaz (kaynak NULL = baglanmamis).
-- db.js ile ayni ifadeler, ayni sira (src/modules/drive_source_schema.js DRIVE_SOURCE_DDL; test: drive_source_schema).
-- source_type + source_id: dosyanin ait oldugu kayit (is kaydi, sayac okumasi, gider, dekont...). Dosya adi da ayni kimligi tasir (IS-123_AB_D13_201026.pdf);
-- belge hem adindan hem kayittan acilsin diye. Ikisi birlikte dolu ya da birlikte bos; tur kisa kucuk-harf kimlik, no pozitif.
-- NOT VALID: mevcut satirlar taranmaz (hepsi NULL/NULL); yeni satirlara uygulanir.

ALTER TABLE drive_files ADD COLUMN IF NOT EXISTS source_type TEXT;

ALTER TABLE drive_files ADD COLUMN IF NOT EXISTS source_id BIGINT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_drive_files_source' AND conrelid = 'drive_files'::regclass
  ) THEN
    ALTER TABLE drive_files ADD CONSTRAINT chk_drive_files_source CHECK ((source_type IS NULL AND source_id IS NULL) OR (source_type IS NOT NULL AND source_id IS NOT NULL AND source_type ~ '^[a-z][a-z_]{0,31}$' AND source_id > 0)) NOT VALID;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_drive_files_source ON drive_files (site_code, source_type, source_id) WHERE source_type IS NOT NULL;
