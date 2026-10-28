// Alacak iadesi (migration 088, karar K4 / P1-4) şeması: tek kaynak. `migrations/088_finance_refunds.sql` bu adımların SQL'inin birleşimidir (test: finance_refunds_schema);
// `ensureFinanceRefundsSchema` (db.js `ensureDbSchema` sonunda, 080'den sonra) AYNI adımları katalog kontrolüyle ve HER ADIM KENDİ otomatik onaylı ifadesiyle uygular.
//
// Model (docs/PLATFORM_FINANS.md "Alacak iadesi"): fazla ödeme varsayılan olarak ALACAK kalır ve sonraki borçtan düşer. İade ISTEĞE BAĞLIDIR: sakin (ya da yönetici sakin adına)
// talep açar -> YÖNETİCİ onaylar / reddeder -> onayda TEK işlemde: (1) defterde avansı tüketen `charge` (source_kind = 'refund', source_id = iade), (2) seçilen kasa / banka hesabından
// çıkış hareketi (account_movements.kind = 'refund', negatif), (3) iade makbuzu (IA-yıl-sıra; değişmez anlık görüntü + doğrulama kodu). Geri alma = ters kayıt + ayna hareket.
//  - finance_refunds: durum makinesi (requested -> approved | rejected | cancelled; approved -> reversed). Tetikleyici: çekirdek sütunlar değişmez, yalnız izinli geçişler, onaylı
//    satırın defter kaydı + hesap hareketi tutar / hesap / daire açısından DB'de de doğrulanır, silinemez (site silinince CASCADE hariç).
//  - finance_refund_counters: iade makbuzu sayacı (site + yıl; boşluksuz, işlemle birlikte geri döner). Mevcut `trg_receipt_counters_guard` işlevi (yalnız +1) yeniden kullanılır.
//  - account_movements: `refund_id` sütunu + `refund` türü (negatif) için kind / sign / source CHECK'leri TEK ALTER ile yenilenir (NOT VALID, ayrı adımda VALIDATE).
//    `trg_account_movements_check` / `trg_finance_immutable` işlevleri (f4b işaretli) DÜZENLENMEZ: iade hareketi için YENİ bir işlev kurulur.
//  - ledger_entries.source_kind CHECK'i 'refund' ve 'liability_transfer' (089) değerlerini de kabul eder (birikimli liste; önceki değerler korunur).
// SIRA (kilit penceresi): yalnız yeni işlevler / tablolar -> hesap hareketleri -> EN SONDA sıcak ledger_entries (her adım kendi kısa kilidi).
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

/** İşlev gövdesine yazılan sürüm işareti (katalog `prosrc` aranır): değişirse işlevler yenilenir. */
export const FINANCE_REFUNDS_MARKER = 'fr:1';

export const FINANCE_REFUNDS_GUARD_TABLES = Object.freeze(['ledger_entries', 'account_movements', 'finance_accounts', 'apartments', 'sites', 'users']);

/** ledger_entries.source_kind izinli değerleri (birikimli; 052'nin beş değeri + 088 + 089). */
export const LEDGER_SOURCE_KINDS = Object.freeze(['manual', 'payment_notice', 'bank_line', 'opening', 'card', 'refund', 'liability_transfer']);

export const REFUND_STATUSES = Object.freeze(['requested', 'approved', 'rejected', 'cancelled', 'reversed']);

const hasTable = (name) => `to_regclass('public.${name}') IS NOT NULL`;
const hasIndex = (name) => `EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = '${name}')`;
const hasFunction = (name) =>
  `EXISTS (SELECT 1 FROM pg_proc WHERE proname = '${name}' AND pronamespace = 'public'::regnamespace AND prosrc LIKE '%${FINANCE_REFUNDS_MARKER}%')`;
const hasTrigger = (name, table) =>
  `EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = '${name}' AND tgrelid = to_regclass('public.${table}') AND NOT tgisinternal)`;
