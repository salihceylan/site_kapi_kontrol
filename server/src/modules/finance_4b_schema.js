// Finans Faz 4b (migration 040) şeması: tek kaynak. `migrations/040_finance_4b.sql` bu adımların SQL'inin birleşimidir (test: finance4b_schema);
// `ensureFinance4bSchema` (db.js `ensureDbSchema` sonunda) AYNI adımları, katalog kontrolüyle ve HER ADIM KENDİ otomatik onaylı ifadesiyle uygular.
//
// Neden dev ensureDbSchema bloğunun İÇİNDE değil: ADD COLUMN / CREATE INDEX / FK'li CREATE TABLE ... IF NOT EXISTS nesne VARKEN bile referans verilen
// tablolarda kilit alır (bloğun tek örtük işleminde kilitler sonuna dek birikir ve açılışta yazıcılarla 40P01 üretir). Burada: eksik olanlar TEK katalog
// sorgusuyla (kilitsiz) belirlenir, yalnız eksik adımlar çalışır; her şey varsa (normal açılış) hiçbir tabloda kilit alınmaz.
//
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Veritabanı". Eklemeli ve idempotent: tablolar `IF NOT EXISTS`, kısıt/tetikleyici/işlevler katalog korumalı
// (işlev gövdesi sürüm işareti taşır: işaret değişirse işlev yenilenir). Mevcut tablolara yalnız EKLEME: ledger_entries.late_fee_run_id (+FK/CHECK
// `NOT VALID` -> `VALIDATE`, uzun kilit yok) ve notification_preferences.email_finance_reminders.
//
// Sözleşmeye göre (belgelenmiş) EK sütunlar: receipts.idempotency_key (iptal tekrarı), receipt_print_events.idempotency_key + site_code,
// late_fee_run_lines.site_code, finance_reminder_runs.run_on (günde 1 çalıştırma kısmi tekil indeksi). Sözleşmedeki
// trg_ledger_entries_reversal_check genişletmesi yerine AYRI ikinci tetikleyici (trg_ledger_entries_late_fee_mirror): 034 işlevi her açılışta dev blokta
// yeniden yazıldığı için onu değiştirmek geçici sürümlere yol açardı.

/** İşlev gövdesine yazılan sürüm işareti (katalog `prosrc` aranır). */
export const F4B_MARKER = 'f4b:2'; // f4b:2: trg_finance_immutable TG_NARGS koruması + late_fee_runs işaret CHECK'leri (R10); f4b:1 ile ensure edilmiş ortamlar yenilenir

const GUARD_TABLES = ['sites', 'users', 'apartments', 'ledger_entries', 'finance_period_closures', 'site_people', 'notification_preferences'];

const has = (table) => `to_regclass('public.${table}') IS NOT NULL`;
const hasIndex = (name) => `EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = '${name}')`;
const hasFunction = (name) =>
  `EXISTS (SELECT 1 FROM pg_proc WHERE proname = '${name}' AND pronamespace = 'public'::regnamespace AND prosrc LIKE '%${F4B_MARKER}%')`;
const hasTrigger = (name, table) =>
  `EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = '${name}' AND tgrelid = to_regclass('public.${table}') AND NOT tgisinternal)`;
const hasConstraint = (name, table) =>
  `EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = to_regclass('public.${table}'))`;
const hasColumn = (table, column) =>
  `EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('public.${table}') AND attname = '${column}' AND NOT attisdropped)`;
const noInvalidConstraint = (names, table) =>
  `NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname IN (${names.map((n) => `'${n}'`).join(', ')}) AND conrelid = to_regclass('public.${table}') AND NOT convalidated)`;

/** Tetikleyici oluşturma (katalog korumalı DO bloğu: migration idempotent). */
function triggerSql(name, table, definition) {
  return `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = '${name}' AND tgrelid = '${table}'::regclass AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER ${name} ${definition};
  END IF;
END $$;`;
}

const steps = [];

// "Sıcak" ebeveyn tablolar: eski uygulama sürümünün yazdığı, FK eklemenin SHARE ROW EXCLUSIVE kilidi aldığı mevcut tablolar. Bir CREATE TABLE ifadesi
// birden fazla sıcak tabloya FK taşırsa kilitleri o ifadenin süresince BİRİKTİRİR (sites -> apartments -> users ...) ve eşzamanlı yazıcılarla (kilit sırası farklı)
// 40P01 üretir (provada ölçüldü: qa_finance4b_upgrade.mjs, "steps" yolu). Bu yüzden sıcak tablolara FK'ler CREATE TABLE'dan AYRI, tek ebeveynli, katalog korumalı
// ifadelerdir: her ifade aynı anda yalnız BİR sıcak tabloyu kilitler (bekleyebilir ama döngü kuramaz). Kısıt adları Postgres'in satır içi FK adlarıyla aynıdır
// (<tablo>_<sütun>_fkey).
const HOT_PARENTS = new Set(['sites', 'users', 'apartments', 'ledger_entries', 'site_people']);
const INLINE_REFERENCE = /^(\s*)(\w+)(\s+[^\n]*?)\s+REFERENCES\s+(\w+)\((\w+)\)((?:\s+ON DELETE (?:CASCADE|SET NULL))?)(,?)[ \t]*$/gm;

