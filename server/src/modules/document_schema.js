// Belgeler (Faz 3b-A) şeması: 039. migrations/039_documents.sql ile AYNI ifadeler, AYNI sırayla (test: document_schema).
//
// Üç yeni tablo (ekleyici): documents, document_versions, announcement_attachments. Mevcut tablolara sütun/indeks EKLENMEZ (`announcements` / `users` DDL'e uğramaz).
// Açılış deadlock'u dersi (R2 F-1, bkz. db.js ensureAccountDeletionSchema): `CREATE TABLE/INDEX IF NOT EXISTS` nesne VARKEN bile kilit alabilir ve dev
// ensureDbSchema bloğunun tek örtük işlemine konursa yazıcılarla 40P01 üretir. Bu yüzden ifadeler db.js'te blok BİTTİKTEN sonra, katalog kontrolüyle
// (pg_class / pg_indexes / pg_constraint) ve her biri kendi otomatik onaylı ifadesiyle yalnız EKSİK olanlar için çalışır. Her şey varsa (normal açılış)
// hiçbir tabloda kilit alınmaz. Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).
//
// R11 F1 (satır içi FK dersi, bkz. bulk_import_schema.js / finance_4b_schema.js HOT_PARENTS): satır içi `REFERENCES sites / users / announcements` içeren tek bir
// CREATE TABLE başvurulan SICAK tabloları ardışık SHARE ROW EXCLUSIVE ile kilitler; eşzamanlı yazıcıyla ters sırada kesişince 40P01 doğar (90 denemede 64 kez).
// Bu yüzden tablolar FK'SIZ oluşturulur; her FK ayrı, katalog korumalı `ALTER TABLE ... ADD CONSTRAINT <tablo>_<sütun>_fkey` ifadesidir (ifade başına TEK
// sıcak üst tablo: bekleyebilir ama kilit döngüsü kuramaz). Kısıt adları Postgres'in satır içi FK adlarıyla AYNIDIR (<tablo>_<sütun>_fkey): eski satır içi
// şemayla kurulmuş veritabanlarında FK'ler "mevcut" sayılır, katalog eşitliği korunur.

const MIMES = [
  'application/pdf',
  'image/jpeg',
  'image/png',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
];

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

