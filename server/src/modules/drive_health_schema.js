// Drive sağlık göstergesi + kota + aktarım doğrulaması (P2-2 / P2-17 / P2-18) şeması: 112. migrations/112_drive_health.sql ile AYNI ifadeler, AYNI sırayla (test: drive_health_schema).
//
// Yalnız ekleyici sütunlar (yeni tablo / FK / indeks yok); mevcut satırlara dokunulmaz (hepsi NULL = henüz denetlenmedi / bilinmiyor):
//  - site_drive_connections: quota_limit_bytes, quota_used_bytes (about.get storageQuota), token_expires_at (erişim belirteci son geçerlilik), health_checked_at (son sağlık denetimi),
//  - drive_files.verify_method: 'sha256' (Drive'ın SHA-256'sı bizimkiyle eşleşti) ya da 'size' (Drive sağlama toplamı bildirmedi; kimlik + boyut),
//  - drive_pending_uploads.error_kind: son denemenin nedeni ('quota' | 'integrity' | 'auth' | 'rate_limit' | 'not_found' | 'transient' | 'local'); kuyruk dolu / kota dolu ayrımı için.
// Eski sunucu sürümü bu sütunları yok sayar (INSERT/UPDATE onları yazmaz), geri alma güvenlidir.
// ALTER'ler yalnız katalog eksik olduğunu söylüyorsa, kendi otomatik onaylı ifadesiyle, lock_timeout 2 sn + 40P01/55P03'te yeniden denemeyle çalışır.
// db.js'te ensureDriveSchema (060) ve ensureDbSchema bloğundan SONRA çağrılır. Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

export const DRIVE_HEALTH_DDL = Object.freeze({
  quotaLimitColumn: `ALTER TABLE site_drive_connections ADD COLUMN IF NOT EXISTS quota_limit_bytes BIGINT`,
  quotaUsedColumn: `ALTER TABLE site_drive_connections ADD COLUMN IF NOT EXISTS quota_used_bytes BIGINT`,
  tokenExpiresColumn: `ALTER TABLE site_drive_connections ADD COLUMN IF NOT EXISTS token_expires_at TIMESTAMPTZ`,
  healthCheckedColumn: `ALTER TABLE site_drive_connections ADD COLUMN IF NOT EXISTS health_checked_at TIMESTAMPTZ`,
  verifyMethodColumn: `ALTER TABLE drive_files ADD COLUMN IF NOT EXISTS verify_method TEXT`,
  errorKindColumn: `ALTER TABLE drive_pending_uploads ADD COLUMN IF NOT EXISTS error_kind TEXT`,
});

/** Sıra BAĞLAYICIDIR (migration ile aynı). Her adım: ifade adı -> { table, column }. */
const STEPS = Object.freeze([
  ['quotaLimitColumn', { table: 'site_drive_connections', column: 'quota_limit_bytes' }],
  ['quotaUsedColumn', { table: 'site_drive_connections', column: 'quota_used_bytes' }],
  ['tokenExpiresColumn', { table: 'site_drive_connections', column: 'token_expires_at' }],
  ['healthCheckedColumn', { table: 'site_drive_connections', column: 'health_checked_at' }],
  ['verifyMethodColumn', { table: 'drive_files', column: 'verify_method' }],
  ['errorKindColumn', { table: 'drive_pending_uploads', column: 'error_kind' }],
]);

export const DRIVE_HEALTH_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

export const driveHealthTuning = { retryDelayMs: 300 };

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
      await sleep(driveHealthTuning.retryDelayMs * attempt);
    }
  }
}

/** Her şey varsa tek katalog sorgusu, kilit yok. 060 tabloları yoksa (henüz uygulanmamış) hiçbir şey yapmaz; ilgili tablo eksikse yalnız o tablonun sütunu atlanır. */
export async function ensureDriveHealthSchema(client) {
  const tables = [...new Set(STEPS.map(([, spec]) => spec.table))];
  const found = await client.query(
    `
      SELECT
        ARRAY(SELECT t FROM unnest($1::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
        ARRAY(
          SELECT c.relname::TEXT || '.' || a.attname::TEXT
          FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
          WHERE c.relname = ANY($1::TEXT[]) AND c.relnamespace = 'public'::regnamespace AND a.attnum > 0 AND NOT a.attisdropped
        ) AS columns
    `,
    [tables],
  );
  const row = found.rows[0] ?? {};
  const presentTables = new Set(row.tables ?? []);
  const presentColumns = new Set(row.columns ?? []);
  const pending = STEPS.filter(([, spec]) => presentTables.has(spec.table) && !presentColumns.has(`${spec.table}.${spec.column}`));
  if (pending.length === 0) return;
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const [name] of pending) await runDdl(client, DRIVE_HEALTH_DDL[name]);
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