const hasConstraint = (name, table) => `EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = to_regclass('public.${table}'))`;
const hasColumn = (table, column) =>
  `EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('public.${table}') AND attname = '${column}' AND NOT attisdropped)`;
const allValid = (names, table) =>
  `NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname IN (${names.map((n) => `'${n}'`).join(', ')}) AND conrelid = to_regclass('public.${table}') AND NOT convalidated)`;
/** CHECK kısıtının tanımı verilen metni taşıyor mu (yenilenmiş mi). */
const constraintMentions = (name, table, text) =>
  `EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = to_regclass('public.${table}') AND pg_get_constraintdef(oid) LIKE '%${text}%')`;

/** NOT VALID kısıtları doğrular (yalnız doğrulanmamışsa; SHARE UPDATE EXCLUSIVE). */
function validateSql(table, names) {
  const body = names
    .map(
      (name) => `  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass AND NOT convalidated
  ) THEN
    ALTER TABLE ${table} VALIDATE CONSTRAINT ${name};
  END IF;`,
    )
    .join('\n');
  return `DO $$
BEGIN
${body}
END $$;`;
}

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

function foreignKeySql(table, name, column, parent, parentColumn, action) {
  return `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass
  ) THEN
    ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE ${action};
  END IF;
END $$;`;
}

const sqlList = (values) => values.map((value) => `'${value}'`).join(', ');

// account_movements: yenilenen CHECK gövdeleri (eski gövdeler + 'refund' türü; diğer türlerde refund_id boş olmalı).
const MOVEMENT_KIND_CHECK = `kind IN ('opening', 'collection', 'expense', 'transfer_out', 'transfer_in', 'adjustment', 'reversal', 'refund')`;
const MOVEMENT_SIGN_CHECK = `(kind = 'collection' AND amount_minor > 0)
    OR (kind = 'expense' AND amount_minor < 0)
    OR (kind = 'transfer_out' AND amount_minor < 0)
    OR (kind = 'transfer_in' AND amount_minor > 0)
    OR (kind = 'refund' AND amount_minor < 0)
    OR kind IN ('opening', 'adjustment', 'reversal')`;
const MOVEMENT_SOURCE_CHECK = `(kind = 'collection' AND ledger_entry_id IS NOT NULL AND expense_id IS NULL AND transfer_id IS NULL AND reverses_movement_id IS NULL AND refund_id IS NULL)
    OR (kind = 'expense' AND expense_id IS NOT NULL AND ledger_entry_id IS NULL AND transfer_id IS NULL AND reverses_movement_id IS NULL AND refund_id IS NULL)
    OR (kind IN ('transfer_out', 'transfer_in') AND transfer_id IS NOT NULL AND ledger_entry_id IS NULL AND expense_id IS NULL AND reverses_movement_id IS NULL AND refund_id IS NULL)
    OR (kind = 'reversal' AND reverses_movement_id IS NOT NULL AND ledger_entry_id IS NULL AND expense_id IS NULL AND transfer_id IS NULL AND refund_id IS NULL)
    OR (kind IN ('opening', 'adjustment') AND ledger_entry_id IS NULL AND expense_id IS NULL AND transfer_id IS NULL AND reverses_movement_id IS NULL AND refund_id IS NULL)
    OR (kind = 'refund' AND refund_id IS NOT NULL AND ledger_entry_id IS NULL AND expense_id IS NULL AND transfer_id IS NULL AND reverses_movement_id IS NULL)`;
const MOVEMENT_CHECK_NAMES = Object.freeze(['chk_account_movements_kind', 'chk_account_movements_sign', 'chk_account_movements_source']);

