// Plaka Tanıma (modül `plate_recognition`) şeması: 073. migrations/073_plate_recognition.sql ile AYNI ifadeler, AYNI sırada.
// Tamamen ekleyici ve idempotent (IF NOT EXISTS); 6B tablolarına (camera_devices, plate_events) DOKUNMAZ, onlara FK koymaz.
// Tablolar FK'SIZ oluşturulur; sites FK'si yalnız tablo bu çağrıda oluşturulduysa ayrı ALTER ile eklenir (açılış deadlock dersi:
// bkz. card_access_schema.js / device_integrations_schema.js). Bu dosya db.js'i İÇE AKTARMAZ.

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

/** Sıra BAĞLAYICIDIR (migration ile aynı). */
export const PLATE_RECOGNITION_DDL = Object.freeze({
  permitTable: `
    CREATE TABLE IF NOT EXISTS plate_guest_permits (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      apartment_id BIGINT NOT NULL,
      plate TEXT NOT NULL,
      valid_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      valid_until TIMESTAMPTZ NOT NULL,
      note TEXT,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      revoked_at TIMESTAMPTZ,
      revoked_by INTEGER,
      CONSTRAINT chk_plate_guest_permits_plate CHECK (plate ~ '^[A-Z0-9]{5,10}$'),
      CONSTRAINT chk_plate_guest_permits_span CHECK (valid_until > valid_from AND valid_until <= valid_from + INTERVAL '30 days'),
      CONSTRAINT chk_plate_guest_permits_note CHECK (note IS NULL OR char_length(note) <= 120)
    )
  `,
  permitSiteFk: siteFk('plate_guest_permits'),
  permitSiteIndex: `CREATE INDEX IF NOT EXISTS idx_plate_guest_permits_site ON plate_guest_permits (site_code, id DESC)`,
  permitPlateIndex: `CREATE INDEX IF NOT EXISTS idx_plate_guest_permits_plate ON plate_guest_permits (site_code, plate) WHERE revoked_at IS NULL`,
  permitCreatorIndex: `CREATE INDEX IF NOT EXISTS idx_plate_guest_permits_creator ON plate_guest_permits (created_by, created_at DESC)`,
  blacklistTable: `
    CREATE TABLE IF NOT EXISTS plate_blacklist (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      plate TEXT NOT NULL,
      reason TEXT,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      removed_at TIMESTAMPTZ,
      removed_by INTEGER,
      CONSTRAINT chk_plate_blacklist_plate CHECK (plate ~ '^[A-Z0-9]{5,10}$'),
      CONSTRAINT chk_plate_blacklist_reason CHECK (reason IS NULL OR char_length(reason) <= 200)
    )
  `,
  blacklistSiteFk: siteFk('plate_blacklist'),
  blacklistActiveIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_plate_blacklist_active ON plate_blacklist (site_code, plate) WHERE removed_at IS NULL`,
  settingsTable: `
    CREATE TABLE IF NOT EXISTS plate_gate_settings (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      door_id BIGINT NOT NULL,
      device_id BIGINT,
      auto_open BOOLEAN NOT NULL DEFAULT FALSE,
      min_confidence NUMERIC(4, 3) NOT NULL DEFAULT 0.85,
      cooldown_seconds INTEGER NOT NULL DEFAULT 30,
      updated_by INTEGER,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_plate_gate_settings_confidence CHECK (min_confidence BETWEEN 0.5 AND 0.999),
      CONSTRAINT chk_plate_gate_settings_cooldown CHECK (cooldown_seconds BETWEEN 5 AND 600),
      CONSTRAINT uq_plate_gate_settings_door UNIQUE (site_code, door_id)
    )
  `,
  settingsSiteFk: siteFk('plate_gate_settings'),
  settingsDeviceIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_plate_gate_settings_device ON plate_gate_settings (site_code, device_id) WHERE device_id IS NOT NULL`,
  decisionTable: `
    CREATE TABLE IF NOT EXISTS plate_decisions (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      event_id BIGINT NOT NULL,
      device_id BIGINT NOT NULL,
      door_id BIGINT,
      plate TEXT NOT NULL,
      confidence NUMERIC(5, 4),
      decision TEXT NOT NULL,
      reason TEXT NOT NULL,
      vehicle_id BIGINT,
      permit_id BIGINT,
      auto_action TEXT NOT NULL DEFAULT 'none',
      decided_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_plate_decisions_plate CHECK (plate ~ '^[A-Z0-9]{5,10}$'),
      CONSTRAINT chk_plate_decisions_decision CHECK (decision IN ('ALLOWED', 'DENIED', 'UNKNOWN')),
      CONSTRAINT chk_plate_decisions_action CHECK (auto_action IN ('none', 'would_open', 'suppressed_cooldown', 'suppressed_rate')),
      CONSTRAINT uq_plate_decisions_event UNIQUE (event_id)
    )
  `,
  decisionSiteFk: siteFk('plate_decisions'),
  decisionSiteIndex: `CREATE INDEX IF NOT EXISTS idx_plate_decisions_site ON plate_decisions (site_code, id DESC)`,
  decisionOpenIndex: `CREATE INDEX IF NOT EXISTS idx_plate_decisions_open ON plate_decisions (door_id, decided_at DESC) WHERE auto_action = 'would_open'`,
});

