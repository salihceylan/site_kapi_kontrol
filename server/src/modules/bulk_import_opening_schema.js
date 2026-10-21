// 055 (devir bakiyesi + hepsi bir arada): migrations/055_opening_balances.sql ile AYNI, ekleyici ve idempotent. db.js ensureDbSchema bloğu BİTTİKTEN sonra,
// 038 ve 052'den sonra çağrılır. Normal açılışta tek katalog sorgusu; yalnız eksik adımlar çalışır.

import { runDdl } from './bulk_import_schema.js';

const fk = (name, column, target, onDelete) => `
  DO $$
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = 'finance_opening_reverts'::regclass) THEN
      ALTER TABLE finance_opening_reverts ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${target} ON DELETE ${onDelete};
    END IF;
  END $$
`;

export const OPENING_DDL = Object.freeze({
  kindFmt: `
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_bulk_import_runs_kind_fmt' AND conrelid = 'bulk_import_runs'::regclass) THEN
        ALTER TABLE bulk_import_runs ADD CONSTRAINT chk_bulk_import_runs_kind_fmt CHECK (kind ~ '^[a-z][a-z_]{2,39}$') NOT VALID;
      END IF;
    END $$
  `,
  kindFmtValidate: `ALTER TABLE bulk_import_runs VALIDATE CONSTRAINT chk_bulk_import_runs_kind_fmt`,
  dropOldKind: `ALTER TABLE bulk_import_runs DROP CONSTRAINT IF EXISTS chk_bulk_import_runs_kind`,
  table: `
    CREATE TABLE IF NOT EXISTS finance_opening_reverts (
      run_id BIGINT PRIMARY KEY,
      site_code BIGINT NOT NULL,
      reversed_count INTEGER NOT NULL,
      reversed_total_minor BIGINT NOT NULL,
      idempotency_key TEXT NOT NULL,
      reverted_by INTEGER,
      reverted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_finance_opening_reverts_key CHECK (char_length(idempotency_key) BETWEEN 8 AND 64),
      CONSTRAINT chk_finance_opening_reverts_amounts CHECK (reversed_count >= 0 AND reversed_total_minor >= 0)
    )
  `,
  runFk: fk('fk_finance_opening_reverts_run', 'run_id', 'bulk_import_runs(id)', 'CASCADE'),
  siteFk: fk('fk_finance_opening_reverts_site', 'site_code', 'sites(site_code)', 'CASCADE'),
  userFk: fk('fk_finance_opening_reverts_user', 'reverted_by', 'users(user_code)', 'SET NULL'),
  keyIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_opening_reverts_key ON finance_opening_reverts (site_code, idempotency_key)`,
  userIndex: `CREATE INDEX IF NOT EXISTS idx_finance_opening_reverts_user ON finance_opening_reverts (reverted_by) WHERE reverted_by IS NOT NULL`,
});

export async function ensureBulkOpeningSchema(client) {
  const found = await client.query(`
    SELECT
      EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_bulk_import_runs_kind_fmt' AND conrelid = to_regclass('public.bulk_import_runs') AND convalidated) AS fmt_valid,
      EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_bulk_import_runs_kind' AND conrelid = to_regclass('public.bulk_import_runs')) AS old_kind,
      to_regclass('public.finance_opening_reverts') IS NOT NULL AS has_table,
      EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_finance_opening_reverts_run' AND conrelid = to_regclass('public.finance_opening_reverts')) AS has_run_fk,
      EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_finance_opening_reverts_site' AND conrelid = to_regclass('public.finance_opening_reverts')) AS has_site_fk,
      EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_finance_opening_reverts_user' AND conrelid = to_regclass('public.finance_opening_reverts')) AS has_user_fk,
      EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'uq_finance_opening_reverts_key') AS has_key_index,
      EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_finance_opening_reverts_user') AS has_user_index
  `);
  const state = found.rows[0] ?? {};
  if (state.fmt_valid !== true) {
    await runDdl(client, OPENING_DDL.kindFmt);
    await runDdl(client, OPENING_DDL.kindFmtValidate);
  }
  if (state.old_kind === true) await runDdl(client, OPENING_DDL.dropOldKind);
  if (state.has_table !== true) await runDdl(client, OPENING_DDL.table);
  if (state.has_run_fk !== true) await runDdl(client, OPENING_DDL.runFk);
  if (state.has_site_fk !== true) await runDdl(client, OPENING_DDL.siteFk);
  if (state.has_user_fk !== true) await runDdl(client, OPENING_DDL.userFk);
  if (state.has_key_index !== true) await runDdl(client, OPENING_DDL.keyIndex);
  if (state.has_user_index !== true) await runDdl(client, OPENING_DDL.userIndex);
}
