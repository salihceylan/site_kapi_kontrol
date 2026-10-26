// Gider türü (R1, migration 056) şeması: tek kaynak. `migrations/056_expense_natures.sql` bu adımların SQL'inin birleşimidir (test: finance_expense_nature).
// Gider satırı DEĞİŞMEZ (trg_finance_immutable); "rutin / beklenmedik" işareti yan tabloda tutulur ve değiştirilebilir.
// Tablo FK'SIZ oluşturulur, her FK ayrı ve katalog korumalıdır (ifade başına tek sıcak üst tablo; açılış 40P01 dersi). Normal açılışta tek katalog sorgusu.
// Bu dosya db.js'i İÇE AKTARMAZ.

export const EXPENSE_NATURE_DDL = Object.freeze({
  table: `CREATE TABLE IF NOT EXISTS expense_natures (
  expense_id BIGINT PRIMARY KEY,
  site_code BIGINT NOT NULL,
  nature TEXT NOT NULL,
  source TEXT NOT NULL,
  set_by INTEGER,
  set_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_expense_natures_nature CHECK (nature IN ('routine', 'unexpected')),
  CONSTRAINT chk_expense_natures_source CHECK (source IN ('suggested', 'manual'))
);`,
  fk_expense: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expense_natures_expense_id_fkey' AND conrelid = 'expense_natures'::regclass
  ) THEN
    ALTER TABLE expense_natures ADD CONSTRAINT expense_natures_expense_id_fkey FOREIGN KEY (expense_id) REFERENCES expenses(id) ON DELETE CASCADE;
  END IF;
END $$;`,
  fk_site: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expense_natures_site_code_fkey' AND conrelid = 'expense_natures'::regclass
  ) THEN
    ALTER TABLE expense_natures ADD CONSTRAINT expense_natures_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;`,
  fk_user: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expense_natures_set_by_fkey' AND conrelid = 'expense_natures'::regclass
  ) THEN
    ALTER TABLE expense_natures ADD CONSTRAINT expense_natures_set_by_fkey FOREIGN KEY (set_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;`,
  idx_site: `CREATE INDEX IF NOT EXISTS idx_expense_natures_site ON expense_natures (site_code, nature);`,
  idx_user: `CREATE INDEX IF NOT EXISTS idx_expense_natures_set_by ON expense_natures (set_by) WHERE set_by IS NOT NULL;`,
});

export const EXPENSE_NATURE_DDL_ORDER = Object.freeze(['table', 'fk_expense', 'fk_site', 'fk_user', 'idx_site', 'idx_user']);

/** Migration dosyasının gövdesi (DDL'lerin birleşimi). */
export const expenseNatureMigrationBody = () => EXPENSE_NATURE_DDL_ORDER.map((name) => EXPENSE_NATURE_DDL[name]).join('\n\n');

/** Eksik nesneler varsa sırayla uygular; hepsi varsa tek katalog sorgusundan sonra hiçbir ifade göndermez. */
export async function ensureExpenseNaturesSchema(client) {
  const found = await client.query(
    `SELECT to_regclass('public.expense_natures') IS NOT NULL AS has_table, to_regclass('public.expenses') IS NOT NULL AS has_expenses,
       ARRAY(SELECT conname::TEXT FROM pg_constraint WHERE contype = 'f' AND conrelid = to_regclass('public.expense_natures')) AS fks,
       ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'expense_natures') AS indexes`,
  );
  const row = found.rows[0] ?? {};
  const fks = new Set(row.fks ?? []);
  const indexes = new Set(row.indexes ?? []);
  const done = {
    table: row.has_table === true,
    fk_expense: fks.has('expense_natures_expense_id_fkey'),
    fk_site: fks.has('expense_natures_site_code_fkey'),
    fk_user: fks.has('expense_natures_set_by_fkey'),
    idx_site: indexes.has('idx_expense_natures_site'),
    idx_user: indexes.has('idx_expense_natures_set_by'),
  };
  // Üst tablo `expenses` yoksa (platform öncesi kesilmiş şema: finans 040 tabloları henüz yok) yabancı anahtar ertelenir; sonraki açılışta tamamlanır.
  const blocked = (name) => name === 'fk_expense' && row.has_expenses === false;
  if (EXPENSE_NATURE_DDL_ORDER.every((name) => done[name] || blocked(name))) {
    return;
  }
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const name of EXPENSE_NATURE_DDL_ORDER) {
      if (done[name] || blocked(name)) continue;
      for (let attempt = 1; ; attempt += 1) {
        try {
          await client.query(EXPENSE_NATURE_DDL[name]);
          break;
        } catch (error) {
          if ((error?.code !== '40P01' && error?.code !== '55P03') || attempt >= 6) throw error;
          await new Promise((resolve) => setTimeout(resolve, 300 * attempt));
        }
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
