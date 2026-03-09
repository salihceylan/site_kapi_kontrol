ALTER TABLE users
ADD COLUMN IF NOT EXISTS login_name TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_login_name_unique
ON users (LOWER(login_name))
WHERE login_name IS NOT NULL;

CREATE OR REPLACE FUNCTION generate_unique_mqtt_site_id()
RETURNS INTEGER AS $$
DECLARE
  generated_code INTEGER;
BEGIN
  LOOP
    generated_code := FLOOR(1000 + random() * 9000)::INTEGER;
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM sites WHERE mqtt_site_id = generated_code
    );
  END LOOP;

  RETURN generated_code;
END;
$$ LANGUAGE plpgsql;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS block_count INTEGER NOT NULL DEFAULT 1;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS apartment_count INTEGER NOT NULL DEFAULT 0;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS door_count INTEGER NOT NULL DEFAULT 1;

ALTER TABLE sites
ADD COLUMN IF NOT EXISTS mqtt_site_id INTEGER;

UPDATE sites
SET mqtt_site_id = generate_unique_mqtt_site_id()
WHERE mqtt_site_id IS NULL;

ALTER TABLE sites
ALTER COLUMN mqtt_site_id SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sites_mqtt_site_id_unique
ON sites(mqtt_site_id);

CREATE TABLE IF NOT EXISTS site_manager_sites (
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  manager_user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (site_code, manager_user_code)
);

CREATE INDEX IF NOT EXISTS idx_site_manager_sites_manager
ON site_manager_sites(manager_user_code);

CREATE TABLE IF NOT EXISTS site_blocks (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  block_name TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (site_code, block_name),
  UNIQUE (site_code, sort_order)
);

CREATE TABLE IF NOT EXISTS apartments (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  block_id BIGINT NOT NULL REFERENCES site_blocks(id) ON DELETE CASCADE,
  unit_label TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  resident_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (site_code, block_id, unit_label),
  UNIQUE (site_code, block_id, sort_order)
);

CREATE INDEX IF NOT EXISTS idx_apartments_site_code
ON apartments(site_code);

CREATE INDEX IF NOT EXISTS idx_apartments_resident_user_code
ON apartments(resident_user_code);

CREATE TABLE IF NOT EXISTS site_doors (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  door_name TEXT NOT NULL,
  door_index INTEGER NOT NULL,
  assigned_device_id BIGINT REFERENCES devices(id) ON DELETE SET NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (site_code, door_index)
);

CREATE INDEX IF NOT EXISTS idx_site_doors_site_code
ON site_doors(site_code);

CREATE UNIQUE INDEX IF NOT EXISTS idx_site_doors_assigned_device_unique
ON site_doors(assigned_device_id)
WHERE assigned_device_id IS NOT NULL;
