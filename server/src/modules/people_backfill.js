// people_v1: mevcut sakinlerin Kişi ve Daire Kayıtları'na (CRM) TEK SEFERLİK aktarımı (ensureDbSchema içinden çağrılır).
//
// Sözleşme: docs/PLATFORM_KISILER.md. Bu dosya db.js'ten içe aktarılır: db.js'i İÇE AKTARMAZ (döngü olmasın).
//  - Kendi transaction'ında çalışır; advisory kilit ile eşzamanlı iki açılış çift çalıştırmaz.
//  - platform_backfills(code) kaydı VARSA hiçbir şey yapmaz (ikinci çalıştırma no-op). Kayıt, aktarımla AYNI transaction'da
//    yazılır: hata olursa hepsi geri alınır ve sonraki açılışta yeniden denenir.
//  - Hiçbir apartment_memberships / kapı yetkisi satırına DOKUNMAZ; yalnız site_people ve apartment_residencies yazılır.

import { runSyncSteps } from './people_sync_sql.js';

export const PEOPLE_BACKFILL_CODE = 'people_v1';
const BACKFILL_LOCK_KEY = 'platform_backfill:people_v1';

/**
 * @param {{ query: Function }} client  tek bağlantı (transaction'ı bu fonksiyon yönetir)
 * @returns {Promise<{ ran: boolean, counts?: Record<string, number> }>}
 */
export async function runPeopleBackfill(client) {
  await client.query('BEGIN');
  try {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [BACKFILL_LOCK_KEY]);
    const done = await client.query('SELECT 1 FROM platform_backfills WHERE code = $1 LIMIT 1', [PEOPLE_BACKFILL_CODE]);
    if ((done.rows?.length ?? 0) > 0) {
      await client.query('COMMIT');
      return { ran: false };
    }
    const counts = await runSyncSteps(client, { siteCode: null, userCode: null });
    await client.query(
      'INSERT INTO platform_backfills (code) VALUES ($1) ON CONFLICT (code) DO NOTHING',
      [PEOPLE_BACKFILL_CODE],
    );
    await client.query('COMMIT');
    return { ran: true, counts };
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (_rollbackError) {
      // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
    }
    throw error;
  }
}
