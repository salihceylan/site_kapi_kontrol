// İki hesap (İP-1A, migration 052) şeması: tek kaynak. `migrations/052_finance_parties.sql` bu adımların SQL'inin birleşimidir (test: finance_parties_schema);
// `ensureFinancePartiesSchema` (db.js `ensureDbSchema` sonunda, 051'den sonra) AYNI adımları katalog kontrolüyle ve HER ADIM KENDİ otomatik onaylı ifadesiyle uygular.
//
// Neden dev ensureDbSchema bloğunun İÇİNDE değil (R2 F-1 / R11 F1 dersi, bkz. finance_4b_schema.js): ADD COLUMN / CREATE INDEX ... IF NOT EXISTS nesne VARKEN bile
// tabloda kilit alır; bloğun tek örtük işleminde kilitler birikir ve açılışta yazıcılarla 40P01 üretir. Burada eksikler TEK katalog sorgusuyla (kilitsiz) belirlenir,
// yalnız eksik adımlar çalışır; her şey varsa (normal açılış) hiçbir tabloda kilit alınmaz. Eksik adım varken lock_timeout 3 sn + 55P03 / 40P01'de en çok 6 deneme.
//
// Sözleşme: docs/PLATFORM_FINANS.md "İki hesap (2026-10-21)" ve docs/superpowers/plans/2026-10-21-eksik-listesi-programi.md 2.1.
//  - ledger_entries: account_party (owner | tenant; NULL = 052 öncesi satır: hesap payer_party'den OKUMADA türetilir, both => owner), source_kind
//    (manual | payment_notice | bank_line | opening | card) + source_id. Varsayılansız, NULL olabilir: defter eklemelidir, GERİ DOLDURMA YAPILMAZ.
//    CHECK'ler NOT VALID eklenir, ayrı adımda VALIDATE edilir (SHARE UPDATE EXCLUSIVE; yazıcıları bekletmez).
//  - trg_ledger_entries_account_party (BEFORE INSERT, yalnız hedefli ters kayıt): ters kaydın hesabı boşsa asılın (türetilmiş) hesabıyla doldurulur, farklıysa
//    reddedilir. Böylece 052 öncesi sürümün yazdığı ters kayıt da asılın hesabına düşer.
//  - fee_definitions.charge_party (occupant | owner; NULL = türe göre varsayılan: aylık occupant, tek seferlik owner).
//  - late_fee_run_lines: account_party (+ hesap tetikleyicisi) ve birincil anahtar (run_id, apartment_id) -> (run_id, ledger_entry_id): aynı dairenin iki
//    hesabına aynı çalıştırmada satır yazılabilsin. Bu, "yalnız ekleyici" kuralının GEREKÇELİ tek istisnasıdır: kısıt yalnız gevşer (veri değişmez, eski kod
//    aynen çalışır); tablo eklemeli ve küçüktür (gecikme tazminatı hukuk onayına kadar kapalı). (run_id, apartment_id, account_party) kısmi tekil indeksi yeni
//    satırların hesap başına tekliğini korur.
// SIRA (kilit penceresi): yalnız yeni işlevler -> küçük tablolar (fee_definitions, late_fee_run_lines) -> sıcak ledger_entries adımları -> EN SONDA
// tazminat satırı tetikleyicisi (işlevi ledger_entries.account_party'yi okur; sütun oluşmadan kurulmaz).
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

/** İşlev gövdesine yazılan sürüm işareti (katalog `prosrc` aranır): değişirse işlevler yenilenir. */
export const FINANCE_PARTIES_MARKER = 'fp:1';

export const FINANCE_PARTIES_GUARD_TABLES = Object.freeze(['ledger_entries', 'fee_definitions', 'late_fee_run_lines', 'apartments']);

const hasIndex = (name) => `EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = '${name}')`;
const hasFunction = (name) =>
  `EXISTS (SELECT 1 FROM pg_proc WHERE proname = '${name}' AND pronamespace = 'public'::regnamespace AND prosrc LIKE '%${FINANCE_PARTIES_MARKER}%')`;
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

const LEDGER_CHECKS = [
  ['chk_ledger_entries_account_party', `account_party IS NULL OR account_party IN ('owner', 'tenant')`],
  [
    'chk_ledger_entries_source',
    `(source_kind IS NULL OR source_kind IN ('manual', 'payment_notice', 'bank_line', 'opening', 'card')) AND (source_id IS NULL OR source_kind IS NOT NULL)`,
  ],
];
const DEFINITION_CHECKS = [['chk_fee_definitions_charge_party', `charge_party IS NULL OR charge_party IN ('occupant', 'owner')`]];
const LATE_FEE_LINE_CHECKS = [['chk_late_fee_run_lines_account', `account_party IS NULL OR account_party IN ('owner', 'tenant')`]];

