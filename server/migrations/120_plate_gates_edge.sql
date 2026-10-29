-- 120: Plaka Tanima A1 - gecis noktalari (kapi), kapi-kamera bagi, kenar istemciler, kamera durumu, site ayari, "iceride" takibi, plate_events genisletme, daire basina park yeri.
-- Kaynak: src/modules/plate_gates_schema.js (ayni ifadeler, ayni sira; test: plate_gates). Tamamen ekleyici ve idempotent; mevcut satirlara dokunmaz.
-- Hicbir sayi / yon / esik koda gomulu degil: hepsi DB kaydi. Yon modu, kamera yonu, karar turu ve misafir kurali CHECK listesidir; yeni deger eklemek tek migration'dir
-- (ALTER TABLE ... DROP CONSTRAINT + ADD CONSTRAINT) ve plate_gates_common.js sabitleriyle test bekcisi tarafindan eslesmesi dogrulanir.
-- plate_events (065): gate_id, direction (giris|cikis), decision_kind (acildi|red|tanimsiz), edge_client_id, client_event_id (kenar istemci olay kimligi, tekil), schema_version, confidence, reason.
-- apartments.parking_slots: daire basina park yeri sayisi (varsayilan 0 = misafir arac kabul edilmez).
-- Plaka kisisel veridir (KVKK): bkz. docs/PLATFORM_PLAKA_TANIMA.md. Kenar istemci anahtari yalniz SHA-256 ozeti olarak saklanir.

