// İki kasa (İşletme / Yatırım ve Demirbaş Fon; migration 080) şeması: tek kaynak. `migrations/080_finance_funds.sql` bu adımların SQL'inin birleşimidir (test: finance_funds_schema);
// `ensureFinanceFundsSchema` (db.js `ensureDbSchema` sonunda) AYNI adımları katalog kontrolüyle ve HER ADIM KENDİ otomatik onaylı ifadesiyle uygular.
//
// Neden dev ensureDbSchema bloğunun İÇİNDE değil (açılış 40P01 dersi, bkz. finance_parties_schema.js): ADD COLUMN / CREATE INDEX ... IF NOT EXISTS nesne VARKEN bile tabloda kilit alır;
// burada eksikler TEK katalog sorgusuyla (kilitsiz) belirlenir, yalnız eksik adımlar çalışır; her şey varsa (normal açılış) hiçbir tabloda kilit alınmaz.
//
// Sözleşme: docs/PLATFORM_FINANS_KASALAR.md.
//  - ledger_entries.fund (NULL | operating | capital). Varsayılansız, NULL olabilir: defter eklemelidir, GERİ DOLDURMA YAPILMAZ; 080 öncesi satırın kasası OKUMADA türetilir
//    (finance_funds.effectiveFund). Tahsilat satırında fund = "yalnız bu kasaya" kısıtıdır (NULL = otomatik). CHECK NOT VALID eklenir, ayrı adımda VALIDATE edilir.
//  - trg_ledger_entries_fund (BEFORE INSERT, yalnız hedefli ters kayıt): ters kaydın kasası boşsa asılınkiyle DOLDURULUR, farklıysa P0001 reddedilir. 080'i bilmeyen eski sürümün
//    yazdığı ters kayıt da doğru kasaya düşer.
//  - expense_categories.fund (NOT NULL DEFAULT 'operating'), expenses.fund (NULL = kategorinin kasası; yeni giderde HER ZAMAN yazılır).
//  - finance_fund_transfers: kasalar arası aktarım; EKLEMELİ (genel değişmezlik tetikleyicisi); düzeltme yalnız TERS aktarım satırıyla (yönler yer değiştirir, aynı tutar).
//  - Her siteye sistem kategorisi "Yatırım ve demirbaş" (fund capital, is_system): kategorisi zaten olan sitelere eklenir; kategorisi hiç olmayan siteye varsayılan küme ilk
//    kullanımda (finance_expenses.ensureDefaultCategories) 13. kategori olarak gelir (burada eklense varsayılan küme hiç oluşmazdı).
// SIRA (kilit penceresi): yalnız yeni işlevler / tablo -> küçük tablolar (expense_categories, expenses) -> EN SONDA sıcak ledger_entries -> veri adımı.
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

import { CAPITAL_CATEGORY_NAME } from './finance_funds.js';

/** İşlev gövdesine yazılan sürüm işareti (katalog `prosrc` aranır): değişirse işlevler yenilenir. */
export const FINANCE_FUNDS_MARKER = 'ff:1';

export const FINANCE_FUNDS_GUARD_TABLES = Object.freeze(['ledger_entries', 'expense_categories', 'expenses', 'sites', 'users']);

const hasTable = (name) => `to_regclass('public.${name}') IS NOT NULL`;
const hasIndex = (name) => `EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = '${name}')`;
const hasFunction = (name) =>
  `EXISTS (SELECT 1 FROM pg_proc WHERE proname = '${name}' AND pronamespace = 'public'::regnamespace AND prosrc LIKE '%${FINANCE_FUNDS_MARKER}%')`;
const hasTrigger = (name, table) =>
  `EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = '${name}' AND tgrelid = to_regclass('public.${table}') AND NOT tgisinternal)`;
const hasConstraint = (name, table) => `EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = to_regclass('public.${table}'))`;
const hasColumn = (table, column) =>
  `EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('public.${table}') AND attname = '${column}' AND NOT attisdropped)`;
const allValid = (names, table) =>
  `NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname IN (${names.map((n) => `'${n}'`).join(', ')}) AND conrelid = to_regclass('public.${table}') AND NOT convalidated)`;