/** Sıra BAĞLAYICIDIR (migration ile aynı): önce tablo, sonra o tablonun FK'leri, sonra indeksleri. */
export const DOCUMENTS_DDL = Object.freeze({
  documentsTable: `
    CREATE TABLE IF NOT EXISTS documents (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT NOT NULL,
      category TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT,
      audience TEXT NOT NULL DEFAULT 'managers',
      target_type TEXT NOT NULL DEFAULT 'site',
      target_block_ids BIGINT[] NOT NULL DEFAULT '{}',
      target_apartment_ids BIGINT[] NOT NULL DEFAULT '{}',
      status TEXT NOT NULL DEFAULT 'pending',
      current_version_no INTEGER,
      version_count INTEGER NOT NULL DEFAULT 0,
      next_version_no INTEGER NOT NULL DEFAULT 1,
      download_count BIGINT NOT NULL DEFAULT 0,
      idempotency_key TEXT,
      created_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      deleted_at TIMESTAMPTZ,
      deleted_by INTEGER,
      CONSTRAINT chk_documents_category CHECK (category IN ('regulation', 'minutes', 'contract', 'notice', 'other')),
      CONSTRAINT chk_documents_title_length CHECK (char_length(title) BETWEEN 1 AND 120),
      CONSTRAINT chk_documents_description_length CHECK (description IS NULL OR char_length(description) <= 1000),
      CONSTRAINT chk_documents_audience CHECK (audience IN ('residents', 'board', 'managers')),
      CONSTRAINT chk_documents_target_type CHECK (target_type IN ('site', 'blocks', 'apartments')),
      CONSTRAINT chk_documents_status CHECK (status IN ('pending', 'active', 'deleted')),
      CONSTRAINT chk_documents_target_audience CHECK (
        audience = 'residents' OR (target_type = 'site' AND cardinality(target_block_ids) = 0 AND cardinality(target_apartment_ids) = 0)
      ),
      CONSTRAINT chk_documents_target_ids CHECK (
        (target_type = 'site' AND cardinality(target_block_ids) = 0 AND cardinality(target_apartment_ids) = 0)
        OR (target_type = 'blocks' AND cardinality(target_block_ids) BETWEEN 1 AND 500 AND cardinality(target_apartment_ids) = 0)
        OR (target_type = 'apartments' AND cardinality(target_apartment_ids) BETWEEN 1 AND 500 AND cardinality(target_block_ids) = 0)
      ),
      CONSTRAINT chk_documents_deleted CHECK ((status = 'deleted') = (deleted_at IS NOT NULL)),
      CONSTRAINT chk_documents_active_version CHECK (status <> 'active' OR current_version_no IS NOT NULL),
      CONSTRAINT chk_documents_idempotency_key CHECK (idempotency_key IS NULL OR char_length(idempotency_key) <= 64)
    )
  `,
  documentsSiteFk: foreignKeySql('documents', 'site_code', 'sites', 'site_code', 'CASCADE'),
  documentsCreatedByFk: foreignKeySql('documents', 'created_by', 'users', 'user_code', 'SET NULL'),
  documentsDeletedByFk: foreignKeySql('documents', 'deleted_by', 'users', 'user_code', 'SET NULL'),
  documentsSiteStatusIndex: `CREATE INDEX IF NOT EXISTS idx_documents_site_status ON documents (site_code, status, id DESC)`,
  documentsSiteCategoryIndex: `CREATE INDEX IF NOT EXISTS idx_documents_site_category ON documents (site_code, category, id DESC) WHERE status = 'active'`,
  documentsIdempotencyIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_documents_idempotency ON documents (site_code, created_by, idempotency_key) WHERE idempotency_key IS NOT NULL`,
  documentsLifecycleIndex: `CREATE INDEX IF NOT EXISTS idx_documents_lifecycle ON documents (status, deleted_at) WHERE status IN ('deleted', 'pending')`,
  documentsCreatedByIndex: `CREATE INDEX IF NOT EXISTS idx_documents_created_by ON documents (created_by) WHERE created_by IS NOT NULL`,
  documentsDeletedByIndex: `CREATE INDEX IF NOT EXISTS idx_documents_deleted_by ON documents (deleted_by) WHERE deleted_by IS NOT NULL`,
  versionsTable: `
    CREATE TABLE IF NOT EXISTS document_versions (
      id BIGSERIAL PRIMARY KEY,
      document_id BIGINT NOT NULL,
      site_code BIGINT NOT NULL,
      version_no INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'uploading',
      storage_key TEXT NOT NULL,
      display_name TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      declared_size_bytes BIGINT NOT NULL,
      size_bytes BIGINT NOT NULL,
      sha256 TEXT,
      scan_status TEXT NOT NULL DEFAULT 'not_scanned',
      note TEXT,
      uploaded_by INTEGER,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      completed_at TIMESTAMPTZ,
      CONSTRAINT uq_document_versions_key UNIQUE (storage_key),
      CONSTRAINT uq_document_versions_number UNIQUE (document_id, version_no),
      CONSTRAINT chk_document_versions_number CHECK (version_no > 0),
      CONSTRAINT chk_document_versions_status CHECK (status IN ('uploading', 'ready')),
      CONSTRAINT chk_document_versions_mime CHECK (mime_type IN (${MIMES.map((mime) => `'${mime}'`).join(', ')})),
      CONSTRAINT chk_document_versions_sizes CHECK (declared_size_bytes > 0 AND size_bytes >= 0),
      CONSTRAINT chk_document_versions_sha CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
      CONSTRAINT chk_document_versions_scan CHECK (scan_status IN ('not_scanned', 'clean', 'infected', 'error')),
      CONSTRAINT chk_document_versions_name_length CHECK (char_length(display_name) BETWEEN 1 AND 120),
      CONSTRAINT chk_document_versions_note_length CHECK (note IS NULL OR char_length(note) <= 200),
      CONSTRAINT chk_document_versions_ready CHECK (status <> 'ready' OR (sha256 IS NOT NULL AND completed_at IS NOT NULL))
    )
  `,
  versionsDocumentFk: foreignKeySql('document_versions', 'document_id', 'documents', 'id', 'CASCADE'),
  versionsSiteFk: foreignKeySql('document_versions', 'site_code', 'sites', 'site_code', 'CASCADE'),
  versionsUploadedByFk: foreignKeySql('document_versions', 'uploaded_by', 'users', 'user_code', 'SET NULL'),
  versionsSiteIndex: `CREATE INDEX IF NOT EXISTS idx_document_versions_site ON document_versions (site_code)`,
  versionsUploadingIndex: `CREATE INDEX IF NOT EXISTS idx_document_versions_uploading ON document_versions (status, created_at) WHERE status = 'uploading'`,
  versionsUploadedByIndex: `CREATE INDEX IF NOT EXISTS idx_document_versions_uploaded_by ON document_versions (uploaded_by) WHERE uploaded_by IS NOT NULL`,
  attachmentsTable: `
    CREATE TABLE IF NOT EXISTS announcement_attachments (
      announcement_id BIGINT NOT NULL,
      document_id BIGINT NOT NULL,
      position SMALLINT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (announcement_id, document_id),
      CONSTRAINT chk_announcement_attachments_position CHECK (position BETWEEN 0 AND 4)
    )
  `,
  attachmentsAnnouncementFk: foreignKeySql('announcement_attachments', 'announcement_id', 'announcements', 'id', 'CASCADE'),
  attachmentsDocumentFk: foreignKeySql('announcement_attachments', 'document_id', 'documents', 'id', 'CASCADE'),
  attachmentsDocumentIndex: `CREATE INDEX IF NOT EXISTS idx_announcement_attachments_document ON announcement_attachments (document_id)`,
});

/**
 * İfade adı -> { tablo | indeks | fk, bağımlılıklar }. Sıra DOCUMENTS_DDL ile aynıdır.
 * `needs`: tablo adımı için önkoşul tablolar; `parent`: FK adımı için başvurulan tablo (sites / users her zaman vardır).
 */
const STEPS = Object.freeze([
  ['documentsTable', { table: 'documents' }],
  ['documentsSiteFk', { fk: 'documents_site_code_fkey', on: 'documents', parent: 'sites' }],
  ['documentsCreatedByFk', { fk: 'documents_created_by_fkey', on: 'documents', parent: 'users' }],
  ['documentsDeletedByFk', { fk: 'documents_deleted_by_fkey', on: 'documents', parent: 'users' }],
  ['documentsSiteStatusIndex', { index: 'idx_documents_site_status', on: 'documents' }],
  ['documentsSiteCategoryIndex', { index: 'idx_documents_site_category', on: 'documents' }],
  ['documentsIdempotencyIndex', { index: 'uq_documents_idempotency', on: 'documents' }],
  ['documentsLifecycleIndex', { index: 'idx_documents_lifecycle', on: 'documents' }],
  ['documentsCreatedByIndex', { index: 'idx_documents_created_by', on: 'documents' }],
  ['documentsDeletedByIndex', { index: 'idx_documents_deleted_by', on: 'documents' }],
  ['versionsTable', { table: 'document_versions', needs: ['documents'] }],
  ['versionsDocumentFk', { fk: 'document_versions_document_id_fkey', on: 'document_versions', parent: 'documents' }],
  ['versionsSiteFk', { fk: 'document_versions_site_code_fkey', on: 'document_versions', parent: 'sites' }],
  ['versionsUploadedByFk', { fk: 'document_versions_uploaded_by_fkey', on: 'document_versions', parent: 'users' }],
  ['versionsSiteIndex', { index: 'idx_document_versions_site', on: 'document_versions' }],
  ['versionsUploadingIndex', { index: 'idx_document_versions_uploading', on: 'document_versions' }],
  ['versionsUploadedByIndex', { index: 'idx_document_versions_uploaded_by', on: 'document_versions' }],
  ['attachmentsTable', { table: 'announcement_attachments', needs: ['documents', 'announcements'] }],
  ['attachmentsAnnouncementFk', { fk: 'announcement_attachments_announcement_id_fkey', on: 'announcement_attachments', parent: 'announcements' }],
  ['attachmentsDocumentFk', { fk: 'announcement_attachments_document_id_fkey', on: 'announcement_attachments', parent: 'documents' }],
  ['attachmentsDocumentIndex', { index: 'idx_announcement_attachments_document', on: 'announcement_attachments' }],
]);

export const DOCUMENTS_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

const RETRYABLE = new Set(['40P01', '55P03']);
/** Test ayarı: yeniden deneme beklemesi (ms) çarpanı. */
export const schemaTuning = { retryDelayMs: 300 };

/**
 * Tek DDL ifadesi. FK ekleme, tablo ile başvurulan tablo üstünde kısa süreli SHARE ROW EXCLUSIVE kilidi ister; yoğun yazma yükü altında (YALNIZ ilk dağıtım)
 * nadiren 40P01 / 55P03 doğabilir. İfade tek başına otomatik onaylı olduğundan güvenle yeniden denenir (en çok 6 deneme, artan bekleme; her deneme en çok 2 sn kilit bekler).
 */
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
 * 039'u uygular (db.js ensureDbSchema bloğu BİTTİKTEN sonra çağrılır). Tek katalog sorgusuyla eksik nesneler belirlenir; yalnız eksikler, sırayla ve
 * kendi otomatik onaylı ifadeleriyle çalışır. `announcements` henüz yoksa (platform öncesi şema) ek tablosu ve FK'leri atlanır; tablo oluşunca sonraki açılışta yapılır.
 * Tablo var ama bir FK eksikse (ör. tablo ile FK arasında süreç çöktü) yalnız o FK tamamlanır.
 */
export async function ensureDocumentsSchema(client) {
  const tables = ['documents', 'document_versions', 'announcement_attachments', 'announcements'];
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
        ) AS fks
    `,
    [tables, indexes, foreignKeys],
  );
  const presentTables = new Set(found.rows[0]?.tables ?? []);
  const presentIndexes = new Set(found.rows[0]?.indexes ?? []);
  const presentFks = new Set(found.rows[0]?.fks ?? []);
  const hasParent = (parent) => parent === 'sites' || parent === 'users' || presentTables.has(parent);
  const fkPresent = (spec) => presentFks.has(`${spec.on}.${spec.fk}`);
  // Eksik nesne yoksa (her normal açılış) hiçbir ifade gönderilmez: kilit alınmaz.
  const pending = STEPS.filter(([, spec]) => {
    if (spec.table) return !presentTables.has(spec.table) && (spec.needs ?? []).every((dependency) => presentTables.has(dependency) || dependency === 'documents');
    if (spec.fk) return presentTables.has(spec.on) && hasParent(spec.parent) && !fkPresent(spec);
    return !presentIndexes.has(spec.index);
  });
  // Henüz oluşmamış tabloların FK'leri de eksiktir: tablo adımı pending ise zaten çalışacak; ondan sonrası aşağıdaki döngüde yürür.
  if (pending.length === 0) {
    return;
  }
  // Kilit kuyruğunda sonsuza dek beklemesin (bekleyen bir DDL, arkasındaki TÜM yazıcıları tıkar): 2 sn sonra 55P03, runDdl yeniden dener.
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const [name, spec] of STEPS) {
      if (spec.table) {
        if (presentTables.has(spec.table)) continue;
        if ((spec.needs ?? []).some((dependency) => !presentTables.has(dependency))) continue;
        await runDdl(client, DOCUMENTS_DDL[name]);
        presentTables.add(spec.table);
      } else if (spec.fk) {
        if (!presentTables.has(spec.on) || !hasParent(spec.parent) || fkPresent(spec)) continue;
        await runDdl(client, DOCUMENTS_DDL[name]);
        presentFks.add(`${spec.on}.${spec.fk}`);
      } else if (!presentIndexes.has(spec.index) && presentTables.has(spec.on)) {
        await runDdl(client, DOCUMENTS_DDL[name]);
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
