-- 045: Ziyaretci ve Kargo (F11.03): visitor_entries
-- Sozlesme: docs/PLATFORM_ZIYARETCI_KARGO.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/visitor_log_schema.js VISITOR_LOG_DDL; test: visitor_log_schema birebir esitlik, ayni sira).
-- Tamamen ekleyici (additive) ve idempotent: mevcut tablolara sutun / indeks EKLEMEZ, hicbir satiri DEGISTIRMEZ / SILMEZ.
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle yalniz EKSIK olanlar icin calisir (acilis 40P01 dersi, bkz. 039, 042, 043).
-- Migration calistiricisi (migrate.js) tek islemde, bilincli ve bir kez uyguladigi icin burada dogrudan yazilir.
-- Yabanci anahtarlar (R11 F1): tablo FK'SIZ olusturulur, her FK ayri ve katalog korumali bir ALTER TABLE'dir (ifade basina tek sicak ust tablo).
-- Silme politikasi: site silinince kayitlar CASCADE; kullanici / daire silinince SET NULL (kayit kalir; kaydeden / sonlandiran "Silinmis Kullanici" gorunur).
-- Sakin bildirimi yalniz uygulama ici (resident_seen_at); e-posta / push YOK (Yakinda).

CREATE TABLE IF NOT EXISTS visitor_entries (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  kind TEXT NOT NULL,
  apartment_id BIGINT,
  visitor_name TEXT NOT NULL,
  company TEXT,
  note TEXT,
  status TEXT NOT NULL,
  arrived_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  recorded_by INTEGER,
  completed_by INTEGER,
  resident_seen_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_visitor_entries_kind CHECK (kind IN ('visitor', 'cargo')),
  CONSTRAINT chk_visitor_entries_name_length CHECK (char_length(visitor_name) BETWEEN 1 AND 120),
  CONSTRAINT chk_visitor_entries_company_length CHECK (company IS NULL OR char_length(company) BETWEEN 1 AND 120),
  CONSTRAINT chk_visitor_entries_note_length CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 500),
  CONSTRAINT chk_visitor_entries_status CHECK (status IN ('bekliyor', 'iceride', 'teslim_edildi', 'ayrildi', 'iptal')),
  CONSTRAINT chk_visitor_entries_completed CHECK ((status IN ('teslim_edildi', 'ayrildi', 'iptal')) = (completed_at IS NOT NULL))
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'visitor_entries_site_code_fkey' AND conrelid = 'visitor_entries'::regclass
  ) THEN
    ALTER TABLE visitor_entries ADD CONSTRAINT visitor_entries_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'visitor_entries_apartment_id_fkey' AND conrelid = 'visitor_entries'::regclass
  ) THEN
    ALTER TABLE visitor_entries ADD CONSTRAINT visitor_entries_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'visitor_entries_recorded_by_fkey' AND conrelid = 'visitor_entries'::regclass
  ) THEN
    ALTER TABLE visitor_entries ADD CONSTRAINT visitor_entries_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'visitor_entries_completed_by_fkey' AND conrelid = 'visitor_entries'::regclass
  ) THEN
    ALTER TABLE visitor_entries ADD CONSTRAINT visitor_entries_completed_by_fkey FOREIGN KEY (completed_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_visitor_entries_site_status ON visitor_entries (site_code, status, arrived_at DESC);

CREATE INDEX IF NOT EXISTS idx_visitor_entries_apartment ON visitor_entries (apartment_id, arrived_at DESC);
