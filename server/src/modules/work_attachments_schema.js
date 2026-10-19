// İş Takibi fotoğraf ekleri şeması: 047. migrations/047_work_attachments.sql ile AYNI ifadeler, AYNI sırayla (test: work_attachments).
//
// Bir yeni tablo (ekleyici): work_item_attachments. Mevcut tablolara sütun / indeks EKLENMEZ; tek istisna work_item_events.chk_work_item_events_type CHECK kısıtının
// iki yeni olay türüyle ('attachment_added', 'attachment_removed') GENİŞLETİLMESİ (katalog korumalı, idempotent DO bloğu; DROP + ADD tek işlemde, kısıtsız pencere yok).
// Açılış deadlock'u dersi (R2 F-1 / R11 F1, bkz. work_tracking_schema.js): ifadeler db.js'te dev ensureDbSchema bloğu BİTTİKTEN sonra, katalog kontrolüyle ve her biri
// kendi otomatik onaylı ifadesiyle yalnız EKSİK olanlar için çalışır; her şey varsa hiçbir tabloda kilit alınmaz. Tablo FK'SIZ oluşturulur; her FK ayrı, katalog
// korumalı `ALTER TABLE ... ADD CONSTRAINT <tablo>_<sütun>_fkey` ifadesidir (ifade başına TEK üst tablo; sites / users sıcak tablolardır).
// Silme politikası: talep silinince (site CASCADE'i dahil) ek satırları CASCADE (dosya diskte kalır, bakım işi yetim olarak süpürür); kullanıcı SATIRI fiziksel silinirse
// uploaded_by SET NULL. Hesap silme satırı silmez (kimliksizleştirir): uploaded_by tombstone hesaba bağlı kalır (document_versions.uploaded_by ile aynı); her iki durumda
// fotoğraf taleple birlikte sitede kalır ve yükleyen "Silinmiş Kullanıcı" görünür. Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

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

export const EVENT_TYPES_WITH_ATTACHMENTS = Object.freeze(['created', 'status_changed', 'assigned', 'priority_changed', 'due_date_changed', 'comment', 'attachment_added', 'attachment_removed']);