const MOVEMENT_CHECK_SQL = `DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_account_movements_kind' AND conrelid = 'account_movements'::regclass AND pg_get_constraintdef(oid) NOT LIKE '%refund%'
  ) THEN
    ALTER TABLE account_movements
      DROP CONSTRAINT chk_account_movements_kind,
      DROP CONSTRAINT chk_account_movements_sign,
      DROP CONSTRAINT chk_account_movements_source,
      ADD CONSTRAINT chk_account_movements_kind CHECK (${MOVEMENT_KIND_CHECK}) NOT VALID,
      ADD CONSTRAINT chk_account_movements_sign CHECK (
    ${MOVEMENT_SIGN_CHECK}
  ) NOT VALID,
      ADD CONSTRAINT chk_account_movements_source CHECK (
    ${MOVEMENT_SOURCE_CHECK}
  ) NOT VALID;
  END IF;
END $$;`;

const LEDGER_SOURCE_CHECK_SQL = `DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_ledger_entries_source' AND conrelid = 'ledger_entries'::regclass
      AND (pg_get_constraintdef(oid) NOT LIKE '%refund%' OR pg_get_constraintdef(oid) NOT LIKE '%liability_transfer%')
  ) THEN
    ALTER TABLE ledger_entries
      DROP CONSTRAINT chk_ledger_entries_source,
      ADD CONSTRAINT chk_ledger_entries_source CHECK ((source_kind IS NULL OR source_kind IN (${sqlList(LEDGER_SOURCE_KINDS)})) AND (source_id IS NULL OR source_kind IS NOT NULL)) NOT VALID;
  END IF;
END $$;`;

