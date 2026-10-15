// Kişi kayıtları (CRM) eşitleme: okuma/yazma anında çağrılan idempotent, küme tabanlı eşitleme.
//
// Sözleşme: docs/PLATFORM_KISILER.md. Mevcut katılım/onay/daire-sakini/davet akışlarına KANCA EKLENMEZ: bu akışların
// sonucu (apartment_memberships / apartments.resident_user_code) listeleme ve kart uçları çağrıldığında CRM'e yansır.
// SQL: people_sync_sql.js (backfill ile ortak).
//
// Okuma uçları eşitlemeyi `*Safe` varyantlarıyla çağırır: havuz bağlantısı tutup site kilidini BEKLEMEZ (pg_try_advisory_xact_lock;
// meşgulse eşitleme ATLANIR, okuma yine çalışır) ve aynı site/kullanıcı için kısa süre içinde tekrar eşitleme yapılmaz
// (bellek içi kısıtlama; PEOPLE_SYNC_MIN_INTERVAL_MS, varsayılan 5000 ms, 0 = kapalı). Yazma uçları ve açık çağrılar kilidi BEKLER.

import { pool } from '../db.js';
import { runSyncSteps } from './people_sync_sql.js';

const DEFAULT_MIN_INTERVAL_MS = 5000;
const THROTTLE_MAX_ENTRIES = 5000;
const throttle = new Map();

function minIntervalMs() {
  const raw = process.env.PEOPLE_SYNC_MIN_INTERVAL_MS;
  if (raw === undefined || raw === '') {
    return DEFAULT_MIN_INTERVAL_MS;
  }
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : DEFAULT_MIN_INTERVAL_MS;
}

/** Test yardımcısı: bellek içi kısıtlamayı sıfırlar. */
export function resetPeopleSyncThrottle() {
  throttle.clear();
}

function recentlySynced(key) {
  const interval = minIntervalMs();
  if (interval <= 0) {
    return false;
  }
  const last = throttle.get(key);
  return last !== undefined && Date.now() - last < interval;
}

function markSynced(key) {
  if (throttle.size >= THROTTLE_MAX_ENTRIES) {
    const cutoff = Date.now() - Math.max(minIntervalMs(), 1000);
    for (const [entryKey, at] of throttle) {
      if (at < cutoff) {
        throttle.delete(entryKey);
      }
    }
    if (throttle.size >= THROTTLE_MAX_ENTRIES) {
      throttle.clear();
    }
  }
  throttle.set(key, Date.now());
}

/** Aynı site için eşitleme ve CRM yazmaları sıraya girsin diye ortak advisory kilit anahtarı. */
export function peopleLockKey(siteCode) {
  return `people_sync:${Number(siteCode)}`;
}

const SKIPPED_BUSY = Object.freeze({ skipped: true, reason: 'busy' });

async function withSyncTransaction(lockKey, work, { wait = true } = {}) {
  const client = await pool.connect();
  let began = false;
  try {
    await client.query('BEGIN');
    began = true;
    if (wait) {
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [lockKey]);
    } else {
      const lock = await client.query('SELECT pg_try_advisory_xact_lock(hashtext($1)) AS locked', [lockKey]);
      if (lock.rows?.[0]?.locked !== true) {
        await client.query('ROLLBACK');
        began = false;
        return SKIPPED_BUSY;
      }
    }
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

/** Bir sitenin CRM kayıtlarını erişim üyelikleriyle eşitler (idempotent; ikinci çağrı satır değiştirmez). `wait:false` meşgulse atlar. */
export async function syncSitePeople(siteCode, { wait = true } = {}) {
  const site = Number(siteCode);
  if (!Number.isSafeInteger(site) || site <= 0) {
    return null;
  }
  return withSyncTransaction(peopleLockKey(site), (client) => runSyncSteps(client, { siteCode: site, userCode: null }), { wait });
}

/** Bir kullanıcının TÜM sitelerdeki kayıtlarını eşitler (sakinin "Kayıtlarım" ekranı için). */
export async function syncUserPeople(userCode, { wait = true } = {}) {
  const user = Number(userCode);
  if (!Number.isSafeInteger(user) || user <= 0) {
    return null;
  }
  return withSyncTransaction(
    `people_sync_user:${user}`,
    async (client) => {
      // Kullanıcı eşitlemesi birden çok sitenin kişi kayıtlarını YAZAR: CRM yazmalarıyla (site kilidi) yarışıp "Taşındı" sonrası
      // hayalet ilişki eklemesin diye ilgili sitelerin kilidi de alınır (okuma ucunda try-lock: meşgulse bu eşitleme atlanır).
      const sites = await client.query(
        `
          SELECT DISTINCT site_code FROM (
            SELECT a.site_code FROM apartment_memberships am INNER JOIN apartments a ON a.id = am.apartment_id WHERE am.user_code = $1
            UNION
            SELECT a.site_code FROM apartments a WHERE a.resident_user_code = $1
            UNION
            SELECT sp.site_code FROM site_people sp WHERE sp.user_code = $1
          ) s
          ORDER BY site_code
        `,
        [user],
      );
      for (const row of sites.rows ?? []) {
        const key = peopleLockKey(row.site_code);
        if (wait) {
          await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [key]);
        } else {
          const lock = await client.query('SELECT pg_try_advisory_xact_lock(hashtext($1)) AS locked', [key]);
          if (lock.rows?.[0]?.locked !== true) {
            return SKIPPED_BUSY;
          }
        }
      }
      return runSyncSteps(client, { siteCode: null, userCode: user });
    },
    { wait },
  );
}

async function safely(key, label, run) {
  if (recentlySynced(key)) {
    return { skipped: true, reason: 'throttled' };
  }
  try {
    const result = await run();
    if (result && result.skipped === true) {
      return result; // meşgul: çalışmakta olan eşitleme zaten tamamlanacak
    }
    markSynced(key);
    return result;
  } catch (error) {
    markSynced(key); // hata tekrarı her istekte DB'yi yormasın
    // eslint-disable-next-line no-console
    console.error(`[people] ${label} basarisiz:`, error?.code || error?.message || error);
    return null;
  }
}

/**
 * Okuma uçları için: eşitleme hatası okumayı ENGELLEMEZ (eski kayıtlar dönmeye devam eder); hata yalnız loglanır.
 * Kilit meşgulse veya kısa süre önce eşitlendiyse ATLANIR.
 */
export async function syncSitePeopleSafe(siteCode) {
  return safely(`site:${Number(siteCode)}`, 'syncSitePeople', () => syncSitePeople(siteCode, { wait: false }));
}

export async function syncUserPeopleSafe(userCode) {
  return safely(`user:${Number(userCode)}`, 'syncUserPeople', () => syncUserPeople(userCode, { wait: false }));
}