/** Sıra BAĞLAYICIDIR (migration ile aynı): önce tablo, sonra FK'leri, sonra indeksleri, en sonda olay türü kısıtının genişletilmesi. */
export const WORK_ATTACHMENTS_DDL = Object.freeze({
  attachmentsTable: `
    CREATE TABLE IF NOT EXISTS work_item_attachments (
      id BIGSERIAL PRIMARY KEY,
      work_item_id BIGINT NOT NULL,
      site_code BIGINT NOT NULL,
      uploaded_by INTEGER,
      file_name TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      size_bytes BIGINT NOT NULL,
      sha256 TEXT,
      status TEXT NOT NULL DEFAULT 'uploading',
      storage_key TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      ready_at TIMESTAMPTZ,
      CONSTRAINT chk_work_item_attachments_file_name CHECK (char_length(file_name) BETWEEN 1 AND 160),
      CONSTRAINT chk_work_item_attachments_mime CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp')),
      CONSTRAINT chk_work_item_attachments_size CHECK (size_bytes BETWEEN 1 AND 5242880),
      CONSTRAINT chk_work_item_attachments_status CHECK (status IN ('uploading', 'ready')),
      CONSTRAINT chk_work_item_attachments_ready CHECK ((status = 'ready') = (ready_at IS NOT NULL)),
      CONSTRAINT chk_work_item_attachments_sha256 CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$')
    )
  `,
  attachmentsItemFk: foreignKeySql('work_item_attachments', 'work_item_id', 'work_items', 'id', 'CASCADE'),
  attachmentsSiteFk: foreignKeySql('work_item_attachments', 'site_code', 'sites', 'site_code', 'CASCADE'),
  attachmentsUploaderFk: foreignKeySql('work_item_attachments', 'uploaded_by', 'users', 'user_code', 'SET NULL'),
  attachmentsItemIndex: `CREATE INDEX IF NOT EXISTS idx_work_item_attachments_item ON work_item_attachments (work_item_id)`,
  attachmentsSiteCreatedIndex: `CREATE INDEX IF NOT EXISTS idx_work_item_attachments_site_created ON work_item_attachments (site_code, created_at)`,
  attachmentsUploaderIndex: `CREATE INDEX IF NOT EXISTS idx_work_item_attachments_uploaded_by ON work_item_attachments (uploaded_by, created_at) WHERE uploaded_by IS NOT NULL`,
  attachmentsUploadingIndex: `CREATE INDEX IF NOT EXISTS idx_work_item_attachments_uploading ON work_item_attachments (created_at) WHERE status = 'uploading'`,
  attachmentsStorageKeyIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_work_item_attachments_storage_key ON work_item_attachments (storage_key) WHERE storage_key IS NOT NULL`,
  eventsTypeCheck: `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_work_item_events_type' AND conrelid = 'work_item_events'::regclass AND pg_get_constraintdef(oid) LIKE '%attachment_added%'
      ) THEN
        ALTER TABLE work_item_events DROP CONSTRAINT IF EXISTS chk_work_item_events_type;
        ALTER TABLE work_item_events ADD CONSTRAINT chk_work_item_events_type CHECK (event_type IN ('created', 'status_changed', 'assigned', 'priority_changed', 'due_date_changed', 'comment', 'attachment_added', 'attachment_removed'));
      END IF;
    END $$
  `,
});

/** İfade adı -> { tablo | indeks | fk | check }. Sıra WORK_ATTACHMENTS_DDL ile aynıdır. */
const STEPS = Object.freeze([
  ['attachmentsTable', { table: 'work_item_attachments' }],
  ['attachmentsItemFk', { fk: 'work_item_attachments_work_item_id_fkey', on: 'work_item_attachments', parent: 'work_items' }],
  ['attachmentsSiteFk', { fk: 'work_item_attachments_site_code_fkey', on: 'work_item_attachments', parent: 'sites' }],
  ['attachmentsUploaderFk', { fk: 'work_item_attachments_uploaded_by_fkey', on: 'work_item_attachments', parent: 'users' }],
  ['attachmentsItemIndex', { index: 'idx_work_item_attachments_item', on: 'work_item_attachments' }],
  ['attachmentsSiteCreatedIndex', { index: 'idx_work_item_attachments_site_created', on: 'work_item_attachments' }],
  ['attachmentsUploaderIndex', { index: 'idx_work_item_attachments_uploaded_by', on: 'work_item_attachments' }],
  ['attachmentsUploadingIndex', { index: 'idx_work_item_attachments_uploading', on: 'work_item_attachments' }],
  ['attachmentsStorageKeyIndex', { index: 'uq_work_item_attachments_storage_key', on: 'work_item_attachments' }],
  ['eventsTypeCheck', { check: 'chk_work_item_events_type', on: 'work_item_events' }],
]);

export const WORK_ATTACHMENTS_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

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
 * 047'yi uygular (db.js'te ensureWorkTrackingSchema'dan SONRA çağrılır). Tek katalog sorgusuyla eksik nesneler belirlenir (tablo, indeks, FK ve olay türü kısıtının
 * genişletilmiş olup olmadığı); yalnız eksikler, sırayla ve kendi otomatik onaylı ifadeleriyle çalışır. Her şey varsa (normal açılış) hiçbir ifade gönderilmez.
 * work_items henüz yoksa (042 kurulmamış) FK ve kısıt adımları atlanır; tablo yine oluşturulur.
 */
export async function ensureWorkAttachmentsSchema(client) {
  const tables = ['work_item_attachments', 'work_items', 'work_item_events'];
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
        EXISTS (
          SELECT 1 FROM pg_constraint c
          WHERE c.conname = 'chk_work_item_events_type' AND c.connamespace = 'public'::regnamespace AND pg_get_constraintdef(c.oid) LIKE '%attachment_added%'
        ) AS events_type_widened
    `,
    [tables, indexes, foreignKeys],
  );
  const presentTables = new Set(found.rows[0]?.tables ?? []);
  const presentIndexes = new Set(found.rows[0]?.indexes ?? []);
  const presentFks = new Set(found.rows[0]?.fks ?? []);
  const widened = found.rows[0]?.events_type_widened === true;
  const hasParent = (parent) => parent === 'sites' || parent === 'users' || presentTables.has(parent);
  const fkPresent = (spec) => presentFks.has(`${spec.on}.${spec.fk}`);
  const checkPending = (spec) => presentTables.has(spec.on) && !widened;
  const pending = STEPS.filter(([, spec]) => {
    if (spec.table) return !presentTables.has(spec.table);
    if (spec.fk) return presentTables.has(spec.on) && hasParent(spec.parent) && !fkPresent(spec);
    if (spec.check) return checkPending(spec);
    return !presentIndexes.has(spec.index);
  });
  // Eksik nesne yoksa (her normal açılış) hiçbir ifade gönderilmez: kilit alınmaz.
  if (pending.length === 0) {
    return;
  }
  // Kilit kuyruğunda sonsuza dek beklemesin: 2 sn sonra 55P03, runDdl yeniden dener.
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const [name, spec] of STEPS) {
      if (spec.table) {
        if (presentTables.has(spec.table)) continue;
        await runDdl(client, WORK_ATTACHMENTS_DDL[name]);
        presentTables.add(spec.table);
      } else if (spec.fk) {
        if (!presentTables.has(spec.on) || !hasParent(spec.parent) || fkPresent(spec)) continue;
        await runDdl(client, WORK_ATTACHMENTS_DDL[name]);
        presentFks.add(`${spec.on}.${spec.fk}`);
      } else if (spec.check) {
        if (!checkPending(spec)) continue;
        await runDdl(client, WORK_ATTACHMENTS_DDL[name]);
      } else if (!presentIndexes.has(spec.index) && presentTables.has(spec.on)) {
        await runDdl(client, WORK_ATTACHMENTS_DDL[name]);
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
