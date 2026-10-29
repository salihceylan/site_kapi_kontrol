// Plaka Tanıma A1 (geçiş noktaları, "içeride" takibi, kenar istemci sözleşmesi) şeması: 120. migrations/120_plate_gates_edge.sql ile AYNI ifadeler, AYNI sırada.
//
// Hiçbir sayı / yön / eşik koda gömülü değildir: kapılar (plate_gates), kapı-kamera bağı (plate_gate_cameras), kenar istemciler (plate_edge_clients),
// kamera durumu (plate_camera_status), site ayarı (plate_site_settings: misafir kuralı + kalp atışı eşikleri), "içeride" durumu (plate_presence) DB kayıtlarıdır.
// Yön modu / kamera yönü / karar türü / misafir kuralı CHECK listeleridir: yeni değer eklemek TEK migration'dır (DROP CONSTRAINT + ADD CONSTRAINT) ve
// plate_gates_common.js sabitleriyle test bekçisi tarafından eşleşmesi doğrulanır.
//
// Ekleyici ve idempotent: yeni tablolar + plate_events (065) yeni sütunları + apartments.parking_slots (daire başına park yeri sayısı, varsayılan 0).
// Mevcut satırlara dokunulmaz. Tablolar FK'SIZ oluşturulur; sites FK'si ayrı, katalog korumalı ALTER ile eklenir (açılış deadlock dersi: card_access_schema.js).
// Bu dosya db.js'i İÇE AKTARMAZ. Her şey varsa tek katalog sorgusu, kilit yok; eksikse tüm (idempotent) ifadeler lock_timeout 2 sn + 40P01/55P03 yeniden denemesiyle çalışır.

function siteFk(table) {
  const name = `${table}_site_code_fkey`;
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass) THEN
        ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
      END IF;
    END $$
  `;
}

function addCheck(table, name, expression) {
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass) THEN
        ALTER TABLE ${table} ADD CONSTRAINT ${name} CHECK (${expression});
      END IF;
    END $$
  `;
}

