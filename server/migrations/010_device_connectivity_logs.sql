-- Migration: 010_device_connectivity_logs.sql
-- Cihazlarin online kalma sureleri ve kopma/offline loglari

CREATE TABLE IF NOT EXISTS device_connectivity_logs (
  id BIGSERIAL PRIMARY KEY,
  device_uid TEXT NOT NULL REFERENCES devices(device_uid) ON DELETE CASCADE,
  event_type TEXT NOT NULL, -- 'offline', 'online', 'wifi_disconnect'
  online_at TIMESTAMPTZ,
  offline_at TIMESTAMPTZ,
  duration_seconds INTEGER,
  reason TEXT, -- 'mqtt_lwt', 'wifi_lost', 'timeout', 'offline'
  wifi_rssi INTEGER,
  wifi_signal_percent INTEGER,
  local_ip TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_device_connectivity_logs_uid_created
ON device_connectivity_logs(device_uid, created_at DESC);