/** Katalogda yoksa CHECK kısıtını NOT VALID ekler (idempotent DO bloğu). */
function addCheckSql(table, checks) {
  const body = checks
    .map(
      ([name, expression]) => `  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass
  ) THEN
    ALTER TABLE ${table} ADD CONSTRAINT ${name} CHECK (${expression}) NOT VALID;
  END IF;`,
    )
    .join('\n');
  return `DO $$
BEGIN
${body}
END $$;`;
}

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

const FUND_VALUES = `'operating', 'capital'`;
const LEDGER_CHECKS = [['chk_ledger_entries_fund', `fund IS NULL OR fund IN (${FUND_VALUES})`]];
const CATEGORY_CHECKS = [['chk_expense_categories_fund', `fund IN (${FUND_VALUES})`]];
const EXPENSE_CHECKS = [['chk_expenses_fund', `fund IS NULL OR fund IN (${FUND_VALUES})`]];

/** Sistem kategorisi: kategorisi olan her siteye (yoksa) eklenir. Sistem + capital olan ya da aynı adlı kategorisi bulunan site atlanır (adın kullanıcıca değişmesi yeniden eklemeyi tetiklemez). */
const CAPITAL_CATEGORY_CONDITION = `(c.is_system AND c.fund = 'capital') OR lower(c.name) = lower('${CAPITAL_CATEGORY_NAME}')`;
const CAPITAL_CATEGORY_SQL = `INSERT INTO expense_categories (site_code, name, is_system, is_active, sort_order, fund)
SELECT c.site_code, '${CAPITAL_CATEGORY_NAME}', TRUE, TRUE, COALESCE(MAX(c.sort_order), 0) + 1, 'capital'
FROM expense_categories c
GROUP BY c.site_code
HAVING NOT bool_or(${CAPITAL_CATEGORY_CONDITION})
ON CONFLICT DO NOTHING;`;

