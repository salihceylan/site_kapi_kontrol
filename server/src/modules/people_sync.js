// Kişi kayıtları (CRM) eşitleme: okuma/yazma anında çağrılan idempotent, küme tabanlı eşitleme.
//
// Sözleşme: docs/PLATFORM_KISILER.md. Mevcut katılım/onay/daire-sakini/davet akışlarına KANCA EKLENMEZ: bu akışların
// sonucu (apartment_memberships / apartments.resident_user_code) listeleme ve kart uçları çağrıldığında CRM'e yansır.
// SQL: people_sync_sql.js (backfill ile ortak).

import { pool } from '../db.js';
import { runSyncSteps } from './people_sync_sql.js';

/** Aynı site için eşitleme ve CRM yazmaları sıraya girsin diye ortak advisory kilit anahtarı. */
export function peopleLockKey(siteCode) {
  return `people_sync:${Number(siteCode)}`;
}

async function withSyncTransaction(lockKey, work) {
  const client = await pool.connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [lockKey]);
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    if (began) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackError) {
        // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
      }
    }
    throw error;
  } finally {
    client.release();
  }
}

/** Bir sitenin CRM kayıtlarını erişim üyelikleriyle eşitler (idempotent; ikinci çağrı satır değiştirmez). */
export async function syncSitePeople(siteCode) {
  const site = Number(siteCode);
  if (!Number.isSafeInteger(site) || site <= 0) {
    return null;
  }
  return withSyncTransaction(peopleLockKey(site), (client) => runSyncSteps(client, { siteCode: site, userCode: null }));
}

/** Bir kullanıcının TÜM sitelerdeki kayıtlarını eşitler (sakinin "Kayıtlarım" ekranı için). */
export async function syncUserPeople(userCode) {
  const user = Number(userCode);
  if (!Number.isSafeInteger(user) || user <= 0) {
    return null;
  }
  return withSyncTransaction(`people_sync_user:${user}`, (client) => runSyncSteps(client, { siteCode: null, userCode: user }));
}

/**
 * Okuma uçları için: eşitleme hatası okumayı ENGELLEMEZ (eski kayıtlar dönmeye devam eder); hata yalnız loglanır.
 */
export async function syncSitePeopleSafe(siteCode) {
  try {
    return await syncSitePeople(siteCode);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[people] syncSitePeople basarisiz:', error?.code || error?.message || error);
    return null;
  }
}

export async function syncUserPeopleSafe(userCode) {
  try {
    return await syncUserPeople(userCode);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[people] syncUserPeople basarisiz:', error?.code || error?.message || error);
    return null;
  }
}
