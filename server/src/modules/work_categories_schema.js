// İş Takibi kategorileri + fotoğraf yeniden kullanım indeksi şeması: 100. migrations/100_work_categories.sql ile AYNI ifadeler, AYNI sırayla (test: work_categories).
//
// Bir yeni tablo (ekleyici): work_categories (site başına yönetilebilir kategori listesi). Mevcut tablolarda üç değişiklik:
//  - work_items.chk_work_items_category (sabit 4 kategori) yerine chk_work_items_category_key: dört varsayılan anahtar YA DA `k_<ad>` (sitenin eklediği kategori).
//    DROP + ADD tek DO bloğunda = tek işlem (kısıtsız pencere yok); eski kısıt yoksa ve yenisi varsa hiçbir şey yapılmaz. Eski kodla UYUMLU: eski sürüm yalnız
//    dört anahtarı yazar (yeni kısıt hepsini kabul eder), sitenin eklediği kategoriyle açılmış talepleri okurken bilinmeyen kategoriyi "Diğer" gösterir.
//  - idx_work_items_site_category (site, kategori): kategori süzgeci, kullanım sayımı ve "kullanılmış kategori silinmez" denetimi için.
//  - idx_work_item_attachments_site_sha256 (site, sha256): "aynı fotoğraf başka kayıtta da var" uyarısı (P2-6) için.
// Açılış deadlock'u dersi (R2 F-1 / R11 F1, bkz. work_tracking_schema.js): ifadeler db.js'te dev ensureDbSchema bloğu BİTTİKTEN sonra, katalog kontrolüyle ve her biri kendi
// otomatik onaylı ifadesiyle yalnız EKSİK olanlar için çalışır; her şey varsa hiçbir tabloda kilit alınmaz. Tablo FK'SIZ oluşturulur; her FK ayrı, katalog korumalı
// `ALTER TABLE ... ADD CONSTRAINT <tablo>_<sütun>_fkey` ifadesidir (ifade başına TEK üst tablo). Silme politikası: site silinince kategoriler CASCADE; kullanıcı silinince
// created_by SET NULL. Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

/** Tek yabancı anahtar: katalogda yoksa ekler (idempotent). Ad = <tablo>_<sütun>_fkey. */
function foreignKeySql(table, column, parent, parentColumn, onDelete) {
  const name = `${table}_${column}_fkey`;
  return `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = '${name}' AND conrelid = '${table}'::regclass
      ) THEN
        ALTER TABLE ${table} ADD CONSTRAINT ${name} FOREIGN KEY (${column}) REFERENCES ${parent}(${parentColumn}) ON DELETE ${onDelete};
      END IF;
    END $$
  `;
}

/** Sıra BAĞLAYICIDIR (migration ile aynı): önce tablo, sonra FK'leri, sonra indeksleri, en sonda work_items kategori kısıtının gevşetilmesi. */
export const WORK_CATEGORIES_DDL = Object.freeze({
  categoriesTable: `
    CREATE TABLE IF NOT EXISTS work_categories (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      key TEXT NOT NULL,
      label TEXT NOT NULL,
      is_system BOOLEAN NOT NULL DEFAULT FALSE,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_work_categories_key CHECK (key IN ('ariza', 'bakim', 'sikayet_oneri', 'diger') OR key ~ '^k_[a-z0-9_]{1,38}$'),
      CONSTRAINT chk_work_categories_label_length CHECK (char_length(label) BETWEEN 1 AND 60),
      CONSTRAINT chk_work_categories_sort_order CHECK (sort_order BETWEEN 0 AND 100000),
      CONSTRAINT chk_work_categories_system_key CHECK (is_system = (key IN ('ariza', 'bakim', 'sikayet_oneri', 'diger')))
    )
  `,
  categoriesSiteFk: foreignKeySql('work_categories', 'site_code', 'sites', 'site_code', 'CASCADE'),
  categoriesCreatedByFk: foreignKeySql('work_categories', 'created_by', 'users', 'user_code', 'SET NULL'),
  categoriesSiteKeyIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_work_categories_site_key ON work_categories (site_code, key)`,
  categoriesSiteLabelIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_work_categories_site_label ON work_categories (site_code, lower(label))`,
  itemsCategoryIndex: `CREATE INDEX IF NOT EXISTS idx_work_items_site_category ON work_items (site_code, category)`,
  attachmentsSha256Index: `CREATE INDEX IF NOT EXISTS idx_work_item_attachments_site_sha256 ON work_item_attachments (site_code, sha256) WHERE sha256 IS NOT NULL`,
  itemsCategoryCheck: `
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_items_category' AND conrelid = 'work_items'::regclass
      ) THEN
        ALTER TABLE work_items DROP CONSTRAINT chk_work_items_category;
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_items_category_key' AND conrelid = 'work_items'::regclass
      ) THEN
        ALTER TABLE work_items ADD CONSTRAINT chk_work_items_category_key CHECK (category IN ('ariza', 'bakim', 'sikayet_oneri', 'diger') OR category ~ '^k_[a-z0-9_]{1,38}$');
      END IF;
    END $$
  `,
});

