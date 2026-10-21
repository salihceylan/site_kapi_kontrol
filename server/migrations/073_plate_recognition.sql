-- 073: Plaka Tanima (modul plate_recognition): misafir plaka izinleri, kara liste, kapi/kamera ayarlari, karar kayitlari.
-- Kaynak: src/modules/plate_recognition_schema.js (ayni ifadeler, ayni sira). Tamamen ekleyici ve idempotent; 6B tablolarina
-- (camera_devices, plate_events) dokunmaz ve onlara FK koymaz. Plaka kisisel veridir (KVKK): bkz. docs/PLATFORM_PLAKA_TANIMA.md.

CREATE TABLE IF NOT EXISTS plate_guest_permits (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  plate TEXT NOT NULL,
  valid_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  valid_until TIMESTAMPTZ NOT NULL,
  note TEXT,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ,
  revoked_by INTEGER,
  CONSTRAINT chk_plate_guest_permits_plate CHECK (plate ~ '^[A-Z0-9]{5,10}$'),
  CONSTRAINT chk_plate_guest_permits_span CHECK (valid_until > valid_from AND valid_until <= valid_from + INTERVAL '30 days'),
  CONSTRAINT chk_plate_guest_permits_note CHECK (note IS NULL OR char_length(note) <= 120)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_guest_permits_site_code_fkey' AND conrelid = 'plate_guest_permits'::regclass) THEN
    ALTER TABLE plate_guest_permits ADD CONSTRAINT plate_guest_permits_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_plate_guest_permits_site ON plate_guest_permits (site_code, id DESC);

CREATE INDEX IF NOT EXISTS idx_plate_guest_permits_plate ON plate_guest_permits (site_code, plate) WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_plate_guest_permits_creator ON plate_guest_permits (created_by, created_at DESC);

CREATE TABLE IF NOT EXISTS plate_blacklist (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  plate TEXT NOT NULL,
  reason TEXT,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  removed_at TIMESTAMPTZ,
  removed_by INTEGER,
  CONSTRAINT chk_plate_blacklist_plate CHECK (plate ~ '^[A-Z0-9]{5,10}$'),
  CONSTRAINT chk_plate_blacklist_reason CHECK (reason IS NULL OR char_length(reason) <= 200)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_blacklist_site_code_fkey' AND conrelid = 'plate_blacklist'::regclass) THEN
    ALTER TABLE plate_blacklist ADD CONSTRAINT plate_blacklist_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_plate_blacklist_active ON plate_blacklist (site_code, plate) WHERE removed_at IS NULL;

CREATE TABLE IF NOT EXISTS plate_gate_settings (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  door_id BIGINT NOT NULL,
  device_id BIGINT,
  auto_open BOOLEAN NOT NULL DEFAULT FALSE,
  min_confidence NUMERIC(4, 3) NOT NULL DEFAULT 0.85,
  cooldown_seconds INTEGER NOT NULL DEFAULT 30,
  updated_by INTEGER,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_plate_gate_settings_confidence CHECK (min_confidence BETWEEN 0.5 AND 0.999),
  CONSTRAINT chk_plate_gate_settings_cooldown CHECK (cooldown_seconds BETWEEN 5 AND 600),
  CONSTRAINT uq_plate_gate_settings_door UNIQUE (site_code, door_id)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_gate_settings_site_code_fkey' AND conrelid = 'plate_gate_settings'::regclass) THEN
    ALTER TABLE plate_gate_settings ADD CONSTRAINT plate_gate_settings_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_plate_gate_settings_device ON plate_gate_settings (site_code, device_id) WHERE device_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS plate_decisions (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  event_id BIGINT NOT NULL,
  device_id BIGINT NOT NULL,
  door_id BIGINT,
  plate TEXT NOT NULL,
  confidence NUMERIC(5, 4),
  decision TEXT NOT NULL,
  reason TEXT NOT NULL,
  vehicle_id BIGINT,
  permit_id BIGINT,
  auto_action TEXT NOT NULL DEFAULT 'none',
  decided_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_plate_decisions_plate CHECK (plate ~ '^[A-Z0-9]{5,10}$'),
  CONSTRAINT chk_plate_decisions_decision CHECK (decision IN ('ALLOWED', 'DENIED', 'UNKNOWN')),
  CONSTRAINT chk_plate_decisions_action CHECK (auto_action IN ('none', 'would_open', 'suppressed_cooldown', 'suppressed_rate')),
  CONSTRAINT uq_plate_decisions_event UNIQUE (event_id)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_decisions_site_code_fkey' AND conrelid = 'plate_decisions'::regclass) THEN
    ALTER TABLE plate_decisions ADD CONSTRAINT plate_decisions_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_plate_decisions_site ON plate_decisions (site_code, id DESC);

CREATE INDEX IF NOT EXISTS idx_plate_decisions_open ON plate_decisions (door_id, decided_at DESC) WHERE auto_action = 'would_open';
