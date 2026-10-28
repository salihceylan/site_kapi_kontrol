-- 103: Geri bildirim (sayfa baglamli): feedback_reports + feedback_attachments
-- Sozlesme: docs/PLATFORM_GERI_BILDIRIM.md. Karar K11: ek en cok 4 dosya, dosya basi 5 MB, toplam 20 MB.
-- db.js ensureDbSchema ile ayni DDL (src/modules/feedback_schema.js FEEDBACK_DDL; test: feedback_schema birebir esitlik, ayni sira).
-- Ekleyici (additive) ve idempotent: mevcut tablolara sutun / indeks EKLEMEZ, hicbir satiri DEGISTIRMEZ / SILMEZ.
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle yalniz EKSIK olanlar icin calisir (acilis 40P01 dersi, bkz. 039 / 042 / 047).
-- Yabanci anahtarlar: tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumali bir ALTER TABLE'dir (ifade basina tek sicak ust tablo).
-- Silme politikasi: site silinince geri bildirimleri CASCADE (dosya diskte kalir); kullanici SATIRI fiziksel silinirse user_code SET NULL; geri bildirim
-- silinince ek satirlari CASCADE. Hesap silme satiri silmez (kimliksizlestirir): gonderen "Silinmis Kullanici" gorunur.
-- Dosya duzeni: <DOCUMENTS_DIR>/feedback_attachments/<site_code | 1000000000>/<uuid> (is takibi fotograflarinin ve belgelerin agaclarindan AYRI).

CREATE TABLE IF NOT EXISTS feedback_reports (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT,
  user_code INTEGER,
  role TEXT NOT NULL,
  screen_name TEXT NOT NULL,
  screen_route TEXT NOT NULL,
  message TEXT NOT NULL,
  app_version TEXT,
  platform TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_feedback_reports_role CHECK (char_length(role) BETWEEN 1 AND 60),
  CONSTRAINT chk_feedback_reports_screen_name CHECK (char_length(screen_name) BETWEEN 1 AND 120),
  CONSTRAINT chk_feedback_reports_screen_route CHECK (char_length(screen_route) BETWEEN 1 AND 120),
  CONSTRAINT chk_feedback_reports_message CHECK (char_length(message) BETWEEN 1 AND 2000),
  CONSTRAINT chk_feedback_reports_app_version CHECK (app_version IS NULL OR char_length(app_version) <= 40),
  CONSTRAINT chk_feedback_reports_platform CHECK (platform IS NULL OR char_length(platform) <= 20)
);

CREATE TABLE IF NOT EXISTS feedback_attachments (
  id BIGSERIAL PRIMARY KEY,
  feedback_id BIGINT NOT NULL,
  file_name TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  size_bytes BIGINT NOT NULL,
  sha256 TEXT,
  status TEXT NOT NULL DEFAULT 'uploading',
  storage_key TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ready_at TIMESTAMPTZ,
  CONSTRAINT chk_feedback_attachments_file_name CHECK (char_length(file_name) BETWEEN 1 AND 160),
  CONSTRAINT chk_feedback_attachments_mime CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp')),
  CONSTRAINT chk_feedback_attachments_size CHECK (size_bytes BETWEEN 1 AND 5242880),
  CONSTRAINT chk_feedback_attachments_status CHECK (status IN ('uploading', 'ready')),
  CONSTRAINT chk_feedback_attachments_ready CHECK ((status = 'ready') = (ready_at IS NOT NULL)),
  CONSTRAINT chk_feedback_attachments_sha256 CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$')
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'feedback_reports_site_code_fkey' AND conrelid = 'feedback_reports'::regclass
  ) THEN
    ALTER TABLE feedback_reports ADD CONSTRAINT feedback_reports_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'feedback_reports_user_code_fkey' AND conrelid = 'feedback_reports'::regclass
  ) THEN
    ALTER TABLE feedback_reports ADD CONSTRAINT feedback_reports_user_code_fkey FOREIGN KEY (user_code) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'feedback_attachments_feedback_id_fkey' AND conrelid = 'feedback_attachments'::regclass
  ) THEN
    ALTER TABLE feedback_attachments ADD CONSTRAINT feedback_attachments_feedback_id_fkey FOREIGN KEY (feedback_id) REFERENCES feedback_reports(id) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_feedback_reports_site ON feedback_reports (site_code, id DESC) WHERE site_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_feedback_reports_user_created ON feedback_reports (user_code, created_at) WHERE user_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_feedback_attachments_feedback ON feedback_attachments (feedback_id);

CREATE INDEX IF NOT EXISTS idx_feedback_attachments_uploading ON feedback_attachments (created_at) WHERE status = 'uploading';

CREATE UNIQUE INDEX IF NOT EXISTS uq_feedback_attachments_storage_key ON feedback_attachments (storage_key) WHERE storage_key IS NOT NULL;
