// İşletme projesi (bütçe) şeması: 059. migrations/059_budget_projects.sql ile AYNI ifadeler, AYNI sırayla (test: budget_common).
//
// İki yeni tablo (ekleyici): budget_projects, budget_items. Mevcut tablolara dokunulmaz. Tablolar FK'SIZ oluşturulur; her FK ayrı, katalog korumalı
// ALTER TABLE'dır (sites / users sıcaktır; açılış deadlock'u dersi, bkz. contracts_schema.js). Ensure: tek katalog sorgusu; her şey varsa hiçbir ifade gönderilmez.
// Silme politikası: site silinince projeler ve kalemler CASCADE; kullanıcı silinince created_by / finalized_by SET NULL; kullanımdaki gider kategorisi RESTRICT.
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

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

/** Sıra BAĞLAYICIDIR (migration ile aynı). */
export const BUDGET_DDL = Object.freeze({
  projectsTable: `
    CREATE TABLE IF NOT EXISTS budget_projects (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      year INTEGER NOT NULL,
      title TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'taslak',
      is_provisional BOOLEAN NOT NULL DEFAULT FALSE,
      provisional_start DATE,
      provisional_until DATE,
      notified_at DATE,
      objection_days INTEGER,
      objection_ends DATE,
      finalized_at TIMESTAMPTZ,
      finalized_by INTEGER,
      note TEXT,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT uq_budget_projects_site_id UNIQUE (site_code, id),
      CONSTRAINT chk_budget_projects_year CHECK (year BETWEEN 2000 AND 2100),
      CONSTRAINT chk_budget_projects_title CHECK (char_length(title) BETWEEN 1 AND 160),
      CONSTRAINT chk_budget_projects_status CHECK (status IN ('taslak', 'teblig', 'kesin')),
      CONSTRAINT chk_budget_projects_provisional CHECK (
        (is_provisional AND provisional_start IS NOT NULL AND provisional_until IS NOT NULL AND provisional_until >= provisional_start)
        OR (NOT is_provisional AND provisional_start IS NULL AND provisional_until IS NULL)
      ),
      CONSTRAINT chk_budget_projects_notified CHECK ((status = 'taslak') = (notified_at IS NULL)),
      CONSTRAINT chk_budget_projects_finalized CHECK ((status = 'kesin') = (finalized_at IS NOT NULL)),
      CONSTRAINT chk_budget_projects_note CHECK (note IS NULL OR char_length(note) BETWEEN 1 AND 1000)
    )
  `,
  projectsSiteFk: foreignKeySql('budget_projects', 'site_code', 'sites', 'site_code', 'CASCADE'),
  projectsCreatedByFk: foreignKeySql('budget_projects', 'created_by', 'users', 'user_code', 'SET NULL'),
  projectsFinalizedByFk: foreignKeySql('budget_projects', 'finalized_by', 'users', 'user_code', 'SET NULL'),
  projectsSiteYearIndex: `CREATE INDEX IF NOT EXISTS idx_budget_projects_site_year ON budget_projects (site_code, year)`,
  projectsFinalUniqueIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_budget_projects_final ON budget_projects (site_code, year) WHERE status = 'kesin'`,
  itemsTable: `
    CREATE TABLE IF NOT EXISTS budget_items (
      id BIGSERIAL PRIMARY KEY,
      project_id BIGINT NOT NULL,
      site_code BIGINT NOT NULL,
      category_id BIGINT NOT NULL,
      category_name TEXT NOT NULL,
      annual_minor BIGINT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT uq_budget_items_category UNIQUE (project_id, category_id),
      CONSTRAINT chk_budget_items_amount CHECK (annual_minor BETWEEN 0 AND 1000000000000)
    )
  `,
  itemsProjectFk: foreignKeySql('budget_items', 'project_id', 'budget_projects', 'id', 'CASCADE'),
  itemsSiteFk: foreignKeySql('budget_items', 'site_code', 'sites', 'site_code', 'CASCADE'),
  itemsCategoryFk: foreignKeySql('budget_items', 'category_id', 'expense_categories', 'id', 'RESTRICT'),
});

export const BUDGET_DDL_ORDER = Object.freeze(Object.keys(BUDGET_DDL));

const TABLES = ['budget_projects', 'budget_items'];
const FKS = [
  'budget_projects_site_code_fkey',
  'budget_projects_created_by_fkey',
  'budget_projects_finalized_by_fkey',
  'budget_items_project_id_fkey',
  'budget_items_site_code_fkey',
  'budget_items_category_id_fkey',
];
const INDEXES = ['idx_budget_projects_site_year', 'uq_budget_projects_final'];

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

/**
 * 059'u uygular (db.js ensureDbSchema bloğu BİTTİKTEN, 040'tan (expense_categories) SONRA çağrılır). Tüm ifadeler idempotenttir; eksik nesne yoksa hiçbir ifade gönderilmez.
 * Gider kategorileri tablosu (040) yoksa kalem FK'si atlanır; sonraki açılışta tamamlanır.
 */
export async function ensureBudgetSchema(client) {
  const found = await client.query(
    `
      SELECT
        ARRAY(SELECT t FROM unnest($1::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
        ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($2::TEXT[])) AS indexes,
        ARRAY(SELECT c.conname::TEXT FROM pg_constraint c WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace AND c.conname = ANY($3::TEXT[])) AS fks,
        to_regclass('public.expense_categories') IS NOT NULL AS has_categories
    `,
    [TABLES, INDEXES, FKS],
  );
  const row = found.rows[0] ?? {};
  const wantedFks = row.has_categories ? FKS.length : FKS.length - 1;
  const missing = (row.tables ?? []).length < TABLES.length || (row.indexes ?? []).length < INDEXES.length || (row.fks ?? []).length < wantedFks;
  if (!missing) {
    return;
  }
  for (const [name, sql] of Object.entries(BUDGET_DDL)) {
    if (name === 'itemsCategoryFk' && !row.has_categories) continue;
    await runDdl(client, sql);
  }
}
