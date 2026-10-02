-- 024_device_inventory_and_defect_management.sql
-- Şirket Cihaz Envanteri, Arıza Yönetimi ve Yetkisiz Cihaz Engelleme

ALTER TABLE devices
ADD COLUMN IF NOT EXISTS is_defective BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE devices
ADD COLUMN IF NOT EXISTS defective_reason TEXT;

ALTER TABLE devices
ADD COLUMN IF NOT EXISTS defective_at TIMESTAMPTZ;

ALTER TABLE devices
ADD COLUMN IF NOT EXISTS inventory_notes TEXT;

CREATE INDEX IF NOT EXISTS idx_devices_is_defective ON devices(is_defective);
CREATE INDEX IF NOT EXISTS idx_devices_owner_user_id ON devices(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_devices_site_code ON devices(site_code);