const hotForeignKeySql = ({ table: owner, column, parent, parentColumn, onDelete }) => {
  const name = `${owner}_${column}_fkey`;
  return `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${owner}'::regclass
  ) THEN
    ALTER TABLE ${owner} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn})${onDelete ? ` ${onDelete}` : ''};
  END IF;
END $$;`;
};

const table = (name, sql) => {
  const hot = [];
  const stripped = sql.replace(INLINE_REFERENCE, (line, indent, column, rest, parent, parentColumn, onDelete, comma) => {
    if (!HOT_PARENTS.has(parent)) {
      return line;
    }
    hot.push({ table: name, column, parent, parentColumn, onDelete: onDelete.trim() });
    return `${indent}${column}${rest}${comma}`;
  });
  steps.push({ id: `table:${name}`, kind: 'table', name, exists: has(name), sql: stripped });
  for (const foreignKey of hot) {
    steps.push({
      id: `fk:${foreignKey.table}.${foreignKey.column}`,
      kind: 'step',
      parent: foreignKey.parent,
      exists: hasConstraint(`${foreignKey.table}_${foreignKey.column}_fkey`, foreignKey.table),
      sql: hotForeignKeySql(foreignKey),
    });
  }
};
const step = (id, exists, sql) => steps.push({ id, kind: 'step', exists, sql });
const fn = (name, sql) => step(`function:${name}`, hasFunction(name), sql);
const trigger = (name, onTable, definition) => {
  step(`trigger:${name}`, hasTrigger(name, onTable), triggerSql(name, onTable, definition));
  steps[steps.length - 1].hot = HOT_PARENTS.has(onTable);
};

// --- 1. Ayarlar -----------------------------------------------------------------------------------------------------------------------------

table(
  'finance_settings',
  `CREATE TABLE IF NOT EXISTS finance_settings (
  site_code BIGINT PRIMARY KEY REFERENCES sites(site_code) ON DELETE CASCADE,
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
  updated_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
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
CREATE INDEX IF NOT EXISTS idx_finance_settings_updated_by ON finance_settings (updated_by) WHERE updated_by IS NOT NULL;`,
);

// --- 2. Gecikme tazminatı --------------------------------------------------------------------------------------------------------------------

table(
  'late_fee_runs',
  `CREATE TABLE IF NOT EXISTS late_fee_runs (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
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
  posted_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  voided_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
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
CREATE INDEX IF NOT EXISTS idx_late_fee_runs_voided_by ON late_fee_runs (voided_by) WHERE voided_by IS NOT NULL;`,
);

// f4b:1 şemasıyla ensure edilmiş (dev / QA / prova) ortamlarda late_fee_runs CHECK'leri ESKİ tanımdadır (total_minor > 0, apartment_count > 0; işaret CHECK'i yok):
// CREATE TABLE IF NOT EXISTS mevcut tabloyu değiştirmez. Tanım farklıysa DROP + ADD ... NOT VALID -> VALIDATE (tablo yalnız 4b kodunca yazılır; kısa). Taze kurulumda no-op.
const lateFeeCheck = (name, fragment) =>
  `EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = to_regclass('public.late_fee_runs') AND pg_get_constraintdef(oid) LIKE '%${fragment}%')`;
step(
  'check:late_fee_runs',
  `${lateFeeCheck('chk_late_fee_runs_total', 'total_minor >= 0')} AND ${lateFeeCheck('chk_late_fee_runs_counts', 'apartment_count >= 0')} AND ${hasConstraint('chk_late_fee_runs_marker', 'late_fee_runs')}`,
  `DO $$
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
END $$;`,
);

