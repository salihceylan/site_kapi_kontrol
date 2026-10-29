-- 122: Plaka Tanima sozlesme surum 3 - uygulamadan uctan uca yonetim: kamera RTSP adresi + kenarin sinama sonucu (camera_devices), uzaktan komut kuyrugu
-- (plate_edge_commands: "agda kamera ara", "kamerayi sina"), kamera basina SON goruntu karesi (plate_camera_snapshots: tarihce YOK, uzerine yazilir; KVKK),
-- goruntuyu izleyen yonetici isareti (plate_snapshot_watch), olaya kimlik baglama (apartment_id, person_id, identity_kind) + kapi komutu sonucu (gate_command),
-- kenarin okuma hazirligi (plate_edge_clients), komut omru + goruntu araliklari + saklama suresi (plate_site_settings sutunlari).
-- Kaynak: src/modules/plate_cameras_schema.js (ayni ifadeler, ayni sira; test: plate_cameras). Ekleyici ve idempotent; mevcut satirlara dokunmaz, DROP yok.
-- Hicbir sayi koda gomulu degil: komut omru, goruntu araliklari ve saklama suresi plate_site_settings kaydi (yonetici ayarindan degisir).

ALTER TABLE camera_devices ADD COLUMN IF NOT EXISTS rtsp_url TEXT;

ALTER TABLE camera_devices ADD COLUMN IF NOT EXISTS probe_status TEXT NOT NULL DEFAULT 'none';

ALTER TABLE camera_devices ADD COLUMN IF NOT EXISTS probe_message TEXT;

ALTER TABLE camera_devices ADD COLUMN IF NOT EXISTS probe_width INTEGER;

ALTER TABLE camera_devices ADD COLUMN IF NOT EXISTS probe_height INTEGER;

ALTER TABLE camera_devices ADD COLUMN IF NOT EXISTS probe_at TIMESTAMPTZ;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_camera_devices_rtsp_url' AND conrelid = 'camera_devices'::regclass) THEN
    ALTER TABLE camera_devices ADD CONSTRAINT chk_camera_devices_rtsp_url CHECK (rtsp_url IS NULL OR (char_length(rtsp_url) BETWEEN 8 AND 500 AND rtsp_url ~ '^rtsps?://'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_camera_devices_probe_status' AND conrelid = 'camera_devices'::regclass) THEN
    ALTER TABLE camera_devices ADD CONSTRAINT chk_camera_devices_probe_status CHECK (probe_status IN ('none', 'pending', 'ok', 'failed'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_camera_devices_probe_message' AND conrelid = 'camera_devices'::regclass) THEN
    ALTER TABLE camera_devices ADD CONSTRAINT chk_camera_devices_probe_message CHECK (probe_message IS NULL OR char_length(probe_message) <= 300);
  END IF;
END $$;

ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS apartment_id BIGINT;

ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS person_id BIGINT;

ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS identity_kind TEXT;

ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS gate_command TEXT;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_events_identity_kind' AND conrelid = 'plate_events'::regclass) THEN
    ALTER TABLE plate_events ADD CONSTRAINT chk_plate_events_identity_kind CHECK (identity_kind IS NULL OR identity_kind IN ('resident', 'guest'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_events_gate_command' AND conrelid = 'plate_events'::regclass) THEN
    ALTER TABLE plate_events ADD CONSTRAINT chk_plate_events_gate_command CHECK (gate_command IS NULL OR gate_command IN ('accepted', 'failed'));
  END IF;
END $$;

ALTER TABLE plate_edge_clients ADD COLUMN IF NOT EXISTS recognition_ready BOOLEAN;

ALTER TABLE plate_edge_clients ADD COLUMN IF NOT EXISTS recognition_note TEXT;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_edge_clients_recognition_note' AND conrelid = 'plate_edge_clients'::regclass) THEN
    ALTER TABLE plate_edge_clients ADD CONSTRAINT chk_plate_edge_clients_recognition_note CHECK (recognition_note IS NULL OR char_length(recognition_note) <= 80);
  END IF;
END $$;

ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS command_ttl_seconds INTEGER NOT NULL DEFAULT 600;

ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS snapshot_interval_seconds INTEGER NOT NULL DEFAULT 4;

ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS snapshot_idle_interval_seconds INTEGER NOT NULL DEFAULT 15;

ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS snapshot_keep_minutes INTEGER NOT NULL DEFAULT 30;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_site_settings_command_ttl' AND conrelid = 'plate_site_settings'::regclass) THEN
    ALTER TABLE plate_site_settings ADD CONSTRAINT chk_plate_site_settings_command_ttl CHECK (command_ttl_seconds BETWEEN 60 AND 3600);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_site_settings_snapshot_interval' AND conrelid = 'plate_site_settings'::regclass) THEN
    ALTER TABLE plate_site_settings ADD CONSTRAINT chk_plate_site_settings_snapshot_interval CHECK (snapshot_interval_seconds BETWEEN 2 AND 60);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_site_settings_snapshot_idle' AND conrelid = 'plate_site_settings'::regclass) THEN
    ALTER TABLE plate_site_settings ADD CONSTRAINT chk_plate_site_settings_snapshot_idle CHECK (snapshot_idle_interval_seconds BETWEEN 5 AND 600);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_plate_site_settings_snapshot_keep' AND conrelid = 'plate_site_settings'::regclass) THEN
    ALTER TABLE plate_site_settings ADD CONSTRAINT chk_plate_site_settings_snapshot_keep CHECK (snapshot_keep_minutes BETWEEN 1 AND 1440);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS plate_edge_commands (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  edge_client_id BIGINT NOT NULL,
  kind TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'pending',
  camera_id BIGINT,
  message TEXT,
  result JSONB,
  requested_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  picked_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  CONSTRAINT chk_plate_edge_commands_kind CHECK (kind IN ('discover', 'probe')),
  CONSTRAINT chk_plate_edge_commands_status CHECK (status IN ('pending', 'running', 'done', 'failed', 'expired')),
  CONSTRAINT chk_plate_edge_commands_message CHECK (message IS NULL OR char_length(message) <= 300)
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_edge_commands_site_code_fkey' AND conrelid = 'plate_edge_commands'::regclass) THEN
    ALTER TABLE plate_edge_commands ADD CONSTRAINT plate_edge_commands_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_plate_edge_commands_open ON plate_edge_commands (edge_client_id, id) WHERE status IN ('pending', 'running');

CREATE INDEX IF NOT EXISTS idx_plate_edge_commands_site ON plate_edge_commands (site_code, kind, id DESC);

CREATE TABLE IF NOT EXISTS plate_camera_snapshots (
  camera_id BIGINT PRIMARY KEY,
  site_code BIGINT NOT NULL,
  edge_client_id BIGINT,
  jpeg BYTEA NOT NULL,
  byte_size INTEGER NOT NULL,
  width INTEGER,
  height INTEGER,
  captured_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_camera_snapshots_site_code_fkey' AND conrelid = 'plate_camera_snapshots'::regclass) THEN
    ALTER TABLE plate_camera_snapshots ADD CONSTRAINT plate_camera_snapshots_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_plate_camera_snapshots_site ON plate_camera_snapshots (site_code, received_at);

CREATE TABLE IF NOT EXISTS plate_snapshot_watch (
  site_code BIGINT PRIMARY KEY,
  watched_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'plate_snapshot_watch_site_code_fkey' AND conrelid = 'plate_snapshot_watch'::regclass) THEN
    ALTER TABLE plate_snapshot_watch ADD CONSTRAINT plate_snapshot_watch_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;
