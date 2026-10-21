// Sayac Okuma ve Faturalandirma semasi: 061. migrations/061_metering.sql ile AYNI ifadeler, AYNI sirayla (test: metering_schema).
//
// Dort yeni tablo (ekleyici): meters, meter_readings, meter_billings, meter_billing_lines. Mevcut tablolara sutun/indeks EKLENMEZ, defter (ledger_entries) semasina
// DOKUNULMAZ (borc kalemi mevcut sutunlarla yazilir; baglanti meter_billing_lines.ledger_entry_id ile, FK'siz).
// Acilis deadlock dersi (bkz. contracts_schema.js): ifadeler db.js'te dev blok BITTIKTEN sonra, katalog kontroluyle yalniz EKSIKLER icin, her biri kendi
// otomatik onayli ifadesiyle calisir. Tablolar FK'SIZ kurulur; her FK ayri, katalog korumali ALTER TABLE'dir. Bu dosya db.js'i ice aktarmaz.

function foreignKeySql(table, column, parent, parentColumn, onDelete) {
  const name = `${table}_${column}_fkey`;
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass
      ) THEN
        ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE ${onDelete};
      END IF;
    END $$
  `;
}

export const METERING_DDL = Object.freeze({
  metersTable: `
    CREATE TABLE IF NOT EXISTS meters (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      apartment_id BIGINT NOT NULL,
      kind TEXT NOT NULL,
      serial_no TEXT NOT NULL,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_meters_kind CHECK (kind IN ('water', 'electricity', 'heat', 'hot_water')),
      CONSTRAINT chk_meters_serial_length CHECK (char_length(serial_no) BETWEEN 1 AND 40)
    )
  `,
  metersSiteFk: foreignKeySql('meters', 'site_code', 'sites', 'site_code', 'CASCADE'),
  metersApartmentFk: foreignKeySql('meters', 'apartment_id', 'apartments', 'id', 'CASCADE'),
  metersCreatedByFk: foreignKeySql('meters', 'created_by', 'users', 'user_code', 'SET NULL'),
  metersSerialIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_meters_site_kind_serial ON meters (site_code, kind, lower(serial_no))`,
  metersApartmentIndex: `CREATE INDEX IF NOT EXISTS idx_meters_apartment ON meters (apartment_id)`,
  readingsTable: `
    CREATE TABLE IF NOT EXISTS meter_readings (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      meter_id BIGINT NOT NULL,
      reading_date DATE NOT NULL,
      value NUMERIC(14,3) NOT NULL,
      source TEXT NOT NULL DEFAULT 'manual',
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_meter_readings_value CHECK (value >= 0),
      CONSTRAINT chk_meter_readings_source CHECK (source IN ('manual', 'file'))
    )
  `,
  readingsSiteFk: foreignKeySql('meter_readings', 'site_code', 'sites', 'site_code', 'CASCADE'),
  readingsMeterFk: foreignKeySql('meter_readings', 'meter_id', 'meters', 'id', 'CASCADE'),
  readingsCreatedByFk: foreignKeySql('meter_readings', 'created_by', 'users', 'user_code', 'SET NULL'),
  readingsMeterDateIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_meter_readings_meter_date ON meter_readings (meter_id, reading_date)`,
  billingsTable: `
    CREATE TABLE IF NOT EXISTS meter_billings (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      kind TEXT NOT NULL,
      method TEXT NOT NULL,
      period_from DATE NOT NULL,
      period_to DATE NOT NULL,
      total_minor BIGINT NOT NULL,
      apartment_count INTEGER NOT NULL,
      params JSONB NOT NULL DEFAULT '{}'::JSONB,
      preview_hash TEXT NOT NULL,
      idempotency_key TEXT NOT NULL,
      request_fingerprint TEXT NOT NULL,
      posted_by INTEGER,
      posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_meter_billings_kind CHECK (kind IN ('water', 'electricity', 'heat', 'hot_water')),
      CONSTRAINT chk_meter_billings_method CHECK (method IN ('unit_price', 'invoice', 'heat')),
      CONSTRAINT chk_meter_billings_period CHECK (period_to > period_from),
      CONSTRAINT chk_meter_billings_total CHECK (total_minor > 0 AND apartment_count > 0)
    )
  `,
  billingsSiteFk: foreignKeySql('meter_billings', 'site_code', 'sites', 'site_code', 'CASCADE'),
  billingsPostedByFk: foreignKeySql('meter_billings', 'posted_by', 'users', 'user_code', 'SET NULL'),
  billingsKeyIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_meter_billings_key ON meter_billings (site_code, idempotency_key)`,
  billingsKindIndex: `CREATE INDEX IF NOT EXISTS idx_meter_billings_site_kind ON meter_billings (site_code, kind, period_to)`,
  linesTable: `
    CREATE TABLE IF NOT EXISTS meter_billing_lines (
      id BIGSERIAL PRIMARY KEY,
      billing_id BIGINT NOT NULL,
      site_code BIGINT NOT NULL,
      apartment_id BIGINT NOT NULL,
      consumption NUMERIC(14,3) NOT NULL,
      amount_minor BIGINT NOT NULL,
      account_party TEXT NOT NULL,
      ledger_entry_id BIGINT,
      CONSTRAINT chk_meter_billing_lines_amount CHECK (amount_minor > 0),
      CONSTRAINT chk_meter_billing_lines_account CHECK (account_party IN ('owner', 'tenant'))
    )
  `,
  linesBillingFk: foreignKeySql('meter_billing_lines', 'billing_id', 'meter_billings', 'id', 'CASCADE'),
  linesSiteFk: foreignKeySql('meter_billing_lines', 'site_code', 'sites', 'site_code', 'CASCADE'),
  linesBillingIndex: `CREATE INDEX IF NOT EXISTS idx_meter_billing_lines_billing ON meter_billing_lines (billing_id)`,
});

