-- 026: Cihaz offline loglarının idempotent teslimi (door_log_service + MQTT logs_ack)
-- Aynı (device_uid, client_log_id) çifti tekrar eklenmez. Tamamen ekleyici (additive) ve idempotent.
ALTER TABLE door_access_logs ADD COLUMN IF NOT EXISTS device_uid TEXT;
ALTER TABLE door_access_logs ADD COLUMN IF NOT EXISTS client_log_id TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_door_access_logs_client_log
  ON door_access_logs (device_uid, client_log_id)
  WHERE client_log_id IS NOT NULL;
