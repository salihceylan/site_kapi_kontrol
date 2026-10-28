// Geri bildirim ekleri (103): bakım adımı. document_maintenance.js turunun içinde (aynı süreçler arası tek çalışan kilidi altında) çağrılır.
//
// 2 saati aşan `uploading` ek kayıtları: ÖNCE SATIR (süre koşulu DELETE'te tekrar sınanır), silindiyse SONRA dosya: geç gelen PUT satırı `ready` yaptıysa dosyaya
// dokunulmaz (iş takibi fotoğraf eki bakımıyla aynı kural). Tablo yoksa (103 kurulmamış) hiçbir şey yapılmaz. Hata bakım turunu durdurmaz (çağıran `safe` sarar).
// Yetim dosya süpürmesi bilerek YOKTUR (geri bildirim ekleri az ve küçüktür); yetim kalan dosya yalnız DB adımı çöktüğünde oluşur ve disk kotasına sayılmaz.

import { removeStoredFile } from './document_storage.js';
import { FEEDBACK_SUBTREE, FEEDBACK_UPLOAD_TTL_MINUTES } from './feedback_common.js';

const BATCH_LIMIT = 200;

async function feedbackTablePresent(db) {
  const result = await db.query(`SELECT to_regclass('public.feedback_attachments') IS NOT NULL AS present`);
  return result.rows?.[0]?.present === true;
}

/**
 * @param {string} root depo kökü
 * @param {{ feedback_stale_uploads: number, errors: number }} summary bakım özeti (yerinde güncellenir)
 * @param {{ query: Function }} db
 */
export async function cleanStaleFeedbackUploads(root, summary, db) {
  if (!(await feedbackTablePresent(db))) return;
  const stale = await db.query(
    `
      SELECT id, storage_key
      FROM feedback_attachments
      WHERE status = 'uploading' AND created_at < NOW() - make_interval(mins => $1::INTEGER)
      ORDER BY created_at
      LIMIT $2
    `,
    [FEEDBACK_UPLOAD_TTL_MINUTES, BATCH_LIMIT],
  );
  for (const row of stale.rows ?? []) {
    try {
      const removed = await db.query(
        `DELETE FROM feedback_attachments WHERE id = $1 AND status = 'uploading' AND created_at < NOW() - make_interval(mins => $2::INTEGER) RETURNING storage_key`,
        [row.id, FEEDBACK_UPLOAD_TTL_MINUTES],
      );
      if (Number(removed.rowCount ?? removed.rows?.length ?? 0) === 0) continue;
      summary.feedback_stale_uploads += 1;
      const key = removed.rows?.[0]?.storage_key ?? row.storage_key;
      if (key) await removeStoredFile(root, key, FEEDBACK_SUBTREE);
    } catch (error) {
      summary.errors += 1;
      // eslint-disable-next-line no-console
      console.error('[feedback] bayat ek yuklemesi temizlenemedi:', error?.code || 'error');
    }
  }
}