CREATE TABLE IF NOT EXISTS plate_gates (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  name TEXT NOT NULL,
  direction_mode TEXT NOT NULL DEFAULT 'cift',
  device_uid TEXT,
  door_id BIGINT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_plate_gates_name CHECK (char_length(name) BETWEEN 1 AND 60),
  CONSTRAINT chk_plate_gates_direction_mode CHECK (direction_mode IN ('giris', 'cikis', 'cift')),
  CONSTRAINT chk_plate_gates_device_uid CHECK (device_uid IS NULL OR char_length(device_uid) BETWEEN 1 AND 64)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_gates_site_code_fkey' AND conrelid = 'plate_gates'::regclass) THEN
    ALTER TABLE plate_gates ADD CONSTRAINT plate_gates_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_plate_gates_name ON plate_gates (site_code, lower(name));

CREATE TABLE IF NOT EXISTS plate_gate_cameras (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  gate_id BIGINT NOT NULL,
  camera_id BIGINT NOT NULL,
  direction TEXT NOT NULL DEFAULT 'auto',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_plate_gate_cameras_direction CHECK (direction IN ('giris', 'cikis', 'auto'))
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_gate_cameras_site_code_fkey' AND conrelid = 'plate_gate_cameras'::regclass) THEN
    ALTER TABLE plate_gate_cameras ADD CONSTRAINT plate_gate_cameras_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_plate_gate_cameras_camera ON plate_gate_cameras (camera_id);

CREATE INDEX IF NOT EXISTS idx_plate_gate_cameras_gate ON plate_gate_cameras (site_code, gate_id);

CREATE TABLE IF NOT EXISTS plate_edge_clients (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  name TEXT NOT NULL,
  key_hash TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  app_version TEXT,
  schema_version INTEGER,
  claimed_at TIMESTAMPTZ,
  last_seen_at TIMESTAMPTZ,
  last_sync_at TIMESTAMPTZ,
  queue_depth INTEGER,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ,
  CONSTRAINT chk_plate_edge_clients_name CHECK (char_length(name) BETWEEN 1 AND 60),
  CONSTRAINT chk_plate_edge_clients_version CHECK (app_version IS NULL OR char_length(app_version) <= 40)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_edge_clients_site_code_fkey' AND conrelid = 'plate_edge_clients'::regclass) THEN
    ALTER TABLE plate_edge_clients ADD CONSTRAINT plate_edge_clients_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_plate_edge_clients_site ON plate_edge_clients (site_code, id DESC);

CREATE TABLE IF NOT EXISTS plate_camera_status (
  camera_id BIGINT PRIMARY KEY,
  site_code BIGINT NOT NULL,
  edge_client_id BIGINT,
  last_frame_at TIMESTAMPTZ,
  last_read_at TIMESTAMPTZ,
  reported_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_camera_status_site_code_fkey' AND conrelid = 'plate_camera_status'::regclass) THEN
    ALTER TABLE plate_camera_status ADD CONSTRAINT plate_camera_status_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_plate_camera_status_site ON plate_camera_status (site_code);

CREATE TABLE IF NOT EXISTS plate_site_settings (
  site_code BIGINT PRIMARY KEY,
  guest_rule TEXT NOT NULL DEFAULT 'tum_bos',
  heartbeat_warn_seconds INTEGER NOT NULL DEFAULT 180,
  heartbeat_crit_seconds INTEGER NOT NULL DEFAULT 600,
  heartbeat_interval_seconds INTEGER NOT NULL DEFAULT 60,
  sync_interval_seconds INTEGER NOT NULL DEFAULT 120,
  updated_by INTEGER,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_plate_site_settings_rule CHECK (guest_rule IN ('tum_bos', 'en_az_bir_bos')),
  CONSTRAINT chk_plate_site_settings_warn CHECK (heartbeat_warn_seconds BETWEEN 30 AND 3600),
  CONSTRAINT chk_plate_site_settings_crit CHECK (heartbeat_crit_seconds BETWEEN 60 AND 7200 AND heartbeat_crit_seconds > heartbeat_warn_seconds),
  CONSTRAINT chk_plate_site_settings_hb CHECK (heartbeat_interval_seconds BETWEEN 10 AND 600),
  CONSTRAINT chk_plate_site_settings_sync CHECK (sync_interval_seconds BETWEEN 30 AND 3600)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_site_settings_site_code_fkey' AND conrelid = 'plate_site_settings'::regclass) THEN
    ALTER TABLE plate_site_settings ADD CONSTRAINT plate_site_settings_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS plate_presence (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  plate TEXT NOT NULL,
  apartment_id BIGINT,
  kind TEXT NOT NULL DEFAULT 'resident',
  gate_id BIGINT,
  inside BOOLEAN NOT NULL,
  since_at TIMESTAMPTZ NOT NULL,
  last_event_id BIGINT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_plate_presence_plate CHECK (plate ~ '^[A-Z0-9]{5,10}$'),
  CONSTRAINT chk_plate_presence_kind CHECK (kind IN ('resident', 'guest', 'other'))
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_presence_site_code_fkey' AND conrelid = 'plate_presence'::regclass) THEN
    ALTER TABLE plate_presence ADD CONSTRAINT plate_presence_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_plate_presence_plate ON plate_presence (site_code, plate);

CREATE INDEX IF NOT EXISTS idx_plate_presence_inside ON plate_presence (site_code, apartment_id) WHERE inside;

CREATE INDEX IF NOT EXISTS idx_plate_presence_updated ON plate_presence (site_code, updated_at);

ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS gate_id BIGINT;

ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS direction TEXT;

ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS decision_kind TEXT;

ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS edge_client_id BIGINT;

ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS client_event_id TEXT;

ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS schema_version INTEGER;

ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS confidence NUMERIC(5, 4);

ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS reason TEXT;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_events_direction' AND conrelid = 'plate_events'::regclass) THEN
    ALTER TABLE plate_events ADD CONSTRAINT chk_plate_events_direction CHECK (direction IS NULL OR direction IN ('giris', 'cikis'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_events_decision_kind' AND conrelid = 'plate_events'::regclass) THEN
    ALTER TABLE plate_events ADD CONSTRAINT chk_plate_events_decision_kind CHECK (decision_kind IS NULL OR decision_kind IN ('acildi', 'red', 'tanimsiz'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_events_client_event_id' AND conrelid = 'plate_events'::regclass) THEN
    ALTER TABLE plate_events ADD CONSTRAINT chk_plate_events_client_event_id CHECK (client_event_id IS NULL OR char_length(client_event_id) BETWEEN 8 AND 64);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_plate_events_client_event ON plate_events (site_code, client_event_id) WHERE client_event_id IS NOT NULL;

ALTER TABLE apartments ADD COLUMN IF NOT EXISTS parking_slots INTEGER NOT NULL DEFAULT 0;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_apartments_parking_slots' AND conrelid = 'apartments'::regclass) THEN
    ALTER TABLE apartments ADD CONSTRAINT chk_apartments_parking_slots CHECK (parking_slots BETWEEN 0 AND 50);
  END IF;
END $$;