/** Sıra BAĞLAYICIDIR (migration ile aynı). */
export const PLATE_GATES_DDL = Object.freeze({
  gatesTable: `
    CREATE TABLE IF NOT EXISTS plate_gates (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      name TEXT NOT NULL,
      direction_mode TEXT NOT NULL DEFAULT 'cift',
      device_uid TEXT,
      door_id BIGINT,
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_plate_gates_name CHECK (char_length(name) BETWEEN 1 AND 60),
      CONSTRAINT chk_plate_gates_direction_mode CHECK (direction_mode IN ('giris', 'cikis', 'cift')),
      CONSTRAINT chk_plate_gates_device_uid CHECK (device_uid IS NULL OR char_length(device_uid) BETWEEN 1 AND 64)
    )
  `,
  gatesSiteFk: siteFk('plate_gates'),
  gatesNameIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_plate_gates_name ON plate_gates (site_code, lower(name))`,
  gateCamerasTable: `
    CREATE TABLE IF NOT EXISTS plate_gate_cameras (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      gate_id BIGINT NOT NULL,
      camera_id BIGINT NOT NULL,
      direction TEXT NOT NULL DEFAULT 'auto',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_plate_gate_cameras_direction CHECK (direction IN ('giris', 'cikis', 'auto'))
    )
  `,
  gateCamerasSiteFk: siteFk('plate_gate_cameras'),
  gateCamerasCameraIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_plate_gate_cameras_camera ON plate_gate_cameras (camera_id)`,
  gateCamerasGateIndex: `CREATE INDEX IF NOT EXISTS idx_plate_gate_cameras_gate ON plate_gate_cameras (site_code, gate_id)`,
  edgeClientsTable: `
    CREATE TABLE IF NOT EXISTS plate_edge_clients (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      name TEXT NOT NULL,
      key_hash TEXT NOT NULL,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      app_version TEXT,
      schema_version INTEGER,
      claimed_at TIMESTAMPTZ,
      last_seen_at TIMESTAMPTZ,
      last_sync_at TIMESTAMPTZ,
      queue_depth INTEGER,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      revoked_at TIMESTAMPTZ,
      CONSTRAINT chk_plate_edge_clients_name CHECK (char_length(name) BETWEEN 1 AND 60),
      CONSTRAINT chk_plate_edge_clients_version CHECK (app_version IS NULL OR char_length(app_version) <= 40)
    )
  `,
  edgeClientsSiteFk: siteFk('plate_edge_clients'),
  edgeClientsSiteIndex: `CREATE INDEX IF NOT EXISTS idx_plate_edge_clients_site ON plate_edge_clients (site_code, id DESC)`,
  cameraStatusTable: `
    CREATE TABLE IF NOT EXISTS plate_camera_status (
      camera_id BIGINT PRIMARY KEY,
      site_code BIGINT NOT NULL,
      edge_client_id BIGINT,
      last_frame_at TIMESTAMPTZ,
      last_read_at TIMESTAMPTZ,
      reported_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `,
  cameraStatusSiteFk: siteFk('plate_camera_status'),
  cameraStatusSiteIndex: `CREATE INDEX IF NOT EXISTS idx_plate_camera_status_site ON plate_camera_status (site_code)`,
  siteSettingsTable: `
    CREATE TABLE IF NOT EXISTS plate_site_settings (
      site_code BIGINT PRIMARY KEY,
      guest_rule TEXT NOT NULL DEFAULT 'tum_bos',
      heartbeat_warn_seconds INTEGER NOT NULL DEFAULT 180,
      heartbeat_crit_seconds INTEGER NOT NULL DEFAULT 600,
      heartbeat_interval_seconds INTEGER NOT NULL DEFAULT 60,
      sync_interval_seconds INTEGER NOT NULL DEFAULT 120,
      updated_by INTEGER,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_plate_site_settings_rule CHECK (guest_rule IN ('tum_bos', 'en_az_bir_bos')),
      CONSTRAINT chk_plate_site_settings_warn CHECK (heartbeat_warn_seconds BETWEEN 30 AND 3600),
      CONSTRAINT chk_plate_site_settings_crit CHECK (heartbeat_crit_seconds BETWEEN 60 AND 7200 AND heartbeat_crit_seconds > heartbeat_warn_seconds),
      CONSTRAINT chk_plate_site_settings_hb CHECK (heartbeat_interval_seconds BETWEEN 10 AND 600),
      CONSTRAINT chk_plate_site_settings_sync CHECK (sync_interval_seconds BETWEEN 30 AND 3600)
    )
  `,
  siteSettingsSiteFk: siteFk('plate_site_settings'),
  presenceTable: `
    CREATE TABLE IF NOT EXISTS plate_presence (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      plate TEXT NOT NULL,
      apartment_id BIGINT,
      kind TEXT NOT NULL DEFAULT 'resident',
      gate_id BIGINT,
      inside BOOLEAN NOT NULL,
      since_at TIMESTAMPTZ NOT NULL,
      last_event_id BIGINT,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_plate_presence_plate CHECK (plate ~ '^[A-Z0-9]{5,10}$'),
      CONSTRAINT chk_plate_presence_kind CHECK (kind IN ('resident', 'guest', 'other'))
    )
  `,
  presenceSiteFk: siteFk('plate_presence'),
  presencePlateIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_plate_presence_plate ON plate_presence (site_code, plate)`,
  presenceInsideIndex: `CREATE INDEX IF NOT EXISTS idx_plate_presence_inside ON plate_presence (site_code, apartment_id) WHERE inside`,
  presenceUpdatedIndex: `CREATE INDEX IF NOT EXISTS idx_plate_presence_updated ON plate_presence (site_code, updated_at)`,
  eventGateColumn: `ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS gate_id BIGINT`,
  eventDirectionColumn: `ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS direction TEXT`,
  eventDecisionColumn: `ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS decision_kind TEXT`,
  eventEdgeColumn: `ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS edge_client_id BIGINT`,
  eventClientIdColumn: `ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS client_event_id TEXT`,
  eventSchemaColumn: `ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS schema_version INTEGER`,
  eventConfidenceColumn: `ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS confidence NUMERIC(5, 4)`,
  eventReasonColumn: `ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS reason TEXT`,
  eventDirectionCheck: addCheck('plate_events', 'chk_plate_events_direction', `direction IS NULL OR direction IN ('giris', 'cikis')`),
  eventDecisionCheck: addCheck('plate_events', 'chk_plate_events_decision_kind', `decision_kind IS NULL OR decision_kind IN ('acildi', 'red', 'tanimsiz')`),
  eventClientIdCheck: addCheck('plate_events', 'chk_plate_events_client_event_id', `client_event_id IS NULL OR char_length(client_event_id) BETWEEN 8 AND 64`),
  eventClientIdIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_plate_events_client_event ON plate_events (site_code, client_event_id) WHERE client_event_id IS NOT NULL`,
  apartmentParkingColumn: `ALTER TABLE apartments ADD COLUMN IF NOT EXISTS parking_slots INTEGER NOT NULL DEFAULT 0`,
  apartmentParkingCheck: addCheck('apartments', 'chk_apartments_parking_slots', `parking_slots BETWEEN 0 AND 50`),
});

