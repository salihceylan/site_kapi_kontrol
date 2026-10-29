// Kampanya "şimdi abone olana 2 ay ücretsiz" şeması: 115. migrations/115_site_free_period.sql ile AYNI ifadeler, AYNI sırayla (test: site_free_period).
//
// Yalnız ekleyici sütunlar (yeni tablo / FK / indeks yok); mevcut sitelere dokunulmaz (NULL = kampanyadan önce açılmış / tanımsız):
//  - sites.subscription_started_at: aboneliğin başladığı gün (DATE),
//  - sites.free_until: ücretsiz dönemin SON günü (DATE; o gün dahil).
// ALTER'ler yalnız katalog eksik olduğunu söylüyorsa, kendi otomatik onaylı ifadesiyle, lock_timeout 2 sn + 40P01/55P03'te yeniden denemeyle çalışır.
// db.js'te ensureDbSchema bloğundan SONRA çağrılır (sites tablosu orada). Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

export const SITE_FREE_PERIOD_DDL = Object.freeze({
  startedColumn: `ALTER TABLE sites ADD COLUMN IF NOT EXISTS subscription_started_at DATE`,
  freeUntilColumn: `ALTER TABLE sites ADD COLUMN IF NOT EXISTS free_until DATE`,
});

/** Sıra BAĞLAYICIDIR (migration ile aynı). */
export const SITE_FREE_PERIOD_DDL_ORDER = Object.freeze(['startedColumn', 'freeUntilColumn']);

const COLUMNS = Object.freeze({ startedColumn: 'subscription_started_at', freeUntilColumn: 'free_until' });

export const siteFreePeriodTuning = { retryDelayMs: 300 };

const RETRYABLE = new Set(['40P01', '55P03']);
const sleep = (ms) => new Promise((resolve) => {
  const timer = setTimeout(resolve, ms);
  timer.unref?.();
});

async function runDdl(client, sql) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      return await client.query(sql);
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await sleep(siteFreePeriodTuning.retryDelayMs * attempt);
    }
  }
}

/** Her şey varsa tek katalog sorgusu, kilit yok. sites tablosu yoksa hiçbir şey yapmaz. */
export async function ensureSiteFreePeriodSchema(client) {
  const found = await client.query(
    `
      SELECT
        to_regclass('public.sites') IS NOT NULL AS has_table,
        ARRAY(
          SELECT a.attname::TEXT
          FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
          WHERE c.relname = 'sites' AND c.relnamespace = 'public'::regnamespace AND a.attnum > 0 AND NOT a.attisdropped
        ) AS columns
    `,
  );
  const row = found.rows[0] ?? {};
  if (!row.has_table) return;
  const present = new Set(row.columns ?? []);
  const pending = SITE_FREE_PERIOD_DDL_ORDER.filter((name) => !present.has(COLUMNS[name]));
  if (pending.length === 0) return;
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const name of pending) await runDdl(client, SITE_FREE_PERIOD_DDL[name]);
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
