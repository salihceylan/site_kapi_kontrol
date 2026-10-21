// Kart ödemesi sağlayıcı ayarları + kamera/plaka bağdaştırıcıları (F6 + T8) şeması: 065. migrations/065_device_integrations.sql ile AYNI ifadeler, AYNI sırada.
// Tamamen ekleyici ve idempotent. Tablolar FK'SIZ oluşturulur; sites FK'si yalnız tablo bu çağrıda oluşturulduysa ayrı, katalog korumalı ALTER ile eklenir
// (açılış deadlock dersi: bkz. card_access_schema.js). Bu dosya db.js'i İÇE AKTARMAZ.

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
export const DEVICE_INTEGRATIONS_DDL = Object.freeze({
  paymentTable: `
    CREATE TABLE IF NOT EXISTS payment_provider_settings (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      provider TEXT NOT NULL,
      commission_info TEXT,
      updated_by INTEGER,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_payment_provider_settings_provider CHECK (provider IN ('iyzico', 'paytr')),
      CONSTRAINT chk_payment_provider_settings_info CHECK (commission_info IS NULL OR char_length(commission_info) <= 300),
      CONSTRAINT uq_payment_provider_settings UNIQUE (site_code, provider)
    )
  `,
  paymentSiteFk: siteFk('payment_provider_settings'),
  cameraTable: `
    CREATE TABLE IF NOT EXISTS camera_devices (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      brand TEXT NOT NULL,
      name TEXT NOT NULL,
      host TEXT NOT NULL,
      port INTEGER,
      username TEXT,
      password_enc TEXT,
      token_hash TEXT NOT NULL,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      last_event_at TIMESTAMPTZ,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_camera_devices_brand CHECK (brand IN ('hikvision', 'tiandy', 'onvif')),
      CONSTRAINT chk_camera_devices_name CHECK (char_length(name) BETWEEN 1 AND 60),
      CONSTRAINT chk_camera_devices_host CHECK (char_length(host) BETWEEN 1 AND 120),
      CONSTRAINT chk_camera_devices_port CHECK (port IS NULL OR port BETWEEN 1 AND 65535)
    )
  `,
  cameraSiteFk: siteFk('camera_devices'),
  cameraSiteIndex: `CREATE INDEX IF NOT EXISTS idx_camera_devices_site ON camera_devices (site_code, id DESC)`,
  eventTable: `
    CREATE TABLE IF NOT EXISTS plate_events (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      device_id BIGINT NOT NULL,
      plate TEXT NOT NULL,
      matched BOOLEAN NOT NULL DEFAULT FALSE,
      vehicle_id BIGINT,
      seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_plate_events_plate CHECK (plate ~ '^[A-Z0-9]{5,10}$')
    )
  `,
  eventSiteFk: siteFk('plate_events'),
  eventSiteIndex: `CREATE INDEX IF NOT EXISTS idx_plate_events_site ON plate_events (site_code, id DESC)`,
});

const STEPS = Object.freeze([
  ['paymentTable', { table: 'payment_provider_settings' }],
  ['paymentSiteFk', { fkOf: 'payment_provider_settings' }],
  ['cameraTable', { table: 'camera_devices' }],
  ['cameraSiteFk', { fkOf: 'camera_devices' }],
  ['cameraSiteIndex', { index: 'idx_camera_devices_site', on: 'camera_devices' }],
  ['eventTable', { table: 'plate_events' }],
  ['eventSiteFk', { fkOf: 'plate_events' }],
  ['eventSiteIndex', { index: 'idx_plate_events_site', on: 'plate_events' }],
]);

export const DEVICE_INTEGRATIONS_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

/** Eksik nesneleri sırayla, her biri kendi otomatik onaylı ifadesiyle oluşturur; her şey varsa hiçbir ifade gönderilmez. */
export async function ensureDeviceIntegrationsSchema(client) {
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
        await client.query(DEVICE_INTEGRATIONS_DDL[name]);
        created.add(spec.table);
      } else if (spec.fkOf) {
        if (created.has(spec.fkOf)) await client.query(DEVICE_INTEGRATIONS_DDL[name]);
      } else if (!hadIndexes.has(spec.index)) {
        await client.query(DEVICE_INTEGRATIONS_DDL[name]);
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
