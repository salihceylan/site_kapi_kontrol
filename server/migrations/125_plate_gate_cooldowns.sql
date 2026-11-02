-- 125: Plaka Tanıma - Kapı bazlı geçiş zamanlamaları:
-- 1) Bir sonraki aracın plakasının okunması için bekleme süresi (consecutive_vehicle_delay_seconds: varsayılan 10 sn)
-- 2) Giren bir aracın arka plakasının çıkış kamerası tarafından okunmaması için bekleme süresi (entry_rear_suppress_seconds: varsayılan 60 sn)
-- 3) Çıkan bir aracın arka plakasının giriş kamerası tarafından okunmaması için bekleme süresi (exit_rear_suppress_seconds: varsayılan 60 sn)

ALTER TABLE plate_gates
  ADD COLUMN IF NOT EXISTS consecutive_vehicle_delay_seconds INTEGER NOT NULL DEFAULT 10,
  ADD COLUMN IF NOT EXISTS entry_rear_suppress_seconds INTEGER NOT NULL DEFAULT 60,
  ADD COLUMN IF NOT EXISTS exit_rear_suppress_seconds INTEGER NOT NULL DEFAULT 60;

ALTER TABLE plate_gates
  DROP CONSTRAINT IF EXISTS chk_plate_gates_consecutive_cd,
  DROP CONSTRAINT IF EXISTS chk_plate_gates_entry_rear,
  DROP CONSTRAINT IF EXISTS chk_plate_gates_exit_rear;

ALTER TABLE plate_gates
  ADD CONSTRAINT chk_plate_gates_consecutive_cd CHECK (consecutive_vehicle_delay_seconds BETWEEN 1 AND 120),
  ADD CONSTRAINT chk_plate_gates_entry_rear CHECK (entry_rear_suppress_seconds BETWEEN 5 AND 600),
  ADD CONSTRAINT chk_plate_gates_exit_rear CHECK (exit_rear_suppress_seconds BETWEEN 5 AND 600);
