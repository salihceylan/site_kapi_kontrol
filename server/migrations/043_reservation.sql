-- 043: Rezervasyon ve Konsiyerj: reservation_areas, reservations, concierge_requests
-- Sozlesme: docs/PLATFORM_REZERVASYON.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/reservation_schema.js RESERVATION_DDL; test: reservation_schema birebir esitlik, ayni sira).
-- Tamamen ekleyici (additive) ve idempotent: mevcut tablolara sutun / indeks EKLEMEZ, hicbir satiri DEGISTIRMEZ / SILMEZ.
-- db.js'te bu ifadeler dev ensureDbSchema blogunun DISINDA, katalog kontroluyle yalniz EKSIK olanlar icin calisir (acilis 40P01 dersi, bkz. 039, 042).
-- Migration calistiricisi (migrate.js) tek islemde, bilincli ve bir kez uyguladigi icin burada dogrudan yazilir.
-- Yabanci anahtarlar (R11 F1): tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumali bir ALTER TABLE'dir (ifade basina tek sicak ust tablo).
-- Silme politikasi: site silinince alan + rezervasyon + talep CASCADE; kullanici / daire silinince SET NULL (kayit kalir; sahibi "Silinmis Kullanici" gorunur).
-- Capraz kontrol (kapasite, limit, cakisma) uygulama katmaninda site+alan advisory kilidi altindadir (EXCLUDE / btree_gist KULLANILMAZ).
-- Ucret / odeme BU surumde yok.

CREATE TABLE IF NOT EXISTS reservation_areas (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  capacity INTEGER NOT NULL DEFAULT 1,
  slot_minutes INTEGER NOT NULL DEFAULT 60,
  min_slots INTEGER NOT NULL DEFAULT 1,
  max_slots INTEGER NOT NULL DEFAULT 4,
  max_days_ahead INTEGER NOT NULL DEFAULT 14,
  approval_mode TEXT NOT NULL DEFAULT 'otomatik',
  cancel_cutoff_hours INTEGER NOT NULL DEFAULT 2,
  per_user_daily_limit INTEGER NOT NULL DEFAULT 2,
  per_user_weekly_limit INTEGER NOT NULL DEFAULT 5,
  weekly_hours JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_reservation_areas_name_length CHECK (char_length(name) BETWEEN 1 AND 80),
  CONSTRAINT chk_reservation_areas_description_length CHECK (description IS NULL OR char_length(description) <= 500),
  CONSTRAINT chk_reservation_areas_capacity CHECK (capacity BETWEEN 1 AND 100),
  CONSTRAINT chk_reservation_areas_slot_minutes CHECK (slot_minutes BETWEEN 15 AND 480),
  CONSTRAINT chk_reservation_areas_slots CHECK (min_slots BETWEEN 1 AND 48 AND max_slots BETWEEN min_slots AND 48),
  CONSTRAINT chk_reservation_areas_days_ahead CHECK (max_days_ahead BETWEEN 1 AND 180),
  CONSTRAINT chk_reservation_areas_approval_mode CHECK (approval_mode IN ('otomatik', 'yonetici_onayli')),
  CONSTRAINT chk_reservation_areas_cutoff CHECK (cancel_cutoff_hours BETWEEN 0 AND 168),
  CONSTRAINT chk_reservation_areas_limits CHECK (per_user_daily_limit BETWEEN 1 AND 20 AND per_user_weekly_limit BETWEEN per_user_daily_limit AND 100),
  CONSTRAINT chk_reservation_areas_hours CHECK (jsonb_typeof(weekly_hours) = 'array' AND jsonb_array_length(weekly_hours) <= 21)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'reservation_areas_site_code_fkey' AND conrelid = 'reservation_areas'::regclass
  ) THEN
    ALTER TABLE reservation_areas ADD CONSTRAINT reservation_areas_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'reservation_areas_created_by_fkey' AND conrelid = 'reservation_areas'::regclass
  ) THEN
    ALTER TABLE reservation_areas ADD CONSTRAINT reservation_areas_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_reservation_areas_name ON reservation_areas (site_code, lower(name));

