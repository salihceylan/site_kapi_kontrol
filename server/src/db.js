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
      ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_users_role_active
      ON users(role, is_active)
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
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
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
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_devices_assigned_user_code
      ON devices(assigned_user_code)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_devices_site_code
      ON devices(site_code)
    `);
  } finally {
    client.release();
  }
}