const STEPS = Object.freeze([
  ['permitTable', { table: 'plate_guest_permits' }],
  ['permitSiteFk', { fkOf: 'plate_guest_permits' }],
  ['permitSiteIndex', { index: 'idx_plate_guest_permits_site' }],
  ['permitPlateIndex', { index: 'idx_plate_guest_permits_plate' }],
  ['permitCreatorIndex', { index: 'idx_plate_guest_permits_creator' }],
  ['blacklistTable', { table: 'plate_blacklist' }],
  ['blacklistSiteFk', { fkOf: 'plate_blacklist' }],
  ['blacklistActiveIndex', { index: 'uq_plate_blacklist_active' }],
  ['settingsTable', { table: 'plate_gate_settings' }],
  ['settingsSiteFk', { fkOf: 'plate_gate_settings' }],
  ['settingsDeviceIndex', { index: 'uq_plate_gate_settings_device' }],
  ['decisionTable', { table: 'plate_decisions' }],
  ['decisionSiteFk', { fkOf: 'plate_decisions' }],
  ['decisionSiteIndex', { index: 'idx_plate_decisions_site' }],
  ['decisionOpenIndex', { index: 'idx_plate_decisions_open' }],
]);

export const PLATE_RECOGNITION_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

/** Eksik nesneleri sırayla, her biri kendi otomatik onaylı ifadesiyle oluşturur; her şey varsa yalnız 1 okuma sorgusu gider. */
export async function ensurePlateRecognitionSchema(client) {
  const tables = STEPS.filter(([, s]) => s.table).map(([, s]) => s.table);
  const indexes = STEPS.filter(([, s]) => s.index).map(([, s]) => s.index);
  const found = await client.query(
    `SELECT
       ARRAY(SELECT t FROM unnest($1::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
       ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($2::TEXT[])) AS indexes`,
    [tables, indexes],
  );
  const hadTables = new Set(found.rows[0]?.tables ?? []);
  const hadIndexes = new Set(found.rows[0]?.indexes ?? []);
  if (tables.every((t) => hadTables.has(t)) && indexes.every((i) => hadIndexes.has(i))) return;
  await client.query("SET lock_timeout = '2s'");
  try {
    const created = new Set();
    for (const [name, spec] of STEPS) {
      if (spec.table) {
        if (hadTables.has(spec.table)) continue;
        await client.query(PLATE_RECOGNITION_DDL[name]);
        created.add(spec.table);
      } else if (spec.fkOf) {
        if (created.has(spec.fkOf)) await client.query(PLATE_RECOGNITION_DDL[name]);
      } else if (!hadIndexes.has(spec.index)) {
        await client.query(PLATE_RECOGNITION_DDL[name]);
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
