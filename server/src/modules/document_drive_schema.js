// Dosya Deposu yalnız-Drive modeli şeması: 116. migrations/119_document_drive_only.sql ile AYNI ifadeler, AYNI sırayla.
// Yalnız ekleyici: document_versions.drive_file_id (drive_files.id; FK yok), server_copy (varsayılan TRUE = mevcut sürümlerin dosyası sunucuda). Eski sunucu sürümü sütunları yok sayar.
// Katalog eksik diyorsa, kendi otomatik onaylı ifadesiyle, lock_timeout 2 sn + 40P01/55P03'te yeniden denemeyle çalışır. db.js'i İÇE AKTARMAZ.

export const DOCUMENT_DRIVE_DDL = Object.freeze({
  driveFileColumn: `ALTER TABLE document_versions ADD COLUMN IF NOT EXISTS drive_file_id BIGINT`,
  serverCopyColumn: `ALTER TABLE document_versions ADD COLUMN IF NOT EXISTS server_copy BOOLEAN NOT NULL DEFAULT TRUE`,
  driveFileIndex: `CREATE INDEX IF NOT EXISTS idx_document_versions_drive_file ON document_versions (drive_file_id) WHERE drive_file_id IS NOT NULL`,
});

export const DOCUMENT_DRIVE_DDL_ORDER = Object.freeze(['driveFileColumn', 'serverCopyColumn', 'driveFileIndex']);

export const documentDriveTuning = { retryDelayMs: 300 };

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
      await sleep(documentDriveTuning.retryDelayMs * attempt);
    }
  }
}

/** Her şey varsa tek katalog sorgusu, kilit yok. document_versions yoksa (039 uygulanmamış) hiçbir şey yapmaz. */
export async function ensureDocumentDriveSchema(client) {
  const found = await client.query(`
    SELECT
      to_regclass('public.document_versions') IS NOT NULL AS has_table,
      EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('public.document_versions') AND attname = 'drive_file_id' AND NOT attisdropped) AS has_drive,
      EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('public.document_versions') AND attname = 'server_copy' AND NOT attisdropped) AS has_copy,
      EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_document_versions_drive_file') AS has_index
  `);
  const state = found.rows[0] ?? {};
  if (state.has_table !== true) return;
  const pending = {
    driveFileColumn: state.has_drive !== true,
    serverCopyColumn: state.has_copy !== true,
    driveFileIndex: state.has_index !== true,
  };
  if (!Object.values(pending).some(Boolean)) return;
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const name of DOCUMENT_DRIVE_DDL_ORDER) {
      if (pending[name]) await runDdl(client, DOCUMENT_DRIVE_DDL[name]);
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
