-- 100: Is Takibi kategorileri (site basina yonetilebilir) + fotograf yeniden kullanim indeksi
-- Sozlesme: docs/PLATFORM_IS_TAKIBI.md "Kategoriler (100)" ve "Fotograf yeniden kullanim uyarisi (100)"
-- db.js ensureDbSchema ile ayni DDL (src/modules/work_categories_schema.js WORK_CATEGORIES_DDL; test: work_categories birebir esitlik, ayni sira).
-- Bir yeni tablo (work_categories) + uc degisiklik: work_items.chk_work_items_category (sabit 4 kategori) yerine chk_work_items_category_key (dort varsayilan anahtar
-- YA DA k_<ad>); DROP + ADD ayni DO blogunda = tek islem, kisitsiz pencere yok; eski kisit yoksa ve yenisi varsa hicbir sey yapilmaz. Eski kodla uyumludur (eski surum
-- yalniz dort anahtari yazar). Iki yeni indeks: idx_work_items_site_category (kategori suzgeci / kullanim sayimi / "kullanilmis kategori silinmez" denetimi) ve
-- idx_work_item_attachments_site_sha256 ("ayni fotograf baska kayitta da var" uyarisi). Hicbir satiri DEGISTIRMEZ / SILMEZ.
-- Varsayilan dort kategori her site icin ILK KULLANIMDA (sunucu kodu) tohumlanir; bu dosyada veri adimi yoktur.
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle yalniz EKSIK olanlar icin calisir (acilis 40P01 dersi, bkz. 042 / 047).
-- Yabanci anahtarlar (R11 F1): tablo FK'SIZ olusturulur, her FK ayri ve katalog korumali bir ALTER TABLE'dir (ifade basina tek sicak ust tablo).
-- Silme politikasi: site silinince kategoriler CASCADE; kullanici silinince created_by SET NULL.

CREATE TABLE IF NOT EXISTS work_categories (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  key TEXT NOT NULL,
  label TEXT NOT NULL,
  is_system BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_work_categories_key CHECK (key IN ('ariza', 'bakim', 'sikayet_oneri', 'diger') OR key ~ '^k_[a-z0-9_]{1,38}$'),
  CONSTRAINT chk_work_categories_label_length CHECK (char_length(label) BETWEEN 1 AND 60),
  CONSTRAINT chk_work_categories_sort_order CHECK (sort_order BETWEEN 0 AND 100000),
  CONSTRAINT chk_work_categories_system_key CHECK (is_system = (key IN ('ariza', 'bakim', 'sikayet_oneri', 'diger')))
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_categories_site_code_fkey' AND conrelid = 'work_categories'::regclass
  ) THEN
    ALTER TABLE work_categories ADD CONSTRAINT work_categories_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_categories_created_by_fkey' AND conrelid = 'work_categories'::regclass
  ) THEN
    ALTER TABLE work_categories ADD CONSTRAINT work_categories_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_work_categories_site_key ON work_categories (site_code, key);

CREATE UNIQUE INDEX IF NOT EXISTS uq_work_categories_site_label ON work_categories (site_code, lower(label));

CREATE INDEX IF NOT EXISTS idx_work_items_site_category ON work_items (site_code, category);

CREATE INDEX IF NOT EXISTS idx_work_item_attachments_site_sha256 ON work_item_attachments (site_code, sha256) WHERE sha256 IS NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_items_category' AND conrelid = 'work_items'::regclass
  ) THEN
    ALTER TABLE work_items DROP CONSTRAINT chk_work_items_category;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_items_category_key' AND conrelid = 'work_items'::regclass
  ) THEN
    ALTER TABLE work_items ADD CONSTRAINT chk_work_items_category_key CHECK (category IN ('ariza', 'bakim', 'sikayet_oneri', 'diger') OR category ~ '^k_[a-z0-9_]{1,38}$');
  END IF;
END $$;
