-- 040: FINANS FAZ 4B (makbuz, gecikme tazminati, gider, kasa/banka, raporlar, borc hatirlatma). Sozlesme: docs/PLATFORM_FINANS_4B.md.
-- Kaynak: server/src/modules/finance_4b_schema.js (tek kaynak; bu dosya adimlarinin birlesimidir, test: finance4b_schema). db.js ensureDbSchema AYNI adimlari
-- (katalog kontrollu, her adim kendi otomatik onayli ifadesiyle) blok SONRASINDA uygular. Ekleyici ve idempotent: tablolar IF NOT EXISTS, tetikleyici /
-- kisit / islev katalog korumali; mevcut tablolara yalniz EKLEME (ledger_entries.late_fee_run_id + FK/CHECK NOT VALID -> VALIDATE,
-- notification_preferences.email_finance_reminders). Veri yazmaz.

CREATE TABLE IF NOT EXISTS finance_settings (
  site_code BIGINT PRIMARY KEY,
  receipts_auto_issue BOOLEAN NOT NULL DEFAULT TRUE,
  late_fee_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  late_fee_rate_bp SMALLINT NOT NULL DEFAULT 500,
  late_fee_method TEXT NOT NULL DEFAULT 'daily_30',
  late_fee_grace_days SMALLINT NOT NULL DEFAULT 0,
  late_fee_start_period DATE,
  reminders_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  reminder_min_overdue_minor BIGINT NOT NULL DEFAULT 5000,
  reminder_min_days_overdue SMALLINT NOT NULL DEFAULT 5,
  reminder_min_interval_days SMALLINT NOT NULL DEFAULT 14,
  reminder_max_consecutive SMALLINT NOT NULL DEFAULT 3,
  settings_version INTEGER NOT NULL DEFAULT 1,
  updated_by INTEGER,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_finance_settings_rate CHECK (late_fee_rate_bp BETWEEN 0 AND 500),
  CONSTRAINT chk_finance_settings_method CHECK (late_fee_method IN ('daily_30', 'daily_actual')),
  CONSTRAINT chk_finance_settings_grace CHECK (late_fee_grace_days BETWEEN 0 AND 90),
  CONSTRAINT chk_finance_settings_start CHECK (
    (late_fee_start_period IS NULL OR EXTRACT(DAY FROM late_fee_start_period) = 1)
    AND (late_fee_enabled = FALSE OR late_fee_start_period IS NOT NULL)
  ),
  CONSTRAINT chk_finance_settings_reminder_amount CHECK (reminder_min_overdue_minor >= 100 AND reminder_min_overdue_minor <= 1000000000000),
  CONSTRAINT chk_finance_settings_reminder_days CHECK (reminder_min_days_overdue BETWEEN 1 AND 120),
  CONSTRAINT chk_finance_settings_reminder_interval CHECK (reminder_min_interval_days BETWEEN 7 AND 90),
  CONSTRAINT chk_finance_settings_reminder_consecutive CHECK (reminder_max_consecutive BETWEEN 1 AND 6),
  CONSTRAINT chk_finance_settings_version CHECK (settings_version >= 1)
);
CREATE INDEX IF NOT EXISTS idx_finance_settings_updated_by ON finance_settings (updated_by) WHERE updated_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS late_fee_runs (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  period DATE NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  params JSONB NOT NULL,
  total_minor BIGINT NOT NULL,
  apartment_count INTEGER NOT NULL,
  waived_apartment_ids BIGINT[] NOT NULL DEFAULT '{}',
  inactive_skipped_count INTEGER NOT NULL DEFAULT 0,
  zero_amount_count INTEGER NOT NULL DEFAULT 0,
  preview_hash TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  posted_by INTEGER,
  posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  voided_by INTEGER,
  voided_at TIMESTAMPTZ,
  void_reason TEXT,
  CONSTRAINT chk_late_fee_runs_status CHECK (status IN ('active', 'voided')),
  CONSTRAINT chk_late_fee_runs_period CHECK (EXTRACT(DAY FROM period) = 1),
  CONSTRAINT chk_late_fee_runs_params CHECK (jsonb_typeof(params) = 'object'),
  CONSTRAINT chk_late_fee_runs_total CHECK (total_minor >= 0 AND total_minor <= 100000000000000),
  CONSTRAINT chk_late_fee_runs_counts CHECK (apartment_count >= 0 AND inactive_skipped_count >= 0 AND zero_amount_count >= 0),
  CONSTRAINT chk_late_fee_runs_marker CHECK ((total_minor = 0) = (apartment_count = 0)),
  CONSTRAINT chk_late_fee_runs_digests CHECK (char_length(preview_hash) = 64 AND char_length(request_fingerprint) = 64),
  CONSTRAINT chk_late_fee_runs_key CHECK (char_length(idempotency_key) BETWEEN 1 AND 64),
  CONSTRAINT chk_late_fee_runs_void CHECK ((status = 'voided') = (voided_at IS NOT NULL)),
  CONSTRAINT chk_late_fee_runs_reason CHECK (void_reason IS NULL OR char_length(void_reason) <= 200)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_late_fee_runs_active_period ON late_fee_runs (site_code, period) WHERE status = 'active';
CREATE UNIQUE INDEX IF NOT EXISTS uq_late_fee_runs_idempotency ON late_fee_runs (site_code, idempotency_key);
CREATE INDEX IF NOT EXISTS idx_late_fee_runs_posted_by ON late_fee_runs (posted_by) WHERE posted_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_late_fee_runs_voided_by ON late_fee_runs (voided_by) WHERE voided_by IS NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_late_fee_runs_total' AND conrelid = 'late_fee_runs'::regclass AND pg_get_constraintdef(oid) NOT LIKE '%total_minor >= 0%'
  ) THEN
    ALTER TABLE late_fee_runs DROP CONSTRAINT chk_late_fee_runs_total;
    ALTER TABLE late_fee_runs ADD CONSTRAINT chk_late_fee_runs_total CHECK (total_minor >= 0 AND total_minor <= 100000000000000) NOT VALID;
    ALTER TABLE late_fee_runs VALIDATE CONSTRAINT chk_late_fee_runs_total;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_late_fee_runs_counts' AND conrelid = 'late_fee_runs'::regclass AND pg_get_constraintdef(oid) NOT LIKE '%apartment_count >= 0%'
  ) THEN
    ALTER TABLE late_fee_runs DROP CONSTRAINT chk_late_fee_runs_counts;
    ALTER TABLE late_fee_runs ADD CONSTRAINT chk_late_fee_runs_counts CHECK (apartment_count >= 0 AND inactive_skipped_count >= 0 AND zero_amount_count >= 0) NOT VALID;
    ALTER TABLE late_fee_runs VALIDATE CONSTRAINT chk_late_fee_runs_counts;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_late_fee_runs_marker' AND conrelid = 'late_fee_runs'::regclass) THEN
    ALTER TABLE late_fee_runs ADD CONSTRAINT chk_late_fee_runs_marker CHECK ((total_minor = 0) = (apartment_count = 0)) NOT VALID;
    ALTER TABLE late_fee_runs VALIDATE CONSTRAINT chk_late_fee_runs_marker;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS late_fee_run_lines (
  run_id BIGINT NOT NULL REFERENCES late_fee_runs(id),
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  apartment_label TEXT NOT NULL,
  amount_minor BIGINT NOT NULL,
  base_day_minor BIGINT NOT NULL,
  peak_overdue_minor BIGINT NOT NULL,
  breakdown JSONB NOT NULL,
  ledger_entry_id BIGINT NOT NULL,
  PRIMARY KEY (run_id, apartment_id),
  CONSTRAINT chk_late_fee_run_lines_amount CHECK (amount_minor > 0 AND base_day_minor > 0 AND peak_overdue_minor > 0),
  CONSTRAINT chk_late_fee_run_lines_label CHECK (char_length(apartment_label) BETWEEN 1 AND 300),
  CONSTRAINT chk_late_fee_run_lines_breakdown CHECK (jsonb_typeof(breakdown) = 'array' AND jsonb_array_length(breakdown) <= 62)
);
CREATE INDEX IF NOT EXISTS idx_late_fee_run_lines_ledger ON late_fee_run_lines (ledger_entry_id);
CREATE INDEX IF NOT EXISTS idx_late_fee_run_lines_site ON late_fee_run_lines (site_code);