CREATE INDEX IF NOT EXISTS idx_reservation_areas_created_by ON reservation_areas (created_by) WHERE created_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS reservations (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  area_id BIGINT NOT NULL,
  user_code INTEGER,
  apartment_id BIGINT,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  slot_count INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'beklemede',
  note TEXT,
  decision_note TEXT,
  decided_by INTEGER,
  decided_at TIMESTAMPTZ,
  cancelled_by_kind TEXT,
  cancelled_at TIMESTAMPTZ,
  idempotency_key TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_reservations_status CHECK (status IN ('beklemede', 'onaylandi', 'reddedildi', 'iptal')),
  CONSTRAINT chk_reservations_range CHECK (ends_at > starts_at),
  CONSTRAINT chk_reservations_slot_count CHECK (slot_count BETWEEN 1 AND 48),
  CONSTRAINT chk_reservations_note_length CHECK (note IS NULL OR char_length(note) <= 200),
  CONSTRAINT chk_reservations_decision_note_length CHECK (decision_note IS NULL OR char_length(decision_note) <= 300),
  CONSTRAINT chk_reservations_cancelled CHECK ((status = 'iptal') = (cancelled_at IS NOT NULL) AND (status = 'iptal') = (cancelled_by_kind IS NOT NULL)),
  CONSTRAINT chk_reservations_cancelled_kind CHECK (cancelled_by_kind IS NULL OR cancelled_by_kind IN ('resident', 'management', 'system')),
  CONSTRAINT chk_reservations_idempotency_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) <= 64)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'reservations_site_code_fkey' AND conrelid = 'reservations'::regclass
  ) THEN
    ALTER TABLE reservations ADD CONSTRAINT reservations_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'reservations_area_id_fkey' AND conrelid = 'reservations'::regclass
  ) THEN
    ALTER TABLE reservations ADD CONSTRAINT reservations_area_id_fkey FOREIGN KEY (area_id) REFERENCES reservation_areas(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'reservations_user_code_fkey' AND conrelid = 'reservations'::regclass
  ) THEN
    ALTER TABLE reservations ADD CONSTRAINT reservations_user_code_fkey FOREIGN KEY (user_code) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'reservations_apartment_id_fkey' AND conrelid = 'reservations'::regclass
  ) THEN
    ALTER TABLE reservations ADD CONSTRAINT reservations_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'reservations_decided_by_fkey' AND conrelid = 'reservations'::regclass
  ) THEN
    ALTER TABLE reservations ADD CONSTRAINT reservations_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_reservations_area_active ON reservations (area_id, starts_at) WHERE status IN ('beklemede', 'onaylandi');

CREATE INDEX IF NOT EXISTS idx_reservations_site_start ON reservations (site_code, starts_at, id);

CREATE INDEX IF NOT EXISTS idx_reservations_user ON reservations (user_code, site_code, id DESC) WHERE user_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_reservations_apartment ON reservations (apartment_id) WHERE apartment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_reservations_decided_by ON reservations (decided_by) WHERE decided_by IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_reservations_idempotency ON reservations (site_code, user_code, idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS concierge_requests (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  user_code INTEGER,
  apartment_id BIGINT,
  category TEXT NOT NULL,
  note TEXT,
  requested_for TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'yeni',
  staff_note TEXT,
  staff_note_by INTEGER,
  idempotency_key TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  closed_at TIMESTAMPTZ,
  CONSTRAINT chk_concierge_requests_category CHECK (category IN ('paket_teslim', 'misafir_hazirlik', 'temizlik', 'tasima', 'diger')),
  CONSTRAINT chk_concierge_requests_status CHECK (status IN ('yeni', 'hazirlaniyor', 'tamamlandi', 'iptal')),
  CONSTRAINT chk_concierge_requests_note_length CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 500),
  CONSTRAINT chk_concierge_requests_other_note CHECK (category <> 'diger' OR note IS NOT NULL),
  CONSTRAINT chk_concierge_requests_staff_note_length CHECK (staff_note IS NULL OR char_length(staff_note) BETWEEN 1 AND 300),
  CONSTRAINT chk_concierge_requests_closed CHECK ((status IN ('tamamlandi', 'iptal')) = (closed_at IS NOT NULL)),
  CONSTRAINT chk_concierge_requests_idempotency_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) <= 64)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'concierge_requests_site_code_fkey' AND conrelid = 'concierge_requests'::regclass
  ) THEN
    ALTER TABLE concierge_requests ADD CONSTRAINT concierge_requests_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'concierge_requests_user_code_fkey' AND conrelid = 'concierge_requests'::regclass
  ) THEN
    ALTER TABLE concierge_requests ADD CONSTRAINT concierge_requests_user_code_fkey FOREIGN KEY (user_code) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'concierge_requests_apartment_id_fkey' AND conrelid = 'concierge_requests'::regclass
  ) THEN
    ALTER TABLE concierge_requests ADD CONSTRAINT concierge_requests_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'concierge_requests_staff_note_by_fkey' AND conrelid = 'concierge_requests'::regclass
  ) THEN
    ALTER TABLE concierge_requests ADD CONSTRAINT concierge_requests_staff_note_by_fkey FOREIGN KEY (staff_note_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_concierge_requests_site_status ON concierge_requests (site_code, status, id DESC);

CREATE INDEX IF NOT EXISTS idx_concierge_requests_site_open ON concierge_requests (site_code) WHERE status NOT IN ('tamamlandi', 'iptal');

CREATE INDEX IF NOT EXISTS idx_concierge_requests_user ON concierge_requests (user_code, site_code, id DESC) WHERE user_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_concierge_requests_apartment ON concierge_requests (apartment_id) WHERE apartment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_concierge_requests_staff_note_by ON concierge_requests (staff_note_by) WHERE staff_note_by IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_concierge_requests_idempotency ON concierge_requests (site_code, user_code, idempotency_key) WHERE idempotency_key IS NOT NULL;
