// Etiketleme ve geri alma kaydi: demo_seed_registry.
//
// Tohum calisirken veritabanina GECICI "AFTER INSERT" yakalama tetikleyicileri kurulur; oturumda
// `demo_seed.batch` ayari doluyken eklenen HER satir (uygulamanin kendi servislerinin yazdigi, tetikleyicilerin
// urettigi satirlar dahil) demo_seed_registry'ye (batch_id, table_name, row_id) olarak yazilir. Tohum bitince
// tetikleyiciler kaldirilir. cleanup.mjs kayitli satirlari ters sirada siler.
//
// Mevcut bir satirda yapilan degisiklikler (UPDATE) icin op='update' + before_image tutulur; cleanup eski haline getirir.
// Diskte olusan dosyalar icin table_name='@file', row_id=mutlak yol.

export const REGISTRY_TABLE = 'demo_seed_registry';
export const CAPTURE_FN = 'demo_seed_capture';
export const CAPTURE_TRIGGER = 'zz_demo_seed_capture';
// Yakalanmayan tablolar (kendi kaydimiz ve surum takibi).
const SKIP_TABLES = new Set([REGISTRY_TABLE, 'schema_migrations', 'app_maintenance_runs']);

export async function ensureRegistry(client) {
  await client.query(`
    CREATE TABLE IF NOT EXISTS ${REGISTRY_TABLE} (
      id BIGSERIAL PRIMARY KEY,
      batch_id TEXT NOT NULL,
      table_name TEXT NOT NULL,
      row_id TEXT NOT NULL,
      op TEXT NOT NULL DEFAULT 'insert',
      before_image JSONB,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await client.query(`CREATE INDEX IF NOT EXISTS idx_${REGISTRY_TABLE}_batch ON ${REGISTRY_TABLE} (batch_id, id)`);
  await client.query(`
    CREATE OR REPLACE FUNCTION ${CAPTURE_FN}() RETURNS trigger LANGUAGE plpgsql AS $fn$
    DECLARE
      b TEXT := current_setting('demo_seed.batch', true);
      j JSONB;
      rid TEXT;
      col TEXT;
    BEGIN
      IF b IS NULL OR b = '' THEN
        RETURN NULL;
      END IF;
      j := to_jsonb(NEW);
      FOREACH col IN ARRAY TG_ARGV LOOP
        rid := CASE WHEN rid IS NULL THEN (j ->> col) ELSE rid || '|' || (j ->> col) END;
      END LOOP;
      INSERT INTO ${REGISTRY_TABLE} (batch_id, table_name, row_id) VALUES (b, TG_TABLE_NAME, rid);
      RETURN NULL;
    END
    $fn$
  `);
}

/** Her tablonun birincil anahtar sutunlari (sirali). */
export async function primaryKeys(client) {
  const result = await client.query(`
    SELECT c.relname AS table_name,
           array_agg(a.attname::text ORDER BY array_position(i.indkey::int2[], a.attnum)) AS cols
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY (i.indkey)
    WHERE i.indisprimary AND n.nspname = 'public' AND c.relkind IN ('r', 'p')
    GROUP BY c.relname
  `);
  const map = new Map();
  for (const row of result.rows) map.set(row.table_name, row.cols);
  return map;
}

async function allTables(client) {
  const result = await client.query(`SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY 1`);
  return result.rows.map((r) => r.tablename).filter((t) => !SKIP_TABLES.has(t));
}

/** Yakalama tetikleyicilerini kurar; birincil anahtarsiz tablolarin listesini dondurur. */
export async function installCapture(client) {
  const pks = await primaryKeys(client);
  const tables = await allTables(client);
  const noPk = [];
  await client.query(`SET lock_timeout = '15s'`);
  for (const table of tables) {
    const cols = pks.get(table);
    if (!cols || cols.length === 0) {
      noPk.push(table);
      continue;
    }
    const args = cols.map((c) => `'${c.replace(/'/g, "''")}'`).join(', ');
    await client.query(`DROP TRIGGER IF EXISTS ${CAPTURE_TRIGGER} ON "${table}"`);
    await client.query(`CREATE TRIGGER ${CAPTURE_TRIGGER} AFTER INSERT ON "${table}" FOR EACH ROW EXECUTE FUNCTION ${CAPTURE_FN}(${args})`);
  }
  await client.query(`RESET lock_timeout`);
  return noPk;
}

export async function removeCapture(client) {
  const tables = await allTables(client);
  await client.query(`SET lock_timeout = '15s'`);
  for (const table of tables) {
    await client.query(`DROP TRIGGER IF EXISTS ${CAPTURE_TRIGGER} ON "${table}"`);
  }
  await client.query(`RESET lock_timeout`);
}

/** Bu oturumdaki eklemeleri `batchId` ile etiketler. */
export async function setBatch(client, batchId) {
  await client.query(`SELECT set_config('demo_seed.batch', $1, false)`, [batchId]);
}

/** Havuzdan acilan her yeni baglantida batch ayarini kurar (uygulama servisleri kendi havuzunu kullanir). */
export function hookPool(pool, batchId) {
  pool.on('connect', (client) => {
    client.query(`SELECT set_config('demo_seed.batch', '${String(batchId).replace(/'/g, '')}', false)`).catch(() => {});
  });
}

export async function trackFile(client, batchId, absolutePath) {
  await client.query(`INSERT INTO ${REGISTRY_TABLE} (batch_id, table_name, row_id, op) VALUES ($1, '@file', $2, 'file')`, [batchId, absolutePath]);
}

/** Var olan satirda yapilacak degisiklikten ONCE cagrilir; cleanup eski haline getirir. */
export async function trackUpdate(client, batchId, table, whereSql, whereParams = []) {
  const pks = await primaryKeys(client);
  const cols = pks.get(table);
  if (!cols) throw new Error(`trackUpdate: ${table} birincil anahtari yok`);
  const rows = await client.query(`SELECT to_jsonb(t) AS j FROM "${table}" t WHERE ${whereSql}`, whereParams);
  for (const row of rows.rows) {
    const rid = cols.map((c) => String(row.j[c])).join('|');
    await client.query(
      `INSERT INTO ${REGISTRY_TABLE} (batch_id, table_name, row_id, op, before_image) VALUES ($1, $2, $3, 'update', $4::jsonb)`,
      [batchId, table, rid, JSON.stringify(row.j)],
    );
  }
  return rows.rowCount;
}

export async function registryCounts(client, batchId) {
  const result = await client.query(
    `SELECT table_name, op, COUNT(*)::INT AS n FROM ${REGISTRY_TABLE} WHERE batch_id = $1 GROUP BY 1, 2 ORDER BY 3 DESC, 1`,
    [batchId],
  );
  return result.rows;
}
