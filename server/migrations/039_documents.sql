-- 039: Belgeler (Faz 3b-A, dosya deposu): documents, document_versions, announcement_attachments
-- Sözleşme: docs/PLATFORM_BELGELER.md Bölüm A (A5)
-- db.js ensureDbSchema ile aynı DDL (src/modules/document_schema.js DOCUMENTS_DDL; test: document_schema birebir eşitlik, aynı sıra).
-- Tamamen ekleyici (additive) ve idempotent: mevcut tablolara sütun / indeks EKLEMEZ, hiçbir satırı DEĞİŞTİRMEZ / SİLMEZ. `announcements` / `users` DDL'e uğramaz.
-- db.js'te bu ifadeler dev ensureDbSchema bloğunun DIŞINDA, katalog kontrolüyle yalnız EKSİK olanlar için çalışır (açılış 40P01 dersi, bkz. ensureAccountDeletionSchema).
-- Migration çalıştırıcısı (migrate.js) tek işlemde, bilinçli ve bir kez uyguladığı için burada doğrudan yazılır.
-- Yabancı anahtarlar (R11 F1): tablolar FK'SIZ oluşturulur, her FK ayrı ve katalog korumalı bir ALTER TABLE'dır (ifade başına tek sıcak üst tablo: satır içi
-- REFERENCES sites / users / announcements açılışta eşzamanlı yazıcıyla 40P01 üretiyordu). Kısıt adları satır içi adlarla aynıdır (<tablo>_<sütun>_fkey).
-- Dosya içerikleri veritabanında DEĞİL, DOCUMENTS_DIR altında tutulur (yedek kümesi = DB dökümü + o dizin; bkz. docs/PLATFORM_BELGELER.md A2).

-- 1. Belge. audience DB varsayılanı en kısıtlı olandır (managers); API'de audience ZORUNLUDUR. hedef (blok/daire) yalnız audience = residents iken anlamlıdır.
-- status: pending (ilk dosya yükleniyor) | active | deleted (yumuşak silme; DOCUMENTS_RETENTION_DAYS sonra bakım işi kalıcı siler).
CREATE TABLE IF NOT EXISTS documents (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  category TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  audience TEXT NOT NULL DEFAULT 'managers',
  target_type TEXT NOT NULL DEFAULT 'site',
  target_block_ids BIGINT[] NOT NULL DEFAULT '{}',
  target_apartment_ids BIGINT[] NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'pending',
  current_version_no INTEGER,
  version_count INTEGER NOT NULL DEFAULT 0,
  next_version_no INTEGER NOT NULL DEFAULT 1,
  download_count BIGINT NOT NULL DEFAULT 0,
  idempotency_key TEXT,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  deleted_by INTEGER,
  CONSTRAINT chk_documents_category CHECK (category IN ('regulation', 'minutes', 'contract', 'notice', 'other')),
  CONSTRAINT chk_documents_title_length CHECK (char_length(title) BETWEEN 1 AND 120),
  CONSTRAINT chk_documents_description_length CHECK (description IS NULL OR char_length(description) <= 1000),
  CONSTRAINT chk_documents_audience CHECK (audience IN ('residents', 'board', 'managers')),
  CONSTRAINT chk_documents_target_type CHECK (target_type IN ('site', 'blocks', 'apartments')),
  CONSTRAINT chk_documents_status CHECK (status IN ('pending', 'active', 'deleted')),
  CONSTRAINT chk_documents_target_audience CHECK (
    audience = 'residents' OR (target_type = 'site' AND cardinality(target_block_ids) = 0 AND cardinality(target_apartment_ids) = 0)
  ),
  CONSTRAINT chk_documents_target_ids CHECK (
    (target_type = 'site' AND cardinality(target_block_ids) = 0 AND cardinality(target_apartment_ids) = 0)
    OR (target_type = 'blocks' AND cardinality(target_block_ids) BETWEEN 1 AND 500 AND cardinality(target_apartment_ids) = 0)
    OR (target_type = 'apartments' AND cardinality(target_apartment_ids) BETWEEN 1 AND 500 AND cardinality(target_block_ids) = 0)
  ),
  CONSTRAINT chk_documents_deleted CHECK ((status = 'deleted') = (deleted_at IS NOT NULL)),
  CONSTRAINT chk_documents_active_version CHECK (status <> 'active' OR current_version_no IS NOT NULL),
  CONSTRAINT chk_documents_idempotency_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) <= 64)
);
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'documents_site_code_fkey' AND conrelid = 'documents'::regclass
  ) THEN
    ALTER TABLE documents ADD CONSTRAINT documents_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'documents_created_by_fkey' AND conrelid = 'documents'::regclass
  ) THEN
    ALTER TABLE documents ADD CONSTRAINT documents_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'documents_deleted_by_fkey' AND conrelid = 'documents'::regclass
  ) THEN
    ALTER TABLE documents ADD CONSTRAINT documents_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_documents_site_status ON documents (site_code, status, id DESC);
