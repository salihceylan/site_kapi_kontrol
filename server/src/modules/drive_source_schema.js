// Drive dosya kaydının kaynak kayda bağlanması (P1-11) şeması: 097. migrations/097_drive_file_source_link.sql ile AYNI ifadeler, AYNI sırayla (test: drive_source_schema).
//
// Ekleyici, yeni tablo / FK yok: drive_files.source_type + source_id (ikisi birlikte dolu ya da birlikte boş), CHECK ve kısmi indeks.
// Mevcut satırlara dokunulmaz (kaynak NULL = bağlanmamış). Eski sunucu sürümü bu sütunları yok sayar (INSERT onları yazmaz), geri alma güvenlidir.
// ALTER'ler yalnız katalog eksik olduğunu söylüyorsa, kendi otomatik onaylı ifadesiyle, lock_timeout 2 sn + 40P01/55P03'te yeniden denemeyle çalışır.
// db.js'te ensureDriveSchema (060) ve ensureDbSchema bloğundan SONRA çağrılır. Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

export const DRIVE_SOURCE_DDL = Object.freeze({
  typeColumn: `ALTER TABLE drive_files ADD COLUMN IF NOT EXISTS source_type TEXT`,
  idColumn: `ALTER TABLE drive_files ADD COLUMN IF NOT EXISTS source_id BIGINT`,
  sourceCheck: `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_drive_files_source' AND conrelid = 'drive_files'::regclass
      ) THEN
        ALTER TABLE drive_files ADD CONSTRAINT chk_drive_files_source CHECK ((source_type IS NULL AND source_id IS NULL) OR (source_type IS NOT NULL AND source_id IS NOT NULL AND source_type ~ '^[a-z][a-z_]{0,31}$' AND source_id > 0)) NOT VALID;
      END IF;
    END $$
  `,
  sourceIndex: `CREATE INDEX IF NOT EXISTS idx_drive_files_source ON drive_files (site_code, source_type, source_id) WHERE source_type IS NOT NULL`,
});

/** Sıra BAĞLAYICIDIR (migration ile aynı): sütunlar -> CHECK -> indeks. */
export const DRIVE_SOURCE_DDL_ORDER = Object.freeze(['typeColumn', 'idColumn', 'sourceCheck', 'sourceIndex']);

export const driveSourceTuning = { retryDelayMs: 300 };

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
      await sleep(driveSourceTuning.retryDelayMs * attempt);
    }
  }
}

/** Her şey varsa tek katalog sorgusu, kilit yok. drive_files yoksa (060 henüz uygulanmamış) hiçbir şey yapmaz. */
export async function ensureDriveSourceSchema(client) {
  const found = await client.query(`
    SELECT
      to_regclass('public.drive_files') IS NOT NULL AS has_table,
      EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('public.drive_files') AND attname = 'source_type' AND NOT attisdropped) AS has_type,
      EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('public.drive_files') AND attname = 'source_id' AND NOT attisdropped) AS has_id,
      EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_drive_files_source' AND conrelid = to_regclass('public.drive_files')) AS has_check,
      EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_drive_files_source') AS has_index
  `);
  const state = found.rows[0] ?? {};
  if (state.has_table !== true) return;
  const pending = {
    typeColumn: state.has_type !== true,
    idColumn: state.has_id !== true,
    sourceCheck: state.has_check !== true,
    sourceIndex: state.has_index !== true,
  };
  if (!Object.values(pending).some(Boolean)) return;
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const name of DRIVE_SOURCE_DDL_ORDER) {
      if (pending[name]) await runDdl(client, DRIVE_SOURCE_DDL[name]);
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