export const PLATE_GATES_DDL_ORDER = Object.freeze(Object.keys(PLATE_GATES_DDL));

// Hızlı yol için katalog beklentisi.
const TABLES = Object.freeze(['plate_gates', 'plate_gate_cameras', 'plate_edge_clients', 'plate_camera_status', 'plate_site_settings', 'plate_presence']);
const INDEXES = Object.freeze([
  'uq_plate_gates_name',
  'uq_plate_gate_cameras_camera',
  'idx_plate_gate_cameras_gate',
  'idx_plate_edge_clients_site',
  'idx_plate_camera_status_site',
  'uq_plate_presence_plate',
  'idx_plate_presence_inside',
  'idx_plate_presence_updated',
  'uq_plate_events_client_event',
]);
const COLUMNS = Object.freeze([
  'plate_events.gate_id',
  'plate_events.direction',
  'plate_events.decision_kind',
  'plate_events.edge_client_id',
  'plate_events.client_event_id',
  'plate_events.schema_version',
  'plate_events.confidence',
  'plate_events.reason',
  'apartments.parking_slots',
]);

export const plateGatesTuning = { retryDelayMs: 300 };

const RETRYABLE = new Set(['40P01', '55P03']);
const sleep = (ms) => new Promise((resolve) => {
  const timer = setTimeout(resolve, ms);
  timer.unref?.();
});

async function runDdl(client, sql) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      return await client.query(sql);
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await sleep(plateGatesTuning.retryDelayMs * attempt);
    }
  }
}

/**
 * Her şey varsa tek katalog sorgusu, kilit yok. Üst tablolar (sites, plate_events 065, apartments) yoksa hiçbir şey yapmaz (sonraki açılışta tamamlanır).
 * Eksik bir şey varsa TÜM ifadeler sırayla çalışır (hepsi idempotent: IF NOT EXISTS / katalog korumalı DO bloğu).
 */
export async function ensurePlateGatesSchema(client) {
  const found = await client.query(
    `
      SELECT
        ARRAY(SELECT t FROM unnest($1::TEXT[] || ARRAY['sites', 'plate_events', 'apartments']) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
        ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($2::TEXT[])) AS indexes,
        ARRAY(
          SELECT c.relname::TEXT || '.' || a.attname::TEXT
          FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
          WHERE c.relname = ANY(ARRAY['plate_events', 'apartments']) AND c.relnamespace = 'public'::regnamespace AND a.attnum > 0 AND NOT a.attisdropped
        ) AS columns
    `,
    [TABLES, INDEXES],
  );
  const row = found.rows[0] ?? {};
  const tables = new Set(row.tables ?? []);
  if (!['sites', 'plate_events', 'apartments'].every((t) => tables.has(t))) return;
  const indexes = new Set(row.indexes ?? []);
  const columns = new Set(row.columns ?? []);
  if (TABLES.every((t) => tables.has(t)) && INDEXES.every((i) => indexes.has(i)) && COLUMNS.every((c) => columns.has(c))) return;
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const name of PLATE_GATES_DDL_ORDER) await runDdl(client, PLATE_GATES_DDL[name]);
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
