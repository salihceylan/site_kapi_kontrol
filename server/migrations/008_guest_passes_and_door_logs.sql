-- Migration 008: Guest passes, door access logs, device online status and telemetry

ALTER TABLE devices
ADD COLUMN IF NOT EXISTS hardware_type TEXT NOT NULL DEFAULT 'esp32_c3';

ALTER TABLE devices
ADD COLUMN IF NOT EXISTS is_online BOOLEAN DEFAULT FALSE;

ALTER TABLE devices
ADD COLUMN IF NOT EXISTS last_online_at TIMESTAMPTZ;

ALTER TABLE devices
ADD COLUMN IF NOT EXISTS last_offline_at TIMESTAMPTZ;

ALTER TABLE device_runtime_status
ADD COLUMN IF NOT EXISTS local_ip TEXT;

ALTER TABLE device_runtime_status
ADD COLUMN IF NOT EXISTS local_control_port INTEGER;

ALTER TABLE device_runtime_status
ADD COLUMN IF NOT EXISTS local_control_available BOOLEAN;

ALTER TABLE device_runtime_status
ADD COLUMN IF NOT EXISTS public_ip TEXT;

ALTER TABLE device_runtime_status
ADD COLUMN IF NOT EXISTS hardware_target TEXT;

CREATE TABLE IF NOT EXISTS guest_passes (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  door_id BIGINT NOT NULL REFERENCES site_doors(id) ON DELETE CASCADE,
  created_by_user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
  title TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  pass_type TEXT NOT NULL DEFAULT 'single_use',
  expires_at TIMESTAMPTZ NOT NULL,
  max_uses INTEGER NOT NULL DEFAULT 1,
  used_count INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_guest_passes_token ON guest_passes(token);
CREATE INDEX IF NOT EXISTS idx_guest_passes_user_code ON guest_passes(created_by_user_code);
CREATE INDEX IF NOT EXISTS idx_guest_passes_door_id ON guest_passes(door_id);

CREATE TABLE IF NOT EXISTS door_access_logs (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  door_id BIGINT,
  door_name TEXT NOT NULL,
  user_code BIGINT,
  user_name TEXT NOT NULL,
  user_role TEXT,
  apartment_label TEXT,
  trigger_type TEXT NOT NULL DEFAULT 'cloud_app',
  opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ip_address TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_door_access_logs_site_date ON door_access_logs(site_code, opened_at DESC);
CREATE INDEX IF NOT EXISTS idx_door_access_logs_door ON door_access_logs(door_id);
