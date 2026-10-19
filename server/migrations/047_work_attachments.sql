-- 047: Is Takibi fotograf ekleri: work_item_attachments + work_item_events olay turu kisitinin genisletilmesi
-- Sozlesme: docs/PLATFORM_IS_TAKIBI.md "Fotograf ekleri"
-- db.js ensureDbSchema ile ayni DDL (src/modules/work_attachments_schema.js WORK_ATTACHMENTS_DDL; test: work_attachments birebir esitlik, ayni sira).
-- Ekleyici (additive) ve idempotent: mevcut tablolara sutun / indeks EKLEMEZ, hicbir satiri DEGISTIRMEZ / SILMEZ. Tek istisna: work_item_events uzerindeki
-- chk_work_item_events_type CHECK kisiti iki yeni olay turuyle ('attachment_added', 'attachment_removed') genisletilir (katalog korumali DO blogu; DROP + ADD
-- ayni DO icinde = tek islem, kisitsiz pencere yok; genislemisse hicbir sey yapilmaz).
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle yalniz EKSIK olanlar icin calisir (acilis 40P01 dersi, bkz. 039 / 042).
-- Yabanci anahtarlar (R11 F1): tablo FK'SIZ olusturulur, her FK ayri ve katalog korumali bir ALTER TABLE'dir (ifade basina tek sicak ust tablo).
-- Silme politikasi: talep silinince (site CASCADE'i dahil) ek satirlari CASCADE (dosya diskte kalir, bakim isi yetim olarak supurur); kullanici SATIRI fiziksel
-- silinirse uploaded_by SET NULL. Hesap silme satiri silmez (kimliksizlestirir): uploaded_by tombstone hesaba bagli kalir (document_versions.uploaded_by ile ayni);
-- her iki durumda fotograf taleple birlikte sitede kalir, yukleyen "Silinmis Kullanici" gorunur.
-- Dosya duzeni: <DOCUMENTS_DIR>/work_attachments/<site_code>/<uuid> (storage_key = <site_code>/<uuid>; belgelerin sites/ agacindan AYRI).

CREATE TABLE IF NOT EXISTS work_item_attachments (
  id BIGSERIAL PRIMARY KEY,
  work_item_id BIGINT NOT NULL,
  site_code BIGINT NOT NULL,
  uploaded_by INTEGER,
  file_name TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  size_bytes BIGINT NOT NULL,
  sha256 TEXT,
  status TEXT NOT NULL DEFAULT 'uploading',
  storage_key TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ready_at TIMESTAMPTZ,
  CONSTRAINT chk_work_item_attachments_file_name CHECK (char_length(file_name) BETWEEN 1 AND 160),
  CONSTRAINT chk_work_item_attachments_mime CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp')),
  CONSTRAINT chk_work_item_attachments_size CHECK (size_bytes BETWEEN 1 AND 5242880),
  CONSTRAINT chk_work_item_attachments_status CHECK (status IN ('uploading', 'ready')),
  CONSTRAINT chk_work_item_attachments_ready CHECK ((status = 'ready') = (ready_at IS NOT NULL)),
  CONSTRAINT chk_work_item_attachments_sha256 CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$')
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_item_attachments_work_item_id_fkey' AND conrelid = 'work_item_attachments'::regclass
  ) THEN
    ALTER TABLE work_item_attachments ADD CONSTRAINT work_item_attachments_work_item_id_fkey FOREIGN KEY (work_item_id) REFERENCES work_items(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_item_attachments_site_code_fkey' AND conrelid = 'work_item_attachments'::regclass
  ) THEN
    ALTER TABLE work_item_attachments ADD CONSTRAINT work_item_attachments_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_item_attachments_uploaded_by_fkey' AND conrelid = 'work_item_attachments'::regclass
  ) THEN
    ALTER TABLE work_item_attachments ADD CONSTRAINT work_item_attachments_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_work_item_attachments_item ON work_item_attachments (work_item_id);

CREATE INDEX IF NOT EXISTS idx_work_item_attachments_site_created ON work_item_attachments (site_code, created_at);

CREATE INDEX IF NOT EXISTS idx_work_item_attachments_uploaded_by ON work_item_attachments (uploaded_by, created_at) WHERE uploaded_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_work_item_attachments_uploading ON work_item_attachments (created_at) WHERE status = 'uploading';

CREATE UNIQUE INDEX IF NOT EXISTS uq_work_item_attachments_storage_key ON work_item_attachments (storage_key) WHERE storage_key IS NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_item_events_type' AND conrelid = 'work_item_events'::regclass AND pg_get_constraintdef(oid) LIKE '%attachment_added%'
  ) THEN
    ALTER TABLE work_item_events DROP CONSTRAINT IF EXISTS chk_work_item_events_type;
    ALTER TABLE work_item_events ADD CONSTRAINT chk_work_item_events_type CHECK (event_type IN ('created', 'status_changed', 'assigned', 'priority_changed', 'due_date_changed', 'comment', 'attachment_added', 'attachment_removed'));
  END IF;
END $$;
