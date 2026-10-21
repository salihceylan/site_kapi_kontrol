// Ekipman, bakim ve teklif sema (068): tek kaynak. migrations/068_equipment.sql bu adimlarin birlesimidir (test: equipment_schema).
// Tablolar FK'SIZ olusturulur, her FK ayri ve katalog korumalidir (ifade basina tek ust tablo; acilis 40P01 dersi). Tamamen ekleyici ve idempotent.
// Silme: site silinince hepsi CASCADE; ekipman silinirse plan/kayit/baglanti CASCADE (API'de silme yok, pasife alinir); kullanici silinince created_by SET NULL.
// Bu dosya db.js'i ICE AKTARMAZ.

function fk(table, column, parent, parentColumn, onDelete) {
  const name = `${table}_${column}_fkey`;
  return {
    name,
    table,
    sql: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass
  ) THEN
    ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE ${onDelete};
  END IF;
END $$;`,
  };
}

const T = {
  equipment_items: `CREATE TABLE IF NOT EXISTS equipment_items (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  kind TEXT NOT NULL,
  name TEXT NOT NULL,
  location TEXT,
  vendor_id BIGINT,
  serial_no TEXT,
  installed_on DATE,
  note TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_equipment_items_kind CHECK (char_length(kind) BETWEEN 1 AND 40),
  CONSTRAINT chk_equipment_items_name CHECK (char_length(name) BETWEEN 1 AND 120),
  CONSTRAINT chk_equipment_items_location CHECK (location IS NULL OR char_length(location) BETWEEN 1 AND 120),
  CONSTRAINT chk_equipment_items_serial CHECK (serial_no IS NULL OR char_length(serial_no) BETWEEN 1 AND 60),
  CONSTRAINT chk_equipment_items_note CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 1000)
);`,
  equipment_plans: `CREATE TABLE IF NOT EXISTS equipment_plans (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  equipment_id BIGINT NOT NULL,
  title TEXT NOT NULL,
  interval_months INTEGER NOT NULL,
  legal BOOLEAN NOT NULL DEFAULT FALSE,
  next_due DATE NOT NULL,
  last_done DATE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_equipment_plans_title CHECK (char_length(title) BETWEEN 1 AND 120),
  CONSTRAINT chk_equipment_plans_interval CHECK (interval_months IN (1, 3, 6, 12))
);`,
  equipment_maintenance_logs: `CREATE TABLE IF NOT EXISTS equipment_maintenance_logs (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  equipment_id BIGINT NOT NULL,
  plan_id BIGINT,
  done_on DATE NOT NULL,
  vendor_name TEXT,
  cost_kurus BIGINT,
  expense_id BIGINT,
  note TEXT,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_equipment_logs_vendor CHECK (vendor_name IS NULL OR char_length(vendor_name) BETWEEN 1 AND 120),
  CONSTRAINT chk_equipment_logs_cost CHECK (cost_kurus IS NULL OR cost_kurus BETWEEN 0 AND 1000000000000),
  CONSTRAINT chk_equipment_logs_note CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 1000)
);`,
  equipment_expense_links: `CREATE TABLE IF NOT EXISTS equipment_expense_links (
  expense_id BIGINT PRIMARY KEY,
  site_code BIGINT NOT NULL,
  equipment_id BIGINT NOT NULL,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);`,
  equipment_quotes: `CREATE TABLE IF NOT EXISTS equipment_quotes (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  topic TEXT NOT NULL,
  vendor_name TEXT NOT NULL,
  amount_kurus BIGINT NOT NULL,
  valid_until DATE,
  document_note TEXT,
  equipment_id BIGINT,
  status TEXT NOT NULL DEFAULT 'open',
  accepted_as TEXT,
  expense_id BIGINT,
  contract_id BIGINT,
  decided_at TIMESTAMPTZ,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_equipment_quotes_topic CHECK (char_length(topic) BETWEEN 1 AND 160),
  CONSTRAINT chk_equipment_quotes_vendor CHECK (char_length(vendor_name) BETWEEN 1 AND 120),
  CONSTRAINT chk_equipment_quotes_amount CHECK (amount_kurus BETWEEN 1 AND 1000000000000),
  CONSTRAINT chk_equipment_quotes_doc CHECK (document_note IS NULL OR char_length(document_note) BETWEEN 1 AND 300),
  CONSTRAINT chk_equipment_quotes_status CHECK (status IN ('open', 'accepted', 'rejected')),
  CONSTRAINT chk_equipment_quotes_accepted_as CHECK (accepted_as IS NULL OR accepted_as IN ('expense', 'contract'))
);`,
};

const FKS = [
  fk('equipment_items', 'site_code', 'sites', 'site_code', 'CASCADE'),
  fk('equipment_items', 'created_by', 'users', 'user_code', 'SET NULL'),
  fk('equipment_plans', 'site_code', 'sites', 'site_code', 'CASCADE'),
  fk('equipment_plans', 'equipment_id', 'equipment_items', 'id', 'CASCADE'),
  fk('equipment_maintenance_logs', 'site_code', 'sites', 'site_code', 'CASCADE'),
  fk('equipment_maintenance_logs', 'equipment_id', 'equipment_items', 'id', 'CASCADE'),
  fk('equipment_maintenance_logs', 'created_by', 'users', 'user_code', 'SET NULL'),
  fk('equipment_expense_links', 'site_code', 'sites', 'site_code', 'CASCADE'),
  fk('equipment_expense_links', 'equipment_id', 'equipment_items', 'id', 'CASCADE'),
  fk('equipment_expense_links', 'expense_id', 'expenses', 'id', 'CASCADE'),
  fk('equipment_quotes', 'site_code', 'sites', 'site_code', 'CASCADE'),
  fk('equipment_quotes', 'created_by', 'users', 'user_code', 'SET NULL'),
];

const INDEXES = [
  ['idx_equipment_items_site', 'equipment_items', 'CREATE INDEX IF NOT EXISTS idx_equipment_items_site ON equipment_items (site_code, is_active, id DESC);'],
  ['idx_equipment_plans_due', 'equipment_plans', 'CREATE INDEX IF NOT EXISTS idx_equipment_plans_due ON equipment_plans (site_code, next_due) WHERE is_active;'],
  ['idx_equipment_plans_equipment', 'equipment_plans', 'CREATE INDEX IF NOT EXISTS idx_equipment_plans_equipment ON equipment_plans (equipment_id);'],
  ['idx_equipment_logs_equipment', 'equipment_maintenance_logs', 'CREATE INDEX IF NOT EXISTS idx_equipment_logs_equipment ON equipment_maintenance_logs (equipment_id, done_on DESC);'],
  ['idx_equipment_links_equipment', 'equipment_expense_links', 'CREATE INDEX IF NOT EXISTS idx_equipment_links_equipment ON equipment_expense_links (site_code, equipment_id);'],
  ['idx_equipment_quotes_topic', 'equipment_quotes', 'CREATE INDEX IF NOT EXISTS idx_equipment_quotes_topic ON equipment_quotes (site_code, lower(topic), status);'],
];

/** Sira BAGLAYICIDIR (migration ile ayni): once tablolar, sonra FK'ler, sonra indeksler. */
export const EQUIPMENT_STEPS = Object.freeze([
  ...Object.entries(T).map(([table, sql]) => ({ kind: 'table', name: table, table, sql })),
  ...FKS.map((f) => ({ kind: 'fk', name: f.name, table: f.table, sql: f.sql })),
  ...INDEXES.map(([name, table, sql]) => ({ kind: 'index', name, table, sql })),
]);

/** Migration dosyasinin govdesi (adimlarin birlesimi). */
export const equipmentMigrationBody = () => `${EQUIPMENT_STEPS.map((s) => s.sql).join('\n\n')}\n`;

export const schemaTuning = { retryDelayMs: 300 };

/** Eksik nesneler varsa sirayla uygular; hepsi varsa tek katalog sorgusundan sonra hicbir ifade gondermez. */
export async function ensureEquipmentSchema(client) {
  const tables = EQUIPMENT_STEPS.filter((s) => s.kind === 'table').map((s) => s.name);
  const fks = EQUIPMENT_STEPS.filter((s) => s.kind === 'fk').map((s) => s.name);
  const idx = EQUIPMENT_STEPS.filter((s) => s.kind === 'index').map((s) => s.name);
  const found = await client.query(
    `SELECT ARRAY(SELECT t FROM unnest($1::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
       ARRAY(SELECT conname::TEXT FROM pg_constraint WHERE contype = 'f' AND connamespace = 'public'::regnamespace AND conname = ANY($2::TEXT[])) AS fks,
       ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($3::TEXT[])) AS indexes`,
    [tables, fks, idx],
  );
  const row = found.rows[0] ?? {};
  const present = new Set([...(row.tables ?? []), ...(row.fks ?? []), ...(row.indexes ?? [])]);
  const pending = EQUIPMENT_STEPS.filter((s) => !present.has(s.name));
  if (pending.length === 0) {
    return;
  }
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const step of pending) {
      for (let attempt = 1; ; attempt += 1) {
        try {
          await client.query(step.sql);
          break;
        } catch (error) {
          if ((error?.code !== '40P01' && error?.code !== '55P03') || attempt >= 6) throw error;
          await new Promise((resolve) => setTimeout(resolve, schemaTuning.retryDelayMs * attempt));
        }
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
