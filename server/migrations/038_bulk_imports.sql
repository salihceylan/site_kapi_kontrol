-- 038: Toplu yükleme (Excel/CSV) çalıştırma kayıtları (Faz 2b)
-- Sözleşme: docs/PLATFORM_TOPLU_ISLEMLER.md ("Veritabanı")
-- db.js ensureDbSchema ile aynı DDL (src/modules/bulk_import_schema.js BULK_IMPORT_DDL; test: bulk_import_schema birebir eşitlik).
-- Ekleyici (additive) ve idempotent: tek yeni tablo; var olan hiçbir tabloya sütun/indeks eklenmez, hiçbir satır DEĞİŞTİRİLMEZ / SİLİNMEZ.
-- db.js'te bu ifadeler dev ensureDbSchema bloğunun DIŞINDA, katalog kontrolüyle yalnız EKSİK olanlar için çalışır (açılışta yazıcılarla 40P01 üretmesin);
-- migration çalıştırıcısı (migrate.js) tek işlemde, bilinçli ve bir kez uyguladığı için burada doğrudan yazılır.
-- Tablo FK'SIZ oluşturulur, iki yabancı anahtar AYRI ifadelerle eklenir: satır içi REFERENCES sites + users ShareRowExclusive kilidini iki tabloda ardışık alır ve
-- (UPDATE sites ... UPDATE users) yapan yazıcılarla açılışta deadlock üretir (QA'da ölçüldü); ayrı ifadeler her seferinde TEK tabloyu kilitler.

-- Bir toplu yükleme (preview'dan onaylanan commit) = bir satır. Kişisel veri TAŞIMAZ: ad, e-posta, telefon, plaka, hücre değeri ASLA saklanmaz; yalnız
-- sayılar ve özetler (counts). (site_code, idempotency_key) tekildir: aynı anahtar + aynı parmak izi yeniden gönderilirse yeni yazım yapılmaz (replay).
-- Kayıtlar silinmez (site silinince CASCADE). created_by: işlemi yapan yönetici (hesap silinirse NULL; kayıt kalır).
CREATE TABLE IF NOT EXISTS bulk_import_runs (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  kind TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  preview_hash TEXT NOT NULL,
  strict BOOLEAN NOT NULL DEFAULT FALSE,
  allow_overwrite BOOLEAN NOT NULL DEFAULT FALSE,
  row_count INTEGER NOT NULL,
  counts JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_bulk_import_runs_kind CHECK (kind IN ('apartments', 'people', 'vehicles')),
  CONSTRAINT chk_bulk_import_runs_key CHECK (char_length(idempotency_key) BETWEEN 8 AND 64),
  CONSTRAINT chk_bulk_import_runs_fingerprint CHECK (char_length(request_fingerprint) = 64),
  CONSTRAINT chk_bulk_import_runs_hash CHECK (char_length(preview_hash) = 64),
  CONSTRAINT chk_bulk_import_runs_rows CHECK (row_count >= 0),
  CONSTRAINT chk_bulk_import_runs_counts CHECK (jsonb_typeof(counts) = 'object')
);
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_bulk_import_runs_site' AND conrelid = 'bulk_import_runs'::regclass
  ) THEN
    ALTER TABLE bulk_import_runs ADD CONSTRAINT fk_bulk_import_runs_site
      FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_bulk_import_runs_created_by' AND conrelid = 'bulk_import_runs'::regclass
  ) THEN
    ALTER TABLE bulk_import_runs ADD CONSTRAINT fk_bulk_import_runs_created_by
      FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS uq_bulk_import_runs_key ON bulk_import_runs (site_code, idempotency_key);
CREATE INDEX IF NOT EXISTS idx_bulk_import_runs_site ON bulk_import_runs (site_code, id DESC);
-- users FK'sinin (ON DELETE SET NULL) kullanıcı KALICI silinirken sıralı taramaya düşmemesi için kısmi indeks.
CREATE INDEX IF NOT EXISTS idx_bulk_import_runs_created_by ON bulk_import_runs (created_by) WHERE created_by IS NOT NULL;