table(
  'late_fee_run_lines',
  `CREATE TABLE IF NOT EXISTS late_fee_run_lines (
  run_id BIGINT NOT NULL REFERENCES late_fee_runs(id),
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  apartment_id BIGINT NOT NULL,
  apartment_label TEXT NOT NULL,
  amount_minor BIGINT NOT NULL,
  base_day_minor BIGINT NOT NULL,
  peak_overdue_minor BIGINT NOT NULL,
  breakdown JSONB NOT NULL,
  ledger_entry_id BIGINT NOT NULL REFERENCES ledger_entries(id),
  PRIMARY KEY (run_id, apartment_id),
  CONSTRAINT chk_late_fee_run_lines_amount CHECK (amount_minor > 0 AND base_day_minor > 0 AND peak_overdue_minor > 0),
  CONSTRAINT chk_late_fee_run_lines_label CHECK (char_length(apartment_label) BETWEEN 1 AND 300),
  CONSTRAINT chk_late_fee_run_lines_breakdown CHECK (jsonb_typeof(breakdown) = 'array' AND jsonb_array_length(breakdown) <= 62)
);
CREATE INDEX IF NOT EXISTS idx_late_fee_run_lines_ledger ON late_fee_run_lines (ledger_entry_id);
CREATE INDEX IF NOT EXISTS idx_late_fee_run_lines_site ON late_fee_run_lines (site_code);`,
);

// ledger_entries: yalnız EKLEME. Her adım kendi otomatik onaylı ifadesi (uzun kilit tutulmaz).
step(
  'ledger:column',
  hasColumn('ledger_entries', 'late_fee_run_id'),
  `ALTER TABLE ledger_entries ADD COLUMN IF NOT EXISTS late_fee_run_id BIGINT;`,
);
step(
  'ledger:fk',
  hasConstraint('fk_ledger_entries_late_fee_run', 'ledger_entries'),
  `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_ledger_entries_late_fee_run' AND conrelid = 'ledger_entries'::regclass
  ) THEN
    ALTER TABLE ledger_entries ADD CONSTRAINT fk_ledger_entries_late_fee_run
      FOREIGN KEY (late_fee_run_id) REFERENCES late_fee_runs(id) NOT VALID;
  END IF;
END $$;`,
);
step(
  'ledger:check',
  hasConstraint('chk_ledger_entries_late_fee', 'ledger_entries'),
  `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_ledger_entries_late_fee' AND conrelid = 'ledger_entries'::regclass
  ) THEN
    ALTER TABLE ledger_entries ADD CONSTRAINT chk_ledger_entries_late_fee CHECK (
      late_fee_run_id IS NULL
      OR (kind IN ('charge', 'reversal') AND (kind = 'reversal' OR (definition_id IS NULL AND run_id IS NULL)))
    ) NOT VALID;
  END IF;
END $$;`,
);
step(
  'ledger:validate',
  noInvalidConstraint(['fk_ledger_entries_late_fee_run', 'chk_ledger_entries_late_fee'], 'ledger_entries'),
  `DO $$
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
END $$;`,
);
step(
  'ledger:index',
  hasIndex('idx_ledger_entries_late_fee_run'),
  `CREATE INDEX IF NOT EXISTS idx_ledger_entries_late_fee_run ON ledger_entries (late_fee_run_id) WHERE late_fee_run_id IS NOT NULL;`,
);

// --- 3. Makbuz ---------------------------------------------------------------------------------------------------------------------------------

table(
  'receipt_counters',
  `CREATE TABLE IF NOT EXISTS receipt_counters (
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  receipt_year SMALLINT NOT NULL,
  last_no INTEGER NOT NULL,
  PRIMARY KEY (site_code, receipt_year),
  CONSTRAINT chk_receipt_counters_last CHECK (last_no >= 1),
  CONSTRAINT chk_receipt_counters_year CHECK (receipt_year BETWEEN 2000 AND 2100)
);`,
);

table(
  'receipts',
  `CREATE TABLE IF NOT EXISTS receipts (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  receipt_year SMALLINT NOT NULL,
  receipt_no INTEGER NOT NULL,
  kind TEXT NOT NULL,
  ledger_entry_id BIGINT NOT NULL REFERENCES ledger_entries(id),
  cancels_receipt_id BIGINT REFERENCES receipts(id),
  apartment_id BIGINT NOT NULL REFERENCES apartments(id),
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
  issued_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
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
CREATE INDEX IF NOT EXISTS idx_receipts_issued_by ON receipts (issued_by) WHERE issued_by IS NOT NULL;`,
);

table(
  'receipt_print_events',
  `CREATE TABLE IF NOT EXISTS receipt_print_events (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  receipt_id BIGINT NOT NULL REFERENCES receipts(id),
  copy_number INTEGER NOT NULL,
  idempotency_key TEXT,
  printed_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  printed_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT uq_receipt_print_events_copy UNIQUE (receipt_id, copy_number),
  CONSTRAINT chk_receipt_print_events_copy CHECK (copy_number >= 1),
  CONSTRAINT chk_receipt_print_events_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) BETWEEN 1 AND 64)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_receipt_print_events_idempotency ON receipt_print_events (receipt_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_receipt_print_events_site ON receipt_print_events (site_code);
CREATE INDEX IF NOT EXISTS idx_receipt_print_events_printed_by ON receipt_print_events (printed_by) WHERE printed_by IS NOT NULL;`,
);

