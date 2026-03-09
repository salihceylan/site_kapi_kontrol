import pg from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const { Pool } = pg;

export const pool = new Pool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 5432),
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

export async function checkDbConnection() {
  const client = await pool.connect();
  try {
    await client.query('SELECT 1');
  } finally {
    client.release();
  }
}

export async function ensureDbSchema() {
  const client = await pool.connect();
  try {
    await client.query(`
      ALTER TABLE users
      ADD COLUMN IF NOT EXISTS login_name TEXT
    `);
    await client.query(`
      ALTER TABLE users
      ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE
    `);
    await client.query(`
      ALTER TABLE users
      ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT TRUE
    `);
    await client.query(`
      ALTER TABLE users
      ADD COLUMN IF NOT EXISTS approval_status TEXT NOT NULL DEFAULT 'approved'
    `);
    await client.query(`
      ALTER TABLE users
      ADD COLUMN IF NOT EXISTS email_verification_code_hash TEXT
    `);
    await client.query(`
      ALTER TABLE users
      ADD COLUMN IF NOT EXISTS email_verification_expires_at TIMESTAMPTZ
    `);
    await client.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1
          FROM pg_constraint
          WHERE conname = 'users_approval_status_check'
        ) THEN
          ALTER TABLE users
          ADD CONSTRAINT users_approval_status_check
          CHECK (approval_status IN ('pending', 'approved', 'rejected'));
        END IF;
      END $$;
    `);
    await client.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS idx_users_login_name_unique
      ON users (LOWER(login_name))
      WHERE login_name IS NOT NULL
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_users_role_active
      ON users(role, is_active)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_users_role_approval_status
      ON users(role, approval_status)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_users_role_email_verified
      ON users(role, email_verified)
    `);
    await client.query(`
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
      $$ LANGUAGE plpgsql
    `);
    await client.query(`
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
      $$ LANGUAGE plpgsql
    `);
    await client.query(`
      CREATE TABLE IF NOT EXISTS sites (
        site_code BIGINT PRIMARY KEY DEFAULT generate_unique_site_code()
          CHECK (site_code BETWEEN 1000000000 AND 9999999999),
        name TEXT NOT NULL,
        address TEXT,
        city TEXT,
        district TEXT,
        block_count INTEGER NOT NULL DEFAULT 1 CHECK (block_count > 0),
        apartment_count INTEGER NOT NULL DEFAULT 0 CHECK (apartment_count >= 0),
        door_count INTEGER NOT NULL DEFAULT 1 CHECK (door_count > 0),
        mqtt_site_id INTEGER NOT NULL UNIQUE DEFAULT generate_unique_mqtt_site_id(),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS block_count INTEGER NOT NULL DEFAULT 1
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS apartment_count INTEGER NOT NULL DEFAULT 0
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS door_count INTEGER NOT NULL DEFAULT 1
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS mqtt_site_id INTEGER
    `);
    await client.query(`
      UPDATE sites
      SET mqtt_site_id = generate_unique_mqtt_site_id()
      WHERE mqtt_site_id IS NULL
    `);
    await client.query(`
      ALTER TABLE sites
      ALTER COLUMN mqtt_site_id SET NOT NULL
    `);
    await client.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS idx_sites_mqtt_site_id_unique
      ON sites(mqtt_site_id)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_sites_name
      ON sites(name)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_sites_city_district
      ON sites(city, district)
    `);
    await client.query(`
      CREATE TABLE IF NOT EXISTS devices (
        id BIGSERIAL PRIMARY KEY,
        device_uid TEXT NOT NULL UNIQUE,
        assigned_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        site_code BIGINT REFERENCES sites(site_code) ON DELETE SET NULL,
        gate_name TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await client.query(`
      ALTER TABLE devices
      ADD COLUMN IF NOT EXISTS gate_name TEXT
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_devices_assigned_user_code
      ON devices(assigned_user_code)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_devices_site_code
      ON devices(site_code)
    `);
    await client.query(`
      CREATE TABLE IF NOT EXISTS site_manager_sites (
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        manager_user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        PRIMARY KEY (site_code, manager_user_code)
      )
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_site_manager_sites_manager
      ON site_manager_sites(manager_user_code)
    `);
    await client.query(`
      CREATE TABLE IF NOT EXISTS site_blocks (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        block_name TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE (site_code, block_name),
        UNIQUE (site_code, sort_order)
      )
    `);
    await client.query(`
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
      )
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_apartments_site_code
      ON apartments(site_code)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_apartments_resident_user_code
      ON apartments(resident_user_code)
    `);
    await client.query(`
      CREATE TABLE IF NOT EXISTS site_doors (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        door_name TEXT NOT NULL,
        door_index INTEGER NOT NULL,
        assigned_device_id BIGINT REFERENCES devices(id) ON DELETE SET NULL,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE (site_code, door_index)
      )
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_site_doors_site_code
      ON site_doors(site_code)
    `);
    await client.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS idx_site_doors_assigned_device_unique
      ON site_doors(assigned_device_id)
      WHERE assigned_device_id IS NOT NULL
    `);
  } finally {
    client.release();
  }
}
