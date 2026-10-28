// 091: aidat / ek borç dağıtım tabanlarına 'person_count' (kişi sayısına göre) eklenir (karar K5; docs/PLATFORM_FINANS.md "Dağıtım ve yuvarlama").
// Tek kaynak: `migrations/091_fee_distribution_person_count.sql` bu adımın SQL'inin birleşimidir (test: finance_distribution_schema); `ensureFeeDistributionSchema`
// (db.js `ensureDbSchema` sonunda, ensureFinanceFundsSchema'dan sonra) AYNI adımı katalog kontrolüyle uygular. Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).
//
// Değişiklik: fee_definitions.chk_fee_definitions_distribution CHECK'i ('fixed', 'equal', 'category', 'land_share', 'area') -> + 'person_count'. Mevcut satırların
// hiçbiri etkilenmez (yeni küme eskinin üst kümesi); 'area' yalnız eski satırlar için listede kalır (m² sistemden kaldırıldı, bkz. 078).
// Kilit: ALTER TABLE ... fee_definitions üzerinde kısa ACCESS EXCLUSIVE (tablo küçüktür: tanım başına bir satır); eşdeğer kısıt zaten varsa HİÇBİR ifade / kilit yoktur.
// lock_timeout hiç ayarlı değilse (psql ile elle çalıştırma) işlem-yerel 5 sn konur; migrate.js (MIGRATE_LOCK_TIMEOUT_MS) ve ensure yolu (3 sn) kendi ayarını taşır.
// Hata politikası (db.js ensureDbSchema): kısıt eklenemezse sunucu AÇILIŞI durdurulmaz ama 'person_count' tanımı yazılamaz (CHECK 23514); sonraki açılış yeniden dener.

export const FEE_DISTRIBUTION_VALUES = Object.freeze(['fixed', 'equal', 'category', 'land_share', 'area', 'person_count']);
const VALUES_SQL = FEE_DISTRIBUTION_VALUES.map((value) => `'${value}'`).join(', ');

const CONSTRAINT_PRESENT = `EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_fee_definitions_distribution' AND conrelid = to_regclass('public.fee_definitions') AND pg_get_constraintdef(oid) LIKE '%person_count%'
  )`;

export const FEE_DISTRIBUTION_STEPS = Object.freeze([
  Object.freeze({
    id: 'fee_definitions:distribution_check',
    exists: CONSTRAINT_PRESENT,
    sql: `DO $$
BEGIN
  IF to_regclass('public.fee_definitions') IS NOT NULL AND NOT ${CONSTRAINT_PRESENT} THEN
    IF current_setting('lock_timeout') = '0' THEN
      PERFORM set_config('lock_timeout', '5s', true);
    END IF;
    ALTER TABLE fee_definitions DROP CONSTRAINT IF EXISTS chk_fee_definitions_distribution;
    ALTER TABLE fee_definitions ADD CONSTRAINT chk_fee_definitions_distribution CHECK (distribution IN (${VALUES_SQL}));
  END IF;
END $$;`,
  }),
]);

/** 091 migration dosyasının gövdesi (adımların SQL'i, sırayla). */
export function feeDistributionMigrationSql() {
  return FEE_DISTRIBUTION_STEPS.map((entry) => entry.sql).join('\n\n');
}

const LOCK_TIMEOUT = '3s';
const MAX_ATTEMPTS = 6;
const RETRYABLE = new Set(['55P03', '40P01']);

/** Test ayarı: yeniden deneme beklemesi. */
export const feeDistributionSchemaHooks = {
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
      await feeDistributionSchemaHooks.sleep(200 * attempt);
    }
  }
}

/**
 * 091'i uygular (db.js `ensureDbSchema` sonu). fee_definitions yoksa HİÇBİR ŞEY yapmaz (034 henüz uygulanmamış kesik şema). Normal açılışta (kısıt güncel) yalnız
 * bir katalog sorgusu çalışır; tabloda kilit alınmaz.
 * @param {{ query: Function }} client
 * @returns {Promise<string[]>} uygulanan adım kimlikleri
 */
export async function ensureFeeDistributionSchema(client) {
  const found = await client.query(
    `SELECT to_regclass('public.fee_definitions') IS NOT NULL AS has_table, ${FEE_DISTRIBUTION_STEPS.map((entry, index) => `(${entry.exists}) AS s${index}`).join(', ')}`,
  );
  const row = found.rows?.[0] ?? {};
  if (row.has_table !== true) {
    return [];
  }
  const applied = [];
  let timeoutSet = false;
  try {
    for (const [index, entry] of FEE_DISTRIBUTION_STEPS.entries()) {
      if (row[`s${index}`] === true) {
        continue;
      }
      if (!timeoutSet) {
        await client.query(`SET lock_timeout = '${LOCK_TIMEOUT}'`);
        timeoutSet = true;
      }
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