// --- 4. Kasa / banka ------------------------------------------------------------------------------------------------------------------------

table(
  'finance_accounts',
  `CREATE TABLE IF NOT EXISTS finance_accounts (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  name TEXT NOT NULL,
  kind TEXT NOT NULL,
  note TEXT,
  opening_date DATE NOT NULL,
  opening_balance_minor BIGINT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  idempotency_key TEXT,
  created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
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
CREATE INDEX IF NOT EXISTS idx_finance_accounts_created_by ON finance_accounts (created_by) WHERE created_by IS NOT NULL;`,
);

table(
  'expense_categories',
  `CREATE TABLE IF NOT EXISTS expense_categories (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  name TEXT NOT NULL,
  is_system BOOLEAN NOT NULL DEFAULT FALSE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_expense_categories_name CHECK (char_length(name) BETWEEN 1 AND 60)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_expense_categories_name ON expense_categories (site_code, lower(name));`,
);

table(
  'finance_suppliers',
  `CREATE TABLE IF NOT EXISTS finance_suppliers (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  name TEXT NOT NULL,
  tax_id TEXT,
  phone TEXT,
  note TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_finance_suppliers_name CHECK (char_length(name) BETWEEN 1 AND 100),
  CONSTRAINT chk_finance_suppliers_tax CHECK (tax_id IS NULL OR tax_id ~ '^[0-9]{10,11}$'),
  CONSTRAINT chk_finance_suppliers_phone CHECK (phone IS NULL OR char_length(phone) <= 20),
  CONSTRAINT chk_finance_suppliers_note CHECK (note IS NULL OR char_length(note) <= 200)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_suppliers_name ON finance_suppliers (site_code, lower(name));
CREATE INDEX IF NOT EXISTS idx_finance_suppliers_created_by ON finance_suppliers (created_by) WHERE created_by IS NOT NULL;`,
);

table(
  'expenses',
  `CREATE TABLE IF NOT EXISTS expenses (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
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
  created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
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
CREATE INDEX IF NOT EXISTS idx_expenses_created_by ON expenses (created_by) WHERE created_by IS NOT NULL;`,
);

table(
  'expense_voids',
  `CREATE TABLE IF NOT EXISTS expense_voids (
  expense_id BIGINT PRIMARY KEY REFERENCES expenses(id),
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  reason TEXT NOT NULL,
  period DATE NOT NULL,
  voided_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  voided_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_expense_voids_reason CHECK (char_length(reason) BETWEEN 1 AND 200),
  CONSTRAINT chk_expense_voids_period CHECK (EXTRACT(DAY FROM period) = 1)
);
CREATE INDEX IF NOT EXISTS idx_expense_voids_site ON expense_voids (site_code, period);
CREATE INDEX IF NOT EXISTS idx_expense_voids_voided_by ON expense_voids (voided_by) WHERE voided_by IS NOT NULL;`,
);

table(
  'expense_documents',
  `CREATE TABLE IF NOT EXISTS expense_documents (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
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
  added_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  removed_at TIMESTAMPTZ,
  removed_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
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
CREATE INDEX IF NOT EXISTS idx_expense_documents_removed_by ON expense_documents (removed_by) WHERE removed_by IS NOT NULL;`,
);

table(
  'account_transfers',
  `CREATE TABLE IF NOT EXISTS account_transfers (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  from_account_id BIGINT NOT NULL REFERENCES finance_accounts(id),
  to_account_id BIGINT NOT NULL REFERENCES finance_accounts(id),
  amount_minor BIGINT NOT NULL,
  transfer_date DATE NOT NULL,
  description TEXT,
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
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
CREATE INDEX IF NOT EXISTS idx_account_transfers_created_by ON account_transfers (created_by) WHERE created_by IS NOT NULL;`,
);

table(
  'account_movements',
  `CREATE TABLE IF NOT EXISTS account_movements (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  account_id BIGINT NOT NULL REFERENCES finance_accounts(id),
  kind TEXT NOT NULL,
  amount_minor BIGINT NOT NULL,
  movement_date DATE NOT NULL,
  period DATE NOT NULL,
  ledger_entry_id BIGINT REFERENCES ledger_entries(id),
  expense_id BIGINT REFERENCES expenses(id),
  transfer_id BIGINT REFERENCES account_transfers(id),
  reverses_movement_id BIGINT REFERENCES account_movements(id),
  reason_code TEXT,
  note TEXT,
  idempotency_key TEXT,
  created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
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
CREATE INDEX IF NOT EXISTS idx_account_movements_created_by ON account_movements (created_by) WHERE created_by IS NOT NULL;`,
);