CREATE INDEX IF NOT EXISTS idx_documents_site_category ON documents (site_code, category, id DESC) WHERE status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS uq_documents_idempotency ON documents (site_code, created_by, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_documents_lifecycle ON documents (status, deleted_at) WHERE status IN ('deleted', 'pending');
CREATE INDEX IF NOT EXISTS idx_documents_created_by ON documents (created_by) WHERE created_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_documents_deleted_by ON documents (deleted_by) WHERE deleted_by IS NOT NULL;

-- 2. Belge sürümü (bir sürümün dosyası BİR KEZ yazılır, üzerine yazılmaz). storage_key = <site_code>/<uuid>; kota = SUM(size_bytes) (uploading rezervasyonları dahil).
-- scan_status: antivirüs kancası (uygulanmadı; not_scanned).
CREATE TABLE IF NOT EXISTS document_versions (
  id BIGSERIAL PRIMARY KEY,
  document_id BIGINT NOT NULL,
  site_code BIGINT NOT NULL,
  version_no INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'uploading',
  storage_key TEXT NOT NULL,
  display_name TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  declared_size_bytes BIGINT NOT NULL,
  size_bytes BIGINT NOT NULL,
  sha256 TEXT,
  scan_status TEXT NOT NULL DEFAULT 'not_scanned',
  note TEXT,
  uploaded_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  CONSTRAINT uq_document_versions_key UNIQUE (storage_key),
  CONSTRAINT uq_document_versions_number UNIQUE (document_id, version_no),
  CONSTRAINT chk_document_versions_number CHECK (version_no > 0),
  CONSTRAINT chk_document_versions_status CHECK (status IN ('uploading', 'ready')),
  CONSTRAINT chk_document_versions_mime CHECK (mime_type IN ('application/pdf', 'image/jpeg', 'image/png', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')),
  CONSTRAINT chk_document_versions_sizes CHECK (declared_size_bytes > 0 AND size_bytes >= 0),
  CONSTRAINT chk_document_versions_sha CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT chk_document_versions_scan CHECK (scan_status IN ('not_scanned', 'clean', 'infected', 'error')),
  CONSTRAINT chk_document_versions_name_length CHECK (char_length(display_name) BETWEEN 1 AND 120),
  CONSTRAINT chk_document_versions_note_length CHECK (note IS NULL OR char_length(note) <= 200),
  CONSTRAINT chk_document_versions_ready CHECK (status <> 'ready' OR (sha256 IS NOT NULL AND completed_at IS NOT NULL))
);
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'document_versions_document_id_fkey' AND conrelid = 'document_versions'::regclass
  ) THEN
    ALTER TABLE document_versions ADD CONSTRAINT document_versions_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'document_versions_site_code_fkey' AND conrelid = 'document_versions'::regclass
  ) THEN
    ALTER TABLE document_versions ADD CONSTRAINT document_versions_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'document_versions_uploaded_by_fkey' AND conrelid = 'document_versions'::regclass
  ) THEN
    ALTER TABLE document_versions ADD CONSTRAINT document_versions_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_document_versions_site ON document_versions (site_code);
CREATE INDEX IF NOT EXISTS idx_document_versions_uploading ON document_versions (status, created_at) WHERE status = 'uploading';
CREATE INDEX IF NOT EXISTS idx_document_versions_uploaded_by ON document_versions (uploaded_by) WHERE uploaded_by IS NOT NULL;

-- 3. Duyuru eki. Aynı-site kuralı serviste (aynı işlemde iki satır FOR KEY SHARE) ve QA'da doğrulanır (announcements'a bileşik benzersiz indeks EKLENMEZ).
CREATE TABLE IF NOT EXISTS announcement_attachments (
  announcement_id BIGINT NOT NULL,
  document_id BIGINT NOT NULL,
  position SMALLINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (announcement_id, document_id),
  CONSTRAINT chk_announcement_attachments_position CHECK (position BETWEEN 0 AND 4)
);
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'announcement_attachments_announcement_id_fkey' AND conrelid = 'announcement_attachments'::regclass
  ) THEN
    ALTER TABLE announcement_attachments ADD CONSTRAINT announcement_attachments_announcement_id_fkey FOREIGN KEY (announcement_id) REFERENCES announcements(id) ON DELETE CASCADE;
  END IF;
END $$;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'announcement_attachments_document_id_fkey' AND conrelid = 'announcement_attachments'::regclass
  ) THEN
    ALTER TABLE announcement_attachments ADD CONSTRAINT announcement_attachments_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE;
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_announcement_attachments_document ON announcement_attachments (document_id);