const steps = [
  // --- 1. Yeni işlevler (tablo kilidi yok) ---------------------------------------------------------------------------------------------------
  {
    id: 'function:trg_finance_refunds_guard',
    exists: hasFunction('trg_finance_refunds_guard'),
    sql: `CREATE OR REPLACE FUNCTION trg_finance_refunds_guard() RETURNS trigger AS $$
-- ${FINANCE_REFUNDS_MARKER}
DECLARE
  col TEXT;
  old_json JSONB;
  new_json JSONB;
  decision_cols TEXT[] := ARRAY['status', 'resolved_by', 'resolved_at', 'reject_reason', 'pay_account_id', 'pay_date', 'pay_method', 'ledger_entry_id', 'receipt_year', 'receipt_no',
    'receipt_issued_on', 'receipt_snapshot', 'receipt_sha256', 'receipt_code', 'decision_key'];
  reversal_cols TEXT[] := ARRAY['status', 'reversed_by', 'reversed_at', 'reversal_reason', 'reversal_ledger_entry_id', 'reversal_key'];
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM sites WHERE site_code = OLD.site_code) THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'finance refunds are append-only';
  END IF;
  old_json := to_jsonb(OLD);
  new_json := to_jsonb(NEW);
  -- kullanıcı silinince ON DELETE SET NULL referans eylemi (başka hiçbir sütun değişemez)
  FOREACH col IN ARRAY ARRAY['requested_by', 'resolved_by', 'reversed_by'] LOOP
    IF (old_json ->> col) IS NOT NULL AND (new_json ->> col) IS NULL
       AND NOT EXISTS (SELECT 1 FROM users WHERE user_code = (old_json ->> col)::INTEGER)
       AND (new_json - col) = (old_json - col) THEN
      RETURN NEW;
    END IF;
  END LOOP;
  IF OLD.status = 'requested' AND NEW.status IN ('approved', 'rejected', 'cancelled') AND (new_json - decision_cols) = (old_json - decision_cols) THEN
    IF NEW.status = 'approved' THEN
      IF NOT EXISTS (
        SELECT 1 FROM account_movements m
        WHERE m.refund_id = NEW.id AND m.kind = 'refund' AND m.site_code = NEW.site_code AND m.account_id = NEW.pay_account_id AND m.amount_minor = -NEW.amount_minor
      ) THEN
        RAISE EXCEPTION 'approved refund needs its account movement';
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM ledger_entries l
        WHERE l.id = NEW.ledger_entry_id AND l.site_code = NEW.site_code AND l.apartment_id = NEW.apartment_id AND l.kind = 'charge'
          AND l.source_kind = 'refund' AND l.source_id = NEW.id AND l.amount_minor = NEW.amount_minor
          AND COALESCE(l.account_party, CASE WHEN l.payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END) = NEW.account_party
      ) THEN
        RAISE EXCEPTION 'approved refund needs its ledger entry';
      END IF;
    END IF;
    RETURN NEW;
  END IF;
  IF OLD.status = 'approved' AND NEW.status = 'reversed' AND (new_json - reversal_cols) = (old_json - reversal_cols) THEN
    IF NOT EXISTS (
      SELECT 1 FROM ledger_entries l WHERE l.id = NEW.reversal_ledger_entry_id AND l.reverses_entry_id = NEW.ledger_entry_id AND l.site_code = NEW.site_code
    ) THEN
      RAISE EXCEPTION 'reversed refund needs the reversal of its ledger entry';
    END IF;
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'invalid finance refund change';
END;
$$ LANGUAGE plpgsql;`,
  },
  {
    id: 'function:trg_account_movements_check_refund',
    exists: hasFunction('trg_account_movements_check_refund'),
    sql: `CREATE OR REPLACE FUNCTION trg_account_movements_check_refund() RETURNS trigger AS $$
-- ${FINANCE_REFUNDS_MARKER}
DECLARE
  src RECORD;
BEGIN
  SELECT site_code, amount_minor, status, apartment_id INTO src FROM finance_refunds WHERE id = NEW.refund_id;
  IF NOT FOUND OR src.site_code <> NEW.site_code OR src.amount_minor <> -NEW.amount_minor OR src.status <> 'requested' THEN
    RAISE EXCEPTION 'refund movement must match its pending refund';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;`,
  },
  // --- 2. Yeni tablolar: FK'siz oluşturulur, her FK ayrı ve katalog korumalıdır --------------------------------------------------------------------
  {
    id: 'refunds:table',
    exists: hasTable('finance_refunds'),
    sql: `CREATE TABLE IF NOT EXISTS finance_refunds (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  apartment_id BIGINT NOT NULL,
  account_party TEXT NOT NULL,
  amount_minor BIGINT NOT NULL,
  status TEXT NOT NULL DEFAULT 'requested',
  requested_by_kind TEXT NOT NULL,
  requested_by INTEGER,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  note TEXT,
  resolved_by INTEGER,
  resolved_at TIMESTAMPTZ,
  reject_reason TEXT,
  pay_account_id BIGINT,
  pay_date DATE,
  pay_method TEXT,
  ledger_entry_id BIGINT,
  receipt_year SMALLINT,
  receipt_no INTEGER,
  receipt_issued_on DATE,
  receipt_snapshot JSONB,
  receipt_sha256 TEXT,
  receipt_code TEXT,
  decision_key TEXT,
  reversed_by INTEGER,
  reversed_at TIMESTAMPTZ,
  reversal_reason TEXT,
  reversal_ledger_entry_id BIGINT,
  reversal_key TEXT,
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  CONSTRAINT chk_finance_refunds_party CHECK (account_party IN ('owner', 'tenant')),
  CONSTRAINT chk_finance_refunds_amount CHECK (amount_minor BETWEEN 1 AND 1000000000000),
  CONSTRAINT chk_finance_refunds_status CHECK (status IN (${sqlList(REFUND_STATUSES)})),
  CONSTRAINT chk_finance_refunds_requester CHECK (requested_by_kind IN ('resident', 'manager')),
  CONSTRAINT chk_finance_refunds_method CHECK (pay_method IS NULL OR pay_method IN ('cash', 'transfer', 'cheque')),
  CONSTRAINT chk_finance_refunds_text CHECK (
    (note IS NULL OR char_length(note) <= 200) AND (reject_reason IS NULL OR char_length(reject_reason) <= 200) AND (reversal_reason IS NULL OR char_length(reversal_reason) <= 200)
  ),
  CONSTRAINT chk_finance_refunds_resolved CHECK (status = 'requested' OR resolved_at IS NOT NULL),
  CONSTRAINT chk_finance_refunds_rejected CHECK (status <> 'rejected' OR reject_reason IS NOT NULL),
  CONSTRAINT chk_finance_refunds_approved CHECK (
    status NOT IN ('approved', 'reversed')
    OR (pay_account_id IS NOT NULL AND pay_date IS NOT NULL AND pay_method IS NOT NULL AND ledger_entry_id IS NOT NULL AND receipt_year IS NOT NULL AND receipt_no IS NOT NULL
        AND receipt_issued_on IS NOT NULL AND receipt_snapshot IS NOT NULL AND receipt_sha256 IS NOT NULL AND receipt_code IS NOT NULL)
  ),
  CONSTRAINT chk_finance_refunds_reversed CHECK (
    (status = 'reversed') = (reversed_at IS NOT NULL AND reversal_reason IS NOT NULL AND reversal_ledger_entry_id IS NOT NULL)
  ),
  CONSTRAINT chk_finance_refunds_receipt CHECK (
    receipt_snapshot IS NULL OR (jsonb_typeof(receipt_snapshot) = 'object' AND char_length(receipt_sha256) = 64 AND char_length(receipt_code) = 12 AND receipt_no >= 1 AND receipt_year BETWEEN 2000 AND 2100)
  ),
  CONSTRAINT chk_finance_refunds_keys CHECK (
    char_length(idempotency_key) BETWEEN 1 AND 64 AND char_length(request_fingerprint) = 64
    AND (decision_key IS NULL OR char_length(decision_key) BETWEEN 1 AND 64) AND (reversal_key IS NULL OR char_length(reversal_key) BETWEEN 1 AND 64)
  ),
  CONSTRAINT uq_finance_refunds_idempotency UNIQUE (site_code, idempotency_key)
);`,
  },
  {
    id: 'refund_counters:table',
    exists: hasTable('finance_refund_counters'),
    sql: `CREATE TABLE IF NOT EXISTS finance_refund_counters (
  site_code BIGINT NOT NULL,
  receipt_year SMALLINT NOT NULL,
  last_no INTEGER NOT NULL,
  PRIMARY KEY (site_code, receipt_year),
  CONSTRAINT chk_finance_refund_counters_last CHECK (last_no >= 1),
  CONSTRAINT chk_finance_refund_counters_year CHECK (receipt_year BETWEEN 2000 AND 2100)
);`,
  },
  {
    id: 'refunds:fk_site',
    exists: hasConstraint('finance_refunds_site_code_fkey', 'finance_refunds'),
    sql: foreignKeySql('finance_refunds', 'finance_refunds_site_code_fkey', 'site_code', 'sites', 'site_code', 'CASCADE'),
  },
  {
    id: 'refunds:fk_apartment',
    exists: hasConstraint('finance_refunds_apartment_id_fkey', 'finance_refunds'),
    sql: foreignKeySql('finance_refunds', 'finance_refunds_apartment_id_fkey', 'apartment_id', 'apartments', 'id', 'CASCADE'),
  },
  {
    id: 'refunds:fk_requested_by',
    exists: hasConstraint('finance_refunds_requested_by_fkey', 'finance_refunds'),
    sql: foreignKeySql('finance_refunds', 'finance_refunds_requested_by_fkey', 'requested_by', 'users', 'user_code', 'SET NULL'),
  },
  {
    id: 'refunds:fk_resolved_by',
    exists: hasConstraint('finance_refunds_resolved_by_fkey', 'finance_refunds'),
    sql: foreignKeySql('finance_refunds', 'finance_refunds_resolved_by_fkey', 'resolved_by', 'users', 'user_code', 'SET NULL'),
  },
  {
    id: 'refunds:fk_reversed_by',
    exists: hasConstraint('finance_refunds_reversed_by_fkey', 'finance_refunds'),
    sql: foreignKeySql('finance_refunds', 'finance_refunds_reversed_by_fkey', 'reversed_by', 'users', 'user_code', 'SET NULL'),
  },
  {
    id: 'refunds:fk_account',
    exists: hasConstraint('finance_refunds_pay_account_id_fkey', 'finance_refunds'),
    sql: foreignKeySql('finance_refunds', 'finance_refunds_pay_account_id_fkey', 'pay_account_id', 'finance_accounts', 'id', 'NO ACTION'),
  },
  {
    id: 'refund_counters:fk_site',
    exists: hasConstraint('finance_refund_counters_site_code_fkey', 'finance_refund_counters'),
    sql: foreignKeySql('finance_refund_counters', 'finance_refund_counters_site_code_fkey', 'site_code', 'sites', 'site_code', 'CASCADE'),
  },
  {
    id: 'refunds:index_site_status',
    exists: hasIndex('idx_finance_refunds_site_status'),
    sql: `CREATE INDEX IF NOT EXISTS idx_finance_refunds_site_status ON finance_refunds (site_code, status, id DESC);`,
  },
  {
    id: 'refunds:index_apartment',
    exists: hasIndex('idx_finance_refunds_apartment'),
    sql: `CREATE INDEX IF NOT EXISTS idx_finance_refunds_apartment ON finance_refunds (apartment_id, account_party, status);`,
  },
  {
    id: 'refunds:index_requested_by',
    exists: hasIndex('idx_finance_refunds_requested_by'),
    sql: `CREATE INDEX IF NOT EXISTS idx_finance_refunds_requested_by ON finance_refunds (requested_by, id DESC) WHERE requested_by IS NOT NULL;`,
  },
  {
    id: 'refunds:index_resolved_by',
    exists: hasIndex('idx_finance_refunds_resolved_by'),
    sql: `CREATE INDEX IF NOT EXISTS idx_finance_refunds_resolved_by ON finance_refunds (resolved_by) WHERE resolved_by IS NOT NULL;`,
  },
  {
    id: 'refunds:index_reversed_by',
    exists: hasIndex('idx_finance_refunds_reversed_by'),
    sql: `CREATE INDEX IF NOT EXISTS idx_finance_refunds_reversed_by ON finance_refunds (reversed_by) WHERE reversed_by IS NOT NULL;`,
  },
  {
    id: 'refunds:index_ledger',
    exists: hasIndex('uq_finance_refunds_ledger'),
    sql: `CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_refunds_ledger ON finance_refunds (ledger_entry_id) WHERE ledger_entry_id IS NOT NULL;`,
  },
  {
    id: 'refunds:index_reversal_ledger',
    exists: hasIndex('uq_finance_refunds_reversal_ledger'),
    sql: `CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_refunds_reversal_ledger ON finance_refunds (reversal_ledger_entry_id) WHERE reversal_ledger_entry_id IS NOT NULL;`,
  },
  {
    id: 'refunds:index_account',
    exists: hasIndex('idx_finance_refunds_pay_account'),
    sql: `CREATE INDEX IF NOT EXISTS idx_finance_refunds_pay_account ON finance_refunds (pay_account_id) WHERE pay_account_id IS NOT NULL;`,
  },
  {
    id: 'refunds:index_receipt',
    exists: hasIndex('uq_finance_refunds_receipt'),
    sql: `CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_refunds_receipt ON finance_refunds (site_code, receipt_year, receipt_no) WHERE receipt_no IS NOT NULL;`,
  },
  {
    id: 'refunds:trigger_guard',
    exists: hasTrigger('trg_finance_refunds_guard', 'finance_refunds'),
    sql: triggerSql('trg_finance_refunds_guard', 'finance_refunds', 'BEFORE UPDATE OR DELETE ON finance_refunds FOR EACH ROW EXECUTE PROCEDURE trg_finance_refunds_guard()'),
  },
  {
    id: 'refunds:trigger_no_truncate',
    exists: hasTrigger('trg_finance_refunds_no_truncate', 'finance_refunds'),
    sql: triggerSql('trg_finance_refunds_no_truncate', 'finance_refunds', 'BEFORE TRUNCATE ON finance_refunds FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate()'),
  },
  {
    id: 'refund_counters:trigger_guard',
    exists: hasTrigger('trg_finance_refund_counters_guard', 'finance_refund_counters'),
    sql: triggerSql(
      'trg_finance_refund_counters_guard',
      'finance_refund_counters',
      'BEFORE UPDATE OR DELETE ON finance_refund_counters FOR EACH ROW EXECUTE PROCEDURE trg_receipt_counters_guard()',
    ),
  },
  {
    id: 'refund_counters:trigger_no_truncate',
    exists: hasTrigger('trg_finance_refund_counters_no_truncate', 'finance_refund_counters'),
    sql: triggerSql(
      'trg_finance_refund_counters_no_truncate',
      'finance_refund_counters',
      'BEFORE TRUNCATE ON finance_refund_counters FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate()',
    ),
  },
  // --- 3. account_movements: iade hareketi (kısa kilitler; ÖNCE sütun + FK + indeks, SONRA kısıt yenileme) --------------------------------------------
  {
    id: 'movements:column',
    exists: hasColumn('account_movements', 'refund_id'),
    sql: `ALTER TABLE account_movements ADD COLUMN IF NOT EXISTS refund_id BIGINT;`,
  },
  {
    id: 'movements:fk_refund',
    exists: hasConstraint('account_movements_refund_id_fkey', 'account_movements'),
    sql: foreignKeySql('account_movements', 'account_movements_refund_id_fkey', 'refund_id', 'finance_refunds', 'id', 'NO ACTION'),
  },
  {
    id: 'movements:index_refund',
    exists: hasIndex('uq_account_movements_refund'),
    sql: `CREATE UNIQUE INDEX IF NOT EXISTS uq_account_movements_refund ON account_movements (refund_id) WHERE kind = 'refund';`,
  },
  {
    id: 'movements:check',
    exists: constraintMentions('chk_account_movements_kind', 'account_movements', 'refund'),
    sql: MOVEMENT_CHECK_SQL,
  },
  {
    id: 'movements:validate',
    exists: allValid(MOVEMENT_CHECK_NAMES, 'account_movements'),
    sql: validateSql('account_movements', MOVEMENT_CHECK_NAMES),
  },
  {
    id: 'movements:trigger_refund',
    exists: hasTrigger('trg_account_movements_check_refund', 'account_movements'),
    sql: triggerSql(
      'trg_account_movements_check_refund',
      'account_movements',
      "BEFORE INSERT ON account_movements FOR EACH ROW WHEN (NEW.kind = 'refund') EXECUTE PROCEDURE trg_account_movements_check_refund()",
    ),
  },
  // --- 4. Sıcak tablo: ledger_entries (EN SONDA; her adım kendi kısa kilidi) ---------------------------------------------------------------------
  {
    id: 'refunds:fk_ledger',
    exists: hasConstraint('finance_refunds_ledger_entry_id_fkey', 'finance_refunds'),
    sql: foreignKeySql('finance_refunds', 'finance_refunds_ledger_entry_id_fkey', 'ledger_entry_id', 'ledger_entries', 'id', 'NO ACTION'),
  },
  {
    id: 'refunds:fk_reversal_ledger',
    exists: hasConstraint('finance_refunds_reversal_ledger_entry_id_fkey', 'finance_refunds'),
    sql: foreignKeySql('finance_refunds', 'finance_refunds_reversal_ledger_entry_id_fkey', 'reversal_ledger_entry_id', 'ledger_entries', 'id', 'NO ACTION'),
  },
  {
    id: 'ledger:source_check',
    exists: `${constraintMentions('chk_ledger_entries_source', 'ledger_entries', 'refund')} AND ${constraintMentions('chk_ledger_entries_source', 'ledger_entries', 'liability_transfer')}`,
    sql: LEDGER_SOURCE_CHECK_SQL,
  },
  {
    id: 'ledger:source_validate',
    exists: allValid(['chk_ledger_entries_source'], 'ledger_entries'),
    sql: validateSql('ledger_entries', ['chk_ledger_entries_source']),
  },
];