table(
  'account_reconciliations',
  `CREATE TABLE IF NOT EXISTS account_reconciliations (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  account_id BIGINT NOT NULL REFERENCES finance_accounts(id),
  as_of_date DATE NOT NULL,
  statement_balance_minor BIGINT NOT NULL,
  computed_balance_minor BIGINT NOT NULL,
  difference_minor BIGINT NOT NULL,
  adjustment_movement_id BIGINT REFERENCES account_movements(id),
  note TEXT,
  idempotency_key TEXT NOT NULL,
  reconciled_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  reconciled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_account_reconciliations_difference CHECK (difference_minor = statement_balance_minor - computed_balance_minor),
  CONSTRAINT chk_account_reconciliations_note CHECK (note IS NULL OR char_length(note) <= 200),
  CONSTRAINT chk_account_reconciliations_key CHECK (char_length(idempotency_key) BETWEEN 1 AND 64),
  CONSTRAINT uq_account_reconciliations_idempotency UNIQUE (site_code, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_account_reconciliations_account ON account_reconciliations (account_id, as_of_date DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_account_reconciliations_adjustment ON account_reconciliations (adjustment_movement_id) WHERE adjustment_movement_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_account_reconciliations_by ON account_reconciliations (reconciled_by) WHERE reconciled_by IS NOT NULL;`,
);

// --- 5. Hatırlatma ---------------------------------------------------------------------------------------------------------------------------

table(
  'finance_reminder_exclusions',
  `CREATE TABLE IF NOT EXISTS finance_reminder_exclusions (
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  apartment_id BIGINT NOT NULL REFERENCES apartments(id) ON DELETE CASCADE,
  reason TEXT,
  created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (site_code, apartment_id),
  CONSTRAINT chk_finance_reminder_exclusions_reason CHECK (reason IS NULL OR char_length(reason) <= 100)
);
CREATE INDEX IF NOT EXISTS idx_finance_reminder_exclusions_apartment ON finance_reminder_exclusions (apartment_id);
CREATE INDEX IF NOT EXISTS idx_finance_reminder_exclusions_by ON finance_reminder_exclusions (created_by) WHERE created_by IS NOT NULL;`,
);

table(
  'finance_reminder_runs',
  `CREATE TABLE IF NOT EXISTS finance_reminder_runs (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
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
  created_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  cancelled_by INTEGER REFERENCES users(user_code) ON DELETE SET NULL,
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
CREATE INDEX IF NOT EXISTS idx_finance_reminder_runs_cancelled_by ON finance_reminder_runs (cancelled_by) WHERE cancelled_by IS NOT NULL;`,
);

table(
  'finance_reminder_items',
  `CREATE TABLE IF NOT EXISTS finance_reminder_items (
  run_id BIGINT NOT NULL REFERENCES finance_reminder_runs(id) ON DELETE CASCADE,
  person_id BIGINT NOT NULL REFERENCES site_people(id) ON DELETE CASCADE,
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
CREATE INDEX IF NOT EXISTS idx_finance_reminder_items_person ON finance_reminder_items (person_id);`,
);

table(
  'finance_reminder_apartments',
  `CREATE TABLE IF NOT EXISTS finance_reminder_apartments (
  site_code BIGINT NOT NULL REFERENCES sites(site_code) ON DELETE CASCADE,
  apartment_id BIGINT NOT NULL REFERENCES apartments(id) ON DELETE CASCADE,
  run_id BIGINT NOT NULL REFERENCES finance_reminder_runs(id) ON DELETE CASCADE,
  reminded_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (apartment_id, run_id)
);
CREATE INDEX IF NOT EXISTS idx_finance_reminder_apartments_recent ON finance_reminder_apartments (site_code, apartment_id, reminded_at DESC);
CREATE INDEX IF NOT EXISTS idx_finance_reminder_apartments_run ON finance_reminder_apartments (run_id);`,
);

step(
  'column:notification_preferences.email_finance_reminders',
  hasColumn('notification_preferences', 'email_finance_reminders'),
  `ALTER TABLE notification_preferences ADD COLUMN IF NOT EXISTS email_finance_reminders BOOLEAN NOT NULL DEFAULT TRUE;`,
);

// --- 6. Değişmezlik ve bütünlük tetikleyicileri ------------------------------------------------------------------------------------------------

