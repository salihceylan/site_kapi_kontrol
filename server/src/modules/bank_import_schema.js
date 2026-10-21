// Banka dosyası şeması (067; Dalga 2 / 2C). migrations/067_bank_imports.sql ile AYNI ifadeler (test: bank_import_schema; dosya bu listeden üretilir).
// Ekleyici ve idempotent. Dış tablolara (sites, finance_accounts, apartments) FK'ler 40P01 dersi gereği AYRI ve katalog korumalı ifadelerdir.
// Bu dosya db.js'i İÇE AKTARMAZ.

const fk = (table, column, parent, parentColumn, onDelete) => {
  const name = `${table}_${column}_fkey`;
  return `DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass) THEN ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE ${onDelete}; END IF; END $$`;
};

export const BANK_IMPORT_STATEMENTS = Object.freeze([
  `CREATE TABLE IF NOT EXISTS bank_import_profiles (
  account_id BIGINT PRIMARY KEY,
  site_code BIGINT NOT NULL,
  format TEXT NOT NULL,
  header_signature TEXT NOT NULL,
  mapping JSONB NOT NULL DEFAULT '{}'::JSONB,
  options JSONB NOT NULL DEFAULT '{}'::JSONB,
  profile_version INTEGER NOT NULL DEFAULT 1,
  updated_by INTEGER,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_bank_import_profiles_format CHECK (format IN ('xlsx', 'csv'))
)`,
  `CREATE TABLE IF NOT EXISTS bank_imports (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  account_id BIGINT NOT NULL,
  format TEXT NOT NULL,
  file_name TEXT NOT NULL,
  file_size INTEGER NOT NULL DEFAULT 0,
  file_sha256 TEXT NOT NULL,
  statement_from DATE,
  statement_to DATE,
  file_account_iban TEXT,
  line_count INTEGER NOT NULL DEFAULT 0,
  duplicate_count INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active',
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reverted_by INTEGER,
  reverted_at TIMESTAMPTZ,
  revert_reason TEXT,
  CONSTRAINT chk_bank_imports_format CHECK (format IN ('xlsx', 'csv', 'mt940')),
  CONSTRAINT chk_bank_imports_status CHECK (status IN ('active', 'reverted')),
  CONSTRAINT chk_bank_imports_sha CHECK (file_sha256 ~ '^[0-9a-f]{64}$')
)`,
  `CREATE UNIQUE INDEX IF NOT EXISTS uq_bank_imports_key ON bank_imports (site_code, idempotency_key)`,
  `CREATE UNIQUE INDEX IF NOT EXISTS uq_bank_imports_file ON bank_imports (account_id, file_sha256) WHERE status = 'active'`,
  `CREATE INDEX IF NOT EXISTS idx_bank_imports_site ON bank_imports (site_code, created_at DESC)`,
  `CREATE TABLE IF NOT EXISTS bank_statement_lines (
  id BIGSERIAL PRIMARY KEY,
  import_id BIGINT NOT NULL REFERENCES bank_imports(id) ON DELETE CASCADE,
  site_code BIGINT NOT NULL,
  account_id BIGINT NOT NULL,
  line_no INTEGER NOT NULL,
  value_date DATE NOT NULL,
  amount_minor BIGINT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  counterparty_name TEXT,
  counterparty_iban TEXT,
  bank_reference TEXT,
  balance_after_minor BIGINT,
  fingerprint TEXT NOT NULL,
  status TEXT NOT NULL,
  match_method TEXT,
  suggested_apartment_id BIGINT,
  suggested_party TEXT,
  ledger_entry_id BIGINT,
  expense_id BIGINT,
  movement_id BIGINT,
  transfer_id BIGINT,
  classification TEXT,
  note TEXT,
  decided_by INTEGER,
  decided_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_bank_lines_amount CHECK (amount_minor <> 0),
  CONSTRAINT chk_bank_lines_status CHECK (status IN ('unmatched', 'suggested', 'posted', 'linked', 'classified', 'ignored', 'reverted')),
  CONSTRAINT chk_bank_lines_party CHECK (suggested_party IS NULL OR suggested_party IN ('owner', 'tenant'))
)`,
  `CREATE INDEX IF NOT EXISTS idx_bank_lines_site_status ON bank_statement_lines (site_code, status)`,
  `CREATE INDEX IF NOT EXISTS idx_bank_lines_import ON bank_statement_lines (import_id, line_no)`,
  `CREATE UNIQUE INDEX IF NOT EXISTS uq_bank_lines_fingerprint ON bank_statement_lines (account_id, fingerprint) WHERE status <> 'reverted'`,
  `CREATE UNIQUE INDEX IF NOT EXISTS uq_bank_lines_ledger ON bank_statement_lines (ledger_entry_id) WHERE status IN ('posted', 'linked') AND ledger_entry_id IS NOT NULL`,
  `CREATE TABLE IF NOT EXISTS bank_payer_ibans (
  site_code BIGINT NOT NULL,
  iban TEXT NOT NULL,
  apartment_id BIGINT NOT NULL,
  account_party TEXT,
  created_import_id BIGINT,
  use_count INTEGER NOT NULL DEFAULT 0,
  last_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (site_code, iban, apartment_id),
  CONSTRAINT chk_bank_payer_ibans_party CHECK (account_party IS NULL OR account_party IN ('owner', 'tenant'))
)`,
  fk('bank_import_profiles', 'account_id', 'finance_accounts', 'id', 'CASCADE'),
  fk('bank_imports', 'account_id', 'finance_accounts', 'id', 'RESTRICT'),
  fk('bank_imports', 'site_code', 'sites', 'site_code', 'CASCADE'),
  fk('bank_payer_ibans', 'apartment_id', 'apartments', 'id', 'CASCADE'),
  fk('bank_payer_ibans', 'site_code', 'sites', 'site_code', 'CASCADE'),
]);

/** db.js: her ifade kendi otomatik onayında; tablolar varsa DDL tekrar çalışır (IF NOT EXISTS) ama FK blokları katalogla korunur. */
export async function ensureBankImportSchema(client) {
  for (const sql of BANK_IMPORT_STATEMENTS) {
    await client.query(sql);
  }
}
