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
      CREATE TABLE IF NOT EXISTS app_maintenance_runs (
        maintenance_key TEXT PRIMARY KEY,
        executed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
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
        block_apartment_counts INTEGER[] NOT NULL DEFAULT ARRAY[0]::INTEGER[],
        approval_status TEXT NOT NULL DEFAULT 'approved',
        approved_at TIMESTAMPTZ,
        mqtt_site_id INTEGER NOT NULL UNIQUE DEFAULT generate_unique_mqtt_site_id(),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS block_apartment_counts INTEGER[] NOT NULL DEFAULT ARRAY[0]::INTEGER[]
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
      ADD COLUMN IF NOT EXISTS approval_status TEXT NOT NULL DEFAULT 'approved'
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS mqtt_site_id INTEGER
    `);
    await client.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1
          FROM pg_constraint
          WHERE conname = 'sites_approval_status_check'
        ) THEN
          ALTER TABLE sites
          ADD CONSTRAINT sites_approval_status_check
          CHECK (approval_status IN ('pending', 'approved', 'rejected'));
        END IF;
      END $$;
    `);
    await client.query(`
      UPDATE sites
      SET block_apartment_counts = CASE
        WHEN block_apartment_counts IS NULL OR array_length(block_apartment_counts, 1) IS NULL
          THEN ARRAY[apartment_count]::INTEGER[]
        ELSE block_apartment_counts
      END
    `);
    await client.query(`
      UPDATE sites
      SET mqtt_site_id = generate_unique_mqtt_site_id()
      WHERE mqtt_site_id IS NULL
    `);
    await client.query(`
      ALTER TABLE sites
      ALTER COLUMN mqtt_site_id SET DEFAULT generate_unique_mqtt_site_id()
    `);
    await client.query(`
      UPDATE sites
      SET approved_at = COALESCE(approved_at, created_at)
      WHERE approval_status = 'approved' AND approved_at IS NULL
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
      CREATE INDEX IF NOT EXISTS idx_sites_approval_status
      ON sites(approval_status)
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
      ALTER TABLE devices
      ADD COLUMN IF NOT EXISTS mqtt_username TEXT
    `);
    await client.query(`
      ALTER TABLE devices
      ADD COLUMN IF NOT EXISTS mqtt_password TEXT
    `);
    await client.query(`
      ALTER TABLE devices
      ADD COLUMN IF NOT EXISTS local_control_token TEXT
    `);
    await client.query(`
      UPDATE devices
      SET local_control_token = md5(random()::text || clock_timestamp()::text || device_uid || id::text)
      WHERE local_control_token IS NULL OR TRIM(local_control_token) = ''
    `);
    await client.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_mqtt_username_unique
      ON devices(mqtt_username)
      WHERE mqtt_username IS NOT NULL
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
      CREATE TABLE IF NOT EXISTS device_runtime_status (
        device_uid TEXT PRIMARY KEY REFERENCES devices(device_uid) ON DELETE CASCADE,
        mqtt_connected BOOLEAN NOT NULL DEFAULT FALSE,
        door_locked BOOLEAN,
        firmware_version TEXT,
        ota_status TEXT,
        ota_last_version TEXT,
        wifi_rssi INTEGER,
        wifi_signal_percent INTEGER,
        last_event TEXT,
        last_event_detail TEXT,
        last_payload_at TIMESTAMPTZ,
        last_seen_at TIMESTAMPTZ,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await client.query(`
      ALTER TABLE device_runtime_status
      ADD COLUMN IF NOT EXISTS local_ip TEXT
    `);
    await client.query(`
      ALTER TABLE device_runtime_status
      ADD COLUMN IF NOT EXISTS local_control_port INTEGER
    `);
    await client.query(`
      ALTER TABLE device_runtime_status
      ADD COLUMN IF NOT EXISTS local_control_available BOOLEAN
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_device_runtime_status_last_seen
      ON device_runtime_status(last_seen_at DESC)
    `);
    await client.query(`
      CREATE TABLE IF NOT EXISTS ota_update_jobs (
        id BIGSERIAL PRIMARY KEY,
        requested_by_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        requested_by_email TEXT,
        requested_count INTEGER NOT NULL DEFAULT 0,
        sent_count INTEGER NOT NULL DEFAULT 0,
        failed_count INTEGER NOT NULL DEFAULT 0,
        installed_count INTEGER NOT NULL DEFAULT 0,
        install_failed_count INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'created',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        completed_at TIMESTAMPTZ
      )
    `);
    await client.query(`
      CREATE TABLE IF NOT EXISTS ota_update_job_devices (
        job_id BIGINT NOT NULL REFERENCES ota_update_jobs(id) ON DELETE CASCADE,
        device_uid TEXT NOT NULL REFERENCES devices(device_uid) ON DELETE CASCADE,
        publish_status TEXT NOT NULL DEFAULT 'pending',
        device_event_status TEXT,
        device_event TEXT,
        device_event_detail TEXT,
        device_event_at TIMESTAMPTZ,
        error_message TEXT,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        PRIMARY KEY (job_id, device_uid)
      )
    `);
    await client.query(`
      ALTER TABLE ota_update_jobs
      ADD COLUMN IF NOT EXISTS installed_count INTEGER NOT NULL DEFAULT 0
    `);
    await client.query(`
      ALTER TABLE ota_update_jobs
      ADD COLUMN IF NOT EXISTS install_failed_count INTEGER NOT NULL DEFAULT 0
    `);
    await client.query(`
      ALTER TABLE ota_update_job_devices
      ADD COLUMN IF NOT EXISTS device_event_status TEXT
    `);
    await client.query(`
      ALTER TABLE ota_update_job_devices
      ADD COLUMN IF NOT EXISTS device_event TEXT
    `);
    await client.query(`
      ALTER TABLE ota_update_job_devices
      ADD COLUMN IF NOT EXISTS device_event_detail TEXT
    `);
    await client.query(`
      ALTER TABLE ota_update_job_devices
      ADD COLUMN IF NOT EXISTS device_event_at TIMESTAMPTZ
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_ota_update_jobs_created_at
      ON ota_update_jobs(created_at DESC)
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
        resident_email TEXT,
        resident_pin_code TEXT,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE (site_code, block_id, unit_label),
        UNIQUE (site_code, block_id, sort_order)
      )
    `);
    await client.query(`
      ALTER TABLE apartments
      ADD COLUMN IF NOT EXISTS resident_email TEXT
    `);
    await client.query(`
      ALTER TABLE apartments
      ADD COLUMN IF NOT EXISTS resident_pin_code TEXT
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
      ALTER TABLE devices
      ADD COLUMN IF NOT EXISTS is_online BOOLEAN DEFAULT FALSE
    `);
    await client.query(`
      ALTER TABLE devices
      ADD COLUMN IF NOT EXISTS last_online_at TIMESTAMPTZ
    `);
    await client.query(`
      ALTER TABLE devices
      ADD COLUMN IF NOT EXISTS last_offline_at TIMESTAMPTZ
    `);
    await client.query(`
      CREATE TABLE IF NOT EXISTS guest_passes (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        door_id BIGINT NOT NULL REFERENCES site_doors(id) ON DELETE CASCADE,
        created_by_user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
        title TEXT NOT NULL,
        token TEXT NOT NULL UNIQUE,
        pass_type TEXT NOT NULL DEFAULT 'single_use',
        expires_at TIMESTAMPTZ NOT NULL,
        max_uses INTEGER NOT NULL DEFAULT 1,
        used_count INTEGER NOT NULL DEFAULT 0,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_guest_passes_token
      ON guest_passes(token)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_guest_passes_user_code
      ON guest_passes(created_by_user_code)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_guest_passes_door_id
      ON guest_passes(door_id)
    `);

    const apartmentResetMaintenanceKey =
      'reset_apartment_residents_after_site_approval_flow_v1';
    const maintenanceCheck = await client.query(
      `
        SELECT 1
        FROM app_maintenance_runs
        WHERE maintenance_key = $1
        LIMIT 1
      `,
      [apartmentResetMaintenanceKey],
    );

    if (maintenanceCheck.rowCount === 0) {
      await client.query(`
        UPDATE apartments
        SET
          resident_user_code = NULL,
          resident_pin_code = NULL
        WHERE resident_user_code IS NOT NULL
           OR resident_pin_code IS NOT NULL
      `);
      await client.query(`
        DELETE FROM users
        WHERE role = 'apartment_owner'
      `);
      await client.query(
        `
          INSERT INTO app_maintenance_runs (maintenance_key)
          VALUES ($1)
        `,
        [apartmentResetMaintenanceKey],
      );
    }

    // Kapı Geçiş & Erişim Logları Tablosu
    await client.query(`
      CREATE TABLE IF NOT EXISTS door_access_logs (
        id BIGSERIAL PRIMARY KEY,
        site_code INT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        door_id INT REFERENCES doors(id) ON DELETE SET NULL,
        door_name TEXT NOT NULL,
        user_code INT REFERENCES users(user_code) ON DELETE SET NULL,
        user_name TEXT NOT NULL,
        user_role TEXT,
        apartment_label TEXT,
        trigger_type TEXT NOT NULL,
        opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        ip_address TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_door_access_logs_site_date
      ON door_access_logs(site_code, opened_at DESC);
      CREATE INDEX IF NOT EXISTS idx_door_access_logs_door
      ON door_access_logs(door_id, opened_at DESC);
    `);
  } finally {
    client.release();
  }
}
