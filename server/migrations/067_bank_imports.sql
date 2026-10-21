-- 067: Banka dosyasi ice aktarma (Dalga 2 / 2C). src/modules/bank_import_schema.js ile AYNI ifadeler.
CREATE TABLE IF NOT EXISTS bank_import_profiles (
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
);

CREATE TABLE IF NOT EXISTS bank_imports (
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
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_bank_imports_key ON bank_imports (site_code, idempotency_key);

CREATE UNIQUE INDEX IF NOT EXISTS uq_bank_imports_file ON bank_imports (account_id, file_sha256) WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_bank_imports_site ON bank_imports (site_code, created_at DESC);

CREATE TABLE IF NOT EXISTS bank_statement_lines (
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
);

CREATE INDEX IF NOT EXISTS idx_bank_lines_site_status ON bank_statement_lines (site_code, status);

CREATE INDEX IF NOT EXISTS idx_bank_lines_import ON bank_statement_lines (import_id, line_no);

CREATE UNIQUE INDEX IF NOT EXISTS uq_bank_lines_fingerprint ON bank_statement_lines (account_id, fingerprint) WHERE status <> 'reverted';

CREATE UNIQUE INDEX IF NOT EXISTS uq_bank_lines_ledger ON bank_statement_lines (ledger_entry_id) WHERE status IN ('posted', 'linked') AND ledger_entry_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS bank_payer_ibans (
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
);

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bank_import_profiles_account_id_fkey' AND conrelid = 'bank_import_profiles'::regclass) THEN ALTER TABLE bank_import_profiles ADD CONSTRAINT bank_import_profiles_account_id_fkey FOREIGN KEY (account_id) REFERENCES finance_accounts(id) ON DELETE CASCADE; END IF; END $$;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bank_imports_account_id_fkey' AND conrelid = 'bank_imports'::regclass) THEN ALTER TABLE bank_imports ADD CONSTRAINT bank_imports_account_id_fkey FOREIGN KEY (account_id) REFERENCES finance_accounts(id) ON DELETE RESTRICT; END IF; END $$;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bank_imports_site_code_fkey' AND conrelid = 'bank_imports'::regclass) THEN ALTER TABLE bank_imports ADD CONSTRAINT bank_imports_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE; END IF; END $$;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bank_payer_ibans_apartment_id_fkey' AND conrelid = 'bank_payer_ibans'::regclass) THEN ALTER TABLE bank_payer_ibans ADD CONSTRAINT bank_payer_ibans_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE CASCADE; END IF; END $$;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bank_payer_ibans_site_code_fkey' AND conrelid = 'bank_payer_ibans'::regclass) THEN ALTER TABLE bank_payer_ibans ADD CONSTRAINT bank_payer_ibans_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE; END IF; END $$;