const steps = [
  // --- 1. Yeni işlevler (tablo kilidi yok) ---------------------------------------------------------------------------------------------------
  {
    id: 'function:trg_ledger_entries_fund',
    exists: hasFunction('trg_ledger_entries_fund'),
    sql: `CREATE OR REPLACE FUNCTION trg_ledger_entries_fund() RETURNS trigger AS $$
-- ${FINANCE_FUNDS_MARKER}
DECLARE
  original_fund TEXT;
BEGIN
  SELECT fund INTO original_fund FROM ledger_entries WHERE id = NEW.reverses_entry_id;
  IF NEW.fund IS NULL THEN
    NEW.fund := original_fund;
  ELSIF original_fund IS NOT NULL AND NEW.fund <> original_fund THEN
    RAISE EXCEPTION 'finance reversal must keep the fund of its original entry';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;`,
  },
  {
    id: 'function:trg_finance_fund_transfers_check',
    exists: hasFunction('trg_finance_fund_transfers_check'),
    sql: `CREATE OR REPLACE FUNCTION trg_finance_fund_transfers_check() RETURNS trigger AS $$
-- ${FINANCE_FUNDS_MARKER}
DECLARE
  src RECORD;
BEGIN
  IF NEW.reverses_transfer_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT site_code, from_fund, to_fund, amount_minor, reverses_transfer_id INTO src FROM finance_fund_transfers WHERE id = NEW.reverses_transfer_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fund transfer reversal must reference an existing transfer';
  END IF;
  IF src.site_code <> NEW.site_code OR src.reverses_transfer_id IS NOT NULL OR src.from_fund <> NEW.to_fund OR src.to_fund <> NEW.from_fund OR src.amount_minor <> NEW.amount_minor THEN
    RAISE EXCEPTION 'fund transfer reversal must mirror its original transfer';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;`,
  },
  // --- 2. Yeni tablo: FK'siz oluşturulur, her FK ayrı ve katalog korumalıdır ---------------------------------------------------------------------
  {
    id: 'fund_transfers:table',
    exists: hasTable('finance_fund_transfers'),
    sql: `CREATE TABLE IF NOT EXISTS finance_fund_transfers (
  id BIGSERIAL PRIMARY KEY,
  site_code BIGINT NOT NULL,
  from_fund TEXT NOT NULL,
  to_fund TEXT NOT NULL,
  amount_minor BIGINT NOT NULL,
  transfer_date DATE NOT NULL,
  period DATE NOT NULL,
  description TEXT,
  reverses_transfer_id BIGINT,
  reversal_reason TEXT,
  idempotency_key TEXT NOT NULL,
  request_fingerprint TEXT NOT NULL,
  created_by INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_finance_fund_transfers_funds CHECK (from_fund IN (${FUND_VALUES}) AND to_fund IN (${FUND_VALUES}) AND from_fund <> to_fund),
  CONSTRAINT chk_finance_fund_transfers_amount CHECK (amount_minor BETWEEN 1 AND 1000000000000),
  CONSTRAINT chk_finance_fund_transfers_period CHECK (EXTRACT(DAY FROM period) = 1),
  CONSTRAINT chk_finance_fund_transfers_text CHECK ((description IS NULL OR char_length(description) <= 200) AND (reversal_reason IS NULL OR char_length(reversal_reason) <= 200)),
  CONSTRAINT chk_finance_fund_transfers_reversal CHECK (reverses_transfer_id IS NOT NULL OR reversal_reason IS NULL),
  CONSTRAINT chk_finance_fund_transfers_key CHECK (char_length(idempotency_key) BETWEEN 1 AND 64 AND char_length(request_fingerprint) = 64),
  CONSTRAINT uq_finance_fund_transfers_idempotency UNIQUE (site_code, idempotency_key)
);`,
  },
  {
    id: 'fund_transfers:fk_reverses',
    exists: hasConstraint('finance_fund_transfers_reverses_fkey', 'finance_fund_transfers'),
    sql: foreignKeySql('finance_fund_transfers', 'finance_fund_transfers_reverses_fkey', 'reverses_transfer_id', 'finance_fund_transfers', 'id', 'NO ACTION'),
  },
  {
    id: 'fund_transfers:fk_user',
    exists: hasConstraint('finance_fund_transfers_created_by_fkey', 'finance_fund_transfers'),
    sql: foreignKeySql('finance_fund_transfers', 'finance_fund_transfers_created_by_fkey', 'created_by', 'users', 'user_code', 'SET NULL'),
  },
  {
    id: 'fund_transfers:fk_site',
    exists: hasConstraint('finance_fund_transfers_site_code_fkey', 'finance_fund_transfers'),
    sql: foreignKeySql('finance_fund_transfers', 'finance_fund_transfers_site_code_fkey', 'site_code', 'sites', 'site_code', 'CASCADE'),
  },
  {
    id: 'fund_transfers:index_date',
    exists: hasIndex('idx_finance_fund_transfers_date'),
    sql: `CREATE INDEX IF NOT EXISTS idx_finance_fund_transfers_date ON finance_fund_transfers (site_code, transfer_date, id);`,
  },
  {
    id: 'fund_transfers:index_reverses',
    exists: hasIndex('uq_finance_fund_transfers_reverses'),
    sql: `CREATE UNIQUE INDEX IF NOT EXISTS uq_finance_fund_transfers_reverses ON finance_fund_transfers (reverses_transfer_id) WHERE reverses_transfer_id IS NOT NULL;`,
  },
  {
    id: 'fund_transfers:index_created_by',
    exists: hasIndex('idx_finance_fund_transfers_created_by'),
    sql: `CREATE INDEX IF NOT EXISTS idx_finance_fund_transfers_created_by ON finance_fund_transfers (created_by) WHERE created_by IS NOT NULL;`,
  },
  {
    id: 'trigger:trg_finance_fund_transfers_immutable',
    exists: hasTrigger('trg_finance_fund_transfers_immutable', 'finance_fund_transfers'),
    sql: triggerSql(
      'trg_finance_fund_transfers_immutable',
      'finance_fund_transfers',
      "BEFORE UPDATE OR DELETE ON finance_fund_transfers FOR EACH ROW EXECUTE PROCEDURE trg_finance_immutable('created_by')",
    ),
  },
  {
    id: 'trigger:trg_finance_fund_transfers_no_truncate',
    exists: hasTrigger('trg_finance_fund_transfers_no_truncate', 'finance_fund_transfers'),
    sql: triggerSql(
      'trg_finance_fund_transfers_no_truncate',
      'finance_fund_transfers',
      'BEFORE TRUNCATE ON finance_fund_transfers FOR EACH STATEMENT EXECUTE PROCEDURE trg_finance_block_truncate()',
    ),
  },
  {
    id: 'trigger:trg_finance_fund_transfers_check',
    exists: hasTrigger('trg_finance_fund_transfers_check', 'finance_fund_transfers'),
    sql: triggerSql(
      'trg_finance_fund_transfers_check',
      'finance_fund_transfers',
      'BEFORE INSERT ON finance_fund_transfers FOR EACH ROW WHEN (NEW.reverses_transfer_id IS NOT NULL) EXECUTE PROCEDURE trg_finance_fund_transfers_check()',
    ),
  },
  // --- 3. Küçük tablolar: expense_categories, expenses ---------------------------------------------------------------------------------------
  {
    id: 'categories:column',
    exists: hasColumn('expense_categories', 'fund'),
    sql: `ALTER TABLE expense_categories ADD COLUMN IF NOT EXISTS fund TEXT NOT NULL DEFAULT 'operating';`,
  },
  {
    id: 'categories:check',
    exists: hasConstraint('chk_expense_categories_fund', 'expense_categories'),
    sql: addCheckSql('expense_categories', CATEGORY_CHECKS),
  },
  {
    id: 'categories:validate',
    exists: allValid(['chk_expense_categories_fund'], 'expense_categories'),
    sql: validateSql('expense_categories', CATEGORY_CHECKS.map(([name]) => name)),
  },
  {
    id: 'expenses:column',
    exists: hasColumn('expenses', 'fund'),
    sql: `ALTER TABLE expenses ADD COLUMN IF NOT EXISTS fund TEXT;`,
  },
  {
    id: 'expenses:check',
    exists: hasConstraint('chk_expenses_fund', 'expenses'),
    sql: addCheckSql('expenses', EXPENSE_CHECKS),
  },
  {
    id: 'expenses:validate',
    exists: allValid(['chk_expenses_fund'], 'expenses'),
    sql: validateSql('expenses', EXPENSE_CHECKS.map(([name]) => name)),
  },
  // --- 4. Sıcak tablo: ledger_entries (EN SONDA; her adım kendi kısa kilidi) ---------------------------------------------------------------------
  {
    id: 'ledger:column',
    exists: hasColumn('ledger_entries', 'fund'),
    sql: `ALTER TABLE ledger_entries ADD COLUMN IF NOT EXISTS fund TEXT;`,
  },
  {
    id: 'ledger:check',
    exists: hasConstraint('chk_ledger_entries_fund', 'ledger_entries'),
    sql: addCheckSql('ledger_entries', LEDGER_CHECKS),
  },
  {
    id: 'ledger:validate',
    exists: allValid(LEDGER_CHECKS.map(([name]) => name), 'ledger_entries'),
    sql: validateSql('ledger_entries', LEDGER_CHECKS.map(([name]) => name)),
  },
  {
    id: 'trigger:trg_ledger_entries_fund',
    exists: hasTrigger('trg_ledger_entries_fund', 'ledger_entries'),
    sql: triggerSql(
      'trg_ledger_entries_fund',
      'ledger_entries',
      "BEFORE INSERT ON ledger_entries FOR EACH ROW WHEN (NEW.kind = 'reversal' AND NEW.reverses_entry_id IS NOT NULL) EXECUTE PROCEDURE trg_ledger_entries_fund()",
    ),
  },
];