const steps = [
  // --- 1. Yeni işlevler (tablo kilidi yok) ---------------------------------------------------------------------------------------------------
  {
    id: 'function:trg_ledger_entries_account_party',
    exists: hasFunction('trg_ledger_entries_account_party'),
    sql: `CREATE OR REPLACE FUNCTION trg_ledger_entries_account_party() RETURNS trigger AS $$
-- ${FINANCE_PARTIES_MARKER}
DECLARE
  original_party TEXT;
BEGIN
  SELECT COALESCE(account_party, CASE WHEN payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END) INTO original_party
  FROM ledger_entries WHERE id = NEW.reverses_entry_id;
  IF original_party IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.account_party IS NULL THEN
    NEW.account_party := original_party;
  ELSIF NEW.account_party <> original_party THEN
    RAISE EXCEPTION 'finance reversal must keep the account of its original entry';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;`,
  },
  {
    id: 'function:trg_late_fee_run_lines_account',
    exists: hasFunction('trg_late_fee_run_lines_account'),
    sql: `CREATE OR REPLACE FUNCTION trg_late_fee_run_lines_account() RETURNS trigger AS $$
-- ${FINANCE_PARTIES_MARKER}
DECLARE
  entry_party TEXT;
BEGIN
  SELECT COALESCE(account_party, CASE WHEN payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END) INTO entry_party
  FROM ledger_entries WHERE id = NEW.ledger_entry_id;
  IF entry_party IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.account_party IS NULL THEN
    NEW.account_party := entry_party;
  ELSIF NEW.account_party <> entry_party THEN
    RAISE EXCEPTION 'late fee line must keep the account of its ledger entry';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;`,
  },
  // --- 2. Küçük tablolar ------------------------------------------------------------------------------------------------------------------------
  {
    id: 'fee_definitions:column',
    exists: hasColumn('fee_definitions', 'charge_party'),
    sql: `ALTER TABLE fee_definitions ADD COLUMN IF NOT EXISTS charge_party TEXT;`,
  },
  {
    id: 'fee_definitions:check',
    exists: hasConstraint('chk_fee_definitions_charge_party', 'fee_definitions'),
    sql: addCheckSql('fee_definitions', DEFINITION_CHECKS),
  },
  {
    id: 'fee_definitions:validate',
    exists: allValid(['chk_fee_definitions_charge_party'], 'fee_definitions'),
    sql: validateSql('fee_definitions', DEFINITION_CHECKS.map(([name]) => name)),
  },
  {
    id: 'late_fee_lines:column',
    exists: hasColumn('late_fee_run_lines', 'account_party'),
    sql: `ALTER TABLE late_fee_run_lines ADD COLUMN IF NOT EXISTS account_party TEXT;`,
  },
  {
    id: 'late_fee_lines:check',
    exists: hasConstraint('chk_late_fee_run_lines_account', 'late_fee_run_lines'),
    sql: addCheckSql('late_fee_run_lines', LATE_FEE_LINE_CHECKS),
  },
  {
    id: 'late_fee_lines:validate',
    exists: allValid(['chk_late_fee_run_lines_account'], 'late_fee_run_lines'),
    sql: validateSql('late_fee_run_lines', LATE_FEE_LINE_CHECKS.map(([name]) => name)),
  },
  {
    id: 'late_fee_lines:pkey',
    exists: `EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'late_fee_run_lines_pkey' AND conrelid = to_regclass('public.late_fee_run_lines') AND pg_get_constraintdef(oid) = 'PRIMARY KEY (run_id, ledger_entry_id)')`,
    sql: `DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'late_fee_run_lines_pkey' AND conrelid = 'late_fee_run_lines'::regclass AND pg_get_constraintdef(oid) = 'PRIMARY KEY (run_id, apartment_id)'
  ) THEN
    ALTER TABLE late_fee_run_lines DROP CONSTRAINT late_fee_run_lines_pkey;
    ALTER TABLE late_fee_run_lines ADD CONSTRAINT late_fee_run_lines_pkey PRIMARY KEY (run_id, ledger_entry_id);
  END IF;
END $$;`,
  },
  {
    id: 'late_fee_lines:index',
    exists: hasIndex('uq_late_fee_run_lines_account'),
    sql: `CREATE UNIQUE INDEX IF NOT EXISTS uq_late_fee_run_lines_account ON late_fee_run_lines (run_id, apartment_id, account_party) WHERE account_party IS NOT NULL;`,
  },
  // --- 3. Sıcak tablo: ledger_entries (EN SONDA; her adım kendi kısa kilidi) ---------------------------------------------------------------------
  {
    id: 'ledger:columns',
    exists: `${hasColumn('ledger_entries', 'account_party')} AND ${hasColumn('ledger_entries', 'source_kind')} AND ${hasColumn('ledger_entries', 'source_id')}`,
    sql: `ALTER TABLE ledger_entries ADD COLUMN IF NOT EXISTS account_party TEXT, ADD COLUMN IF NOT EXISTS source_kind TEXT, ADD COLUMN IF NOT EXISTS source_id BIGINT;`,
  },
  {
    id: 'ledger:checks',
    exists: `${hasConstraint('chk_ledger_entries_account_party', 'ledger_entries')} AND ${hasConstraint('chk_ledger_entries_source', 'ledger_entries')}`,
    sql: addCheckSql('ledger_entries', LEDGER_CHECKS),
  },
  {
    id: 'ledger:validate',
    exists: allValid(LEDGER_CHECKS.map(([name]) => name), 'ledger_entries'),
    sql: validateSql('ledger_entries', LEDGER_CHECKS.map(([name]) => name)),
  },
  {
    id: 'ledger:index',
    exists: hasIndex('idx_ledger_entries_source'),
    sql: `CREATE INDEX IF NOT EXISTS idx_ledger_entries_source ON ledger_entries (site_code, source_kind, source_id) WHERE source_id IS NOT NULL;`,
  },
  {
    id: 'trigger:trg_ledger_entries_account_party',
    exists: hasTrigger('trg_ledger_entries_account_party', 'ledger_entries'),
    sql: triggerSql(
      'trg_ledger_entries_account_party',
      'ledger_entries',
      "BEFORE INSERT ON ledger_entries FOR EACH ROW WHEN (NEW.kind = 'reversal' AND NEW.reverses_entry_id IS NOT NULL) EXECUTE PROCEDURE trg_ledger_entries_account_party()",
    ),
  },
  // --- 4. Tazminat satırı hesap tetikleyicisi (inceleme): işlevi ledger_entries.account_party sütununu okur; sütun VAR olduktan sonra kurulur.
  //        Önce kurulsaydı açılış iki adım arasında kalırsa ya da ledger adımı düşüp eski sürüme dönülürse tazminat satırı yazımı "sütun yok" hatası alırdı.
  //        Tetikleyici yalnız late_fee_run_lines'ı kilitler (ledger_entries'e dokunmaz).
  {
    id: 'trigger:trg_late_fee_run_lines_account',
    exists: hasTrigger('trg_late_fee_run_lines_account', 'late_fee_run_lines'),
    sql: triggerSql(
      'trg_late_fee_run_lines_account',
      'late_fee_run_lines',
      'BEFORE INSERT ON late_fee_run_lines FOR EACH ROW EXECUTE PROCEDURE trg_late_fee_run_lines_account()',
    ),
  },
];

