-- 112: Drive saglik gostergesi + kota izleme + aktarim dogrulamasi (P2-2 / P2-17 / P2-18). Ekleyici, idempotent; mevcut satirlara dokunmaz (NULL = henuz denetlenmedi / bilinmiyor).
-- db.js ile ayni ifadeler, ayni sira (src/modules/drive_health_schema.js DRIVE_HEALTH_DDL; test: drive_health_schema).
-- site_drive_connections: quota_limit_bytes / quota_used_bytes (about.get storageQuota; limit NULL + kontrol edilmis = sinirsiz), token_expires_at (erisim belirteci son gecerlilik), health_checked_at (son saglik denetimi).
-- drive_files.verify_method: 'sha256' (Drive'in SHA-256'si bizimkiyle eslesti) ya da 'size' (Drive saglama toplami bildirmedi; kimlik + boyut).
-- drive_pending_uploads.error_kind: son denemenin nedeni (quota | integrity | auth | rate_limit | not_found | transient | local); "kuyruk dolu" ile "Google kotasi dolu" ayrimi icin.

ALTER TABLE site_drive_connections ADD COLUMN IF NOT EXISTS quota_limit_bytes BIGINT;

ALTER TABLE site_drive_connections ADD COLUMN IF NOT EXISTS quota_used_bytes BIGINT;

ALTER TABLE site_drive_connections ADD COLUMN IF NOT EXISTS token_expires_at TIMESTAMPTZ;

ALTER TABLE site_drive_connections ADD COLUMN IF NOT EXISTS health_checked_at TIMESTAMPTZ;

ALTER TABLE drive_files ADD COLUMN IF NOT EXISTS verify_method TEXT;

ALTER TABLE drive_pending_uploads ADD COLUMN IF NOT EXISTS error_kind TEXT;