CREATE TABLE IF NOT EXISTS receipt_counters (
  site_code BIGINT NOT NULL,
  receipt_year SMALLINT NOT NULL,
  last_no INTEGER NOT NULL,
  PRIMARY KEY (site_code, receipt_year),
  CONSTRAINT chk_receipt_counters_last CHECK (last_no >= 1),
  CONSTRAINT chk_receipt_counters_year CHECK (receipt_year BETWEEN 2000 AND 2100)
);

CREATE TABLE IF NOT EXISTS receipts (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  receipt_year SMALLINT NOT NULL,
  receipt_no INTEGER NOT NULL,
  kind TEXT NOT NULL,
  ledger_entry_id BIGINT NOT NULL,
  cancels_receipt_id BIGINT REFERENCES receipts(id),
  apartment_id BIGINT NOT NULL,
  amount_minor BIGINT NOT NULL,
  paid_on DATE NOT NULL,
  issued_on DATE NOT NULL,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  snapshot JSONB NOT NULL,
  snapshot_sha256 TEXT NOT NULL,
  verification_code TEXT NOT NULL,
  template_version SMALLINT NOT NULL DEFAULT 1,
  cancel_reason_code TEXT,
  cancel_note TEXT,
  idempotency_key TEXT,
  issued_by INTEGER,
  CONSTRAINT uq_receipts_number UNIQUE (site_code, receipt_year, receipt_no),
  CONSTRAINT chk_receipts_kind CHECK (kind IN ('collection', 'cancellation')),
  CONSTRAINT chk_receipts_number CHECK (receipt_no >= 1 AND receipt_year BETWEEN 2000 AND 2100),
  CONSTRAINT chk_receipts_amount CHECK (amount_minor > 0 AND amount_minor <= 1000000000000),
  CONSTRAINT chk_receipts_cancel_link CHECK ((kind = 'cancellation') = (cancels_receipt_id IS NOT NULL)),
  CONSTRAINT chk_receipts_cancel_reason CHECK (
    (kind = 'cancellation' AND cancel_reason_code IS NOT NULL AND cancel_reason_code IN ('payment_reversed', 'payment_corrected', 'issued_in_error'))
    OR (kind = 'collection' AND cancel_reason_code IS NULL AND cancel_note IS NULL)
  ),
  CONSTRAINT chk_receipts_note CHECK (cancel_note IS NULL OR char_length(cancel_note) <= 200),
  CONSTRAINT chk_receipts_digests CHECK (char_length(snapshot_sha256) = 64 AND char_length(verification_code) = 12),
  CONSTRAINT chk_receipts_snapshot CHECK (jsonb_typeof(snapshot) = 'object'),
  CONSTRAINT chk_receipts_template CHECK (template_version >= 1),
  CONSTRAINT chk_receipts_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) BETWEEN 1 AND 64)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_receipts_cancels ON receipts (cancels_receipt_id) WHERE cancels_receipt_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_receipts_idempotency ON receipts (site_code, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_receipts_ledger ON receipts (ledger_entry_id);
CREATE INDEX IF NOT EXISTS idx_receipts_apartment ON receipts (apartment_id);
CREATE INDEX IF NOT EXISTS idx_receipts_site_id ON receipts (site_code, id DESC);
CREATE INDEX IF NOT EXISTS idx_receipts_issued_by ON receipts (issued_by) WHERE issued_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS receipt_print_events (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  receipt_id BIGINT NOT NULL REFERENCES receipts(id),
  copy_number INTEGER NOT NULL,
  idempotency_key TEXT,
  printed_by INTEGER,
  printed_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT uq_receipt_print_events_copy UNIQUE (receipt_id, copy_number),
  CONSTRAINT chk_receipt_print_events_copy CHECK (copy_number >= 1),
  CONSTRAINT chk_receipt_print_events_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) BETWEEN 1 AND 64)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_receipt_print_events_idempotency ON receipt_print_events (receipt_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_receipt_print_events_site ON receipt_print_events (site_code);
CREATE INDEX IF NOT EXISTS idx_receipt_print_events_printed_by ON receipt_print_events (printed_by) WHERE printed_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS finance_accounts (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  name TEXT NOT NULL,
  kind TEXT NOT NULL,
  note TEXT,
  opening_date DATE NOT NULL,
  opening_balance_minor BIGINT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  idempotency_key TEXT,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_finance_accounts_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) BETWEEN 1 AND 64),
  CONSTRAINT chk_finance_accounts_name CHECK (char_length(name) BETWEEN 1 AND 60),
  CONSTRAINT chk_finance_accounts_kind CHECK (kind IN ('cash', 'bank')),
  CONSTRAINT chk_finance_accounts_note CHECK (note IS NULL OR char_length(note) <= 200),
  CONSTRAINT chk_finance_accounts_opening CHECK (opening_balance_minor BETWEEN -1000000000000 AND 1000000000000)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_accounts_name ON finance_accounts (site_code, lower(name));
CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_accounts_idempotency ON finance_accounts (site_code, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_finance_accounts_created_by ON finance_accounts (created_by) WHERE created_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS expense_categories (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  name TEXT NOT NULL,
  is_system BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_expense_categories_name CHECK (char_length(name) BETWEEN 1 AND 60)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_expense_categories_name ON expense_categories (site_code, lower(name));

CREATE TABLE IF NOT EXISTS finance_suppliers (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  name TEXT NOT NULL,
  tax_id TEXT,
  phone TEXT,
  note TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_finance_suppliers_name CHECK (char_length(name) BETWEEN 1 AND 100),
  CONSTRAINT chk_finance_suppliers_tax CHECK (tax_id IS NULL OR tax_id ~ '^[0-9]{10,11}$'),
  CONSTRAINT chk_finance_suppliers_phone CHECK (phone IS NULL OR char_length(phone) <= 20),
  CONSTRAINT chk_finance_suppliers_note CHECK (note IS NULL OR char_length(note) <= 200)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_suppliers_name ON finance_suppliers (site_code, lower(name));
CREATE INDEX IF NOT EXISTS idx_finance_suppliers_created_by ON finance_suppliers (created_by) WHERE created_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS expenses (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  category_id BIGINT NOT NULL REFERENCES expense_categories(id),
  category_name TEXT NOT NULL,
  supplier_id BIGINT REFERENCES finance_suppliers(id),
  supplier_name TEXT,
  description TEXT NOT NULL,
  amount_minor BIGINT NOT NULL,
  vat_minor BIGINT,
  expense_date DATE NOT NULL,
  period DATE NOT NULL,
  account_id BIGINT NOT NULL REFERENCES finance_accounts(id),
  document_kind TEXT NOT NULL DEFAULT 'none',
  document_no TEXT,
  document_no_norm TEXT,
  corrects_expense_id BIGINT REFERENCES expenses(id),
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_expenses_amount CHECK (amount_minor BETWEEN 1 AND 1000000000000),
  CONSTRAINT chk_expenses_vat CHECK (vat_minor IS NULL OR (vat_minor >= 0 AND vat_minor <= amount_minor)),
  CONSTRAINT chk_expenses_text CHECK (
    char_length(description) BETWEEN 1 AND 200 AND char_length(category_name) BETWEEN 1 AND 60
    AND (supplier_name IS NULL OR char_length(supplier_name) BETWEEN 1 AND 100)
  ),
  CONSTRAINT chk_expenses_period CHECK (EXTRACT(DAY FROM period) = 1 AND period = expense_date - (EXTRACT(DAY FROM expense_date)::INTEGER - 1)),
  CONSTRAINT chk_expenses_document CHECK (
    document_kind IN ('invoice', 'receipt', 'contract', 'other', 'none')
    AND (document_no IS NULL OR char_length(document_no) <= 40)
    AND (document_no_norm IS NULL OR document_no IS NOT NULL)
  ),
  CONSTRAINT chk_expenses_key CHECK (char_length(idempotency_key) BETWEEN 1 AND 64 AND char_length(request_fingerprint) = 64),
  CONSTRAINT uq_expenses_idempotency UNIQUE (site_code, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses (site_code, expense_date, id);
CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses (site_code, category_id);
CREATE INDEX IF NOT EXISTS idx_expenses_supplier ON expenses (site_code, supplier_id) WHERE supplier_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_expenses_document_no ON expenses (site_code, supplier_id, document_no_norm) WHERE document_no_norm IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_expenses_account ON expenses (account_id);
CREATE INDEX IF NOT EXISTS idx_expenses_corrects ON expenses (corrects_expense_id) WHERE corrects_expense_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_expenses_supplier_fk ON expenses (supplier_id) WHERE supplier_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_expenses_category_fk ON expenses (category_id);
CREATE INDEX IF NOT EXISTS idx_expenses_created_by ON expenses (created_by) WHERE created_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS expense_voids (
  expense_id BIGINT PRIMARY KEY REFERENCES expenses(id),
  site_code BIGINT NOT NULL,
  reason TEXT NOT NULL,
  period DATE NOT NULL,
  voided_by INTEGER,
  voided_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_expense_voids_reason CHECK (char_length(reason) BETWEEN 1 AND 200),
  CONSTRAINT chk_expense_voids_period CHECK (EXTRACT(DAY FROM period) = 1)
);
CREATE INDEX IF NOT EXISTS idx_expense_voids_site ON expense_voids (site_code, period);
CREATE INDEX IF NOT EXISTS idx_expense_voids_voided_by ON expense_voids (voided_by) WHERE voided_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS expense_documents (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  expense_id BIGINT NOT NULL REFERENCES expenses(id),
  status TEXT NOT NULL DEFAULT 'uploading',
  storage_key TEXT NOT NULL,
  display_name TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  declared_size_bytes BIGINT NOT NULL,
  size_bytes BIGINT NOT NULL,
  sha256 TEXT,
  kind TEXT NOT NULL,
  idempotency_key TEXT,
  added_by INTEGER,
  added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  removed_at TIMESTAMPTZ,
  removed_by INTEGER,
  removal_reason TEXT,
  CONSTRAINT uq_expense_documents_storage UNIQUE (storage_key),
  CONSTRAINT chk_expense_documents_status CHECK (status IN ('uploading', 'ready')),
  CONSTRAINT chk_expense_documents_name CHECK (char_length(display_name) BETWEEN 1 AND 120),
  CONSTRAINT chk_expense_documents_mime CHECK (mime_type IN ('application/pdf', 'image/jpeg', 'image/png')),
  CONSTRAINT chk_expense_documents_sizes CHECK (declared_size_bytes > 0 AND size_bytes >= 0),
  CONSTRAINT chk_expense_documents_sha CHECK (sha256 IS NULL OR char_length(sha256) = 64),
  CONSTRAINT chk_expense_documents_kind CHECK (kind IN ('invoice', 'receipt', 'photo', 'other')),
  CONSTRAINT chk_expense_documents_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) BETWEEN 1 AND 64),
  CONSTRAINT chk_expense_documents_reason CHECK (removal_reason IS NULL OR char_length(removal_reason) <= 200),
  CONSTRAINT chk_expense_documents_ready CHECK (status = 'uploading' OR (sha256 IS NOT NULL AND completed_at IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_expense_documents_sha ON expense_documents (site_code, expense_id, sha256) WHERE sha256 IS NOT NULL AND removed_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_expense_documents_idempotency ON expense_documents (site_code, expense_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_expense_documents_expense ON expense_documents (expense_id);
CREATE INDEX IF NOT EXISTS idx_expense_documents_site ON expense_documents (site_code, status);
CREATE INDEX IF NOT EXISTS idx_expense_documents_added_by ON expense_documents (added_by) WHERE added_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_expense_documents_removed_by ON expense_documents (removed_by) WHERE removed_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS account_transfers (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  from_account_id BIGINT NOT NULL REFERENCES finance_accounts(id),
  to_account_id BIGINT NOT NULL REFERENCES finance_accounts(id),
  amount_minor BIGINT NOT NULL,
  transfer_date DATE NOT NULL,
  description TEXT,
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_account_transfers_amount CHECK (amount_minor BETWEEN 1 AND 1000000000000),
  CONSTRAINT chk_account_transfers_accounts CHECK (from_account_id <> to_account_id),
  CONSTRAINT chk_account_transfers_text CHECK (description IS NULL OR char_length(description) <= 200),
  CONSTRAINT chk_account_transfers_key CHECK (char_length(idempotency_key) BETWEEN 1 AND 64 AND char_length(request_fingerprint) = 64),
  CONSTRAINT uq_account_transfers_idempotency UNIQUE (site_code, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_account_transfers_date ON account_transfers (site_code, transfer_date, id);
CREATE INDEX IF NOT EXISTS idx_account_transfers_from ON account_transfers (from_account_id);
CREATE INDEX IF NOT EXISTS idx_account_transfers_to ON account_transfers (to_account_id);
CREATE INDEX IF NOT EXISTS idx_account_transfers_created_by ON account_transfers (created_by) WHERE created_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS account_movements (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  account_id BIGINT NOT NULL REFERENCES finance_accounts(id),
  kind TEXT NOT NULL,
  amount_minor BIGINT NOT NULL,
  movement_date DATE NOT NULL,
  period DATE NOT NULL,
  ledger_entry_id BIGINT,
  expense_id BIGINT REFERENCES expenses(id),
  transfer_id BIGINT REFERENCES account_transfers(id),
  reverses_movement_id BIGINT REFERENCES account_movements(id),
  reason_code TEXT,
  note TEXT,
  idempotency_key TEXT,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_account_movements_kind CHECK (kind IN ('opening', 'collection', 'expense', 'transfer_out', 'transfer_in', 'adjustment', 'reversal')),
  CONSTRAINT chk_account_movements_amount CHECK (amount_minor <> 0 AND amount_minor BETWEEN -1000000000000 AND 1000000000000),
  CONSTRAINT chk_account_movements_sign CHECK (
    (kind = 'collection' AND amount_minor > 0)
    OR (kind = 'expense' AND amount_minor < 0)
    OR (kind = 'transfer_out' AND amount_minor < 0)
    OR (kind = 'transfer_in' AND amount_minor > 0)
    OR kind IN ('opening', 'adjustment', 'reversal')
  ),
  CONSTRAINT chk_account_movements_source CHECK (
    (kind = 'collection' AND ledger_entry_id IS NOT NULL AND expense_id IS NULL AND transfer_id IS NULL AND reverses_movement_id IS NULL)
    OR (kind = 'expense' AND expense_id IS NOT NULL AND ledger_entry_id IS NULL AND transfer_id IS NULL AND reverses_movement_id IS NULL)
    OR (kind IN ('transfer_out', 'transfer_in') AND transfer_id IS NOT NULL AND ledger_entry_id IS NULL AND expense_id IS NULL AND reverses_movement_id IS NULL)
    OR (kind = 'reversal' AND reverses_movement_id IS NOT NULL AND ledger_entry_id IS NULL AND expense_id IS NULL AND transfer_id IS NULL)
    OR (kind IN ('opening', 'adjustment') AND ledger_entry_id IS NULL AND expense_id IS NULL AND transfer_id IS NULL AND reverses_movement_id IS NULL)
  ),
  CONSTRAINT chk_account_movements_reason CHECK (
    (kind = 'adjustment' AND reason_code IS NOT NULL AND reason_code IN ('bank_fee', 'bank_interest', 'cash_count', 'other'))
    OR (kind <> 'adjustment' AND reason_code IS NULL)
  ),
  CONSTRAINT chk_account_movements_period CHECK (EXTRACT(DAY FROM period) = 1),
  CONSTRAINT chk_account_movements_note CHECK (note IS NULL OR char_length(note) <= 200),
  CONSTRAINT chk_account_movements_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) BETWEEN 1 AND 64)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_account_movements_collection ON account_movements (ledger_entry_id) WHERE kind = 'collection';
CREATE UNIQUE INDEX IF NOT EXISTS uq_account_movements_expense ON account_movements (expense_id) WHERE kind = 'expense';
CREATE UNIQUE INDEX IF NOT EXISTS uq_account_movements_transfer ON account_movements (transfer_id, kind) WHERE kind IN ('transfer_out', 'transfer_in');
CREATE UNIQUE INDEX IF NOT EXISTS uq_account_movements_reverses ON account_movements (reverses_movement_id) WHERE reverses_movement_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_account_movements_idempotency ON account_movements (site_code, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_account_movements_opening ON account_movements (account_id) WHERE kind = 'opening';
CREATE INDEX IF NOT EXISTS idx_account_movements_account ON account_movements (site_code, account_id, movement_date, id);
CREATE INDEX IF NOT EXISTS idx_account_movements_period ON account_movements (site_code, period);
CREATE INDEX IF NOT EXISTS idx_account_movements_account_fk ON account_movements (account_id);
CREATE INDEX IF NOT EXISTS idx_account_movements_created_by ON account_movements (created_by) WHERE created_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS account_reconciliations (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  account_id BIGINT NOT NULL REFERENCES finance_accounts(id),
  as_of_date DATE NOT NULL,
  statement_balance_minor BIGINT NOT NULL,
  computed_balance_minor BIGINT NOT NULL,
  difference_minor BIGINT NOT NULL,
  adjustment_movement_id BIGINT REFERENCES account_movements(id),
  note TEXT,
  idempotency_key TEXT NOT NULL,
  reconciled_by INTEGER,
  reconciled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_account_reconciliations_difference CHECK (difference_minor = statement_balance_minor - computed_balance_minor),
  CONSTRAINT chk_account_reconciliations_note CHECK (note IS NULL OR char_length(note) <= 200),
  CONSTRAINT chk_account_reconciliations_key CHECK (char_length(idempotency_key) BETWEEN 1 AND 64),
  CONSTRAINT uq_account_reconciliations_idempotency UNIQUE (site_code, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_account_reconciliations_account ON account_reconciliations (account_id, as_of_date DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_account_reconciliations_adjustment ON account_reconciliations (adjustment_movement_id) WHERE adjustment_movement_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_account_reconciliations_by ON account_reconciliations (reconciled_by) WHERE reconciled_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS finance_reminder_exclusions (
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  reason TEXT,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (site_code, apartment_id),
  CONSTRAINT chk_finance_reminder_exclusions_reason CHECK (reason IS NULL OR char_length(reason) <= 100)
);
CREATE INDEX IF NOT EXISTS idx_finance_reminder_exclusions_apartment ON finance_reminder_exclusions (apartment_id);
CREATE INDEX IF NOT EXISTS idx_finance_reminder_exclusions_by ON finance_reminder_exclusions (created_by) WHERE created_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS finance_reminder_runs (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  tone TEXT NOT NULL,
  note TEXT,
  params JSONB NOT NULL,
  apartment_count INTEGER NOT NULL,
  person_count INTEGER NOT NULL,
  with_amount_count INTEGER NOT NULL,
  preview_hash TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  run_on DATE NOT NULL,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  cancelled_by INTEGER,
  cancelled_at TIMESTAMPTZ,
  CONSTRAINT chk_finance_reminder_runs_status CHECK (status IN ('active', 'cancelled') AND ((status = 'cancelled') = (cancelled_at IS NOT NULL))),
  CONSTRAINT chk_finance_reminder_runs_tone CHECK (tone IN ('friendly', 'standard')),
  CONSTRAINT chk_finance_reminder_runs_note CHECK (note IS NULL OR char_length(note) <= 300),
  CONSTRAINT chk_finance_reminder_runs_params CHECK (jsonb_typeof(params) = 'object'),
  CONSTRAINT chk_finance_reminder_runs_counts CHECK (apartment_count >= 1 AND person_count >= 1 AND with_amount_count >= 0 AND with_amount_count <= person_count),
  CONSTRAINT chk_finance_reminder_runs_digests CHECK (char_length(preview_hash) = 64 AND char_length(request_fingerprint) = 64),
  CONSTRAINT chk_finance_reminder_runs_key CHECK (char_length(idempotency_key) BETWEEN 1 AND 64),
  CONSTRAINT uq_finance_reminder_runs_idempotency UNIQUE (site_code, idempotency_key)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_reminder_runs_day ON finance_reminder_runs (site_code, run_on) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_finance_reminder_runs_site ON finance_reminder_runs (site_code, id DESC);
CREATE INDEX IF NOT EXISTS idx_finance_reminder_runs_created_by ON finance_reminder_runs (created_by) WHERE created_by IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_finance_reminder_runs_cancelled_by ON finance_reminder_runs (cancelled_by) WHERE cancelled_by IS NOT NULL;

CREATE TABLE IF NOT EXISTS finance_reminder_items (
  run_id BIGINT NOT NULL REFERENCES finance_reminder_runs(id) ON DELETE CASCADE,
  person_id BIGINT NOT NULL,
  apartment_ids BIGINT[] NOT NULL,
  with_amount BOOLEAN NOT NULL,
  has_account BOOLEAN NOT NULL,
  email TEXT,
  email_hash TEXT,
  email_status TEXT NOT NULL DEFAULT 'pending',
  email_attempts INTEGER NOT NULL DEFAULT 0,
  email_claimed_at TIMESTAMPTZ,
  email_next_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  PRIMARY KEY (run_id, person_id),
  CONSTRAINT chk_finance_reminder_items_apartments CHECK (cardinality(apartment_ids) BETWEEN 1 AND 20),
  CONSTRAINT chk_finance_reminder_items_status CHECK (
    email_status IN ('pending', 'sent', 'failed', 'no_address', 'skipped_pref', 'duplicate', 'capped', 'resolved', 'cancelled')
  ),
  CONSTRAINT chk_finance_reminder_items_attempts CHECK (email_attempts >= 0)
);
CREATE INDEX IF NOT EXISTS idx_finance_reminder_items_pending ON finance_reminder_items (email_status) WHERE email_status = 'pending';
CREATE INDEX IF NOT EXISTS idx_finance_reminder_items_email_hash ON finance_reminder_items (email_hash) WHERE email_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_finance_reminder_items_person ON finance_reminder_items (person_id);

CREATE TABLE IF NOT EXISTS finance_reminder_apartments (
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  run_id BIGINT NOT NULL REFERENCES finance_reminder_runs(id) ON DELETE CASCADE,
  reminded_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (apartment_id, run_id)
);
CREATE INDEX IF NOT EXISTS idx_finance_reminder_apartments_recent ON finance_reminder_apartments (site_code, apartment_id, reminded_at DESC);
CREATE INDEX IF NOT EXISTS idx_finance_reminder_apartments_run ON finance_reminder_apartments (run_id);

CREATE OR REPLACE FUNCTION trg_finance_immutable() RETURNS trigger AS $$
-- f4b:2
DECLARE
  col TEXT;
  old_json JSONB;
  new_json JSONB;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
      RETURN OLD;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF TG_NARGS > 0 THEN
      old_json := to_jsonb(OLD);
      new_json := to_jsonb(NEW);
      FOREACH col IN ARRAY TG_ARGV LOOP
        IF (old_json ->> col) IS NOT NULL AND (new_json ->> col) IS NULL
           AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = (old_json ->> col)::INTEGER)
           AND (new_json - col) = (old_json - col) THEN
          RETURN NEW;
        END IF;
      END LOOP;
    END IF;
  END IF;
  RAISE EXCEPTION 'finance records are append-only';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_late_fee_runs_guard() RETURNS trigger AS $$
-- f4b:2
DECLARE
  col TEXT;
  old_json JSONB;
  new_json JSONB;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
      RETURN OLD;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    old_json := to_jsonb(OLD);
    new_json := to_jsonb(NEW);
    IF OLD.status = 'active' AND NEW.status = 'voided' AND NEW.voided_at IS NOT NULL
       AND (new_json - ARRAY['status', 'voided_by', 'voided_at', 'void_reason']) = (old_json - ARRAY['status', 'voided_by', 'voided_at', 'void_reason']) THEN
      RETURN NEW;
    END IF;
    FOREACH col IN ARRAY ARRAY['posted_by', 'voided_by'] LOOP
      IF (old_json ->> col) IS NOT NULL AND (new_json ->> col) IS NULL
         AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = (old_json ->> col)::INTEGER)
         AND (new_json - col) = (old_json - col) THEN
        RETURN NEW;
      END IF;
    END LOOP;
  END IF;
  RAISE EXCEPTION 'finance late fee runs are append-only';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_late_fee_runs_chain() RETURNS trigger AS $$
-- f4b:2
DECLARE
  last_period DATE;
  start_period DATE;
  expected DATE;
BEGIN
  IF NEW.status <> 'active' THEN
    RAISE EXCEPTION 'late fee run must start active';
  END IF;
  SELECT MAX(period) INTO last_period FROM late_fee_runs WHERE site_code = NEW.site_code AND status = 'active';
  IF last_period IS NOT NULL THEN
    expected := (last_period + INTERVAL '1 month')::DATE;
  ELSE
    SELECT late_fee_start_period INTO start_period FROM finance_settings WHERE site_code = NEW.site_code;
    expected := start_period;
  END IF;
  IF expected IS NULL OR NEW.period <> expected THEN
    RAISE EXCEPTION 'late fee period must follow the chain';
  END IF;
  IF (NEW.period + INTERVAL '1 month')::DATE > (clock_timestamp() AT TIME ZONE 'Europe/Istanbul')::DATE THEN
    RAISE EXCEPTION 'late fee period must have ended';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM finance_period_closures WHERE site_code = NEW.site_code AND period >= NEW.period) THEN
    RAISE EXCEPTION 'late fee period must be closed';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_late_fee_run_lines_check() RETURNS trigger AS $$
-- f4b:2
BEGIN
  IF EXISTS (
    SELECT 1
    FROM (SELECT run_id, SUM(amount_minor) AS total, COUNT(*) AS n FROM new_lines GROUP BY run_id) s
    INNER JOIN late_fee_runs r ON r.id = s.run_id
    WHERE s.total <> r.total_minor OR s.n <> r.apartment_count
  ) THEN
    RAISE EXCEPTION 'late fee lines must add up to the run total';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM new_lines n
    LEFT JOIN ledger_entries l ON l.id = n.ledger_entry_id
    WHERE l.id IS NULL OR l.amount_minor <> n.amount_minor OR l.apartment_id <> n.apartment_id
       OR l.site_code <> n.site_code OR l.late_fee_run_id IS DISTINCT FROM n.run_id OR l.kind <> 'charge'
  ) THEN
    RAISE EXCEPTION 'late fee line must match its ledger entry';
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_ledger_entries_late_fee_mirror() RETURNS trigger AS $$
-- f4b:2
DECLARE
  original_run BIGINT;
BEGIN
  SELECT late_fee_run_id INTO original_run FROM ledger_entries WHERE id = NEW.reverses_entry_id;
  IF NEW.late_fee_run_id IS DISTINCT FROM original_run THEN
    RAISE EXCEPTION 'finance reversal must keep the late fee run of its original entry';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_receipt_counters_guard() RETURNS trigger AS $$
-- f4b:2
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
      RETURN OLD;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.last_no = OLD.last_no + 1 AND NEW.site_code = OLD.site_code AND NEW.receipt_year = OLD.receipt_year THEN
      RETURN NEW;
    END IF;
  END IF;
  RAISE EXCEPTION 'receipt counters only move forward by one';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_receipts_insert_check() RETURNS trigger AS $$
-- f4b:2
DECLARE
  led RECORD;
  target RECORD;
BEGIN
  IF NEW.kind = 'collection' THEN
    SELECT site_code, kind, amount_minor, apartment_id, entry_date INTO led FROM ledger_entries WHERE id = NEW.ledger_entry_id;
    IF NOT FOUND OR led.site_code <> NEW.site_code OR led.kind <> 'payment' OR led.amount_minor <> -NEW.amount_minor
       OR led.apartment_id <> NEW.apartment_id OR led.entry_date <> NEW.paid_on THEN
      RAISE EXCEPTION 'receipt must match its payment';
    END IF;
    IF EXISTS (SELECT 1 FROM ledger_entries WHERE reverses_entry_id = NEW.ledger_entry_id) THEN
      RAISE EXCEPTION 'receipt for a reversed payment';
    END IF;
    IF EXISTS (
      SELECT 1 FROM receipts c
      WHERE c.ledger_entry_id = NEW.ledger_entry_id AND c.kind = 'collection'
        AND NOT EXISTS (SELECT 1 FROM receipts x WHERE x.cancels_receipt_id = c.id)
    ) THEN
      RAISE EXCEPTION 'payment already has an active receipt';
    END IF;
  ELSE
    SELECT site_code, kind, ledger_entry_id, apartment_id, amount_minor INTO target FROM receipts WHERE id = NEW.cancels_receipt_id;
    IF NOT FOUND OR target.kind <> 'collection' OR target.site_code <> NEW.site_code OR target.ledger_entry_id <> NEW.ledger_entry_id
       OR target.apartment_id <> NEW.apartment_id OR target.amount_minor <> NEW.amount_minor THEN
      RAISE EXCEPTION 'cancellation must match its receipt';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_finance_accounts_guard() RETURNS trigger AS $$
-- f4b:2
DECLARE
  old_json JSONB;
  new_json JSONB;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
      RETURN OLD;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    old_json := to_jsonb(OLD);
    new_json := to_jsonb(NEW);
    IF (new_json - ARRAY['name', 'note', 'is_active', 'sort_order', 'updated_at']) = (old_json - ARRAY['name', 'note', 'is_active', 'sort_order', 'updated_at']) THEN
      RETURN NEW;
    END IF;
    IF OLD.created_by IS NOT NULL AND NEW.created_by IS NULL
       AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = OLD.created_by)
       AND (new_json - 'created_by') = (old_json - 'created_by') THEN
      RETURN NEW;
    END IF;
  END IF;
  RAISE EXCEPTION 'finance account opening data is immutable';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_finance_settings_guard() RETURNS trigger AS $$
-- f4b:2
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.settings_version = OLD.settings_version + 1 AND NEW.site_code = OLD.site_code THEN
      RETURN NEW;
    END IF;
    IF OLD.updated_by IS NOT NULL AND NEW.updated_by IS NULL
       AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = OLD.updated_by)
       AND (to_jsonb(NEW) - 'updated_by') = (to_jsonb(OLD) - 'updated_by') THEN
      RETURN NEW;
    END IF;
  END IF;
  RAISE EXCEPTION 'finance settings version must advance by one';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_expense_documents_guard() RETURNS trigger AS $$
-- f4b:2
DECLARE
  col TEXT;
  old_json JSONB;
  new_json JSONB;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
      RETURN OLD;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    old_json := to_jsonb(OLD);
    new_json := to_jsonb(NEW);
    IF OLD.status = 'uploading' AND NEW.status = 'ready'
       AND (new_json - ARRAY['status', 'storage_key', 'size_bytes', 'sha256', 'completed_at', 'mime_type']) = (old_json - ARRAY['status', 'storage_key', 'size_bytes', 'sha256', 'completed_at', 'mime_type']) THEN
      RETURN NEW;
    END IF;
    IF OLD.removed_at IS NULL AND NEW.removed_at IS NOT NULL
       AND (new_json - ARRAY['removed_at', 'removed_by', 'removal_reason']) = (old_json - ARRAY['removed_at', 'removed_by', 'removal_reason']) THEN
      RETURN NEW;
    END IF;
    FOREACH col IN ARRAY ARRAY['added_by', 'removed_by'] LOOP
      IF (old_json ->> col) IS NOT NULL AND (new_json ->> col) IS NULL
         AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = (old_json ->> col)::INTEGER)
         AND (new_json - col) = (old_json - col) THEN
        RETURN NEW;
      END IF;
    END LOOP;
  END IF;
  RAISE EXCEPTION 'expense documents are append-only';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_finance_reminder_runs_guard() RETURNS trigger AS $$
-- f4b:2
DECLARE
  col TEXT;
  old_json JSONB;
  new_json JSONB;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
      RETURN OLD;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    old_json := to_jsonb(OLD);
    new_json := to_jsonb(NEW);
    IF OLD.status = 'active' AND NEW.status = 'cancelled' AND NEW.cancelled_at IS NOT NULL
       AND (new_json - ARRAY['status', 'cancelled_by', 'cancelled_at']) = (old_json - ARRAY['status', 'cancelled_by', 'cancelled_at']) THEN
      RETURN NEW;
    END IF;
    FOREACH col IN ARRAY ARRAY['created_by', 'cancelled_by'] LOOP
      IF (old_json ->> col) IS NOT NULL AND (new_json ->> col) IS NULL
         AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = (old_json ->> col)::INTEGER)
         AND (new_json - col) = (old_json - col) THEN
        RETURN NEW;
      END IF;
    END LOOP;
  END IF;
  RAISE EXCEPTION 'finance reminder runs are append-only';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_account_movements_check() RETURNS trigger AS $$
-- f4b:2
DECLARE
  acc RECORD;
  src RECORD;
  orig RECORD;
BEGIN
  SELECT site_code, opening_date INTO acc FROM finance_accounts WHERE id = NEW.account_id;
  IF NOT FOUND OR acc.site_code <> NEW.site_code THEN
    RAISE EXCEPTION 'account movement must stay in its site';
  END IF;
  IF NEW.kind = 'reversal' THEN
    SELECT site_code, account_id, kind, amount_minor INTO orig FROM account_movements WHERE id = NEW.reverses_movement_id;
    IF NOT FOUND OR orig.kind IN ('reversal', 'opening') OR orig.site_code <> NEW.site_code
       OR orig.account_id <> NEW.account_id OR NEW.amount_minor <> -orig.amount_minor THEN
      RAISE EXCEPTION 'account reversal must mirror its original movement';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.kind <> 'opening' AND NEW.movement_date < acc.opening_date THEN
    RAISE EXCEPTION 'account movement before opening date';
  END IF;
  IF NEW.kind = 'collection' THEN
    SELECT site_code, kind, amount_minor INTO src FROM ledger_entries WHERE id = NEW.ledger_entry_id;
    IF NOT FOUND OR src.site_code <> NEW.site_code OR src.kind <> 'payment' OR src.amount_minor <> -NEW.amount_minor THEN
      RAISE EXCEPTION 'collection movement must match its payment';
    END IF;
  ELSIF NEW.kind = 'expense' THEN
    SELECT site_code, amount_minor, account_id INTO src FROM expenses WHERE id = NEW.expense_id;
    IF NOT FOUND OR src.site_code <> NEW.site_code OR src.amount_minor <> -NEW.amount_minor OR src.account_id <> NEW.account_id THEN
      RAISE EXCEPTION 'expense movement must match its expense';
    END IF;
  ELSIF NEW.kind IN ('transfer_out', 'transfer_in') THEN
    SELECT site_code, amount_minor, from_account_id, to_account_id INTO src FROM account_transfers WHERE id = NEW.transfer_id;
    IF NOT FOUND OR src.site_code <> NEW.site_code OR src.amount_minor <> abs(NEW.amount_minor)
       OR (NEW.kind = 'transfer_out' AND src.from_account_id <> NEW.account_id)
       OR (NEW.kind = 'transfer_in' AND src.to_account_id <> NEW.account_id) THEN
      RAISE EXCEPTION 'transfer movement must match its transfer';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_receipts_immutable' AND tgrelid = 'receipts'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_receipts_immutable BEFORE UPDATE OR DELETE ON receipts FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable('issued_by');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_receipt_print_events_immutable' AND tgrelid = 'receipt_print_events'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_receipt_print_events_immutable BEFORE UPDATE OR DELETE ON receipt_print_events FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable('printed_by');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_late_fee_run_lines_immutable' AND tgrelid = 'late_fee_run_lines'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_late_fee_run_lines_immutable BEFORE UPDATE OR DELETE ON late_fee_run_lines FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_expenses_immutable' AND tgrelid = 'expenses'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_expenses_immutable BEFORE UPDATE OR DELETE ON expenses FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable('created_by');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_expense_voids_immutable' AND tgrelid = 'expense_voids'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_expense_voids_immutable BEFORE UPDATE OR DELETE ON expense_voids FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable('voided_by');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_account_movements_immutable' AND tgrelid = 'account_movements'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_account_movements_immutable BEFORE UPDATE OR DELETE ON account_movements FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable('created_by');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_account_transfers_immutable' AND tgrelid = 'account_transfers'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_account_transfers_immutable BEFORE UPDATE OR DELETE ON account_transfers FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable('created_by');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_account_reconciliations_immutable' AND tgrelid = 'account_reconciliations'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_account_reconciliations_immutable BEFORE UPDATE OR DELETE ON account_reconciliations FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable('reconciled_by');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_late_fee_runs_guard' AND tgrelid = 'late_fee_runs'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_late_fee_runs_guard BEFORE UPDATE OR DELETE ON late_fee_runs FOR EACH ROW EXECUTE PROCEDURE trg_late_fee_runs_guard();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_late_fee_runs_chain' AND tgrelid = 'late_fee_runs'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_late_fee_runs_chain BEFORE INSERT ON late_fee_runs FOR EACH ROW EXECUTE PROCEDURE trg_late_fee_runs_chain();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_late_fee_run_lines_check' AND tgrelid = 'late_fee_run_lines'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_late_fee_run_lines_check AFTER INSERT ON late_fee_run_lines REFERENCING NEW TABLE AS new_lines FOR EACH STATEMENT EXECUTE PROCEDURE trg_late_fee_run_lines_check();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_receipt_counters_guard' AND tgrelid = 'receipt_counters'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_receipt_counters_guard BEFORE UPDATE OR DELETE ON receipt_counters FOR EACH ROW EXECUTE PROCEDURE trg_receipt_counters_guard();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_receipts_insert_check' AND tgrelid = 'receipts'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_receipts_insert_check BEFORE INSERT ON receipts FOR EACH ROW EXECUTE PROCEDURE trg_receipts_insert_check();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_finance_accounts_guard' AND tgrelid = 'finance_accounts'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_accounts_guard BEFORE UPDATE OR DELETE ON finance_accounts FOR EACH ROW EXECUTE PROCEDURE trg_finance_accounts_guard();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_finance_settings_guard' AND tgrelid = 'finance_settings'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_settings_guard BEFORE UPDATE ON finance_settings FOR EACH ROW EXECUTE PROCEDURE trg_finance_settings_guard();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_expense_documents_guard' AND tgrelid = 'expense_documents'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_expense_documents_guard BEFORE UPDATE OR DELETE ON expense_documents FOR EACH ROW EXECUTE PROCEDURE trg_expense_documents_guard();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_finance_reminder_runs_guard' AND tgrelid = 'finance_reminder_runs'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_finance_reminder_runs_guard BEFORE UPDATE OR DELETE ON finance_reminder_runs FOR EACH ROW EXECUTE PROCEDURE trg_finance_reminder_runs_guard();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_account_movements_check' AND tgrelid = 'account_movements'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_account_movements_check BEFORE INSERT ON account_movements FOR EACH ROW EXECUTE PROCEDURE trg_account_movements_check();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_late_fee_runs_no_truncate' AND tgrelid = 'late_fee_runs'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_late_fee_runs_no_truncate BEFORE TRUNCATE ON late_fee_runs FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_late_fee_run_lines_no_truncate' AND tgrelid = 'late_fee_run_lines'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_late_fee_run_lines_no_truncate BEFORE TRUNCATE ON late_fee_run_lines FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_receipt_counters_no_truncate' AND tgrelid = 'receipt_counters'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_receipt_counters_no_truncate BEFORE TRUNCATE ON receipt_counters FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_receipts_no_truncate' AND tgrelid = 'receipts'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_receipts_no_truncate BEFORE TRUNCATE ON receipts FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_receipt_print_events_no_truncate' AND tgrelid = 'receipt_print_events'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_receipt_print_events_no_truncate BEFORE TRUNCATE ON receipt_print_events FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_expenses_no_truncate' AND tgrelid = 'expenses'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_expenses_no_truncate BEFORE TRUNCATE ON expenses FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_expense_voids_no_truncate' AND tgrelid = 'expense_voids'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_expense_voids_no_truncate BEFORE TRUNCATE ON expense_voids FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_expense_documents_no_truncate' AND tgrelid = 'expense_documents'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_expense_documents_no_truncate BEFORE TRUNCATE ON expense_documents FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_account_movements_no_truncate' AND tgrelid = 'account_movements'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_account_movements_no_truncate BEFORE TRUNCATE ON account_movements FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_account_transfers_no_truncate' AND tgrelid = 'account_transfers'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_account_transfers_no_truncate BEFORE TRUNCATE ON account_transfers FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_account_reconciliations_no_truncate' AND tgrelid = 'account_reconciliations'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_account_reconciliations_no_truncate BEFORE TRUNCATE ON account_reconciliations FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate();
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_settings_updated_by_fkey' AND conrelid = 'finance_settings'::regclass
  ) THEN
    ALTER TABLE finance_settings ADD CONSTRAINT finance_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'late_fee_runs_posted_by_fkey' AND conrelid = 'late_fee_runs'::regclass
  ) THEN
    ALTER TABLE late_fee_runs ADD CONSTRAINT late_fee_runs_posted_by_fkey FOREIGN KEY (posted_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'late_fee_runs_voided_by_fkey' AND conrelid = 'late_fee_runs'::regclass
  ) THEN
    ALTER TABLE late_fee_runs ADD CONSTRAINT late_fee_runs_voided_by_fkey FOREIGN KEY (voided_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'receipts_issued_by_fkey' AND conrelid = 'receipts'::regclass
  ) THEN
    ALTER TABLE receipts ADD CONSTRAINT receipts_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'receipt_print_events_printed_by_fkey' AND conrelid = 'receipt_print_events'::regclass
  ) THEN
    ALTER TABLE receipt_print_events ADD CONSTRAINT receipt_print_events_printed_by_fkey FOREIGN KEY (printed_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_accounts_created_by_fkey' AND conrelid = 'finance_accounts'::regclass
  ) THEN
    ALTER TABLE finance_accounts ADD CONSTRAINT finance_accounts_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_suppliers_created_by_fkey' AND conrelid = 'finance_suppliers'::regclass
  ) THEN
    ALTER TABLE finance_suppliers ADD CONSTRAINT finance_suppliers_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expenses_created_by_fkey' AND conrelid = 'expenses'::regclass
  ) THEN
    ALTER TABLE expenses ADD CONSTRAINT expenses_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expense_voids_voided_by_fkey' AND conrelid = 'expense_voids'::regclass
  ) THEN
    ALTER TABLE expense_voids ADD CONSTRAINT expense_voids_voided_by_fkey FOREIGN KEY (voided_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expense_documents_added_by_fkey' AND conrelid = 'expense_documents'::regclass
  ) THEN
    ALTER TABLE expense_documents ADD CONSTRAINT expense_documents_added_by_fkey FOREIGN KEY (added_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expense_documents_removed_by_fkey' AND conrelid = 'expense_documents'::regclass
  ) THEN
    ALTER TABLE expense_documents ADD CONSTRAINT expense_documents_removed_by_fkey FOREIGN KEY (removed_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'account_transfers_created_by_fkey' AND conrelid = 'account_transfers'::regclass
  ) THEN
    ALTER TABLE account_transfers ADD CONSTRAINT account_transfers_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'account_movements_created_by_fkey' AND conrelid = 'account_movements'::regclass
  ) THEN
    ALTER TABLE account_movements ADD CONSTRAINT account_movements_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'account_reconciliations_reconciled_by_fkey' AND conrelid = 'account_reconciliations'::regclass
  ) THEN
    ALTER TABLE account_reconciliations ADD CONSTRAINT account_reconciliations_reconciled_by_fkey FOREIGN KEY (reconciled_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_reminder_exclusions_created_by_fkey' AND conrelid = 'finance_reminder_exclusions'::regclass
  ) THEN
    ALTER TABLE finance_reminder_exclusions ADD CONSTRAINT finance_reminder_exclusions_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_reminder_runs_created_by_fkey' AND conrelid = 'finance_reminder_runs'::regclass
  ) THEN
    ALTER TABLE finance_reminder_runs ADD CONSTRAINT finance_reminder_runs_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_reminder_runs_cancelled_by_fkey' AND conrelid = 'finance_reminder_runs'::regclass
  ) THEN
    ALTER TABLE finance_reminder_runs ADD CONSTRAINT finance_reminder_runs_cancelled_by_fkey FOREIGN KEY (cancelled_by) REFERENCES users(user_code) ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'receipts_apartment_id_fkey' AND conrelid = 'receipts'::regclass
  ) THEN
    ALTER TABLE receipts ADD CONSTRAINT receipts_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_reminder_exclusions_apartment_id_fkey' AND conrelid = 'finance_reminder_exclusions'::regclass
  ) THEN
    ALTER TABLE finance_reminder_exclusions ADD CONSTRAINT finance_reminder_exclusions_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_reminder_apartments_apartment_id_fkey' AND conrelid = 'finance_reminder_apartments'::regclass
  ) THEN
    ALTER TABLE finance_reminder_apartments ADD CONSTRAINT finance_reminder_apartments_apartment_id_fkey FOREIGN KEY (apartment_id) REFERENCES apartments(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_reminder_items_person_id_fkey' AND conrelid = 'finance_reminder_items'::regclass
  ) THEN
    ALTER TABLE finance_reminder_items ADD CONSTRAINT finance_reminder_items_person_id_fkey FOREIGN KEY (person_id) REFERENCES site_people(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'late_fee_run_lines_ledger_entry_id_fkey' AND conrelid = 'late_fee_run_lines'::regclass
  ) THEN
    ALTER TABLE late_fee_run_lines ADD CONSTRAINT late_fee_run_lines_ledger_entry_id_fkey FOREIGN KEY (ledger_entry_id) REFERENCES ledger_entries(id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'receipts_ledger_entry_id_fkey' AND conrelid = 'receipts'::regclass
  ) THEN
    ALTER TABLE receipts ADD CONSTRAINT receipts_ledger_entry_id_fkey FOREIGN KEY (ledger_entry_id) REFERENCES ledger_entries(id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'account_movements_ledger_entry_id_fkey' AND conrelid = 'account_movements'::regclass
  ) THEN
    ALTER TABLE account_movements ADD CONSTRAINT account_movements_ledger_entry_id_fkey FOREIGN KEY (ledger_entry_id) REFERENCES ledger_entries(id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_settings_site_code_fkey' AND conrelid = 'finance_settings'::regclass
  ) THEN
    ALTER TABLE finance_settings ADD CONSTRAINT finance_settings_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'late_fee_runs_site_code_fkey' AND conrelid = 'late_fee_runs'::regclass
  ) THEN
    ALTER TABLE late_fee_runs ADD CONSTRAINT late_fee_runs_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'late_fee_run_lines_site_code_fkey' AND conrelid = 'late_fee_run_lines'::regclass
  ) THEN
    ALTER TABLE late_fee_run_lines ADD CONSTRAINT late_fee_run_lines_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'receipt_counters_site_code_fkey' AND conrelid = 'receipt_counters'::regclass
  ) THEN
    ALTER TABLE receipt_counters ADD CONSTRAINT receipt_counters_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'receipts_site_code_fkey' AND conrelid = 'receipts'::regclass
  ) THEN
    ALTER TABLE receipts ADD CONSTRAINT receipts_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'receipt_print_events_site_code_fkey' AND conrelid = 'receipt_print_events'::regclass
  ) THEN
    ALTER TABLE receipt_print_events ADD CONSTRAINT receipt_print_events_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_accounts_site_code_fkey' AND conrelid = 'finance_accounts'::regclass
  ) THEN
    ALTER TABLE finance_accounts ADD CONSTRAINT finance_accounts_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expense_categories_site_code_fkey' AND conrelid = 'expense_categories'::regclass
  ) THEN
    ALTER TABLE expense_categories ADD CONSTRAINT expense_categories_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_suppliers_site_code_fkey' AND conrelid = 'finance_suppliers'::regclass
  ) THEN
    ALTER TABLE finance_suppliers ADD CONSTRAINT finance_suppliers_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expenses_site_code_fkey' AND conrelid = 'expenses'::regclass
  ) THEN
    ALTER TABLE expenses ADD CONSTRAINT expenses_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expense_voids_site_code_fkey' AND conrelid = 'expense_voids'::regclass
  ) THEN
    ALTER TABLE expense_voids ADD CONSTRAINT expense_voids_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'expense_documents_site_code_fkey' AND conrelid = 'expense_documents'::regclass
  ) THEN
    ALTER TABLE expense_documents ADD CONSTRAINT expense_documents_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'account_transfers_site_code_fkey' AND conrelid = 'account_transfers'::regclass
  ) THEN
    ALTER TABLE account_transfers ADD CONSTRAINT account_transfers_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'account_movements_site_code_fkey' AND conrelid = 'account_movements'::regclass
  ) THEN
    ALTER TABLE account_movements ADD CONSTRAINT account_movements_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'account_reconciliations_site_code_fkey' AND conrelid = 'account_reconciliations'::regclass
  ) THEN
    ALTER TABLE account_reconciliations ADD CONSTRAINT account_reconciliations_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_reminder_exclusions_site_code_fkey' AND conrelid = 'finance_reminder_exclusions'::regclass
  ) THEN
    ALTER TABLE finance_reminder_exclusions ADD CONSTRAINT finance_reminder_exclusions_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_reminder_runs_site_code_fkey' AND conrelid = 'finance_reminder_runs'::regclass
  ) THEN
    ALTER TABLE finance_reminder_runs ADD CONSTRAINT finance_reminder_runs_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'finance_reminder_apartments_site_code_fkey' AND conrelid = 'finance_reminder_apartments'::regclass
  ) THEN
    ALTER TABLE finance_reminder_apartments ADD CONSTRAINT finance_reminder_apartments_site_code_fkey FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
  END IF;