export const METERING_DDL_ORDER = Object.freeze(Object.keys(METERING_DDL));

/** Adim -> { tablo | indeks | fk }: ensure yalniz eksikleri calistirir. */
const STEPS = Object.freeze([
  ['metersTable', { table: 'meters' }],
  ['metersSiteFk', { fk: 'meters_site_code_fkey', on: 'meters', parent: 'sites' }],
  ['metersApartmentFk', { fk: 'meters_apartment_id_fkey', on: 'meters', parent: 'apartments' }],
  ['metersCreatedByFk', { fk: 'meters_created_by_fkey', on: 'meters', parent: 'users' }],
  ['metersSerialIndex', { index: 'uq_meters_site_kind_serial', on: 'meters' }],
  ['metersApartmentIndex', { index: 'idx_meters_apartment', on: 'meters' }],
  ['readingsTable', { table: 'meter_readings' }],
  ['readingsSiteFk', { fk: 'meter_readings_site_code_fkey', on: 'meter_readings', parent: 'sites' }],
  ['readingsMeterFk', { fk: 'meter_readings_meter_id_fkey', on: 'meter_readings', parent: 'meters' }],
  ['readingsCreatedByFk', { fk: 'meter_readings_created_by_fkey', on: 'meter_readings', parent: 'users' }],
  ['readingsMeterDateIndex', { index: 'uq_meter_readings_meter_date', on: 'meter_readings' }],
  ['billingsTable', { table: 'meter_billings' }],
  ['billingsSiteFk', { fk: 'meter_billings_site_code_fkey', on: 'meter_billings', parent: 'sites' }],
  ['billingsPostedByFk', { fk: 'meter_billings_posted_by_fkey', on: 'meter_billings', parent: 'users' }],
  ['billingsKeyIndex', { index: 'uq_meter_billings_key', on: 'meter_billings' }],
  ['billingsKindIndex', { index: 'idx_meter_billings_site_kind', on: 'meter_billings' }],
  ['linesTable', { table: 'meter_billing_lines' }],
  ['linesBillingFk', { fk: 'meter_billing_lines_billing_id_fkey', on: 'meter_billing_lines', parent: 'meter_billings' }],
  ['linesSiteFk', { fk: 'meter_billing_lines_site_code_fkey', on: 'meter_billing_lines', parent: 'sites' }],
  ['linesBillingIndex', { index: 'idx_meter_billing_lines_billing', on: 'meter_billing_lines' }],
]);

export const METERING_STEP_NAMES = Object.freeze(STEPS.map(([name]) => name));

const RETRYABLE = new Set(['40P01', '55P03']);
export const schemaTuning = { retryDelayMs: 300 };

async function runDdl(client, sql) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await client.query(sql);
      return;
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await new Promise((resolve) => setTimeout(resolve, schemaTuning.retryDelayMs * attempt));
    }
  }
}

/** 061'i uygular (db.js dev blok BITTIKTEN sonra). Tek katalog sorgusu; her sey varsa hicbir ifade gonderilmez. */
export async function ensureMeteringSchema(client) {
  const tables = STEPS.filter(([, s]) => s.table).map(([, s]) => s.table);
  const indexes = STEPS.filter(([, s]) => s.index).map(([, s]) => s.index);
  const fks = STEPS.filter(([, s]) => s.fk).map(([, s]) => s.fk);
  const found = await client.query(
    `
      SELECT
        ARRAY(SELECT t FROM unnest($1::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
        ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($2::TEXT[])) AS indexes,
        ARRAY(
          SELECT (SELECT r.relname::TEXT FROM pg_class r WHERE r.oid = c.conrelid) || '.' || c.conname::TEXT
          FROM pg_constraint c
          WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace AND c.conname = ANY($3::TEXT[])
        ) AS fks
    `,
    [tables, indexes, fks],
  );
  const presentTables = new Set(found.rows[0]?.tables ?? []);
  const presentIndexes = new Set(found.rows[0]?.indexes ?? []);
  const presentFks = new Set(found.rows[0]?.fks ?? []);
  const missing = (s) => (s.table ? !presentTables.has(s.table) : s.fk ? !presentFks.has(`${s.on}.${s.fk}`) : !presentIndexes.has(s.index));
  if (!STEPS.some(([, s]) => missing(s))) return;
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const [name, s] of STEPS) {
      if (!missing(s)) continue;
      if (!s.table && !presentTables.has(s.on)) continue;
      if (s.fk && !['sites', 'users', 'apartments'].includes(s.parent) && !presentTables.has(s.parent)) continue;
      await runDdl(client, METERING_DDL[name]);
      if (s.table) presentTables.add(s.table);
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