// Genel değişmez tablo koruması: UPDATE/DELETE hata; istisnalar: DELETE yalnız üst sites satırı artık yoksa (site silme CASCADE); UPDATE yalnız TG_ARGV'deki
// `*_by` sütunlarından BİRİNİ NULL'a çevirir VE kullanıcı artık yoksa (users silme ON DELETE SET NULL eylemi; başka hiçbir sütun değişmez).
fn(
  'trg_finance_immutable',
  `CREATE OR REPLACE FUNCTION trg_finance_immutable() RETURNS trigger AS $$
-- ${F4B_MARKER}
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
$$ LANGUAGE plpgsql;`,
);

// Durum geçişli tablolar için ortak koruma: TG_ARGV[0] = 'transition' kuralı adı yerine işlev başına ayrı yazılır (okunabilirlik).
fn(
  'trg_late_fee_runs_guard',
  `CREATE OR REPLACE FUNCTION trg_late_fee_runs_guard() RETURNS trigger AS $$
-- ${F4B_MARKER}
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
$$ LANGUAGE plpgsql;`,
);

// Zincir koruması: yeni aktif çalıştırmanın dönemi = (aktif çalıştırmaların en büyük dönemi) + 1 ay (hiç yoksa ayarlardaki başlangıç ayı); ay KAPALI olmalı.
fn(
  'trg_late_fee_runs_chain',
  `CREATE OR REPLACE FUNCTION trg_late_fee_runs_chain() RETURNS trigger AS $$
-- ${F4B_MARKER}
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
$$ LANGUAGE plpgsql;`,
);

// Satırlar toplamı = çalıştırma toplamı (ifade başına bir kez; geçişli tablo) ve her satır kendi defter kaydıyla tutarlı.
fn(
  'trg_late_fee_run_lines_check',
  `CREATE OR REPLACE FUNCTION trg_late_fee_run_lines_check() RETURNS trigger AS $$
-- ${F4B_MARKER}
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
$$ LANGUAGE plpgsql;`,
);

// Ters kaydın late_fee_run_id'si asılınkiyle AYNI olmalı (034 ayna tetikleyicisine EK, ayrı tetikleyici).
fn(
  'trg_ledger_entries_late_fee_mirror',
  `CREATE OR REPLACE FUNCTION trg_ledger_entries_late_fee_mirror() RETURNS trigger AS $$
-- ${F4B_MARKER}
DECLARE
  original_run BIGINT;
BEGIN
  SELECT late_fee_run_id INTO original_run FROM ledger_entries WHERE id = NEW.reverses_entry_id;
  IF NEW.late_fee_run_id IS DISTINCT FROM original_run THEN
    RAISE EXCEPTION 'finance reversal must keep the late fee run of its original entry';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;`,
);

fn(
  'trg_receipt_counters_guard',
  `CREATE OR REPLACE FUNCTION trg_receipt_counters_guard() RETURNS trigger AS $$
-- ${F4B_MARKER}
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
$$ LANGUAGE plpgsql;`,
);

fn(
  'trg_receipts_insert_check',
  `CREATE OR REPLACE FUNCTION trg_receipts_insert_check() RETURNS trigger AS $$
-- ${F4B_MARKER}
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
$$ LANGUAGE plpgsql;`,
);

fn(
  'trg_finance_accounts_guard',
  `CREATE OR REPLACE FUNCTION trg_finance_accounts_guard() RETURNS trigger AS $$
-- ${F4B_MARKER}
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
$$ LANGUAGE plpgsql;`,
);

fn(
  'trg_finance_settings_guard',
  `CREATE OR REPLACE FUNCTION trg_finance_settings_guard() RETURNS trigger AS $$
-- ${F4B_MARKER}
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
$$ LANGUAGE plpgsql;`,
);

fn(
  'trg_expense_documents_guard',
  `CREATE OR REPLACE FUNCTION trg_expense_documents_guard() RETURNS trigger AS $$
-- ${F4B_MARKER}
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
$$ LANGUAGE plpgsql;`,
);

fn(
  'trg_finance_reminder_runs_guard',
  `CREATE OR REPLACE FUNCTION trg_finance_reminder_runs_guard() RETURNS trigger AS $$
-- ${F4B_MARKER}
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
$$ LANGUAGE plpgsql;`,
);

fn(
  'trg_account_movements_check',
  `CREATE OR REPLACE FUNCTION trg_account_movements_check() RETURNS trigger AS $$
-- ${F4B_MARKER}
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
$$ LANGUAGE plpgsql;`,
);

// Tetikleyiciler -------------------------------------------------------------------------------------------------------------------------------