/** İfade adı -> { tablo | indeks | fk | check }. Sıra WORK_CATEGORIES_DDL ile aynıdır. */
const STEPS = Object.freeze([
  ['categoriesTable', { table: 'work_categories' }],
  ['categoriesSiteFk', { fk: 'work_categories_site_code_fkey', on: 'work_categories', parent: 'sites' }],
  ['categoriesCreatedByFk', { fk: 'work_categories_created_by_fkey', on: 'work_categories', parent: 'users' }],
  ['categoriesSiteKeyIndex', { index: 'uq_work_categories_site_key', on: 'work_categories' }],
  ['categoriesSiteLabelIndex', { index: 'uq_work_categories_site_label', on: 'work_categories' }],
  ['itemsCategoryIndex', { index: 'idx_work_items_site_category', on: 'work_items' }],
  ['attachmentsSha256Index', { index: 'idx_work_item_attachments_site_sha256', on: 'work_item_attachments' }],
  ['itemsCategoryCheck', { check: 'chk_work_items_category_key', on: 'work_items' }],
]);

export const WORK_CATEGORIES_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

const RETRYABLE = new Set(['40P01', '55P03']);
/** Test ayarı: yeniden deneme beklemesi (ms) çarpanı. */
export const schemaTuning = { retryDelayMs: 300 };

/** Tek DDL ifadesi; 40P01 / 55P03'te (yalnız ilk dağıtım, yoğun yazma) en çok 6 deneme, artan bekleme. İfade tek başına otomatik onaylıdır. */
async function runDdl(client, sql) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await client.query(sql);
      return;
    } catch (error) {
      if (!RETRYABLE.has(error?.code) || attempt >= 6) throw error;
      await new Promise((resolve) => setTimeout(resolve, schemaTuning.retryDelayMs * attempt));
    }
  }
}

/**
 * 100'ü uygular (db.js'te ensureWorkTrackingSchema, ensureWorkAttachmentsSchema'dan SONRA çağrılır). Tek katalog sorgusuyla eksik nesneler belirlenir (tablo, indeks, FK ve
 * kategori kısıtının gevşetilip gevşetilmediği); yalnız eksikler, sırayla ve kendi otomatik onaylı ifadeleriyle çalışır. Her şey varsa (normal açılış) hiçbir ifade
 * gönderilmez. work_items / work_item_attachments henüz yoksa (042 / 047 kurulmamış) o tablolara bağlı adımlar atlanır; work_categories yine oluşturulur.
 */
export async function ensureWorkCategoriesSchema(client) {
  const tables = ['work_categories', 'work_items', 'work_item_attachments'];
  const indexes = STEPS.filter(([, spec]) => spec.index).map(([, spec]) => spec.index);
  const foreignKeys = STEPS.filter(([, spec]) => spec.fk).map(([, spec]) => spec.fk);
  const found = await client.query(
    `
      SELECT
        ARRAY(SELECT t FROM unnest($1::TEXT[]) AS t WHERE to_regclass('public.' || t) IS NOT NULL) AS tables,
        ARRAY(SELECT indexname::TEXT FROM pg_indexes WHERE schemaname = 'public' AND indexname = ANY($2::TEXT[])) AS indexes,
        ARRAY(
          SELECT (SELECT r.relname::TEXT FROM pg_class r WHERE r.oid = c.conrelid) || '.' || c.conname::TEXT
          FROM pg_constraint c
          WHERE c.contype = 'f' AND c.connamespace = 'public'::regnamespace AND c.conname = ANY($3::TEXT[])
        ) AS fks,
        EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conname = 'chk_work_items_category' AND c.connamespace = 'public'::regnamespace) AS old_check_present,
        EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conname = 'chk_work_items_category_key' AND c.connamespace = 'public'::regnamespace) AS new_check_present
    `,
    [tables, indexes, foreignKeys],
  );
  const presentTables = new Set(found.rows[0]?.tables ?? []);
  const presentIndexes = new Set(found.rows[0]?.indexes ?? []);
  const presentFks = new Set(found.rows[0]?.fks ?? []);
  const checkPendingNow = found.rows[0]?.old_check_present === true || found.rows[0]?.new_check_present !== true;
  const hasParent = (parent) => parent === 'sites' || parent === 'users' || presentTables.has(parent);
  const fkPresent = (spec) => presentFks.has(`${spec.on}.${spec.fk}`);
  const pending = STEPS.filter(([, spec]) => {
    if (spec.table) return !presentTables.has(spec.table);
    if (spec.fk) return presentTables.has(spec.on) && hasParent(spec.parent) && !fkPresent(spec);
    if (spec.check) return presentTables.has(spec.on) && checkPendingNow;
    return presentTables.has(spec.on) && !presentIndexes.has(spec.index);
  });
  // Eksik nesne yoksa (her normal açılış) hiçbir DDL gönderilmez: kilit alınmaz.
  if (pending.length === 0) {
    return;
  }
  // Kilit kuyruğunda sonsuza dek beklemesin: 2 sn sonra 55P03, runDdl yeniden dener.
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const [name, spec] of STEPS) {
      if (spec.table) {
        if (presentTables.has(spec.table)) continue;
        await runDdl(client, WORK_CATEGORIES_DDL[name]);
        presentTables.add(spec.table);
      } else if (spec.fk) {
        if (!presentTables.has(spec.on) || !hasParent(spec.parent) || fkPresent(spec)) continue;
        await runDdl(client, WORK_CATEGORIES_DDL[name]);
        presentFks.add(`${spec.on}.${spec.fk}`);
      } else if (spec.check) {
        if (!presentTables.has(spec.on) || !checkPendingNow) continue;
        await runDdl(client, WORK_CATEGORIES_DDL[name]);
      } else if (presentTables.has(spec.on) && !presentIndexes.has(spec.index)) {
        await runDdl(client, WORK_CATEGORIES_DDL[name]);
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
