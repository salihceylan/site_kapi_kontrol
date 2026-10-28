// Geri bildirim şeması: 103. migrations/103_feedback.sql ile AYNI ifadeler, AYNI sırayla (test: feedback_schema).
//
// İki yeni tablo (ekleyici): feedback_reports (site, kullanıcı, rol, ekran adı + rota, metin) ve feedback_attachments (en çok 4 fotoğraf; iş takibi fotoğraf eki
// deseni: `uploading` -> `ready`, storage_key sunucuda üretilir). Mevcut tablolara sütun / indeks EKLENMEZ.
// Açılış deadlock'u dersi (bkz. work_attachments_schema.js): ifadeler db.js'te dev ensureDbSchema bloğu BİTTİKTEN sonra, katalog kontrolüyle ve her biri kendi otomatik
// onaylı ifadesiyle yalnız EKSİK olanlar için çalışır; her şey varsa hiçbir tabloda kilit alınmaz. Tablolar FK'SIZ oluşturulur; her FK ayrı, katalog korumalı
// `ALTER TABLE ... ADD CONSTRAINT <tablo>_<sütun>_fkey` ifadesidir (ifade başına TEK üst tablo; sites / users sıcak tablolardır).
// Silme politikası: site silinince geri bildirimleri CASCADE (dosyalar diskte kalır); kullanıcı SATIRI fiziksel silinirse user_code SET NULL (gönderen "Silinmiş
// Kullanıcı" görünür); geri bildirim silinince ek satırları CASCADE. Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

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

/** Sıra BAĞLAYICIDIR (migration ile aynı): önce tablolar, sonra FK'ler, sonra indeksler. */
export const FEEDBACK_DDL = Object.freeze({
  reportsTable: `
    CREATE TABLE IF NOT EXISTS feedback_reports (
      id BIGSERIAL PRIMARY KEY,
      site_code BIGINT,
      user_code INTEGER,
      role TEXT NOT NULL,
      screen_name TEXT NOT NULL,
      screen_route TEXT NOT NULL,
      message TEXT NOT NULL,
      app_version TEXT,
      platform TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CONSTRAINT chk_feedback_reports_role CHECK (char_length(role) BETWEEN 1 AND 60),
      CONSTRAINT chk_feedback_reports_screen_name CHECK (char_length(screen_name) BETWEEN 1 AND 120),
      CONSTRAINT chk_feedback_reports_screen_route CHECK (char_length(screen_route) BETWEEN 1 AND 120),
      CONSTRAINT chk_feedback_reports_message CHECK (char_length(message) BETWEEN 1 AND 2000),
      CONSTRAINT chk_feedback_reports_app_version CHECK (app_version IS NULL OR char_length(app_version) <= 40),
      CONSTRAINT chk_feedback_reports_platform CHECK (platform IS NULL OR char_length(platform) <= 20)
    )
  `,
  attachmentsTable: `
    CREATE TABLE IF NOT EXISTS feedback_attachments (
      id BIGSERIAL PRIMARY KEY,
      feedback_id BIGINT NOT NULL,
      file_name TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      size_bytes BIGINT NOT NULL,
      sha256 TEXT,
      status TEXT NOT NULL DEFAULT 'uploading',
      storage_key TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      ready_at TIMESTAMPTZ,
      CONSTRAINT chk_feedback_attachments_file_name CHECK (char_length(file_name) BETWEEN 1 AND 160),
      CONSTRAINT chk_feedback_attachments_mime CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp')),
      CONSTRAINT chk_feedback_attachments_size CHECK (size_bytes BETWEEN 1 AND 5242880),
      CONSTRAINT chk_feedback_attachments_status CHECK (status IN ('uploading', 'ready')),
      CONSTRAINT chk_feedback_attachments_ready CHECK ((status = 'ready') = (ready_at IS NOT NULL)),
      CONSTRAINT chk_feedback_attachments_sha256 CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$')
    )
  `,
  reportsSiteFk: foreignKeySql('feedback_reports', 'site_code', 'sites', 'site_code', 'CASCADE'),
  reportsUserFk: foreignKeySql('feedback_reports', 'user_code', 'users', 'user_code', 'SET NULL'),
  attachmentsFeedbackFk: foreignKeySql('feedback_attachments', 'feedback_id', 'feedback_reports', 'id', 'CASCADE'),
  reportsSiteIndex: `CREATE INDEX IF NOT EXISTS idx_feedback_reports_site ON feedback_reports (site_code, id DESC) WHERE site_code IS NOT NULL`,
  reportsUserIndex: `CREATE INDEX IF NOT EXISTS idx_feedback_reports_user_created ON feedback_reports (user_code, created_at) WHERE user_code IS NOT NULL`,
  attachmentsFeedbackIndex: `CREATE INDEX IF NOT EXISTS idx_feedback_attachments_feedback ON feedback_attachments (feedback_id)`,
  attachmentsUploadingIndex: `CREATE INDEX IF NOT EXISTS idx_feedback_attachments_uploading ON feedback_attachments (created_at) WHERE status = 'uploading'`,
  attachmentsStorageKeyIndex: `CREATE UNIQUE INDEX IF NOT EXISTS uq_feedback_attachments_storage_key ON feedback_attachments (storage_key) WHERE storage_key IS NOT NULL`,
});