const IMMUTABLE = [
  ['receipts', 'issued_by'],
  ['receipt_print_events', 'printed_by'],
  ['late_fee_run_lines', null],
  ['expenses', 'created_by'],
  ['expense_voids', 'voided_by'],
  ['account_movements', 'created_by'],
  ['account_transfers', 'created_by'],
  ['account_reconciliations', 'reconciled_by'],
];
for (const [name, byColumn] of IMMUTABLE) {
  trigger(
    `trg_${name}_immutable`,
    name,
    `BEFORE UPDATE OR DELETE ON ${name} FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable(${byColumn === null ? '' : `'${byColumn}'`})`,
  );
}
trigger('trg_late_fee_runs_guard', 'late_fee_runs', 'BEFORE UPDATE OR DELETE ON late_fee_runs FOR EACH ROW EXECUTE PROCEDURE trg_late_fee_runs_guard()');
trigger('trg_late_fee_runs_chain', 'late_fee_runs', 'BEFORE INSERT ON late_fee_runs FOR EACH ROW EXECUTE PROCEDURE trg_late_fee_runs_chain()');
trigger(
  'trg_late_fee_run_lines_check',
  'late_fee_run_lines',
  'AFTER INSERT ON late_fee_run_lines REFERENCING NEW TABLE AS new_lines FOR EACH STATEMENT EXECUTE PROCEDURE trg_late_fee_run_lines_check()',
);
trigger(
  'trg_ledger_entries_late_fee_mirror',
  'ledger_entries',
  "BEFORE INSERT ON ledger_entries FOR EACH ROW WHEN (NEW.kind = 'reversal' AND NEW.reverses_entry_id IS NOT NULL) EXECUTE PROCEDURE trg_ledger_entries_late_fee_mirror()",
);
trigger('trg_receipt_counters_guard', 'receipt_counters', 'BEFORE UPDATE OR DELETE ON receipt_counters FOR EACH ROW EXECUTE PROCEDURE trg_receipt_counters_guard()');
trigger('trg_receipts_insert_check', 'receipts', 'BEFORE INSERT ON receipts FOR EACH ROW EXECUTE PROCEDURE trg_receipts_insert_check()');
trigger('trg_finance_accounts_guard', 'finance_accounts', 'BEFORE UPDATE OR DELETE ON finance_accounts FOR EACH ROW EXECUTE PROCEDURE trg_finance_accounts_guard()');
trigger('trg_finance_settings_guard', 'finance_settings', 'BEFORE UPDATE ON finance_settings FOR EACH ROW EXECUTE PROCEDURE trg_finance_settings_guard()');
trigger('trg_expense_documents_guard', 'expense_documents', 'BEFORE UPDATE OR DELETE ON expense_documents FOR EACH ROW EXECUTE PROCEDURE trg_expense_documents_guard()');
trigger(
  'trg_finance_reminder_runs_guard',
  'finance_reminder_runs',
  'BEFORE UPDATE OR DELETE ON finance_reminder_runs FOR EACH ROW EXECUTE PROCEDURE trg_finance_reminder_runs_guard()',
);
trigger('trg_account_movements_check', 'account_movements', 'BEFORE INSERT ON account_movements FOR EACH ROW EXECUTE PROCEDURE trg_account_movements_check()');

// TRUNCATE engeli (034 işlevi trg_finance_block_truncate yeniden kullanılır; dev blokta oluşur).
const NO_TRUNCATE = [
  'late_fee_runs',
  'late_fee_run_lines',
  'receipt_counters',
  'receipts',
  'receipt_print_events',
  'expenses',
  'expense_voids',
  'expense_documents',
  'account_movements',
  'account_transfers',
  'account_reconciliations',
];
for (const name of NO_TRUNCATE) {
  trigger(`trg_${name}_no_truncate`, name, `BEFORE TRUNCATE ON ${name} FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate()`);
}

