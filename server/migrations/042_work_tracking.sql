-- 042: Is Takibi (ariza, bakim, talep): work_items, work_item_events
-- Sozlesme: docs/PLATFORM_IS_TAKIBI.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/work_tracking_schema.js WORK_TRACKING_DDL; test: work_tracking_schema birebir esitlik, ayni sira).
-- Tamamen ekleyici (additive) ve idempotent: mevcut tablolara sutun / indeks EKLEMEZ, hicbir satiri DEGISTIRMEZ / SILMEZ.
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle yalniz EKSIK olanlar icin calisir (acilis 40P01 dersi, bkz. 039).
-- Migration calistiricisi (migrate.js) tek islemde, bilincli ve bir kez uyguladigi icin burada dogrudan yazilir.
-- Yabanci anahtarlar (R11 F1): tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumali bir ALTER TABLE'dir (ifade basina tek sicak ust tablo).
-- Silme politikasi: site silinince talep + olaylar CASCADE; kullanici / daire / blok silinince SET NULL (talep kalir; acan "Silinmis Kullanici" gorunur).
-- Olaylar (work_item_events) kod duzeyinde degismezdir (yalniz EKLENIR). Yorum / olay metni audit_log'a YAZILMAZ.
-- Ek / fotograf BU surumde yok.

CREATE TABLE IF NOT EXISTS work_items (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  category TEXT NOT NULL,
  location_type TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  apartment_id BIGINT,
  block_id BIGINT,
  status TEXT NOT NULL DEFAULT 'yeni',
  priority TEXT NOT NULL DEFAULT 'normal',
  resident_urgent BOOLEAN NOT NULL DEFAULT FALSE,
  assigned_to INTEGER,
  due_date DATE,
  idempotency_key TEXT,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  closed_at TIMESTAMPTZ,
  requester_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resident_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_work_items_category CHECK (category IN ('ariza', 'bakim', 'sikayet_oneri', 'diger')),
  CONSTRAINT chk_work_items_location CHECK (location_type IN ('ortak_alan', 'daire')),
  CONSTRAINT chk_work_items_title_length CHECK (char_length(title) BETWEEN 1 AND 120),
  CONSTRAINT chk_work_items_description_length CHECK (char_length(description) BETWEEN 1 AND 2000),
  CONSTRAINT chk_work_items_status CHECK (status IN ('yeni', 'islemde', 'beklemede', 'cozuldu', 'kapandi', 'iptal')),
  CONSTRAINT chk_work_items_priority CHECK (priority IN ('dusuk', 'normal', 'acil')),
  CONSTRAINT chk_work_items_apartment_location CHECK (location_type = 'daire' OR apartment_id IS NULL),
  CONSTRAINT chk_work_items_closed CHECK ((status IN ('kapandi', 'iptal')) = (closed_at IS NOT NULL)),
  CONSTRAINT chk_work_items_idempotency_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) <= 64)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_items_site_code_fkey' AND conrelid = 'work_items'::regclass
  ) THEN
    ALTER TABLE work_items ADD CONSTRAINT work_items_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_items_created_by_fkey' AND conrelid = 'work_items'::regclass
  ) THEN
    ALTER TABLE work_items ADD CONSTRAINT work_items_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_items_assigned_to_fkey' AND conrelid = 'work_items'::regclass
  ) THEN
    ALTER TABLE work_items ADD CONSTRAINT work_items_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_items_apartment_id_fkey' AND conrelid = 'work_items'::regclass
  ) THEN
    ALTER TABLE work_items ADD CONSTRAINT work_items_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_items_block_id_fkey' AND conrelid = 'work_items'::regclass
  ) THEN
    ALTER TABLE work_items ADD CONSTRAINT work_items_block_id_fkey FOREIGN KEY (block_id) REFERENCES site_blocks(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_work_items_site_status ON work_items (site_code, status, id DESC);

CREATE INDEX IF NOT EXISTS idx_work_items_site_open ON work_items (site_code) WHERE status NOT IN ('kapandi', 'iptal');

CREATE INDEX IF NOT EXISTS idx_work_items_created_by ON work_items (created_by, site_code, id DESC) WHERE created_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_work_items_assigned_to ON work_items (assigned_to) WHERE assigned_to IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_work_items_apartment ON work_items (apartment_id) WHERE apartment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_work_items_block ON work_items (block_id) WHERE block_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_work_items_idempotency ON work_items (site_code, created_by, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS work_item_events (
  id BIGSERIAL PRIMARY KEY,
  work_item_id BIGINT NOT NULL,
  site_code BIGINT NOT NULL,
  event_type TEXT NOT NULL,
  visibility TEXT NOT NULL DEFAULT 'internal',
  actor_user_code INTEGER,
  actor_kind TEXT NOT NULL,
  from_value TEXT,
  to_value TEXT,
  body TEXT,
  idempotency_key TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_work_item_events_type CHECK (event_type IN ('created', 'status_changed', 'assigned', 'priority_changed', 'due_date_changed', 'comment')),
  CONSTRAINT chk_work_item_events_visibility CHECK (visibility IN ('public', 'internal')),
  CONSTRAINT chk_work_item_events_actor_kind CHECK (actor_kind IN ('resident', 'staff', 'manager')),
  CONSTRAINT chk_work_item_events_comment_body CHECK ((event_type = 'comment') = (body IS NOT NULL)),
  CONSTRAINT chk_work_item_events_body_length CHECK (body IS NULL OR char_length(body) BETWEEN 1 AND 1000),
  CONSTRAINT chk_work_item_events_resident_public CHECK (actor_kind <> 'resident' OR visibility = 'public'),
  CONSTRAINT chk_work_item_events_values_length CHECK ((from_value IS NULL OR char_length(from_value) <= 40) AND (to_value IS NULL OR char_length(to_value) <= 40)),
  CONSTRAINT chk_work_item_events_idempotency_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) <= 64)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_item_events_work_item_id_fkey' AND conrelid = 'work_item_events'::regclass
  ) THEN
    ALTER TABLE work_item_events ADD CONSTRAINT work_item_events_work_item_id_fkey FOREIGN KEY (work_item_id) REFERENCES work_items(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_item_events_site_code_fkey' AND conrelid = 'work_item_events'::regclass
  ) THEN
    ALTER TABLE work_item_events ADD CONSTRAINT work_item_events_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'work_item_events_actor_user_code_fkey' AND conrelid = 'work_item_events'::regclass
  ) THEN
    ALTER TABLE work_item_events ADD CONSTRAINT work_item_events_actor_user_code_fkey FOREIGN KEY (actor_user_code) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_work_item_events_item ON work_item_events (work_item_id, id);

CREATE INDEX IF NOT EXISTS idx_work_item_events_site ON work_item_events (site_code);

CREATE INDEX IF NOT EXISTS idx_work_item_events_actor ON work_item_events (actor_user_code) WHERE actor_user_code IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_work_item_events_idempotency ON work_item_events (work_item_id, actor_user_code, idempotency_key) WHERE idempotency_key IS NOT NULL;