export const FINANCE_PARTIES_STEPS = Object.freeze(steps.map((entry) => Object.freeze({ ...entry })));

/** 052 migration dosyasının gövdesi (adımların SQL'i, sırayla). */
export function financePartiesMigrationSql() {
  return FINANCE_PARTIES_STEPS.map((entry) => entry.sql).join('\n\n');
}

const LOCK_TIMEOUT = '3s';
const MAX_ATTEMPTS = 6;
const RETRYABLE = new Set(['55P03', '40P01']);

/** Test ayarı: yeniden deneme beklemesi. */
export const partiesSchemaHooks = {
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
      await partiesSchemaHooks.sleep(200 * attempt);
    }
  }
}

/**
 * 052'yi uygular (db.js `ensureDbSchema` sonu). Ön koşul tabloları yoksa HİÇBİR ŞEY yapmaz. Normal açılışta (her şey var) yalnız tek katalog sorgusu çalışır.
 * @param {{ query: Function }} client
 * @returns {Promise<string[]>} uygulanan adım kimlikleri
 */
export async function ensureFinancePartiesSchema(client) {
  const guards = FINANCE_PARTIES_GUARD_TABLES.map((name) => `to_regclass('public.${name}') IS NOT NULL AS g_${name}`).join(', ');
  const stepColumns = FINANCE_PARTIES_STEPS.map((entry, index) => `(${entry.exists}) AS s${index}`).join(', ');
  const applied = [];
  let timeoutSet = false;
  try {
    // Katalog anlık görüntüsü adımlardan ÖNCE alınır; sonradan oluşan nesnelere bağlı adımlar (VALIDATE) bir sonraki turda yakalanır (en çok 3 tur).
    for (let pass = 0; pass < 3; pass += 1) {
      const found = await client.query(`SELECT ${guards}, ${stepColumns}`);
      const row = found.rows?.[0] ?? {};
      if (FINANCE_PARTIES_GUARD_TABLES.some((name) => row[`g_${name}`] !== true)) {
        return applied;
      }
      let ran = 0;
      for (const [index, entry] of FINANCE_PARTIES_STEPS.entries()) {
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
