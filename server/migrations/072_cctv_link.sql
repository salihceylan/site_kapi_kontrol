-- 072: Kamera (CCTV) baglantisi: cctv_cameras, cctv_camera_doors. Sozlesme: docs/PLATFORM_KAMERA_CCTV.md
-- db.js ensureDbSchema ile ayni DDL (src/modules/cctv_schema.js CCTV_STEPS; ayni sira). Tamamen ekleyici ve idempotent; mevcut tablolara dokunmaz.
-- Tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumalidir. Silme: site CASCADE; kamera silinirse kapi eslemeleri CASCADE; kullanici silinirse created_by SET NULL.
-- Video sunucuda SAKLANMAZ; kayit sistemi baglanti sablonu ve istege bagli anlik goruntu adresi tutulur. Parola AES-256-GCM ile sifreli (device_integrations_service.encryptSecret).

CREATE TABLE IF NOT EXISTS cctv_cameras (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  name TEXT NOT NULL,
  location TEXT,
  kind TEXT NOT NULL DEFAULT 'ip_camera',
  channel TEXT,
  clip_url_template TEXT,
  snapshot_url TEXT,
  username TEXT,
  password_enc TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_cctv_cameras_name CHECK (char_length(name) BETWEEN 1 AND 80),
  CONSTRAINT chk_cctv_cameras_location CHECK (location IS NULL OR char_length(location) BETWEEN 1 AND 160),
  CONSTRAINT chk_cctv_cameras_kind CHECK (kind IN ('ip_camera', 'nvr_channel')),
  CONSTRAINT chk_cctv_cameras_channel CHECK (channel IS NULL OR char_length(channel) BETWEEN 1 AND 40),
  CONSTRAINT chk_cctv_cameras_clip CHECK (clip_url_template IS NULL OR char_length(clip_url_template) BETWEEN 1 AND 1000),
  CONSTRAINT chk_cctv_cameras_snapshot CHECK (snapshot_url IS NULL OR char_length(snapshot_url) BETWEEN 1 AND 500),
  CONSTRAINT chk_cctv_cameras_username CHECK (username IS NULL OR char_length(username) BETWEEN 1 AND 80)
);

CREATE TABLE IF NOT EXISTS cctv_camera_doors (
  camera_id BIGINT NOT NULL,
  door_id BIGINT NOT NULL,
  site_code BIGINT NOT NULL,
  PRIMARY KEY (camera_id, door_id)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'cctv_cameras_site_code_fkey' AND conrelid = 'cctv_cameras'::regclass
  ) THEN
    ALTER TABLE cctv_cameras ADD CONSTRAINT cctv_cameras_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'cctv_cameras_created_by_fkey' AND conrelid = 'cctv_cameras'::regclass
  ) THEN
    ALTER TABLE cctv_cameras ADD CONSTRAINT cctv_cameras_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'cctv_camera_doors_camera_id_fkey' AND conrelid = 'cctv_camera_doors'::regclass
  ) THEN
    ALTER TABLE cctv_camera_doors ADD CONSTRAINT cctv_camera_doors_camera_id_fkey FOREIGN KEY (camera_id) REFERENCES cctv_cameras(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'cctv_camera_doors_door_id_fkey' AND conrelid = 'cctv_camera_doors'::regclass
  ) THEN
    ALTER TABLE cctv_camera_doors ADD CONSTRAINT cctv_camera_doors_door_id_fkey FOREIGN KEY (door_id) REFERENCES site_doors(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'cctv_camera_doors_site_code_fkey' AND conrelid = 'cctv_camera_doors'::regclass
  ) THEN
    ALTER TABLE cctv_camera_doors ADD CONSTRAINT cctv_camera_doors_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_cctv_cameras_site ON cctv_cameras (site_code, id DESC);

CREATE INDEX IF NOT EXISTS idx_cctv_camera_doors_door ON cctv_camera_doors (site_code, door_id);
