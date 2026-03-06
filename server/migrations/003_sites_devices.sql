CREATE OR REPLACE FUNCTION generate_unique_site_code()
RETURNS BIGINT AS $$
DECLARE
  generated_code BIGINT;
BEGIN
  LOOP
    generated_code := FLOOR(1000000000 + random() * 9000000000)::BIGINT;
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM sites WHERE site_code = generated_code
    );
  END LOOP;

  RETURN generated_code;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS sites (
  site_code BIGINT PRIMARY KEY DEFAULT generate_unique_site_code()
    CHECK (site_code BETWEEN 1000000000 AND 9999999999),
  name TEXT NOT NULL,
  address TEXT,
  city TEXT,
  district TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sites_name ON sites(name);
CREATE INDEX IF NOT EXISTS idx_sites_city_district ON sites(city, district);

CREATE TABLE IF NOT EXISTS devices (
  id BIGSERIAL PRIMARY KEY,
  device_uid TEXT NOT NULL UNIQUE,
  assigned_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  site_code BIGINT REFERENCES sites(site_code) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_devices_assigned_user_code
ON devices(assigned_user_code);

CREATE INDEX IF NOT EXISTS idx_devices_site_code
ON devices(site_code);
