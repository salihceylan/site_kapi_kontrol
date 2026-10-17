// Toplu yükleme (Faz 2b) şeması: 038. migrations/038_bulk_imports.sql ile AYNI ifadeler (test: bulk_import_schema).
//
// Tek yeni tablo `bulk_import_runs` (ekleyici). Kişisel veri TAŞIMAZ: yalnız sayılar ve özetler. Var olan tablolara sütun/indeks eklenmez.
//
// Açılış kilitleri (R2 F-1 dersi + bu faz için ölçüldü): (1) `CREATE TABLE/INDEX IF NOT EXISTS` nesne VARKEN bile kilit alabilir ve dev ensureDbSchema
// bloğunun tek örtük işlemine konursa yazıcılarla 40P01 üretir; bu yüzden ifadeler db.js'te blok BİTTİKTEN sonra, katalog kontrolüyle ve her biri kendi
// otomatik onaylı ifadesiyle yalnız EKSİK olanlar için çalışır. (2) Satır içi `REFERENCES sites(...) / users(...)` içeren CREATE TABLE iki başvurulan tabloda
// (sites, users) ShareRowExclusive kilidini ARDIŞIK alır: bir yazıcı (UPDATE sites ... UPDATE users) ile ters sırada kesişince QA'da 18 denemenin 15'inde 40P01
// çıktı. Bu yüzden tablo FK'SIZ oluşturulur, iki FK ayrı ifadelerle eklenir (her ifade TEK başvurulan tabloyu kilitler; kilit döngüsü kurulamaz) ve her
// ifade kısa lock_timeout ile yeniden denenir (kilit zinciri uzun bir işlemde takılırsa yazıcıları uzun bekletmez, 40P01/55P03'te yeniden dener).
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın); db.js bunu içe aktarır.

export const BULK_IMPORT_DDL = Object.freeze({
  table: `
    CREATE TABLE IF NOT EXISTS bulk_import_runs (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      kind TEXT NOT NULL,
      idempotency_key TEXT NOT NULL,
      request_fingerprint TEXT NOT NULL,
      preview_hash TEXT NOT NULL,
      strict BOOLEAN NOT NULL DEFAULT FALSE,
      allow_overwrite BOOLEAN NOT NULL DEFAULT FALSE,
      row_count INTEGER NOT NULL,
      counts JSONB NOT NULL DEFAULT '{}'::jsonb,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_bulk_import_runs_kind CHECK (kind IN ('apartments', 'people', 'vehicles')),
      CONSTRAINT chk_bulk_import_runs_key CHECK (char_length(idempotency_key) BETWEEN 8 AND 64),
      CONSTRAINT chk_bulk_import_runs_fingerprint CHECK (char_length(request_fingerprint) = 64),
      CONSTRAINT chk_bulk_import_runs_hash CHECK (char_length(preview_hash) = 64),
      CONSTRAINT chk_bulk_import_runs_rows CHECK (row_count >= 0),
      CONSTRAINT chk_bulk_import_runs_counts CHECK (jsonb_typeof(counts) = 'object')
    )
  `,
  siteFk: `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_bulk_import_runs_site' AND conrelid = 'bulk_import_runs'::regclass
      ) THEN
        ALTER TABLE bulk_import_runs ADD CONSTRAINT fk_bulk_import_runs_site
          FOREIGN KEY (site_code) REFERENCES sites(site_code) ON DELETE CASCADE;
      END IF;
    END $$
  `,
  userFk: `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_bulk_import_runs_created_by' AND conrelid = 'bulk_import_runs'::regclass
      ) THEN
        ALTER TABLE bulk_import_runs ADD CONSTRAINT fk_bulk_import_runs_created_by
          FOREIGN KEY (created_by) REFERENCES users(user_code) ON DELETE SET NULL;
      END IF;
    END $$
  `,
  keyIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_bulk_import_runs_key ON bulk_import_runs (site_code, idempotency_key)`,
  siteIndex: `CREATE INDEX IF NOT EXISTS idx_bulk_import_runs_site ON bulk_import_runs (site_code, id DESC)`,
  createdByIndex: `CREATE INDEX IF NOT EXISTS idx_bulk_import_runs_created_by ON bulk_import_runs (created_by) WHERE created_by IS NOT NULL`,
});

const LOCK_TIMEOUT = '3s';
const MAX_ATTEMPTS = 6;
const RETRYABLE = new Set(['55P03', '40P01']);

export const schemaHooks = {
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
};

/**
 * Tek DDL ifadesini kısa lock_timeout ile çalıştırır; kilit zaman aşımında (55P03) ya da deadlock'ta (40P01) bekleyip yeniden dener (en çok 6 deneme).
 * lock_timeout oturum düzeyindedir ve her denemeden sonra SIFIRLANIR (havuz bağlantısı başka işe değiştirilmiş kalmasın).
 */
async function runDdl(client, statement) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await client.query(`SET lock_timeout = '${LOCK_TIMEOUT}'`);
      await client.query(statement);
      return;
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= MAX_ATTEMPTS) {
        throw error;
      }
      await schemaHooks.sleep(200 * attempt);
    } finally {
      await client.query('RESET lock_timeout').catch(() => {});
    }
  }
}

/**
 * 038'i uygular (db.js ensureDbSchema bloğu BİTTİKTEN sonra çağrılır). Tek katalog sorgusuyla eksik nesneler belirlenir; yalnız eksikler çalışır
 * (normal açılışta HİÇ DDL / kilit yok). `users` / `sites` tabloları ensureDbSchema başında zaten doğrulanmıştır (FK hedefleri).
 */
export async function ensureBulkImportSchema(client) {
  const found = await client.query(`
    SELECT
      to_regclass('public.bulk_import_runs') IS NOT NULL AS has_table,
      EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_bulk_import_runs_site' AND conrelid = to_regclass('public.bulk_import_runs')) AS has_site_fk,
      EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_bulk_import_runs_created_by' AND conrelid = to_regclass('public.bulk_import_runs')) AS has_user_fk,
      EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'uq_bulk_import_runs_key') AS has_key_index,
      EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_bulk_import_runs_site') AS has_site_index,
      EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_bulk_import_runs_created_by') AS has_created_by_index
  `);
  const state = found.rows[0] ?? {};
  if (state.has_table !== true) {
    await runDdl(client, BULK_IMPORT_DDL.table);
  }
  if (state.has_site_fk !== true) {
    await runDdl(client, BULK_IMPORT_DDL.siteFk);
  }
  if (state.has_user_fk !== true) {
    await runDdl(client, BULK_IMPORT_DDL.userFk);
  }
  if (state.has_key_index !== true) {
    await runDdl(client, BULK_IMPORT_DDL.keyIndex);
  }
  if (state.has_site_index !== true) {
    await runDdl(client, BULK_IMPORT_DDL.siteIndex);
  }
  if (state.has_created_by_index !== true) {
    await runDdl(client, BULK_IMPORT_DDL.createdByIndex);
  }
}