// SIRA (kilit penceresi): 0) yalnız YENİ nesneler (tablolar, indeksler, işlevler, yeni tablolardaki tetikleyiciler) -> 1) sıcak tablolara FK'ler (sabit ebeveyn
// sırası, adım başına tek ebeveyn) -> 2) mevcut tablolardaki değişiklikler (ledger_entries sütun/kısıt/indeks/tetikleyici, notification_preferences sütunu).
// migrate.js 040'ı TEK işlemde çalıştırır: sıcak tablo kilitleri yalnız 1-2. aşamada alınır, işlem sonuna kadar tutulan pencere kısa kalır; ensure yolunda her adım zaten kendi onayıdır.
// Aşama 1 sırası: users, apartments, site_people, ledger_entries, EN SON sites (en çok başvurulan ebeveyn; eski yazıcıların çoğu önce users/apartments, sonra sites satırını günceller:
// sites kilidini en geç almak, yazıcılarla ters sırada bekleme döngüsü kurma olasılığını azaltır). Ölçüm: scripts/qa_finance4b_upgrade.mjs (8 eşzamanlı yazıcı, 10 deneme).
const PARENT_RANK = ['users', 'apartments', 'site_people', 'ledger_entries', 'sites'];
const phaseOf = (entry) => {
  if (entry.id.startsWith('fk:')) return 1;
  if (entry.id.startsWith('ledger:') || entry.id.startsWith('column:') || entry.hot === true) return 2;
  return 0;
};
const ordered = steps
  .map((entry, index) => ({ entry, index }))
  .sort((a, b) => phaseOf(a.entry) - phaseOf(b.entry) || (phaseOf(a.entry) === 1 ? PARENT_RANK.indexOf(a.entry.parent) - PARENT_RANK.indexOf(b.entry.parent) : 0) || a.index - b.index)
  .map(({ entry }) => entry);

export const FINANCE_4B_STEPS = Object.freeze(ordered.map((entry) => Object.freeze({ ...entry })));
export const FINANCE_4B_TABLES = Object.freeze(steps.filter((entry) => entry.kind === 'table').map((entry) => entry.name));

/** 040 migration dosyasının gövdesi (adımların SQL'i, sırayla). */
export function financeMigrationSql() {
  return FINANCE_4B_STEPS.map((entry) => entry.sql).join('\n\n');
}

/**
 * 040'ı uygular (db.js `ensureDbSchema` sonu). Ön koşul tabloları yoksa (platform öncesi kesilmiş şema) HİÇBİR ŞEY yapmaz. Normal açılışta (her şey var)
 * yalnız tek katalog sorgusu çalışır ve hiçbir tabloda kilit alınmaz. Eksik adımlar sırayla, HER BİRİ kendi otomatik onaylı ifadesiyle çalışır.
 * @param {{ query: Function }} client
 * @returns {Promise<string[]>} uygulanan adım kimlikleri
 */
const LOCK_TIMEOUT = '3s';
const MAX_ATTEMPTS = 6;
const RETRYABLE = new Set(['55P03', '40P01']);

/** Test ayarı: yeniden deneme beklemesi. */
export const schemaHooks = {
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
};

/**
 * Tek adım (kendi otomatik onaylı ifadesi): kilit zaman aşımında (55P03) ya da deadlock'ta (40P01) bekleyip yeniden dener (en çok 6 deneme). Adımlar katalog korumalı ve
 * idempotent olduğundan yeniden deneme güvenlidir. lock_timeout (3 sn) çağıran tarafından, YALNIZ eksik adım varken kurulur: uzun bir işlemin arkasında bekleyen bir DDL
 * (örn. ACCESS EXCLUSIVE isteyen ALTER) arkasındaki TÜM yazıcıları tıkardı.
 */
async function runStep(client, sql) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await client.query(sql);
      return;
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= MAX_ATTEMPTS) {
        throw error;
      }
      await schemaHooks.sleep(200 * attempt);
    }
  }
}

export async function ensureFinance4bSchema(client) {
  const guards = GUARD_TABLES.map((name) => `${has(name)} AS g_${name}`).join(', ');
  const stepColumns = FINANCE_4B_STEPS.map((entry, index) => `(${entry.exists}) AS s${index}`).join(', ');
  const applied = [];
  let timeoutSet = false;
  try {
    // Katalog anlık görüntüsü adımlardan ÖNCE alınır; sonradan oluşan nesnelere bağlı adımlar (VALIDATE) bir sonraki turda yakalanır (en çok 3 tur).
    for (let pass = 0; pass < 3; pass += 1) {
      const found = await client.query(`SELECT ${guards}, ${stepColumns}`);
      const row = found.rows?.[0] ?? {};
      if (GUARD_TABLES.some((name) => row[`g_${name}`] !== true)) {
        return applied;
      }
      let ran = 0;
      for (const [index, entry] of FINANCE_4B_STEPS.entries()) {
        if (row[`s${index}`] === true) {
          continue; // katalogda varsa ALTER / CREATE'e HİÇ girilmez (normal açılışta kilit yok)
        }
        if (!timeoutSet) {
          await client.query(`SET lock_timeout = '${LOCK_TIMEOUT}'`);
          timeoutSet = true;
        }
        await runStep(client, entry.sql);
        applied.push(entry.id);
        ran += 1;
      }
      if (ran === 0) {
        break;
      }
    }
    return applied;
  } finally {
    if (timeoutSet) {
      await client.query('RESET lock_timeout').catch(() => {}); // oturum düzeyi ayar havuz bağlantısında kalmasın
    }
  }
}