export const FINANCE_REFUNDS_STEPS = Object.freeze(steps.map((entry) => Object.freeze({ ...entry })));

/** 088 migration dosyasının gövdesi (adımların SQL'i, sırayla). */
export function financeRefundsMigrationSql() {
  return FINANCE_REFUNDS_STEPS.map((entry) => entry.sql).join('\n\n');
}

const LOCK_TIMEOUT = '3s';
const MAX_ATTEMPTS = 6;
const RETRYABLE = new Set(['55P03', '40P01']);

/** Test ayarı: yeniden deneme beklemesi. */
export const refundsSchemaHooks = {
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
};

async function runStep(client, sql) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await client.query(sql);
      return;
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= MAX_ATTEMPTS) {
        throw error;
      }
      await refundsSchemaHooks.sleep(200 * attempt);
    }
  }
}

/**
 * 088'i uygular (db.js `ensureDbSchema` sonu). Ön koşul tabloları ya da `trg_finance_immutable` / `trg_finance_block_truncate` / `trg_receipt_counters_guard` işlevleri
 * yoksa HİÇBİR ŞEY yapmaz. Normal açılışta (her şey var) yalnız tek katalog sorgusu çalışır; hiçbir tabloda kilit alınmaz.
 * @param {{ query: Function }} client
 * @returns {Promise<string[]>} uygulanan adım kimlikleri
 */