/**
 * Veri adımı: sütunlar OLUŞTUKTAN sonra değerlendirilir (var-mı sorgusu `expense_categories.fund` sütununu okur; katalog anlık görüntüsünde olamaz).
 */
const dataSteps = [
  {
    id: 'data:capital_category',
    exists: `NOT EXISTS (SELECT 1 FROM expense_categories c GROUP BY c.site_code HAVING NOT bool_or(${CAPITAL_CATEGORY_CONDITION}))`,
    sql: CAPITAL_CATEGORY_SQL,
  },
];

export const FINANCE_FUNDS_STEPS = Object.freeze([...steps, ...dataSteps].map((entry) => Object.freeze({ ...entry })));
const CATALOG_STEPS = FINANCE_FUNDS_STEPS.filter((entry) => !entry.id.startsWith('data:'));
const DATA_STEPS = FINANCE_FUNDS_STEPS.filter((entry) => entry.id.startsWith('data:'));

/** 080 migration dosyasının gövdesi (adımların SQL'i, sırayla). */
export function financeFundsMigrationSql() {
  return FINANCE_FUNDS_STEPS.map((entry) => entry.sql).join('\n\n');
}

const LOCK_TIMEOUT = '3s';
const MAX_ATTEMPTS = 6;
const RETRYABLE = new Set(['55P03', '40P01']);

