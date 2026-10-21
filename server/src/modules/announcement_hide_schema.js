// Duyuru gizleme ve yumuşak silme şeması: 057. migrations/057_announcement_hide_delete.sql ile AYNI ifadeler, AYNI sırayla (test: announcement_hide_schema).
//
// Ekleyici, yeni tablo / FK yok:
//  - announcement_recipients.hidden_at: alıcının duyuruyu KENDİ listesinden kaldırması (okundu bilgisine dokunmaz; Geri al = NULL).
//  - announcements.deleted_at: yöneticinin yumuşak silmesi (yalnız withdrawn satırda; kayıt saklanır).
// ALTER'ler yalnız katalog sütunun eksik olduğunu söylüyorsa, kendi otomatik onaylı ifadesiyle, lock_timeout 2 sn + 40P01/55P03'te yeniden denemeyle çalışır.
// Bu dosya db.js'i İÇE AKTARMAZ (döngü olmasın).

export const ANNOUNCEMENT_HIDE_DDL = Object.freeze({
  deletedColumn: `ALTER TABLE announcements ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ`,
  hiddenColumn: `ALTER TABLE announcement_recipients ADD COLUMN IF NOT EXISTS hidden_at TIMESTAMPTZ`,
  deletedCheck: `
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_announcements_deleted_withdrawn' AND conrelid = 'announcements'::regclass
      ) THEN
        ALTER TABLE announcements ADD CONSTRAINT chk_announcements_deleted_withdrawn CHECK (deleted_at IS NULL OR status = 'withdrawn') NOT VALID;
      END IF;
    END $$
  `,
});

export const ANNOUNCEMENT_HIDE_DDL_ORDER = Object.freeze(['deletedColumn', 'hiddenColumn', 'deletedCheck']);

export const announcementHideTuning = { retryDelayMs: 300 };

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
      await sleep(announcementHideTuning.retryDelayMs * attempt);
    }
  }
}

/** db.js'te ensureDbSchema bloğu BİTTİKTEN sonra çağrılır. Her şey varsa tek katalog sorgusu, kilit yok. */
export async function ensureAnnouncementHideSchema(client) {
  const found = await client.query(`
    SELECT
      to_regclass('public.announcements') IS NOT NULL AND to_regclass('public.announcement_recipients') IS NOT NULL AS has_tables,
      EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('public.announcements') AND attname = 'deleted_at' AND NOT attisdropped) AS has_deleted,
      EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = to_regclass('public.announcement_recipients') AND attname = 'hidden_at' AND NOT attisdropped) AS has_hidden,
      EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_announcements_deleted_withdrawn' AND conrelid = to_regclass('public.announcements')) AS has_check
  `);
  const state = found.rows[0] ?? {};
  if (state.has_tables !== true) return;
  const pending = {
    deletedColumn: state.has_deleted !== true,
    hiddenColumn: state.has_hidden !== true,
    deletedCheck: state.has_check !== true,
  };
  if (!Object.values(pending).some(Boolean)) return;
  await client.query("SET lock_timeout = '2s'");
  try {
    for (const name of ANNOUNCEMENT_HIDE_DDL_ORDER) {
      if (pending[name]) await runDdl(client, ANNOUNCEMENT_HIDE_DDL[name]);
    }
  } finally {
    await client.query('RESET lock_timeout').catch(() => {});
  }
}
