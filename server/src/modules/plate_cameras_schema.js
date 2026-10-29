// Plaka Tanıma sözleşme sürüm 3 (uygulamadan uçtan uca yönetim) şeması: 122. migrations/122_plate_cameras_edge.sql ile AYNI ifadeler, AYNI sırada.
//
// Eklenenler: kamera RTSP adresi + kenarın sınama sonucu (camera_devices), uzaktan komut kuyruğu (plate_edge_commands: "ağda kamera ara", "kamerayı sına"),
// kamera başına SON görüntü karesi (plate_camera_snapshots: tarihçe YOK, üzerine yazılır; KVKK), görüntüyü izleyen yönetici işareti (plate_snapshot_watch),
// olaya kimlik bağlama (apartment_id, person_id, identity_kind) + kapı komutu sonucu (gate_command), kenarın okuma hazırlığı (plate_edge_clients),
// komut ömrü ve görüntü aralıkları (plate_site_settings).
//
// Hiçbir sayı koda gömülü değildir: komut ömrü, görüntü aralıkları ve saklama süresi plate_site_settings sütunlarıdır (varsayılanlar DEFAULT_SITE_SETTINGS aynası).
// Ekleyici ve idempotent: sütunlar IF NOT EXISTS, CHECK'ler katalog korumalı; mevcut satırlara dokunulmaz. Tablolar FK'SIZ oluşturulur; sites FK'si ayrı, katalog
// korumalı ALTER ile eklenir (açılış deadlock dersi: card_access_schema.js). Bu dosya db.js'i İÇE AKTARMAZ.

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
export const PLATE_CAMERAS_DDL = Object.freeze({
  cameraRtspColumn: `ALTER TABLE camera_devices ADD COLUMN IF NOT EXISTS rtsp_url TEXT`,
  cameraProbeStatusColumn: `ALTER TABLE camera_devices ADD COLUMN IF NOT EXISTS probe_status TEXT NOT NULL DEFAULT 'none'`,
  cameraProbeMessageColumn: `ALTER TABLE camera_devices ADD COLUMN IF NOT EXISTS probe_message TEXT`,
  cameraProbeWidthColumn: `ALTER TABLE camera_devices ADD COLUMN IF NOT EXISTS probe_width INTEGER`,
  cameraProbeHeightColumn: `ALTER TABLE camera_devices ADD COLUMN IF NOT EXISTS probe_height INTEGER`,
  cameraProbeAtColumn: `ALTER TABLE camera_devices ADD COLUMN IF NOT EXISTS probe_at TIMESTAMPTZ`,
  cameraRtspCheck: addCheck('camera_devices', 'chk_camera_devices_rtsp_url', `rtsp_url IS NULL OR (char_length(rtsp_url) BETWEEN 8 AND 500 AND rtsp_url ~ '^rtsps?://')`),
  cameraProbeStatusCheck: addCheck('camera_devices', 'chk_camera_devices_probe_status', `probe_status IN ('none', 'pending', 'ok', 'failed')`),
  cameraProbeMessageCheck: addCheck('camera_devices', 'chk_camera_devices_probe_message', `probe_message IS NULL OR char_length(probe_message) <= 300`),
  eventApartmentColumn: `ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS apartment_id BIGINT`,
  eventPersonColumn: `ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS person_id BIGINT`,
  eventIdentityColumn: `ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS identity_kind TEXT`,
  eventGateCommandColumn: `ALTER TABLE plate_events ADD COLUMN IF NOT EXISTS gate_command TEXT`,
  eventIdentityCheck: addCheck('plate_events', 'chk_plate_events_identity_kind', `identity_kind IS NULL OR identity_kind IN ('resident', 'guest')`),
  eventGateCommandCheck: addCheck('plate_events', 'chk_plate_events_gate_command', `gate_command IS NULL OR gate_command IN ('accepted', 'failed')`),
  edgeRecognitionReadyColumn: `ALTER TABLE plate_edge_clients ADD COLUMN IF NOT EXISTS recognition_ready BOOLEAN`,
  edgeRecognitionNoteColumn: `ALTER TABLE plate_edge_clients ADD COLUMN IF NOT EXISTS recognition_note TEXT`,
  edgeRecognitionNoteCheck: addCheck('plate_edge_clients', 'chk_plate_edge_clients_recognition_note', `recognition_note IS NULL OR char_length(recognition_note) <= 80`),
  settingsCommandTtlColumn: `ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS command_ttl_seconds INTEGER NOT NULL DEFAULT 600`,
  settingsSnapshotIntervalColumn: `ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS snapshot_interval_seconds INTEGER NOT NULL DEFAULT 4`,
  settingsSnapshotIdleColumn: `ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS snapshot_idle_interval_seconds INTEGER NOT NULL DEFAULT 15`,
  settingsSnapshotKeepColumn: `ALTER TABLE plate_site_settings ADD COLUMN IF NOT EXISTS snapshot_keep_minutes INTEGER NOT NULL DEFAULT 30`,
  settingsCommandTtlCheck: addCheck('plate_site_settings', 'chk_plate_site_settings_command_ttl', 'command_ttl_seconds BETWEEN 60 AND 3600'),
  settingsSnapshotIntervalCheck: addCheck('plate_site_settings', 'chk_plate_site_settings_snapshot_interval', 'snapshot_interval_seconds BETWEEN 2 AND 60'),
  settingsSnapshotIdleCheck: addCheck('plate_site_settings', 'chk_plate_site_settings_snapshot_idle', 'snapshot_idle_interval_seconds BETWEEN 5 AND 600'),
  settingsSnapshotKeepCheck: addCheck('plate_site_settings', 'chk_plate_site_settings_snapshot_keep', 'snapshot_keep_minutes BETWEEN 1 AND 1440'),
  commandsTable: `
    CREATE TABLE IF NOT EXISTS plate_edge_commands (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      edge_client_id BIGINT NOT NULL,
      kind TEXT NOT NULL,
      payload JSONB NOT NULL DEFAULT '{}'::jsonb,
      status TEXT NOT NULL DEFAULT 'pending',
      camera_id BIGINT,
      message TEXT,
      result JSONB,
      requested_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      picked_at TIMESTAMPTZ,
      completed_at TIMESTAMPTZ,
      CONSTRAINT chk_plate_edge_commands_kind CHECK (kind IN ('discover', 'probe')),
      CONSTRAINT chk_plate_edge_commands_status CHECK (status IN ('pending', 'running', 'done', 'failed', 'expired')),
      CONSTRAINT chk_plate_edge_commands_message CHECK (message IS NULL OR char_length(message) <= 300)
    )
  `,
  commandsSiteFk: siteFk('plate_edge_commands'),
  commandsOpenIndex: `CREATE INDEX IF NOT EXISTS idx_plate_edge_commands_open ON plate_edge_commands (edge_client_id, id) WHERE status IN ('pending', 'running')`,
  commandsSiteIndex: `CREATE INDEX IF NOT EXISTS idx_plate_edge_commands_site ON plate_edge_commands (site_code, kind, id DESC)`,
  snapshotsTable: `
    CREATE TABLE IF NOT EXISTS plate_camera_snapshots (
      camera_id BIGINT PRIMARY KEY,
      site_code BIGINT NOT NULL,
      edge_client_id BIGINT,
      jpeg BYTEA NOT NULL,
      byte_size INTEGER NOT NULL,
      width INTEGER,
      height INTEGER,
      captured_at TIMESTAMPTZ NOT NULL,
      received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `,
  snapshotsSiteFk: siteFk('plate_camera_snapshots'),
  snapshotsSiteIndex: `CREATE INDEX IF NOT EXISTS idx_plate_camera_snapshots_site ON plate_camera_snapshots (site_code, received_at)`,
  watchTable: `
    CREATE TABLE IF NOT EXISTS plate_snapshot_watch (
      site_code BIGINT PRIMARY KEY,
      watched_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `,
  watchSiteFk: siteFk('plate_snapshot_watch'),
});

