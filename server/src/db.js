process.env.TZ = 'Europe/Istanbul';

import pg from 'pg';
import dotenv from 'dotenv';
import { generateLocalControlToken } from './utils/helpers.js';
import { runPeopleBackfill } from './modules/people_backfill.js';
import { ensureBulkImportSchema } from './modules/bulk_import_schema.js';
import { ensureFinance4bSchema } from './modules/finance_4b_schema.js';
import { ensureDocumentsSchema } from './modules/document_schema.js';
import { ensureWorkTrackingSchema } from './modules/work_tracking_schema.js';
import { ensureWorkAttachmentsSchema } from './modules/work_attachments_schema.js';
import { ensureReservationSchema } from './modules/reservation_schema.js';
import { ensureSurveySchema } from './modules/survey_schema.js';
import { ensureVisitorLogSchema } from './modules/visitor_log_schema.js';
import { ensureCardAccessSchema } from './modules/card_access_schema.js';
import { ensureContractsSchema } from './modules/contracts_schema.js';
import { ensureDecisionBookSchema } from './modules/decision_book_schema.js';
import { ensurePushSchema } from './modules/push_schema.js';
import { ensureApartmentPinSchema } from './modules/apartment_pin_schema.js';
import { ensureFinancePartiesSchema } from './modules/finance_parties_schema.js';
import { ensurePlatformRulesSchema } from './modules/platform_rules_schema.js';
import { ensureManagementCompanySchema } from './modules/management_company_schema.js';

dotenv.config();

const { Pool } = pg;

// Dayanıklılık (donma/kilitlenme önleme): havuz sınırlı, bağlantı/sorgu zaman aşımlı; açık kalmış
// transaction sunucu tarafında kapatılır; boştaki bağlantı hatası süreci düşürmez.
const DB_POOL_MAX = Math.max(2, Number(process.env.DB_POOL_MAX) || 12);
const DB_STATEMENT_TIMEOUT_MS = Math.max(1000, Number(process.env.DB_STATEMENT_TIMEOUT_MS) || 30000);
const DB_CONNECT_TIMEOUT_MS = Math.max(1000, Number(process.env.DB_CONNECT_TIMEOUT_MS) || 5000);

export const pool = new Pool({
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT || 5432),
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  options: '-c timezone=Europe/Istanbul -c idle_in_transaction_session_timeout=60000',
  max: DB_POOL_MAX,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: DB_CONNECT_TIMEOUT_MS,
  statement_timeout: DB_STATEMENT_TIMEOUT_MS,
  query_timeout: DB_STATEMENT_TIMEOUT_MS + 5000,
  keepAlive: true,
  application_name: 'kapi-api',
});

pool.on('error', (error) => {
  // eslint-disable-next-line no-console
  console.error('[DB] Bosta bekleyen istemci hatasi:', error?.code || error?.message);
});

export async function checkDbConnection() {
  const client = await pool.connect();
  try {
    await client.query('SELECT 1');
  } finally {
    client.release();
  }
}

/** 035: pending_registrations.accepted_documents. migrations/035_platform_services.sql ile AYNI ifade (test: platform_config_schema). */
export const PENDING_CONSENTS_COLUMN_DDL = `
  ALTER TABLE pending_registrations
    ADD COLUMN IF NOT EXISTS accepted_documents JSONB CHECK (accepted_documents IS NULL OR jsonb_typeof(accepted_documents) = 'array')
`;

/**
 * 035'in tek ALTER'i. `ADD COLUMN IF NOT EXISTS` sutun VARKEN bile tabloda ACCESS EXCLUSIVE kilit alir; dev ensureDbSchema blogu tek ortuk
 * islem oldugundan (kilitler sonuna dek birikir) bunu o blokta calistirmak, acilista kayit / dogrulama yazicilariyla 40P01 uretiyordu.
 * Burada: blok BITTIKTEN sonra (kilit tutulmuyor; tablo artik kesin var), kendi otomatik onayli ifadesiyle ve yalnız katalog sutunun eksik
 * oldugunu soyluyorsa ALTER calisir. Sutun varsa (her acilis) hic kilit alinmaz.
 */
async function ensurePendingConsentsColumn(client) {
  const found = await client.query(`
    SELECT EXISTS (
      SELECT 1 FROM pg_attribute
      WHERE attrelid = to_regclass('public.pending_registrations') AND attname = 'accepted_documents' AND NOT attisdropped
    ) AS present
  `);
  if (found.rows[0]?.present !== true) {
    await client.query(PENDING_CONSENTS_COLUMN_DDL);
  }
}

/**
 * 036 (hesap silme + kisisel veri disa aktarma): DDL ifadeleri. migrations/036_account_deletion.sql ile AYNI ifadeler (test: account_schema).
 * Hesap silme KIMLIKSIZLESTIRMEDIR (users satiri kalir; yabanci anahtarlar bozulmaz); silinen hesabi isaretleyen tek sutun users.deleted_at'tir.
 *  - deleted_at dolu <=> hesap kimliksizlestirilmistir ve ASLA aktif olamaz (CHECK, kisit ihlali 23514): yonetici "aktif et" yapsa bile silinmis hesap acilamaz.
 *  - account_data_exports: dis aktarma hiz siniri kaydi (kullanici basina 24 saatte 3); yalniz zaman damgasi, kisisel veri SAKLANMAZ.
 *  - audit_log(actor_user_code) kismi indeksi: FK'nin (ON DELETE SET NULL) kullanici KALICI silinirken siralı taramaya dusmemesi icin; audit_log hic temizlenmez.
 *  - door_access_logs(user_code, opened_at DESC) kismi indeksi: kapi gecis kayitlari kullaniciya gore kimliksizlestirilir / disa aktarilir (30 gun saklanir).
 */
export const ACCOUNT_DELETION_DDL = Object.freeze({
  deletedAtColumn: `ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ`,
  deletedInactiveCheck: `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_users_deleted_inactive' AND conrelid = 'users'::regclass
      ) THEN
        ALTER TABLE users ADD CONSTRAINT chk_users_deleted_inactive CHECK (deleted_at IS NULL OR is_active = FALSE);
      END IF;
    END $$
  `,
  exportsTable: `
    CREATE TABLE IF NOT EXISTS account_data_exports (
      id BIGSERIAL PRIMARY KEY,
      user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
      requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `,
  exportsIndex: `CREATE INDEX IF NOT EXISTS idx_account_data_exports_user ON account_data_exports (user_code, requested_at DESC)`,
  auditActorIndex: `CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON audit_log (actor_user_code) WHERE actor_user_code IS NOT NULL`,
  doorUserIndex: `CREATE INDEX IF NOT EXISTS idx_door_access_logs_user ON door_access_logs (user_code, opened_at DESC) WHERE user_code IS NOT NULL`,
});

/**
 * 036'yi uygular. `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` ve `CREATE INDEX IF NOT EXISTS` nesne VARKEN bile tabloda kilit alir (ACCESS EXCLUSIVE /
 * SHARE); bunlari dev ensureDbSchema blogunun tek ortuk islemine koymak kilitleri sonuna dek biriktirir ve her acilista yazicilarla 40P01 uretir
 * (R2 F-1). Burada: dev blok BITTIKTEN sonra (kilit tutulmuyor), TEK katalog sorgusuyla (kilitsiz) eksik olanlar belirlenir ve YALNIZ eksikler kendi
 * otomatik onayli ifadesiyle calisir. Her sey varsa (her normal acilis) hicbir tabloda kilit alinmaz. audit_log / door_access_logs henuz yoksa
 * (platform oncesi sema) ilgili indeks atlanir; tablo olusunca sonraki acilista yapilir.
 */
async function ensureAccountDeletionSchema(client) {
  const found = await client.query(`
    SELECT
      EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('public.users') AND attname = 'deleted_at' AND NOT attisdropped) AS has_column,
      EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_deleted_inactive' AND conrelid = to_regclass('public.users')) AS has_check,
      to_regclass('public.account_data_exports') IS NOT NULL AS has_exports_table,
      EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_account_data_exports_user') AS has_exports_index,
      to_regclass('public.audit_log') IS NOT NULL AS has_audit_table,
      EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_audit_log_actor') AS has_audit_index,
      to_regclass('public.door_access_logs') IS NOT NULL AS has_door_table,
      EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_door_access_logs_user') AS has_door_index
  `);
  const state = found.rows[0] ?? {};
  if (state.has_column !== true) {
    await client.query(ACCOUNT_DELETION_DDL.deletedAtColumn);
  }
  if (state.has_check !== true) {
    await client.query(ACCOUNT_DELETION_DDL.deletedInactiveCheck);
  }
  if (state.has_exports_table !== true) {
    await client.query(ACCOUNT_DELETION_DDL.exportsTable);
  }
  if (state.has_exports_index !== true) {
    await client.query(ACCOUNT_DELETION_DDL.exportsIndex);
  }
  if (state.has_audit_table === true && state.has_audit_index !== true) {
    await client.query(ACCOUNT_DELETION_DDL.auditActorIndex);
  }
  if (state.has_door_table === true && state.has_door_index !== true) {
    await client.query(ACCOUNT_DELETION_DDL.doorUserIndex);
  }
}

