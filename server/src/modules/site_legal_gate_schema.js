// Site başına hukuk onayı bayrağı (sites.legal_ok) şeması: 114. migrations/114_site_legal_gate.sql ile AYNI ifadeler, AYNI sırayla (test: site_legal_gate_schema).
//
// Satışa hazırlık kararı: gecikme tazminatı ve borç hatırlatma (hukuk kapısı) artık sistem geneli `platform_settings finance.legal_ok` yerine SİTE bazında kapılanır.
//  - Sütun `DEFAULT TRUE` ile eklenir: eklendiği anda MEVCUT tüm siteler AÇIK kalır (canlıda davranış kırılmaz; PG 11+ metadata değişikliği, yeniden yazma yok),
//  - ardından varsayılan FALSE yapılır: bundan sonra oluşan YENİ siteler KAPALI başlar (süper kullanıcı avukat onayından sonra açar).
// İki adım ayrı ifadedir; süreç ikisinin arasında ölürse sütun var ama varsayılan hâlâ TRUE kalır: bu yüzden varsayılan KATALOGDAN denetlenir ve eksikse yalnız ikinci adım
// yeniden çalışır (kendini onarır). Mevcut satırların değeri hiçbir koşulda yeniden yazılmaz. Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

export const SITE_LEGAL_GATE_DDL = Object.freeze({
  column: `ALTER TABLE sites ADD COLUMN IF NOT EXISTS legal_ok BOOLEAN NOT NULL DEFAULT TRUE`,
  newSitesDefault: `ALTER TABLE sites ALTER COLUMN legal_ok SET DEFAULT FALSE`,
});

/** Sıra BAĞLAYICIDIR (migration ile aynı). */
export const SITE_LEGAL_GATE_DDL_ORDER = Object.freeze(['column', 'newSitesDefault']);

export const siteLegalGateTuning = { retryDelayMs: 300 };

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
      await sleep(siteLegalGateTuning.retryDelayMs * attempt);
    }
  }
}

/** Her şey yerindeyse tek katalog sorgusu, kilit yok. `sites` yoksa (henüz uygulanmamış) hiçbir şey yapmaz. */
export async function ensureSiteLegalGateSchema(client) {
  const found = await client.query(
    `
      SELECT
        to_regclass('public.sites') IS NOT NULL AS has_sites,
        EXISTS (
          SELECT 1 FROM pg_attribute a
          WHERE a.attrelid = to_regclass('public.sites') AND a.attname = 'legal_ok' AND a.attnum > 0 AND NOT a.attisdropped
        ) AS has_column,
        (
          SELECT pg_get_expr(d.adbin, d.adrelid)
          FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
          WHERE d.adrelid = to_regclass('public.sites') AND a.attname = 'legal_ok'
        ) AS column_default
    `,
  );
  const row = found.rows[0] ?? {};
  if (row.has_sites !== true) return;
  const steps = [];
  if (row.has_column !== true) steps.push('column', 'newSitesDefault');
  else if (String(row.column_default ?? '').toLowerCase() !== 'false') steps.push('newSitesDefault');
  if (steps.length === 0) return;
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const name of steps) await runDdl(client, SITE_LEGAL_GATE_DDL[name]);
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