export async function ensureFinanceRefundsSchema(client) {
  const guards = [
    ...FINANCE_REFUNDS_GUARD_TABLES.map((name) => `${hasTable(name)} AS g_${name}`),
    ...['trg_finance_immutable', 'trg_finance_block_truncate', 'trg_receipt_counters_guard', 'trg_account_movements_check'].map(
      (name) => `EXISTS (SELECT 1 FROM pg_proc WHERE proname = '${name}' AND pronamespace = 'public'::regnamespace) AS g_${name}`,
    ),
    `${hasColumn('ledger_entries', 'fund')} AS g_ledger_fund`,
  ].join(', ');
  const stepColumns = FINANCE_REFUNDS_STEPS.map((entry, index) => `(${entry.exists}) AS s${index}`).join(', ');
  const required = [
    ...FINANCE_REFUNDS_GUARD_TABLES.map((name) => `g_${name}`),
    'g_trg_finance_immutable',
    'g_trg_finance_block_truncate',
    'g_trg_receipt_counters_guard',
    'g_trg_account_movements_check',
    'g_ledger_fund',
  ];
  const applied = [];
  let timeoutSet = false;
  try {
    // Katalog anlık görüntüsü adımlardan ÖNCE alınır; sonradan oluşan nesnelere bağlı adımlar (VALIDATE) bir sonraki turda yakalanır (en çok 3 tur).
    for (let pass = 0; pass < 3; pass += 1) {
      const found = await client.query(`SELECT ${guards}, ${stepColumns}`);
      const row = found.rows?.[0] ?? {};
      if (required.some((name) => row[name] !== true)) {
        return applied;
      }
      let ran = 0;
      for (const [index, entry] of FINANCE_REFUNDS_STEPS.entries()) {
        if (row[`s${index}`] === true) {
          continue;
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
      await client.query('RESET lock_timeout').catch(() => {});
    }
  }
}
