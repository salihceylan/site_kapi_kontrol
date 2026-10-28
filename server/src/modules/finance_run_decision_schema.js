// Demirbaş / Fon tahakkukunun dayanağı (Karar Defteri kaydı ya da gerekçe; migration 090) şeması: tek kaynak. `migrations/090_finance_run_decision.sql` bu adımların SQL'inin birleşimidir
// (test: finance_run_decision_schema); `ensureFinanceRunDecisionSchema` (db.js `ensureDbSchema` sonunda) AYNI adımları katalog kontrolüyle ve HER ADIM KENDİ otomatik onaylı ifadesiyle uygular.
//
// Neden dev ensureDbSchema bloğunun İÇİNDE değil (açılış 40P01 dersi, bkz. finance_funds_schema.js): ADD COLUMN / CREATE INDEX ... IF NOT EXISTS nesne VARKEN bile tabloda kilit alır;
// burada eksikler TEK katalog sorgusuyla (kilitsiz) belirlenir, yalnız eksik adımlar çalışır; her şey varsa (normal açılış) hiçbir tabloda kilit alınmaz.
//
// Sözleşme: docs/PLATFORM_FINANS_KARAR_BAGI.md.
//  - fee_runs.decision_id (NULL | kesin karar kimliği) ve fee_runs.decision_reason (NULL | 1..300 karakter): TAHAKKUK kaydının (çalıştırma) dayanağı. Varsayılansız ve NULL olabilir: 090 öncesi çalıştırmalar
//    ve işletme (Aidat) hesabı borçları dayanaksız kalır, GERİ DOLDURMA YAPILMAZ. Zorunluluk (Fon hesabı borcu) uygulama katmanındadır: veritabanı tetikleyicisi KONMAZ, çünkü canlıdaki geri alma hedefi
//    (090'ı bilmeyen sürüm) Fon çalıştırmasını dayanaksız yazar ve bir tetikleyici onu bozardı.
//  - Bileşik yabancı anahtar (site_code, decision_id) -> board_decisions (site_code, id): karar AYNI sitede olmak zorundadır (IDOR'a karşı veritabanı güvencesi). NO ACTION: kesin karar silinemez,
//    site silme CASCADE zinciri aynı ifadede iki tabloyu da siler (040 ilkesi); SET NULL KULLANILMAZ (fee_runs eklemelidir, trg_fee_runs_append_only UPDATE'i reddeder).
//  - fee_runs zaten eklemelidir (trg_fee_runs_append_only): dayanak çalıştırma yazılırken konur, sonradan DEĞİŞMEZ.
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

export const FINANCE_RUN_DECISION_GUARD_TABLES = Object.freeze(['fee_runs', 'board_decisions', 'sites']);

/** Gerekçe metninin en çok karakter sayısı (CHECK ve uygulama aynı sınırı kullanır). */
export const RUN_DECISION_REASON_DB_MAX = 300;

const hasTable = (name) => `to_regclass('public.${name}') IS NOT NULL`;
const hasIndex = (name) => `EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = '${name}')`;
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

const RUN_CHECKS = [['chk_fee_runs_decision', `decision_reason IS NULL OR char_length(decision_reason) BETWEEN 1 AND ${RUN_DECISION_REASON_DB_MAX}`]];

const steps = [
  {
    id: 'runs:columns',
    exists: `${hasColumn('fee_runs', 'decision_id')} AND ${hasColumn('fee_runs', 'decision_reason')}`,
    sql: `ALTER TABLE fee_runs ADD COLUMN IF NOT EXISTS decision_id BIGINT, ADD COLUMN IF NOT EXISTS decision_reason TEXT;`,
  },
  {
    id: 'runs:check',
    exists: hasConstraint('chk_fee_runs_decision', 'fee_runs'),
    sql: addCheckSql('fee_runs', RUN_CHECKS),
  },
  {
    id: 'runs:validate',
    exists: allValid(RUN_CHECKS.map(([name]) => name), 'fee_runs'),
    sql: validateSql('fee_runs', RUN_CHECKS.map(([name]) => name)),
  },
  {
    id: 'runs:fk_decision',
    exists: hasConstraint('fee_runs_decision_fkey', 'fee_runs'),
    sql: `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fee_runs_decision_fkey' AND conrelid = 'fee_runs'::regclass
  ) THEN
    ALTER TABLE fee_runs ADD CONSTRAINT fee_runs_decision_fkey FOREIGN KEY (site_code, decision_id) REFERENCES board_decisions (site_code, id) ON DELETE NO ACTION;
  END IF;
END $$;`,
  },
  {
    id: 'runs:index_decision',
    exists: hasIndex('idx_fee_runs_decision'),
    sql: `CREATE INDEX IF NOT EXISTS idx_fee_runs_decision ON fee_runs (site_code, decision_id) WHERE decision_id IS NOT NULL;`,
  },
];

export const FINANCE_RUN_DECISION_STEPS = Object.freeze(steps.map((entry) => Object.freeze({ ...entry })));

/** 090 migration dosyasının gövdesi (adımların SQL'i, sırayla). */
export function financeRunDecisionMigrationSql() {
  return FINANCE_RUN_DECISION_STEPS.map((entry) => entry.sql).join('\n\n');
}

const LOCK_TIMEOUT = '3s';
const MAX_ATTEMPTS = 6;
const RETRYABLE = new Set(['55P03', '40P01']);

/** Test ayarı: yeniden deneme beklemesi. */
export const runDecisionSchemaHooks = {
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
      await runDecisionSchemaHooks.sleep(200 * attempt);
    }
  }
}

/**
 * 090'ı uygular (db.js `ensureDbSchema` sonu). Ön koşul tablolar (fee_runs, board_decisions, sites) ya da board_decisions (site_code, id) tekil anahtarı yoksa HİÇBİR ŞEY yapmaz.
 * Normal açılışta (her şey var) yalnız tek katalog sorgusu çalışır; hiçbir tabloda kilit alınmaz.
 * @param {{ query: Function }} client
 * @returns {Promise<string[]>} uygulanan adım kimlikleri
 */
export async function ensureFinanceRunDecisionSchema(client) {
  const guards = [
    ...FINANCE_RUN_DECISION_GUARD_TABLES.map((name) => `${hasTable(name)} AS g_${name}`),
    `${hasConstraint('uq_board_decisions_site_id', 'board_decisions')} AS g_unique`,
  ].join(', ');
  const stepColumns = FINANCE_RUN_DECISION_STEPS.map((entry, index) => `(${entry.exists}) AS s${index}`).join(', ');
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
      if (FINANCE_RUN_DECISION_GUARD_TABLES.some((name) => row[`g_${name}`] !== true) || row.g_unique !== true) {
        return applied;
      }
      let ran = 0;
      for (const [index, entry] of FINANCE_RUN_DECISION_STEPS.entries()) {
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
    return applied;
  } finally {
    if (timeoutSet) {
      await client.query('RESET lock_timeout').catch(() => {});
    }
  }
}