export async function ensureDbSchema() {
  const client = await pool.connect();
  try {
    // Temel tablolar migration'larla gelir; bos veritabaninda ALTER TABLE users yerine anlasilir bir hata ver.
    const baseTables = await client.query(`SELECT to_regclass('public.users') AS users_table`);
    if (!baseTables.rows[0]?.users_table) {
      throw new Error(
        'Veritabani semasi kurulu degil ("users" tablosu yok). Bos veritabaninda once `node scripts/migrate.js --apply` calistirin.',
      );
    }
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
      ALTER TABLE users
      ADD COLUMN IF NOT EXISTS password_reset_token_hash TEXT,
      ADD COLUMN IF NOT EXISTS password_reset_expires_at TIMESTAMPTZ
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_users_password_reset_token
      ON users (password_reset_token_hash)
      WHERE password_reset_token_hash IS NOT NULL
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
    // users_role_check: tanım zaten 4 rolü de içeriyorsa DOKUNULMAZ (her açılışta DROP/ADD yapılmaz);
    // yalnızca kısıt yoksa eklenir veya eski (individual içermeyen) tanımsa yenilenir.
    await client.query(`
      DO $$
      DECLARE
        current_def TEXT;
      BEGIN
        SELECT pg_get_constraintdef(c.oid) INTO current_def
        FROM pg_constraint c
        WHERE c.conname = 'users_role_check' AND c.conrelid = 'users'::regclass;

        IF current_def IS NULL THEN
          ALTER TABLE users ADD CONSTRAINT users_role_check
            CHECK (role IN ('super_user', 'site_manager', 'apartment_owner', 'individual'));
        ELSIF current_def NOT LIKE '%super_user%'
           OR current_def NOT LIKE '%site_manager%'
           OR current_def NOT LIKE '%apartment_owner%'
           OR current_def NOT LIKE '%individual%' THEN
          ALTER TABLE users DROP CONSTRAINT users_role_check;
          ALTER TABLE users ADD CONSTRAINT users_role_check
            CHECK (role IN ('super_user', 'site_manager', 'apartment_owner', 'individual'));
        END IF;
      END $$;
    `);
    // users.updated_at: membership/site servisleri bu kolonu güncelliyor; hiçbir migration eklemediği için
    // (eski kurulumlarda eksik olabilir) idempotent olarak garanti edilir.
    await client.query(`
      ALTER TABLE users
      ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    `);
    // LOWER(email) ile yapılan aramalar (giriş, kayıt, doğrulama) için fonksiyonel indeks (benzersiz DEĞİL:
    // eski verideki büyük/küçük harf çakışmaları başlatmayı engellemesin).
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_users_email_lower
      ON users (LOWER(email))
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
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS feature_qr_enabled BOOLEAN NOT NULL DEFAULT TRUE
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS feature_remote_open_enabled BOOLEAN NOT NULL DEFAULT TRUE
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS feature_local_udp_enabled BOOLEAN NOT NULL DEFAULT TRUE
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS feature_guest_pass_enabled BOOLEAN NOT NULL DEFAULT TRUE
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS qr_entry_active BOOLEAN NOT NULL DEFAULT TRUE
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS require_geofence BOOLEAN NOT NULL DEFAULT FALSE
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS geofence_latitude DOUBLE PRECISION
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS geofence_longitude DOUBLE PRECISION
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS geofence_radius_meters INTEGER NOT NULL DEFAULT 100
    `);
    // Tek varsayılan yarıçap 100 m (istemci + geofence_service ile aynı). Eski kurulumlarda sütun varsayılanı 75'ti:
    // yalnızca SÜTUN VARSAYILANI idempotent olarak 100'e çekilir; mevcut site satırlarının değerlerine DOKUNULMAZ.
    await client.query(`
      ALTER TABLE sites
      ALTER COLUMN geofence_radius_meters SET DEFAULT 100
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS qr_totp_secret TEXT
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS qr_rotation_seconds INTEGER NOT NULL DEFAULT 30
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS deletion_status TEXT NOT NULL DEFAULT 'none'
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS deletion_requested_by_user_code BIGINT
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS deletion_requested_by_name TEXT
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS deletion_requested_by_role TEXT
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS deletion_requested_at TIMESTAMPTZ
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS deletion_email_code VARCHAR(10)
    `);
    await client.query(`
      ALTER TABLE sites
      ADD COLUMN IF NOT EXISTS deletion_email_code_expires_at TIMESTAMPTZ
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
      ADD COLUMN IF NOT EXISTS hardware_type TEXT NOT NULL DEFAULT 'esp32_c3'
    `);
    await client.query(`
      ALTER TABLE devices
      ADD COLUMN IF NOT EXISTS qr_reader_enabled BOOLEAN NOT NULL DEFAULT FALSE
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
      ALTER TABLE devices
      ADD COLUMN IF NOT EXISTS owner_user_id BIGINT REFERENCES users(id) ON DELETE SET NULL
    `);
    await client.query(`
      ALTER TABLE devices
      ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ
    `);
    await client.query(`
      ALTER TABLE devices
      ADD COLUMN IF NOT EXISTS is_defective BOOLEAN NOT NULL DEFAULT FALSE
    `);
    await client.query(`
      ALTER TABLE devices
      ADD COLUMN IF NOT EXISTS defective_reason TEXT
    `);
    await client.query(`
      ALTER TABLE devices
      ADD COLUMN IF NOT EXISTS defective_at TIMESTAMPTZ
    `);
    await client.query(`
      ALTER TABLE devices
      ADD COLUMN IF NOT EXISTS inventory_notes TEXT
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_devices_is_defective
      ON devices(is_defective)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_devices_owner_user_id
      ON devices(owner_user_id)
    `);
    // Yerel kontrol token'ı olmayan cihazlara CSPRNG ile token üret (eski kod md5(random()) kullanıyordu).
    const missingTokenDevices = await client.query(`
      SELECT id FROM devices
      WHERE local_control_token IS NULL OR TRIM(local_control_token) = ''
    `);
    for (const row of missingTokenDevices.rows) {
      await client.query(
        `
          UPDATE devices
          SET local_control_token = $1
          WHERE id = $2 AND (local_control_token IS NULL OR TRIM(local_control_token) = '')
        `,
        [generateLocalControlToken(), row.id],
      );
    }
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
      ALTER TABLE device_runtime_status
      ADD COLUMN IF NOT EXISTS public_ip TEXT
    `);
    await client.query(`
      ALTER TABLE device_runtime_status
      ADD COLUMN IF NOT EXISTS hardware_target TEXT
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

    // QR ve GM60 ile Kapı Açma Tokenleri Tablosu
    await client.query(`
      CREATE TABLE IF NOT EXISTS qr_access_tokens (
        id BIGSERIAL PRIMARY KEY,
        token TEXT NOT NULL UNIQUE,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        door_id BIGINT NOT NULL REFERENCES site_doors(id) ON DELETE CASCADE,
        user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
        user_role TEXT NOT NULL,
        user_name TEXT,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        revoked_at TIMESTAMPTZ
      )
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_token
      ON qr_access_tokens(token)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_door_active
      ON qr_access_tokens(door_id, is_active)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_user
      ON qr_access_tokens(user_code)
    `);

    // NOT: Eskiden burada tek seferlik "apartment_owner kullanıcılarını sil / daire sakinlerini sıfırla"
    // bloğu vardı (reset_apartment_residents_after_site_approval_flow_v1). Üretimde uygulanmıştı;
    // yedekten dönüş/yeni kurulumda kullanıcı verisini silme riski taşıdığı için KALDIRILDI.
    // ensureDbSchema yalnızca additive ve IF NOT EXISTS DDL içerir.

    // Kapı Geçiş & Erişim Logları Tablosu
    await client.query(`
      CREATE TABLE IF NOT EXISTS door_access_logs (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL,
        door_id BIGINT,
        door_name TEXT NOT NULL,
        user_code BIGINT,
        user_name TEXT NOT NULL,
        user_role TEXT,
        apartment_label TEXT,
        trigger_type TEXT NOT NULL,
        opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        ip_address TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
      ALTER TABLE door_access_logs ALTER COLUMN site_code TYPE BIGINT;
      ALTER TABLE door_access_logs ALTER COLUMN user_code TYPE BIGINT;
      ALTER TABLE door_access_logs ALTER COLUMN door_id TYPE BIGINT;
      CREATE INDEX IF NOT EXISTS idx_door_access_logs_site_date
      ON door_access_logs(site_code, opened_at DESC);
      CREATE INDEX IF NOT EXISTS idx_door_access_logs_door
      ON door_access_logs(door_id, opened_at DESC);
      -- 026: cihaz offline loglarının idempotent teslimi (door_log_service / MQTT logs_ack)
      ALTER TABLE door_access_logs ADD COLUMN IF NOT EXISTS device_uid TEXT;
      ALTER TABLE door_access_logs ADD COLUMN IF NOT EXISTS client_log_id TEXT;
      CREATE UNIQUE INDEX IF NOT EXISTS idx_door_access_logs_client_log
      ON door_access_logs(device_uid, client_log_id) WHERE client_log_id IS NOT NULL;
    `);

    // Cihaz Çevrimiçi Kalma Süreleri ve Wi-Fi Kopma / Offline Logları Tablosu
    await client.query(`
      CREATE TABLE IF NOT EXISTS device_connectivity_logs (
        id BIGSERIAL PRIMARY KEY,
        device_uid TEXT NOT NULL REFERENCES devices(device_uid) ON DELETE CASCADE,
        event_type TEXT NOT NULL,
        online_at TIMESTAMPTZ,
        offline_at TIMESTAMPTZ,
        duration_seconds INTEGER,
        reason TEXT,
        wifi_rssi INTEGER,
        wifi_signal_percent INTEGER,
        local_ip TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_device_connectivity_logs_uid_created
      ON device_connectivity_logs(device_uid, created_at DESC);
    `);

    // 011: QR ve GM60 ile Kapı Açma Tabloları ve Bayrakları
    await client.query(`
      ALTER TABLE devices
      ADD COLUMN IF NOT EXISTS qr_reader_enabled BOOLEAN NOT NULL DEFAULT FALSE;

      CREATE TABLE IF NOT EXISTS qr_access_tokens (
        id BIGSERIAL PRIMARY KEY,
        token TEXT NOT NULL UNIQUE,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        door_id BIGINT NOT NULL REFERENCES site_doors(id) ON DELETE CASCADE,
        user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
        user_role TEXT NOT NULL,
        user_name TEXT,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        expires_at TIMESTAMPTZ,
        revoked_at TIMESTAMPTZ
      );

      ALTER TABLE qr_access_tokens
      ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

      UPDATE qr_access_tokens
      SET expires_at = created_at + INTERVAL '10 years'
      WHERE expires_at IS NULL;

      CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_token
      ON qr_access_tokens(token);

      CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_door_active
      ON qr_access_tokens(door_id, is_active);

      CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_user
      ON qr_access_tokens(user_code);

      CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_expires
      ON qr_access_tokens(expires_at);

      -- 020: QR Güvenliği, Token İptali, Geofence ve Sahte Konum Koruması
      ALTER TABLE qr_access_tokens
      ADD COLUMN IF NOT EXISTS superseded_at TIMESTAMPTZ;

      ALTER TABLE qr_access_tokens
      ADD COLUMN IF NOT EXISTS request_latitude DOUBLE PRECISION;

      ALTER TABLE qr_access_tokens
      ADD COLUMN IF NOT EXISTS request_longitude DOUBLE PRECISION;

      ALTER TABLE qr_access_tokens
      ADD COLUMN IF NOT EXISTS request_accuracy DOUBLE PRECISION;

      ALTER TABLE qr_access_tokens
      ADD COLUMN IF NOT EXISTS is_mocked BOOLEAN NOT NULL DEFAULT FALSE;

      CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_user_door_active
      ON qr_access_tokens(user_code, door_id, is_active);

      CREATE INDEX IF NOT EXISTS idx_qr_access_tokens_superseded
      ON qr_access_tokens(superseded_at)
      WHERE superseded_at IS NOT NULL;

      -- 016: ÜYELİK YÖNETİM SİSTEMİ V2 (MEMBERSHIP & ACCESS SCHEMA)
      CREATE TABLE IF NOT EXISTS email_verifications (
        id BIGSERIAL PRIMARY KEY,
        email TEXT NOT NULL,
        code_hash TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        is_verified BOOLEAN NOT NULL DEFAULT FALSE,
        verified_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_email_verifications_email ON email_verifications(LOWER(email));
      CREATE INDEX IF NOT EXISTS idx_email_verifications_created ON email_verifications(created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_email_verifications_email_created ON email_verifications(LOWER(email), created_at DESC);

      -- 028: BEKLEYEN KAYIT. Bireysel self-servis kayitta users satiri e-posta dogrulanana kadar OLUSTURULMAZ;
      -- ad ve parola OZETI (bcrypt, duz metin degil) burada bekler (db.js ile migrations/028 ayni DDL).
      CREATE TABLE IF NOT EXISTS pending_registrations (
        id BIGSERIAL PRIMARY KEY,
        email TEXT NOT NULL,
        full_name TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
      CREATE UNIQUE INDEX IF NOT EXISTS uq_pending_registrations_email
        ON pending_registrations (LOWER(email));
      CREATE INDEX IF NOT EXISTS idx_pending_registrations_updated
        ON pending_registrations (updated_at);

      CREATE TABLE IF NOT EXISTS site_memberships (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
        role TEXT NOT NULL DEFAULT 'RESIDENT',
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT chk_site_membership_role CHECK (role IN ('SITE_OWNER', 'SITE_ADMIN', 'RESIDENT')),
        UNIQUE (site_code, user_code)
      );
      CREATE INDEX IF NOT EXISTS idx_site_memberships_user ON site_memberships(user_code);
      CREATE INDEX IF NOT EXISTS idx_site_memberships_site ON site_memberships(site_code);

      CREATE TABLE IF NOT EXISTS apartment_memberships (
        id BIGSERIAL PRIMARY KEY,
        apartment_id BIGINT NOT NULL REFERENCES apartments(id) ON DELETE CASCADE,
        user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
        role TEXT NOT NULL DEFAULT 'FAMILY_MEMBER',
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT chk_apt_membership_role CHECK (role IN ('APARTMENT_ADMIN', 'FAMILY_MEMBER')),
        UNIQUE (apartment_id, user_code)
      );
      CREATE INDEX IF NOT EXISTS idx_apt_memberships_apt ON apartment_memberships(apartment_id);
      CREATE INDEX IF NOT EXISTS idx_apt_memberships_user ON apartment_memberships(user_code);

      CREATE TABLE IF NOT EXISTS site_join_tokens (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        token TEXT NOT NULL UNIQUE,
        created_by_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        revoked_at TIMESTAMPTZ
      );
      CREATE INDEX IF NOT EXISTS idx_site_join_tokens_token ON site_join_tokens(token);
      CREATE INDEX IF NOT EXISTS idx_site_join_tokens_site_active ON site_join_tokens(site_code, is_active);

      CREATE TABLE IF NOT EXISTS join_requests (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        block_id BIGINT NOT NULL REFERENCES site_blocks(id) ON DELETE CASCADE,
        apartment_id BIGINT NOT NULL REFERENCES apartments(id) ON DELETE CASCADE,
        user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
        status TEXT NOT NULL DEFAULT 'PENDING',
        reviewed_by_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        rejection_reason TEXT,
        reviewed_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT chk_join_request_status CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED'))
      );
      CREATE INDEX IF NOT EXISTS idx_join_requests_site_status ON join_requests(site_code, status);
      CREATE INDEX IF NOT EXISTS idx_join_requests_user ON join_requests(user_code);
      CREATE INDEX IF NOT EXISTS idx_join_requests_apartment ON join_requests(apartment_id);
      ALTER TABLE join_requests ADD COLUMN IF NOT EXISTS notes TEXT;

      ALTER TABLE site_doors
      ADD COLUMN IF NOT EXISTS access_scope TEXT NOT NULL DEFAULT 'SITE_COMMON';

      ALTER TABLE site_doors
      ADD COLUMN IF NOT EXISTS block_id BIGINT REFERENCES site_blocks(id) ON DELETE SET NULL;

      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint WHERE conname = 'chk_site_doors_access_scope'
        ) THEN
          ALTER TABLE site_doors
          ADD CONSTRAINT chk_site_doors_access_scope
          CHECK (access_scope IN ('SITE_COMMON', 'BLOCK', 'CUSTOM'));
        END IF;
      END $$;

      CREATE TABLE IF NOT EXISTS door_access_overrides (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        door_id BIGINT NOT NULL REFERENCES site_doors(id) ON DELETE CASCADE,
        user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
        is_allowed BOOLEAN NOT NULL DEFAULT TRUE,
        granted_by_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        notes TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE (door_id, user_code)
      );
      CREATE INDEX IF NOT EXISTS idx_door_overrides_door ON door_access_overrides(door_id);
      CREATE INDEX IF NOT EXISTS idx_door_overrides_user ON door_access_overrides(user_code);

      CREATE TABLE IF NOT EXISTS site_manager_invitations (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        email VARCHAR(255) NOT NULL,
        full_name VARCHAR(255),
        invited_by_user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
        token VARCHAR(64) NOT NULL UNIQUE,
        status VARCHAR(32) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACCEPTED', 'EXPIRED', 'REVOKED')),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
        UNIQUE (site_code, email)
      );
      CREATE INDEX IF NOT EXISTS idx_site_mgr_inv_email ON site_manager_invitations(LOWER(email));
      CREATE INDEX IF NOT EXISTS idx_site_mgr_inv_site ON site_manager_invitations(site_code);

      -- 029: PLATFORM MODUL SISTEMI (Faz 1). db.js ile migrations/029_platform_modules.sql AYNI DDL; ekleyici ve idempotent.
      -- Eski sitelere satir YAZILMAZ: modul satiri olmayan site katalog varsayilanina gore davranir (door_control ACIK).
      ALTER TABLE sites ADD COLUMN IF NOT EXISTS management_type TEXT NOT NULL DEFAULT 'apartment_site';

      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint
          WHERE conname = 'sites_management_type_check' AND conrelid = 'sites'::regclass
        ) THEN
          ALTER TABLE sites ADD CONSTRAINT sites_management_type_check
            CHECK (management_type IN ('apartment_site', 'residence', 'business_center', 'cooperative', 'shopping_mall'));
        END IF;
      END $$;

      CREATE TABLE IF NOT EXISTS site_modules (
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        module_code TEXT NOT NULL,
        enabled BOOLEAN NOT NULL,
        updated_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        PRIMARY KEY (site_code, module_code)
      );

      CREATE TABLE IF NOT EXISTS audit_log (
        id BIGSERIAL PRIMARY KEY,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        actor_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        actor_name TEXT,
        actor_role TEXT,
        action TEXT NOT NULL,
        site_code BIGINT,
        target_type TEXT,
        target_id TEXT,
        details JSONB NOT NULL DEFAULT '{}'::jsonb
      );
      CREATE INDEX IF NOT EXISTS idx_audit_log_site_id ON audit_log (site_code, id DESC);
      CREATE INDEX IF NOT EXISTS idx_audit_log_id ON audit_log (id DESC);

      DO $$
      DECLARE
        old_check RECORD;
      BEGIN
        FOR old_check IN
          SELECT c.conname
          FROM pg_constraint c
          WHERE c.conrelid = 'site_memberships'::regclass
            AND c.contype = 'c'
            AND pg_get_constraintdef(c.oid) LIKE '%SITE_OWNER%'
            AND pg_get_constraintdef(c.oid) NOT LIKE '%BOARD_MEMBER%'
        LOOP
          EXECUTE format('ALTER TABLE site_memberships DROP CONSTRAINT %I', old_check.conname);
        END LOOP;

        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint
          WHERE conname = 'chk_site_membership_role' AND conrelid = 'site_memberships'::regclass
        ) THEN
          ALTER TABLE site_memberships ADD CONSTRAINT chk_site_membership_role
            CHECK (role IN ('SITE_OWNER', 'SITE_ADMIN', 'RESIDENT', 'BOARD_MEMBER', 'STAFF'));
        END IF;
      END $$;

      -- 030: MODUL TALEBI (Faz 1.1). db.js ile migrations/030_module_requests.sql AYNI DDL; ekleyici ve idempotent.
      CREATE TABLE IF NOT EXISTS module_requests (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        module_code TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        requested_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        requested_by_name TEXT,
        note TEXT,
        decided_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        decided_by_name TEXT,
        decision_note TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        decided_at TIMESTAMPTZ,
        CONSTRAINT chk_module_requests_status CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled'))
      );
      CREATE UNIQUE INDEX IF NOT EXISTS uq_module_requests_pending
        ON module_requests (site_code, module_code) WHERE status = 'pending';
      CREATE INDEX IF NOT EXISTS idx_module_requests_status_id ON module_requests (status, id DESC);
      CREATE INDEX IF NOT EXISTS idx_module_requests_site_id ON module_requests (site_code, id DESC);

      -- 031: KISI VE DAIRE KAYITLARI (Faz 2a). db.js ile migrations/031_people_and_apartments.sql AYNI DDL; ekleyici ve idempotent.
      -- 1. Kişi kaydı. user_code doluysa ad/telefon/e-posta users'tan okunur (burada boş bırakılır; yedek alan olarak kalabilir).
      CREATE TABLE IF NOT EXISTS site_people (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        full_name TEXT,
        phone TEXT,
        email TEXT,
        note TEXT,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
      CREATE UNIQUE INDEX IF NOT EXISTS uq_site_people_user
        ON site_people (site_code, user_code) WHERE user_code IS NOT NULL;
      CREATE UNIQUE INDEX IF NOT EXISTS uq_site_people_email
        ON site_people (site_code, lower(email)) WHERE user_code IS NULL AND email IS NOT NULL AND is_active;
      CREATE INDEX IF NOT EXISTS idx_site_people_site ON site_people (site_code, is_active, id);
      CREATE INDEX IF NOT EXISTS idx_site_people_user ON site_people (user_code) WHERE user_code IS NOT NULL;

      -- 2. Daire ilişkileri (malik/kiracı/aile üyesi/sakin) ve geçmişi. Silinmez: taşınan kişi is_current=false olur.
      CREATE TABLE IF NOT EXISTS apartment_residencies (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        apartment_id BIGINT NOT NULL REFERENCES apartments(id) ON DELETE CASCADE,
        person_id BIGINT NOT NULL REFERENCES site_people(id) ON DELETE CASCADE,
        relation TEXT NOT NULL DEFAULT 'resident',
        is_current BOOLEAN NOT NULL DEFAULT TRUE,
        move_in_date DATE,
        move_out_date DATE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT chk_apartment_residencies_relation CHECK (relation IN ('owner', 'tenant', 'family_member', 'resident'))
      );
      -- Aynı kişi aynı dairede bir kez GÜNCEL; bir dairede en çok bir güncel malik ve bir güncel kiracı.
      CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_residencies_current
        ON apartment_residencies (apartment_id, person_id) WHERE is_current;
      CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_residencies_owner
        ON apartment_residencies (apartment_id) WHERE is_current AND relation = 'owner';
      CREATE UNIQUE INDEX IF NOT EXISTS uq_apartment_residencies_tenant
        ON apartment_residencies (apartment_id) WHERE is_current AND relation = 'tenant';
      CREATE INDEX IF NOT EXISTS idx_apartment_residencies_person ON apartment_residencies (person_id);
      CREATE INDEX IF NOT EXISTS idx_apartment_residencies_apartment ON apartment_residencies (apartment_id, is_current);
      -- Iliskinin kaynagi: 'manual' = CRM'den eklenen (yalniz acik "Tasindi"/pasiflestirmeyle biter); 'sync' = erisim uyeliklerinden
      -- yansitilan (destekleyen uyelik/hesap gercekten kalmayinca otomatik biter). Yonetici elle girdigi kayit sessizce kapanmaz.
      ALTER TABLE apartment_residencies ADD COLUMN IF NOT EXISTS origin TEXT NOT NULL DEFAULT 'manual';
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint
          WHERE conname = 'chk_apartment_residencies_origin' AND conrelid = 'apartment_residencies'::regclass
        ) THEN
          ALTER TABLE apartment_residencies ADD CONSTRAINT chk_apartment_residencies_origin
            CHECK (origin IN ('manual', 'sync'));
        END IF;
      END $$;

      -- 3. Daire alanları (hepsi isteğe bağlı; borç ve bildirim tarafı varsayılan "ikisi de").
      ALTER TABLE apartments ADD COLUMN IF NOT EXISTS floor INTEGER;
      ALTER TABLE apartments ADD COLUMN IF NOT EXISTS gross_area_m2 NUMERIC(8,2);
      ALTER TABLE apartments ADD COLUMN IF NOT EXISTS net_area_m2 NUMERIC(8,2);
      ALTER TABLE apartments ADD COLUMN IF NOT EXISTS land_share_numerator INTEGER;
      ALTER TABLE apartments ADD COLUMN IF NOT EXISTS land_share_denominator INTEGER;
      ALTER TABLE apartments ADD COLUMN IF NOT EXISTS category TEXT;
      ALTER TABLE apartments ADD COLUMN IF NOT EXISTS responsible_party TEXT NOT NULL DEFAULT 'both';

      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint
          WHERE conname = 'chk_apartments_responsible_party' AND conrelid = 'apartments'::regclass
        ) THEN
          ALTER TABLE apartments ADD CONSTRAINT chk_apartments_responsible_party
            CHECK (responsible_party IN ('owner', 'tenant', 'both'));
        END IF;
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint
          WHERE conname = 'chk_apartments_land_share' AND conrelid = 'apartments'::regclass
        ) THEN
          ALTER TABLE apartments ADD CONSTRAINT chk_apartments_land_share
            CHECK (
              (land_share_numerator IS NULL AND land_share_denominator IS NULL)
              OR (land_share_numerator IS NOT NULL AND land_share_denominator IS NOT NULL
                  AND land_share_denominator > 0 AND land_share_numerator >= 0
                  AND land_share_numerator <= land_share_denominator)
            );
        END IF;
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint
          WHERE conname = 'chk_apartments_category_length' AND conrelid = 'apartments'::regclass
        ) THEN
          ALTER TABLE apartments ADD CONSTRAINT chk_apartments_category_length
            CHECK (category IS NULL OR char_length(category) <= 40);
        END IF;
      END $$;

      -- 4. Araçlar. Plaka normalize saklanır (büyük harf, boşluksuz); aynı sitede aktif aynı plaka tekildir.
      CREATE TABLE IF NOT EXISTS vehicles (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        person_id BIGINT REFERENCES site_people(id) ON DELETE SET NULL,
        apartment_id BIGINT REFERENCES apartments(id) ON DELETE SET NULL,
        plate TEXT NOT NULL,
        plate_display TEXT,
        note TEXT,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
      CREATE UNIQUE INDEX IF NOT EXISTS uq_vehicles_plate ON vehicles (site_code, plate) WHERE is_active;
      CREATE INDEX IF NOT EXISTS idx_vehicles_person ON vehicles (person_id);
      CREATE INDEX IF NOT EXISTS idx_vehicles_site ON vehicles (site_code, id DESC);

      -- 5. Tek seferlik aktarım kaydı (people_v1 vb.): kod ensureDbSchema içinde bu tabloyla korunur.
      CREATE TABLE IF NOT EXISTS platform_backfills (
        code TEXT PRIMARY KEY,
        done_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );

      -- 6. Hesap silinince (eski silme/sifirlama akislari dahil) kisi kaydi KORUNUR: ad/telefon yedeklenir, iletisim e-postasi
      -- temizlenir (uq_site_people_email ile cakisip silmeyi 500 yapmasin), kisi pasif olur, guncel iliskileri ve araclari biter.
      -- Kayitlar silinmez (gecmis kalir); tetikleyici silmeyi ENGELLEMEZ (yalniz kilit + basit UPDATE ifadeleri; denetim yazimi alt blokta).
      CREATE OR REPLACE FUNCTION trg_users_preserve_site_people() RETURNS trigger AS $$
      BEGIN
        -- Kilit sirasi: apartments (id sirasiyla) -> users -> site_people / apartment_residencies / vehicles. CRM yazmalari da ayni
        -- sirayi izler; boylece kullanici silme ile "Tasindi"/pasiflestirme yarisi 40P01 (deadlock) uretmez.
        PERFORM a.id
        FROM apartments a
        WHERE a.resident_user_code = OLD.user_code
           OR a.id IN (SELECT am.apartment_id FROM apartment_memberships am WHERE am.user_code = OLD.user_code)
           OR a.id IN (
             SELECT r.apartment_id FROM apartment_residencies r
             INNER JOIN site_people sp ON sp.id = r.person_id
             WHERE sp.user_code = OLD.user_code AND r.is_current
           )
        ORDER BY a.id
        FOR UPDATE;
        -- Denetim YALNIZ aktiften pasife gecen kisiler icin (zaten pasif olanlar icin tekrar yazilmaz); hata silmeyi engellemez.
        BEGIN
          INSERT INTO audit_log (actor_name, actor_role, action, site_code, target_type, target_id, details)
          SELECT 'Sistem', 'system', 'person.deactivated', sp.site_code, 'person', sp.id::text,
                 jsonb_build_object('reason', 'account_deleted', 'auto', TRUE)
          FROM site_people sp
          WHERE sp.user_code = OLD.user_code AND sp.is_active;
        EXCEPTION WHEN OTHERS THEN
          NULL;
        END;
        UPDATE site_people
        SET full_name = COALESCE(full_name, NULLIF(OLD.full_name, '')),
            phone = COALESCE(phone, NULLIF(OLD.phone_number, '')),
            email = NULL,
            is_active = FALSE,
            updated_at = NOW()
        WHERE user_code = OLD.user_code;
        UPDATE apartment_residencies r
        SET is_current = FALSE, move_out_date = COALESCE(r.move_out_date, CURRENT_DATE), updated_at = NOW()
        FROM site_people sp
        WHERE r.person_id = sp.id AND sp.user_code = OLD.user_code AND r.is_current;
        UPDATE vehicles v
        SET is_active = FALSE
        FROM site_people sp
        WHERE v.person_id = sp.id AND sp.user_code = OLD.user_code AND v.is_active;
        RETURN OLD;
      END;
      $$ LANGUAGE plpgsql;
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgname = 'trg_users_preserve_site_people' AND tgrelid = 'users'::regclass AND NOT tgisinternal
        ) THEN
          CREATE TRIGGER trg_users_preserve_site_people BEFORE DELETE ON users
            FOR EACH ROW EXECUTE PROCEDURE trg_users_preserve_site_people();
        END IF;
      END $$;

      -- 032: DUYURU VE BILDIRIM (Faz 3a). db.js ile migrations/032_announcements.sql AYNI DDL; ekleyici ve idempotent.
      -- 1. Duyuru. Metin düz yazıdır (HTML kabul edilmez). scheduled durumunda publish_at DOLU, published/withdrawn durumunda published_at DOLU olmalıdır.
      -- published_by: yayını yapan yönetici (zamanlayıcı yayınında oluşturan); publish_attempts / next_attempt_at: zamanlanmış yayının
      -- başarısızlık sayacı ve üstel geri çekilmesi (zehirli kayıt tüm kuyruğu tıkamasın). email_requested_by / email_requested_at: yöneticinin
      -- kabul edilen e-postalı İSTEĞİ (elle yayın ya da zamanlama / yeniden zamanlama) ve zamanı; saatlik yönetici sınırı bu sayaçla çalışır.
      CREATE TABLE IF NOT EXISTS announcements (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        importance TEXT NOT NULL DEFAULT 'normal',
        status TEXT NOT NULL DEFAULT 'draft',
        target_type TEXT NOT NULL DEFAULT 'site',
        target_block_ids BIGINT[] NOT NULL DEFAULT '{}',
        target_apartment_ids BIGINT[] NOT NULL DEFAULT '{}',
        send_email BOOLEAN NOT NULL DEFAULT FALSE,
        publish_at TIMESTAMPTZ,
        published_at TIMESTAMPTZ,
        withdrawn_at TIMESTAMPTZ,
        edited_at TIMESTAMPTZ,
        edit_count INTEGER NOT NULL DEFAULT 0,
        recipient_count INTEGER NOT NULL DEFAULT 0,
        created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        published_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        email_requested_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        email_requested_at TIMESTAMPTZ,
        publish_attempts INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT chk_announcements_importance CHECK (importance IN ('normal', 'urgent')),
        CONSTRAINT chk_announcements_status CHECK (status IN ('draft', 'scheduled', 'published', 'withdrawn')),
        CONSTRAINT chk_announcements_target_type CHECK (target_type IN ('site', 'blocks', 'apartments')),
        CONSTRAINT chk_announcements_title_length CHECK (char_length(title) BETWEEN 1 AND 120),
        CONSTRAINT chk_announcements_body_length CHECK (char_length(body) BETWEEN 1 AND 5000),
        CONSTRAINT chk_announcements_scheduled_at CHECK (status <> 'scheduled' OR publish_at IS NOT NULL),
        CONSTRAINT chk_announcements_published_at CHECK (status NOT IN ('published', 'withdrawn') OR published_at IS NOT NULL)
      );
      -- Önceki 032 sürümüyle kurulmuş yerel / QA veritabanları için: sonradan eklenen sütunlar ve kısıt idempotent eklenir (yeni kurulumda hepsi
      -- zaten CREATE TABLE içindedir ve bu ifadeler hiçbir şey yapmaz). Kısıt NOT VALID eklenir: eski satırları taramaz, yeni yazımları denetler.
      ALTER TABLE announcements ADD COLUMN IF NOT EXISTS published_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL;
      ALTER TABLE announcements ADD COLUMN IF NOT EXISTS email_requested_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL;
      ALTER TABLE announcements ADD COLUMN IF NOT EXISTS email_requested_at TIMESTAMPTZ;
      ALTER TABLE announcements ADD COLUMN IF NOT EXISTS publish_attempts INTEGER NOT NULL DEFAULT 0;
      ALTER TABLE announcements ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ;
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint
          WHERE conname = 'chk_announcements_published_at' AND conrelid = 'announcements'::regclass
        ) THEN
          ALTER TABLE announcements ADD CONSTRAINT chk_announcements_published_at
            CHECK (status NOT IN ('published', 'withdrawn') OR published_at IS NOT NULL) NOT VALID;
        END IF;
      END $$;
      CREATE INDEX IF NOT EXISTS idx_announcements_site_status
        ON announcements (site_code, status, published_at DESC, id DESC);
      CREATE INDEX IF NOT EXISTS idx_announcements_due
        ON announcements (publish_at) WHERE status = 'scheduled';
      -- Yabancı anahtar indeksleri (kullanıcı silinirken SET NULL taraması) + yöneticinin saatlik yayın sayımı.
      CREATE INDEX IF NOT EXISTS idx_announcements_created_by
        ON announcements (created_by) WHERE created_by IS NOT NULL;
      CREATE INDEX IF NOT EXISTS idx_announcements_published_by
        ON announcements (published_by, published_at) WHERE published_by IS NOT NULL;
      CREATE INDEX IF NOT EXISTS idx_announcements_email_requested
        ON announcements (email_requested_by, email_requested_at) WHERE email_requested_by IS NOT NULL;

      -- 2. Alıcı anlık görüntüsü (yayın anında alınır) + okundu bilgisi + e-posta kuyruğu durumu.
      -- email yalnız gönderilene kadar (pending) tutulur; son durumda NULL'lanır. email_hash: adresin tuzlu SHA-256 özeti (düz adres değil);
      -- adres başına günlük sınır ve bastırma listesi bu özetle çalışır. email_claimed_at: kuyruk işçisi satırı talep etti (gönderim sürüyor;
      -- geri çekme bu satırı iptal ETMEZ); email_next_at: yeniden deneme geri çekilmesi.
      CREATE TABLE IF NOT EXISTS announcement_recipients (
        announcement_id BIGINT NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
        person_id BIGINT NOT NULL REFERENCES site_people(id) ON DELETE CASCADE,
        email TEXT,
        email_hash TEXT,
        email_status TEXT NOT NULL DEFAULT 'none',
        email_attempts INTEGER NOT NULL DEFAULT 0,
        email_claimed_at TIMESTAMPTZ,
        email_next_at TIMESTAMPTZ,
        read_at TIMESTAMPTZ,
        PRIMARY KEY (announcement_id, person_id),
        CONSTRAINT chk_announcement_recipients_email_status CHECK (
          email_status IN ('none', 'pending', 'sent', 'failed', 'no_address', 'skipped_pref', 'capped', 'duplicate')
        )
      );
      -- Önceki 032 sürümüyle kurulmuş veritabanları için sonradan eklenen sütunlar (yeni kurulumda hiçbir şey yapmaz).
      ALTER TABLE announcement_recipients ADD COLUMN IF NOT EXISTS email_hash TEXT;
      ALTER TABLE announcement_recipients ADD COLUMN IF NOT EXISTS email_claimed_at TIMESTAMPTZ;
      ALTER TABLE announcement_recipients ADD COLUMN IF NOT EXISTS email_next_at TIMESTAMPTZ;
      CREATE INDEX IF NOT EXISTS idx_announcement_recipients_person
        ON announcement_recipients (person_id, announcement_id DESC);
      CREATE INDEX IF NOT EXISTS idx_announcement_recipients_unread
        ON announcement_recipients (announcement_id) WHERE read_at IS NULL;
      CREATE INDEX IF NOT EXISTS idx_announcement_recipients_pending
        ON announcement_recipients (email_status) WHERE email_status = 'pending';
      CREATE INDEX IF NOT EXISTS idx_announcement_recipients_email_hash
        ON announcement_recipients (email_hash) WHERE email_hash IS NOT NULL;

      -- 3. Bildirim tercihleri (kullanıcı başına). push_announcements Faz 3b için saklanır; bugün etkisizdir.
      CREATE TABLE IF NOT EXISTS notification_preferences (
        user_code INTEGER PRIMARY KEY REFERENCES users(user_code) ON DELETE CASCADE,
        email_announcements BOOLEAN NOT NULL DEFAULT TRUE,
        push_announcements BOOLEAN NOT NULL DEFAULT TRUE,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );

      -- 4. E-posta bastırma listesi: alıcının e-postadaki "abonelikten çık" bağlantısıyla çıktığı adresler (düz adres değil, tuzlu özet).
      -- Bastırılan adres sonraki duyurularda skipped_pref olur (acil dahil); uygulamadaki duyuruyu ETKİLEMEZ.
      CREATE TABLE IF NOT EXISTS announcement_email_suppressions (
        email_hash TEXT PRIMARY KEY,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );

      -- 033: SITE YONETICISI OLMA / SITE BASVURUSU. db.js ile migrations/033_site_applications.sql AYNI DDL; ekleyici ve idempotent.
      -- Mevcut sitelere abonelik satiri YAZILMAZ (backfill yok); yalniz iki yapilandirma tohumu yazilir (ON CONFLICT DO NOTHING).
      -- 1. Abonelik planları. Ödeme sağlayıcısı ve fiyatlar YOKTUR: fiyat NULL, "standard" planı kapalı ("Yakında…").
      CREATE TABLE IF NOT EXISTS subscription_plans (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        is_active BOOLEAN NOT NULL DEFAULT FALSE,
        price_minor INTEGER,
        currency TEXT NOT NULL DEFAULT 'TRY',
        billing_period TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT chk_subscription_plans_price CHECK (price_minor IS NULL OR price_minor >= 0),
        CONSTRAINT chk_subscription_plans_billing_period CHECK (billing_period IS NULL OR billing_period IN ('monthly', 'yearly'))
      );
      INSERT INTO subscription_plans (code, name, description, is_active)
      VALUES
        ('manual_approval', 'Elle Onaylı', 'Süper kullanıcı onayıyla kurulan site.', TRUE),
        ('standard', 'Standart', 'Yakında…', FALSE)
      ON CONFLICT (code) DO NOTHING;

      -- 2. Site aboneliği (site başına en çok bir satır). application_id düz kimliktir, site_applications'a FK DEĞİLDİR (döngüsel bağımlılık yok).
      CREATE TABLE IF NOT EXISTS site_subscriptions (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL UNIQUE REFERENCES sites(site_code) ON DELETE CASCADE,
        plan_code TEXT NOT NULL REFERENCES subscription_plans(code),
        status TEXT NOT NULL,
        source TEXT NOT NULL,
        application_id BIGINT,
        started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        expires_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT chk_site_subscriptions_status CHECK (status IN ('active', 'trial', 'past_due', 'cancelled', 'expired')),
        CONSTRAINT chk_site_subscriptions_source CHECK (source IN ('manual_approval', 'payment', 'admin'))
      );

      -- 3. Platform ayarları. site_onboarding.mode: 'approval' (bugün) | 'payment' (ileride; bugün seçilemez).
      CREATE TABLE IF NOT EXISTS platform_settings (
        key TEXT PRIMARY KEY,
        value JSONB NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL
      );
      INSERT INTO platform_settings (key, value)
      VALUES ('site_onboarding', '{"mode":"approval"}'::jsonb)
      ON CONFLICT (key) DO NOTHING;

      -- 4. Site başvurusu. blocks / doors: normalizeSetupSiteInput çıktısının JSON hâli (onayda TEKRAR doğrulanır).
      -- Başvuru sırasında cihaz KİLİTLENMEZ (device_uid yalnız bilgidir); onayda sahiplik yeniden doğrulanır. Başvuran silinirse satır kalır
      -- (applicant_user_code NULL). Kişi başına tek bekleyen başvuru: kısmi tekil indeks.
      CREATE TABLE IF NOT EXISTS site_applications (
        id BIGSERIAL PRIMARY KEY,
        applicant_user_code INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        site_name TEXT NOT NULL,
        city TEXT,
        district TEXT,
        address TEXT,
        management_type TEXT NOT NULL DEFAULT 'apartment_site',
        blocks JSONB NOT NULL,
        doors JSONB NOT NULL,
        block_count INTEGER NOT NULL,
        apartment_count INTEGER NOT NULL,
        door_count INTEGER NOT NULL,
        device_uid TEXT,
        note TEXT,
        plan_code TEXT REFERENCES subscription_plans(code),
        payment_status TEXT NOT NULL DEFAULT 'not_required',
        payment_reference TEXT,
        decision_source TEXT,
        decided_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        decided_at TIMESTAMPTZ,
        decision_note TEXT,
        site_code BIGINT REFERENCES sites(site_code) ON DELETE SET NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT chk_site_applications_status CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
        CONSTRAINT chk_site_applications_payment_status CHECK (payment_status IN ('not_required', 'pending', 'paid', 'failed', 'refunded')),
        CONSTRAINT chk_site_applications_decision_source CHECK (decision_source IS NULL OR decision_source IN ('super_user', 'payment', 'system'))
      );
      CREATE UNIQUE INDEX IF NOT EXISTS uq_site_applications_pending
        ON site_applications (applicant_user_code) WHERE status = 'pending';
      CREATE INDEX IF NOT EXISTS idx_site_applications_status_created
        ON site_applications (status, created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_site_applications_applicant_created
        ON site_applications (applicant_user_code, created_at DESC);

      -- 5. Site yöneticisi bağının kaynağı. NULL = eski kayıt (sahip sayılır); 'owner' = site başvurusu onayı / anlık kurulum; 'invited' = mevcut
      -- yöneticinin daveti / ortak yönetici ataması. Anlık site kurulumu yalnız onaylı bir sitede 'invited' OLMAYAN en az bir bağı olan yöneticiye açıktır;
      -- diğer site yöneticileri ve bireysel kullanıcılar site için başvuru yapar.
      ALTER TABLE site_manager_sites ADD COLUMN IF NOT EXISTS link_source TEXT CHECK (link_source IS NULL OR link_source IN ('owner', 'invited'));

      -- 6. Yabancı anahtar indeksleri: hesap / site silinirken (ON DELETE SET NULL) sıralı tarama olmasın.
      CREATE INDEX IF NOT EXISTS idx_site_applications_site
        ON site_applications (site_code) WHERE site_code IS NOT NULL;
      CREATE INDEX IF NOT EXISTS idx_site_applications_decided_by
        ON site_applications (decided_by) WHERE decided_by IS NOT NULL;
      CREATE INDEX IF NOT EXISTS idx_platform_settings_updated_by
        ON platform_settings (updated_by) WHERE updated_by IS NOT NULL;

      -- 034: AIDAT VE FINANS (Faz 4a). db.js ile migrations/034_finance.sql AYNI DDL; ekleyici ve idempotent.
      -- Yeni tablolar ve defter degismezligi tetikleyicisi; mevcut tablolara ve satirlara dokunmaz, veri yazmaz.
      -- 1. Aidat / ek borç tanımları. amount_minor: fixed = daire başı tutar; equal / land_share / area = TOPLAM tutar; category = NULL (category_amounts kullanılır).
      -- Her koşul IS NULL / IS NOT NULL ile açık yazılır: CHECK, NULL sonucunu "geçti" sayar.
      CREATE TABLE IF NOT EXISTS fee_definitions (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        distribution TEXT NOT NULL,
        area_basis TEXT,
        amount_minor BIGINT,
        category_amounts JSONB,
        due_day SMALLINT,
        start_period DATE NOT NULL,
        end_period DATE,
        target_type TEXT NOT NULL DEFAULT 'site',
        target_block_ids BIGINT[] NOT NULL DEFAULT '{}',
        target_apartment_ids BIGINT[] NOT NULL DEFAULT '{}',
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT chk_fee_definitions_name CHECK (char_length(name) BETWEEN 1 AND 80),
        CONSTRAINT chk_fee_definitions_kind CHECK (kind IN ('recurring', 'one_time')),
        CONSTRAINT chk_fee_definitions_distribution CHECK (distribution IN ('fixed', 'equal', 'category', 'land_share', 'area')),
        CONSTRAINT chk_fee_definitions_area_basis CHECK (
          (distribution = 'area' AND area_basis IS NOT NULL AND area_basis IN ('gross', 'net'))
          OR (distribution <> 'area' AND area_basis IS NULL)
        ),
        CONSTRAINT chk_fee_definitions_amount CHECK (
          (distribution = 'category' AND amount_minor IS NULL AND category_amounts IS NOT NULL
            AND jsonb_typeof(category_amounts) = 'object' AND category_amounts <> '{}'::jsonb)
          OR (distribution <> 'category' AND category_amounts IS NULL AND amount_minor IS NOT NULL
            AND amount_minor > 0 AND amount_minor <= 1000000000000)
        ),
        CONSTRAINT chk_fee_definitions_due_day CHECK (
          (due_day IS NULL OR due_day BETWEEN 1 AND 28) AND (kind <> 'recurring' OR due_day IS NOT NULL)
        ),
        CONSTRAINT chk_fee_definitions_periods CHECK (
          EXTRACT(DAY FROM start_period) = 1
          AND (end_period IS NULL OR (EXTRACT(DAY FROM end_period) = 1 AND end_period >= start_period))
        ),
        CONSTRAINT chk_fee_definitions_target CHECK (
          (target_type = 'site' AND cardinality(target_block_ids) = 0 AND cardinality(target_apartment_ids) = 0)
          OR (target_type = 'blocks' AND cardinality(target_block_ids) BETWEEN 1 AND 500 AND cardinality(target_apartment_ids) = 0)
          OR (target_type = 'apartments' AND cardinality(target_apartment_ids) BETWEEN 1 AND 5000 AND cardinality(target_block_ids) = 0)
        )
      );
      CREATE INDEX IF NOT EXISTS idx_fee_definitions_site ON fee_definitions (site_code, is_active, id);
      CREATE INDEX IF NOT EXISTS idx_fee_definitions_created_by ON fee_definitions (created_by) WHERE created_by IS NOT NULL;

      -- 2. Borçlandırma çalıştırması. UNIQUE (definition_id, period): aynı ay ikinci kez borçlandırılamaz. idempotency_key: istemci yeniden denemesi aynı çalıştırmayı döndürür.
      -- request_fingerprint: isteğin kanonik gövdesinin sha256 özeti (aynı anahtar + farklı gövde = 409 IDEMPOTENCY_CONFLICT). natural_key: ek borcun doğal özeti
      -- (ad + tutar + dağıtım + hedef + vade; son 24 saatte aynı sitede tekrarı 409 DUPLICATE_CHARGE olur). Her ikisi de yalnız özet taşır (metin / kişi verisi YOK).
      -- skipped_count: skip_missing ile hariç tutulan (eksik verili) daire sayısı.
      CREATE TABLE IF NOT EXISTS fee_runs (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        definition_id BIGINT NOT NULL REFERENCES fee_definitions(id),
        period DATE NOT NULL,
        total_minor BIGINT NOT NULL,
        apartment_count INTEGER NOT NULL,
        skipped_count INTEGER NOT NULL DEFAULT 0,
        idempotency_key TEXT,
        request_fingerprint TEXT,
        natural_key TEXT,
        posted_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT uq_fee_runs_definition_period UNIQUE (definition_id, period),
        CONSTRAINT chk_fee_runs_total CHECK (total_minor > 0 AND total_minor <= 100000000000000),
        CONSTRAINT chk_fee_runs_count CHECK (apartment_count > 0 AND skipped_count >= 0),
        CONSTRAINT chk_fee_runs_period CHECK (EXTRACT(DAY FROM period) = 1),
        CONSTRAINT chk_fee_runs_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) BETWEEN 1 AND 64),
        CONSTRAINT chk_fee_runs_digests CHECK (
          (request_fingerprint IS NULL OR char_length(request_fingerprint) = 64) AND (natural_key IS NULL OR char_length(natural_key) = 64)
        )
      );
      CREATE INDEX IF NOT EXISTS idx_fee_runs_site_period ON fee_runs (site_code, period);
      CREATE UNIQUE INDEX IF NOT EXISTS uq_fee_runs_idempotency ON fee_runs (site_code, idempotency_key) WHERE idempotency_key IS NOT NULL;
      CREATE INDEX IF NOT EXISTS idx_fee_runs_posted_by ON fee_runs (posted_by) WHERE posted_by IS NOT NULL;
      CREATE INDEX IF NOT EXISTS idx_fee_runs_natural ON fee_runs (site_code, natural_key, posted_at DESC) WHERE natural_key IS NOT NULL;

      -- 3. Defter (append-only). amount_minor > 0 borç (daire borçlu), < 0 tahsilat / alacak; bakiye = SUM(amount_minor).
      -- charge > 0, payment < 0, reversal karşı işaret; reversal <=> reverses_entry_id dolu. Daire silinemez (RESTRICT); site silinince CASCADE geçer.
      -- definition_name: borçlandırma anındaki tanım adının ANLIK GÖRÜNTÜSÜ (tanım adı sonradan değişse de ekstre değişmez; ters kayıt asıldan kopyalar).
      CREATE TABLE IF NOT EXISTS ledger_entries (
        id BIGSERIAL PRIMARY KEY,
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        apartment_id BIGINT NOT NULL REFERENCES apartments(id) ON DELETE RESTRICT,
        kind TEXT NOT NULL,
        amount_minor BIGINT NOT NULL,
        currency TEXT NOT NULL DEFAULT 'TRY',
        period DATE NOT NULL,
        entry_date DATE NOT NULL,
        due_date DATE,
        definition_id BIGINT REFERENCES fee_definitions(id),
        definition_name TEXT,
        run_id BIGINT REFERENCES fee_runs(id),
        payer_party TEXT NOT NULL,
        method TEXT,
        description TEXT,
        reverses_entry_id BIGINT REFERENCES ledger_entries(id),
        reversal_reason TEXT,
        idempotency_key TEXT,
        created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        CONSTRAINT chk_ledger_entries_kind CHECK (kind IN ('charge', 'payment', 'reversal')),
        CONSTRAINT chk_ledger_entries_amount CHECK (amount_minor <> 0 AND amount_minor BETWEEN -1000000000000 AND 1000000000000),
        CONSTRAINT chk_ledger_entries_sign CHECK (
          (kind = 'charge' AND amount_minor > 0) OR (kind = 'payment' AND amount_minor < 0) OR kind = 'reversal'
        ),
        CONSTRAINT chk_ledger_entries_currency CHECK (currency ~ '^[A-Z]{3}$'),
        CONSTRAINT chk_ledger_entries_period CHECK (EXTRACT(DAY FROM period) = 1),
        CONSTRAINT chk_ledger_entries_payer CHECK (payer_party IN ('owner', 'tenant', 'both')),
        CONSTRAINT chk_ledger_entries_method CHECK (
          (kind = 'payment' AND method IS NOT NULL AND method IN ('cash', 'transfer', 'cheque'))
          OR (kind <> 'payment' AND method IS NULL)
        ),
        CONSTRAINT chk_ledger_entries_reversal CHECK ((kind = 'reversal') = (reverses_entry_id IS NOT NULL)),
        CONSTRAINT chk_ledger_entries_reason CHECK (kind = 'reversal' OR reversal_reason IS NULL),
        CONSTRAINT chk_ledger_entries_text CHECK (
          (description IS NULL OR char_length(description) <= 200) AND (reversal_reason IS NULL OR char_length(reversal_reason) <= 200)
        ),
        CONSTRAINT chk_ledger_entries_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) BETWEEN 1 AND 64),
        CONSTRAINT chk_ledger_entries_definition_name CHECK (definition_name IS NULL OR char_length(definition_name) BETWEEN 1 AND 80)
      );
      CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_entries_reverses ON ledger_entries (reverses_entry_id) WHERE reverses_entry_id IS NOT NULL;
      CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_entries_idempotency ON ledger_entries (site_code, idempotency_key) WHERE idempotency_key IS NOT NULL;
      CREATE INDEX IF NOT EXISTS idx_ledger_entries_apartment ON ledger_entries (site_code, apartment_id, entry_date, id);
      CREATE INDEX IF NOT EXISTS idx_ledger_entries_period ON ledger_entries (site_code, period);
      CREATE INDEX IF NOT EXISTS idx_ledger_entries_run ON ledger_entries (run_id);
      -- Yabancı anahtar indeksleri: daire silme (RESTRICT denetimi), tanım ve kullanıcı silme (SET NULL) sıralı tarama yapmasın.
      CREATE INDEX IF NOT EXISTS idx_ledger_entries_apartment_fk ON ledger_entries (apartment_id);
      CREATE INDEX IF NOT EXISTS idx_ledger_entries_definition ON ledger_entries (definition_id) WHERE definition_id IS NOT NULL;
      CREATE INDEX IF NOT EXISTS idx_ledger_entries_created_by ON ledger_entries (created_by) WHERE created_by IS NOT NULL;

      -- 4. Dönem kapanışları. Bir ay, ay <= MAX(kapalı dönem) ise KAPALIDIR (ilk kapatılan aydan önceki aylar dahil). İlk kapatmada herhangi bir ay (<= bu ay),
      -- sonra yalnız closed_through + 1 ay kapatılabilir; yalnız EN SON kapatılan ay yeniden açılır (yalnız süper kullanıcı). Satır silme = yeniden açma.
      CREATE TABLE IF NOT EXISTS finance_period_closures (
        site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
        period DATE NOT NULL,
        closed_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
        closed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        PRIMARY KEY (site_code, period),
        CONSTRAINT chk_finance_period_closures_period CHECK (EXTRACT(DAY FROM period) = 1)
      );
      CREATE INDEX IF NOT EXISTS idx_finance_period_closures_closed_by ON finance_period_closures (closed_by) WHERE closed_by IS NOT NULL;

      -- 5. Değişmezlik tetikleyicileri. Defter (ledger_entries): UPDATE ve DELETE hata verir; tek istisnalar: (a) DELETE, üst sites satırı artık yoksa (site silme CASCADE),
      -- (b) UPDATE yalnızca created_by'ı NULL'a çeviriyorsa VE o kullanıcı artık yoksa (users silinince ON DELETE SET NULL referans eylemi; başka hiçbir sütun değişemez).
      -- Aynı kurallar fee_runs (posted_by) için geçerlidir; finance_period_closures'ta UPDATE yasaktır (closed_by -> NULL istisnası aynı), DELETE serbesttir (yeniden açma).
      -- ledger_entries / fee_runs tablolarini toplu bosaltma (BEFORE tetikleyicisi) engellenir. Yeni defter satırı eklenirken ters kayıt asılı aynalamalıdır (aynı site, aynı daire, karşı tutar, asıl ters kayıt değil).
      CREATE OR REPLACE FUNCTION trg_ledger_entries_append_only() RETURNS trigger AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
            RETURN OLD;
          END IF;
        ELSIF TG_OP = 'UPDATE' THEN
          IF OLD.created_by IS NOT NULL AND NEW.created_by IS NULL
             AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = OLD.created_by)
             AND (to_jsonb(NEW) - 'created_by') = (to_jsonb(OLD) - 'created_by') THEN
            RETURN NEW;
          END IF;
        END IF;
        RAISE EXCEPTION 'finance ledger is append-only';
      END;
      $$ LANGUAGE plpgsql;
      CREATE OR REPLACE FUNCTION trg_ledger_entries_reversal_check() RETURNS trigger AS $$
      DECLARE
        original ledger_entries%ROWTYPE;
      BEGIN
        -- Yalnız hedefli ters kayıtta çalışır (WHEN). Hedefsiz ters kayıt / hedefli borç-tahsilat CHECK kısıtıyla (chk_ledger_entries_reversal) reddedilir.
        SELECT * INTO original FROM ledger_entries WHERE id = NEW.reverses_entry_id;
        IF NOT FOUND OR original.kind = 'reversal' OR original.site_code <> NEW.site_code
           OR original.apartment_id <> NEW.apartment_id OR NEW.amount_minor <> -original.amount_minor THEN
          RAISE EXCEPTION 'finance reversal must mirror its original entry';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      CREATE OR REPLACE FUNCTION trg_fee_runs_append_only() RETURNS trigger AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
            RETURN OLD;
          END IF;
        ELSIF TG_OP = 'UPDATE' THEN
          IF OLD.posted_by IS NOT NULL AND NEW.posted_by IS NULL
             AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = OLD.posted_by)
             AND (to_jsonb(NEW) - 'posted_by') = (to_jsonb(OLD) - 'posted_by') THEN
            RETURN NEW;
          END IF;
        END IF;
        RAISE EXCEPTION 'finance runs are append-only';
      END;
      $$ LANGUAGE plpgsql;
      CREATE OR REPLACE FUNCTION trg_finance_period_closures_no_update() RETURNS trigger AS $$
      BEGIN
        IF OLD.closed_by IS NOT NULL AND NEW.closed_by IS NULL
           AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = OLD.closed_by)
           AND (to_jsonb(NEW) - 'closed_by') = (to_jsonb(OLD) - 'closed_by') THEN
          RETURN NEW;
        END IF;
        RAISE EXCEPTION 'finance period closures cannot be updated';
      END;
      $$ LANGUAGE plpgsql;
      CREATE OR REPLACE FUNCTION trg_finance_block_truncate() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'finance ledger is append-only';
      END;
      $$ LANGUAGE plpgsql;
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgname = 'trg_ledger_entries_append_only' AND tgrelid = 'ledger_entries'::regclass AND NOT tgisinternal
        ) THEN
          CREATE TRIGGER trg_ledger_entries_append_only BEFORE UPDATE OR DELETE ON ledger_entries
            FOR EACH ROW EXECUTE PROCEDURE trg_ledger_entries_append_only();
        END IF;
        IF NOT EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgname = 'trg_ledger_entries_reversal_check' AND tgrelid = 'ledger_entries'::regclass AND NOT tgisinternal
        ) THEN
          CREATE TRIGGER trg_ledger_entries_reversal_check BEFORE INSERT ON ledger_entries
            FOR EACH ROW WHEN (NEW.kind = 'reversal' AND NEW.reverses_entry_id IS NOT NULL)
            EXECUTE PROCEDURE trg_ledger_entries_reversal_check();
        END IF;
        IF NOT EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgname = 'trg_ledger_entries_no_truncate' AND tgrelid = 'ledger_entries'::regclass AND NOT tgisinternal
        ) THEN
          CREATE TRIGGER trg_ledger_entries_no_truncate BEFORE TRUNCATE ON ledger_entries
            FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
        END IF;
        IF NOT EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgname = 'trg_fee_runs_append_only' AND tgrelid = 'fee_runs'::regclass AND NOT tgisinternal
        ) THEN
          CREATE TRIGGER trg_fee_runs_append_only BEFORE UPDATE OR DELETE ON fee_runs
            FOR EACH ROW EXECUTE PROCEDURE trg_fee_runs_append_only();
        END IF;
        IF NOT EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgname = 'trg_fee_runs_no_truncate' AND tgrelid = 'fee_runs'::regclass AND NOT tgisinternal
        ) THEN
          CREATE TRIGGER trg_fee_runs_no_truncate BEFORE TRUNCATE ON fee_runs
            FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
        END IF;
        IF NOT EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgname = 'trg_finance_period_closures_no_update' AND tgrelid = 'finance_period_closures'::regclass AND NOT tgisinternal
        ) THEN
          CREATE TRIGGER trg_finance_period_closures_no_update BEFORE UPDATE ON finance_period_closures
            FOR EACH ROW EXECUTE PROCEDURE trg_finance_period_closures_no_update();
        END IF;
      END $$;

      -- 035: PLATFORM HIZMETLERI (satisa hazirlik). db.js ile migrations/035_platform_services.sql AYNI DDL; ekleyici ve idempotent.
      -- 1. Kullanici onay kayitlari (yasal belge + surum). Ayni belge + surum bir kullanici icin tek satir.
      CREATE TABLE IF NOT EXISTS user_consents (
        id BIGSERIAL PRIMARY KEY,
        user_code INTEGER NOT NULL REFERENCES users(user_code) ON DELETE CASCADE,
        document_id TEXT NOT NULL,
        version TEXT NOT NULL,
        accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        source TEXT NOT NULL DEFAULT 'in_app',
        CONSTRAINT uq_user_consents_user_document_version UNIQUE (user_code, document_id, version),
        CONSTRAINT chk_user_consents_document_id CHECK (document_id ~ '^[a-z][a-z0-9_]{1,39}$'),
        CONSTRAINT chk_user_consents_version CHECK (char_length(version) BETWEEN 1 AND 40),
        CONSTRAINT chk_user_consents_source CHECK (source ~ '^[a-z][a-z_]{1,39}$')
      );

      -- 2. Istemci hata raporlari (kisisel veriden temizlenmis, parmak izine gore tekillestirilmis; kullanici / cihaz / IP saklanmaz).
      CREATE TABLE IF NOT EXISTS client_error_reports (
        id BIGSERIAL PRIMARY KEY,
        fingerprint TEXT NOT NULL,
        error_type TEXT NOT NULL,
        message TEXT NOT NULL,
        app_version TEXT NOT NULL,
        build TEXT,
        platform TEXT NOT NULL,
        os_version TEXT,
        route TEXT,
        fatal BOOLEAN NOT NULL DEFAULT FALSE,
        count INTEGER NOT NULL DEFAULT 1,
        first_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        sample_stack TEXT,
        CONSTRAINT uq_client_error_reports_fingerprint UNIQUE (fingerprint),
        CONSTRAINT chk_client_error_reports_fingerprint CHECK (char_length(fingerprint) = 64),
        CONSTRAINT chk_client_error_reports_platform CHECK (platform IN ('android', 'ios', 'web', 'other')),
        CONSTRAINT chk_client_error_reports_count CHECK (count >= 1),
        CONSTRAINT chk_client_error_reports_sizes CHECK (
          char_length(error_type) <= 100 AND char_length(message) <= 500 AND (sample_stack IS NULL OR char_length(sample_stack) <= 8000)
        )
      );
      CREATE INDEX IF NOT EXISTS idx_client_error_reports_last_seen ON client_error_reports (last_seen DESC, id DESC);
      CREATE INDEX IF NOT EXISTS idx_client_error_reports_first_seen ON client_error_reports (first_seen);

      -- 3. Bekleyen kayitta yasal belge onaylari: pending_registrations.accepted_documents ([{id, version, accepted_at}]; hesap olusurken ayni islemde
      -- user_consents'a yazilir). ALTER bu dev blokta DEGIL: ensurePendingConsentsColumn (asagida) blok BITTIKTEN sonra, katalog kontroluyle calisir
      -- (ADD COLUMN IF NOT EXISTS sutun varken bile ACCESS EXCLUSIVE alir; dev blogun tek ortuk islemine konursa acilista yazicilarla 40P01 uretir).

      -- 036 (hesap silme + kisisel veri disa aktarma): DDL bu dev blokta DEGIL; ensureAccountDeletionSchema (yukarida) blok BITTIKTEN sonra, katalog
      -- kontroluyle ve kendi otomatik onayli ifadeleriyle calisir (ADD COLUMN / CREATE INDEX IF NOT EXISTS nesne varken bile kilit alir; dev blogun tek ortuk
      -- islemine konursa acilista yazicilarla 40P01 uretir). Ifadeler: ACCOUNT_DELETION_DDL = migrations/036_account_deletion.sql.

    `);

    await ensurePendingConsentsColumn(client);
    await ensureAccountDeletionSchema(client);
    // 038 (toplu yukleme, faz 2b): dev blokta DEGIL; katalog kontrolu + her adim kendi otomatik onayli ifadesi (bulk_import_schema.js = migrations/038).
    await ensureBulkImportSchema(client);
    // 040 (finans faz 4b): dev blokta DEGIL; katalog kontrolu + her adim kendi otomatik onayli ifadesi (finance_4b_schema.js = migrations/040).
    await ensureFinance4bSchema(client);
    // 039 (belgeler, faz 3b-A): dev blokta DEGIL; katalog kontrolu + her adim kendi otomatik onayli ifadesi (document_schema.js = migrations/039).
    await ensureDocumentsSchema(client);
    // 041 (telefon bildirimi, faz 3b-B): dev blokta DEGIL; katalog kontrolu + her adim kendi otomatik onayli ifadesi (push_schema.js = migrations/041).
    // notification_preferences'a ALTER yalniz sutunlar eksikse calisir (normal acilista hic kilit yok).
    await ensurePushSchema(client);
    // 042 (is takibi): dev blokta DEGIL; katalog kontrolu + her adim kendi otomatik onayli ifadesi (work_tracking_schema.js = migrations/042).
    await ensureWorkTrackingSchema(client);
    // 043 (rezervasyon ve konsiyerj): dev blokta DEGIL; katalog kontrolu + her adim kendi otomatik onayli ifadesi (reservation_schema.js = migrations/043).
    await ensureReservationSchema(client);
    // 044 (anket ve oylama): dev blokta DEGIL; katalog kontrolu + her adim kendi otomatik onayli ifadesi (survey_schema.js = migrations/044).
    await ensureSurveySchema(client);
    // 045 (ziyaretci ve kargo): dev blokta DEGIL; katalog kontrolu + her adim kendi otomatik onayli ifadesi (visitor_log_schema.js = migrations/045).
    await ensureVisitorLogSchema(client);
    // 046 (kartli gecis, F10): dev blokta DEGIL; katalog kontrolu + her adim kendi otomatik onayli ifadesi (card_access_schema.js = migrations/046).
    await ensureCardAccessSchema(client);
    // 047 (is takibi fotograf ekleri): 042'den SONRA; katalog kontrolu + her adim kendi otomatik onayli ifadesi (work_attachments_schema.js = migrations/047).
    await ensureWorkAttachmentsSchema(client);
    // 049 (firma ve sozlesme takibi): dev blokta DEGIL; katalog kontrolu + her adim kendi otomatik onayli ifadesi (contracts_schema.js = migrations/049).
    await ensureContractsSchema(client);
    // 050 (karar defteri): dev blokta DEGIL; katalog kontrolu + her adim kendi otomatik onayli ifadesi (decision_book_schema.js = migrations/050).
    await ensureDecisionBookSchema(client);
    // 051 (daire PIN'i duz metin kopyasi silinir): katalog kontrolu + kendi otomatik onayli ALTER'i; aktarim partili ve kilitli satiri atlar
    // (apartment_pin_schema.js = migrations/051). Aktarim hatasi acilisi durdurmaz (sonraki acilista yeniden denenir). Isaret bcrypt ile dogrulanir;
    // acilis en cok ~3 sn bekler, kalan satirlar sunucu acildiktan sonra arka planda (havuzdan ayri baglantiyla) tamamlanir.
    await ensureApartmentPinSchema(client, { connect: () => pool.connect() });
    // 052 (iki hesap: malik / kiraci, IP-1A): 040'tan SONRA (late_fee_run_lines); katalog kontrolu + her adim kendi otomatik onayli ifadesi
    // (finance_parties_schema.js = migrations/052). Sicak ledger_entries adimlari en sonda; normal acilista yalniz tek katalog sorgusu.
    await ensureFinancePartiesSchema(client);
    // 053 (kurallar tablosu, G11): dev blokta DEGIL; katalog kontrolu + her adim kendi otomatik onayli ifadesi (platform_rules_schema.js = migrations/053).
    await ensurePlatformRulesSchema(client);
    // 062 (yonetim firmasi Y1/Y2, deneme suresi): katalog kontrolu; management_company_schema.js = migrations/062.
    await ensureManagementCompanySchema(client);

    // 031 people_v1: mevcut sakinlerin CRM'e tek seferlik aktarimi. Savunmaci: hata sunucunun acilmasini ENGELLEMEZ
    // (kendi transaction'i geri alinir, isaret yazilmaz => sonraki acilista yeniden denenir; okuma anindaki
    // syncSitePeople zaten eksikleri tamamlar). Hicbir apartment_memberships / kapi yetkisi satirina dokunmaz.
    try {
      await runPeopleBackfill(client);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[DB] people_v1 aktarimi basarisiz (sonraki acilista tekrar denenecek):', error?.code || error?.message);
    }
  } finally {
    client.release();
  }
}