END $$;

ALTER TABLE ledger_entries ADD COLUMN IF NOT EXISTS late_fee_run_id BIGINT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_ledger_entries_late_fee_run' AND conrelid = 'ledger_entries'::regclass
  ) THEN
    ALTER TABLE ledger_entries ADD CONSTRAINT fk_ledger_entries_late_fee_run
      FOREIGN KEY (late_fee_run_id) REFERENCES late_fee_runs(id) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_ledger_entries_late_fee' AND conrelid = 'ledger_entries'::regclass
  ) THEN
    ALTER TABLE ledger_entries ADD CONSTRAINT chk_ledger_entries_late_fee CHECK (
      late_fee_run_id IS NULL
      OR (kind IN ('charge', 'reversal') AND (kind = 'reversal' OR (definition_id IS NULL AND run_id IS NULL)))
    ) NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_ledger_entries_late_fee_run' AND conrelid = 'ledger_entries'::regclass AND NOT convalidated
  ) THEN
    ALTER TABLE ledger_entries VALIDATE CONSTRAINT fk_ledger_entries_late_fee_run;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_ledger_entries_late_fee' AND conrelid = 'ledger_entries'::regclass AND NOT convalidated
  ) THEN
    ALTER TABLE ledger_entries VALIDATE CONSTRAINT chk_ledger_entries_late_fee;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_ledger_entries_late_fee_run ON ledger_entries (late_fee_run_id) WHERE late_fee_run_id IS NOT NULL;

ALTER TABLE notification_preferences ADD COLUMN IF NOT EXISTS email_finance_reminders BOOLEAN NOT NULL DEFAULT TRUE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_ledger_entries_late_fee_mirror' AND tgrelid = 'ledger_entries'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER trg_ledger_entries_late_fee_mirror BEFORE INSERT ON ledger_entries FOR EACH ROW WHEN (NEW.kind = 'reversal' AND NEW.reverses_entry_id IS NOT NULL) EXECUTE PROCEDURE trg_ledger_entries_late_fee_mirror();
  END IF;
END $$;