export const PLATE_CAMERAS_DDL_ORDER = Object.freeze(Object.keys(PLATE_CAMERAS_DDL));

// Hızlı yol için katalog beklentisi.
const TABLES = Object.freeze(['plate_edge_commands', 'plate_camera_snapshots', 'plate_snapshot_watch']);
const INDEXES = Object.freeze(['idx_plate_edge_commands_open', 'idx_plate_edge_commands_site', 'idx_plate_camera_snapshots_site']);
const COLUMNS = Object.freeze([
  'camera_devices.rtsp_url',
  'camera_devices.probe_status',
  'camera_devices.probe_message',
  'camera_devices.probe_width',
  'camera_devices.probe_height',
  'camera_devices.probe_at',
  'plate_events.apartment_id',
  'plate_events.person_id',
  'plate_events.identity_kind',
  'plate_events.gate_command',
  'plate_edge_clients.recognition_ready',
  'plate_edge_clients.recognition_note',
  'plate_site_settings.command_ttl_seconds',
  'plate_site_settings.snapshot_interval_seconds',
  'plate_site_settings.snapshot_idle_interval_seconds',
  'plate_site_settings.snapshot_keep_minutes',
]);
const PARENTS = Object.freeze(['sites', 'camera_devices', 'plate_events', 'plate_edge_clients', 'plate_site_settings']);

export const plateCamerasTuning = { retryDelayMs: 300 };

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
      await sleep(plateCamerasTuning.retryDelayMs * attempt);
    }
  }
}

/**
 * Her şey varsa tek katalog sorgusu, kilit yok. Üst tablolar (sites, camera_devices 065, plate_events 065, plate_edge_clients / plate_site_settings 120) yoksa
 * hiçbir şey yapmaz (sonraki açılışta tamamlanır). Eksik bir şey varsa TÜM ifadeler sırayla çalışır (hepsi idempotent).
 */
export async function ensurePlateCamerasSchema(client) {
  const found = await client.query(
    `
      SELECT
        ARRAY(SELECT t FROM unnest($1::TEXT[] || $3::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
        ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($2::TEXT[])) AS indexes,
        ARRAY(
          SELECT c.relname::TEXT || '.' || a.attname::TEXT
          FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
          WHERE c.relname = ANY(ARRAY['camera_devices', 'plate_events', 'plate_edge_clients', 'plate_site_settings'])
            AND c.relnamespace = 'public'::regnamespace AND a.attnum > 0 AND NOT a.attisdropped
        ) AS columns
    `,
    [TABLES, INDEXES, PARENTS],
  );
  const row = found.rows[0] ?? {};
  const tables = new Set(row.tables ?? []);
  if (!PARENTS.every((t) => tables.has(t))) return;
  const indexes = new Set(row.indexes ?? []);
  const columns = new Set(row.columns ?? []);
  if (TABLES.every((t) => tables.has(t)) && INDEXES.every((i) => indexes.has(i)) && COLUMNS.every((c) => columns.has(c))) return;
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const name of PLATE_CAMERAS_DDL_ORDER) await runDdl(client, PLATE_CAMERAS_DDL[name]);
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