/** Test ayarı: yeniden deneme beklemesi. */
export const fundsSchemaHooks = {
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
      await fundsSchemaHooks.sleep(200 * attempt);
    }
  }
}

/**
 * 080'i uygular (db.js `ensureDbSchema` sonu). Ön koşul tabloları ya da `trg_finance_immutable` / `trg_finance_block_truncate` işlevleri yoksa HİÇBİR ŞEY yapmaz.
 * Normal açılışta (her şey var) yalnız katalog sorgusu + veri adımının var-mı sorgusu çalışır; hiçbir tabloda kilit alınmaz.
 * @param {{ query: Function }} client
 * @returns {Promise<string[]>} uygulanan adım kimlikleri
 */
export async function ensureFinanceFundsSchema(client) {
  const guards = [
    ...FINANCE_FUNDS_GUARD_TABLES.map((name) => `${hasTable(name)} AS g_${name}`),
    `EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'trg_finance_immutable' AND pronamespace = 'public'::regnamespace) AS g_immutable`,
    `EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'trg_finance_block_truncate' AND pronamespace = 'public'::regnamespace) AS g_truncate`,
  ].join(', ');
  const stepColumns = CATALOG_STEPS.map((entry, index) => `(${entry.exists}) AS s${index}`).join(', ');
  const applied = [];
  let timeoutSet = false;
  const setTimeoutOnce = async () => {
    if (!timeoutSet) {
      await client.query(`SET lock_timeout = '${LOCK_TIMEOUT}'`);
      timeoutSet = true;
    }
  };
  try {
    // Katalog anlık görüntüsü adımlardan ÖNCE alınır; sonradan oluşan nesnelere bağlı adımlar (VALIDATE) bir sonraki turda yakalanır (en çok 3 tur).
    for (let pass = 0; pass < 3; pass += 1) {
      const found = await client.query(`SELECT ${guards}, ${stepColumns}`);
      const row = found.rows?.[0] ?? {};
      if (FINANCE_FUNDS_GUARD_TABLES.some((name) => row[`g_${name}`] !== true) || row.g_immutable !== true || row.g_truncate !== true) {
        return applied;
      }
      let ran = 0;
      for (const [index, entry] of CATALOG_STEPS.entries()) {
        if (row[`s${index}`] === true) {
          continue;
        }
        await setTimeoutOnce();
        await runStep(client, entry.sql);
        applied.push(entry.id);
        ran += 1;
      }
      if (ran === 0) {
        break;
      }
    }
    for (const entry of DATA_STEPS) {
      const found = await client.query(`SELECT (${entry.exists}) AS done`);
      if (found.rows?.[0]?.done === true) {
        continue;
      }
      await setTimeoutOnce();
      await runStep(client, entry.sql);
      applied.push(entry.id);
    }
    return applied;
  } finally {
    if (timeoutSet) {
      await client.query('RESET lock_timeout').catch(() => {});
    }
  }
}