/** İfade adı -> { tablo | indeks | fk }. Sıra FEEDBACK_DDL ile aynıdır. */
const STEPS = Object.freeze([
  ['reportsTable', { table: 'feedback_reports' }],
  ['attachmentsTable', { table: 'feedback_attachments' }],
  ['reportsSiteFk', { fk: 'feedback_reports_site_code_fkey', on: 'feedback_reports', parent: 'sites' }],
  ['reportsUserFk', { fk: 'feedback_reports_user_code_fkey', on: 'feedback_reports', parent: 'users' }],
  ['attachmentsFeedbackFk', { fk: 'feedback_attachments_feedback_id_fkey', on: 'feedback_attachments', parent: 'feedback_reports' }],
  ['reportsSiteIndex', { index: 'idx_feedback_reports_site', on: 'feedback_reports' }],
  ['reportsUserIndex', { index: 'idx_feedback_reports_user_created', on: 'feedback_reports' }],
  ['attachmentsFeedbackIndex', { index: 'idx_feedback_attachments_feedback', on: 'feedback_attachments' }],
  ['attachmentsUploadingIndex', { index: 'idx_feedback_attachments_uploading', on: 'feedback_attachments' }],
  ['attachmentsStorageKeyIndex', { index: 'uq_feedback_attachments_storage_key', on: 'feedback_attachments' }],
]);

export const FEEDBACK_DDL_ORDER = Object.freeze(STEPS.map(([name]) => name));

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
 * 103'ü uygular (db.js'te yeterince geç çağrılır). Tek katalog sorgusuyla eksik nesneler belirlenir; yalnız eksikler, sırayla ve kendi otomatik onaylı
 * ifadeleriyle çalışır. Her şey varsa (normal açılış) hiçbir ifade gönderilmez.
 */
export async function ensureFeedbackSchema(client) {
  const tables = ['feedback_reports', 'feedback_attachments'];
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
  const pending = STEPS.filter(([, spec]) => {
    if (spec.table) return !presentTables.has(spec.table);
    if (spec.fk) return presentTables.has(spec.on) && hasParent(spec.parent) && !fkPresent(spec);
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
        await runDdl(client, FEEDBACK_DDL[name]);
        presentTables.add(spec.table);
      } else if (spec.fk) {
        if (!presentTables.has(spec.on) || !hasParent(spec.parent) || fkPresent(spec)) continue;
        await runDdl(client, FEEDBACK_DDL[name]);
        presentFks.add(`${spec.on}.${spec.fk}`);
      } else if (!presentIndexes.has(spec.index) && presentTables.has(spec.on)) {
        await runDdl(client, FEEDBACK_DDL[name]);
      }
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
