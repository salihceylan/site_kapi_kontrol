// Duyuru zamanlayıcısı: zamanı gelen `scheduled` duyuruları yayınlar ve e-posta kuyruğunu sürer.
//
// Sözleşme: docs/PLATFORM_DUYURU.md ("Zamanlayıcı").
//  - startAnnouncementScheduler() sunucu açılışında (server.js) başlar; 30 sn'de bir tikler; setInterval unref'lidir (süreci tutmaz) ve
//    stopAnnouncementScheduler() ile temiz durur (kapanışta çalışan tikin bitmesi beklenir).
//  - Süreçler arası TEK ÇALIŞAN: pg_try_advisory_lock (iki-int anahtar, announcement_lock.js). Kilit başka yerdeyse tik atlanır.
//  - Her tikte en çok 20 duyuru yayınlanır (yayınlayan "Sistem"); kitle 0 ise duyuru yine `published` olur (recipient_count 0).
//    Her duyuru kendi transaction'ındadır: biri başarısız olursa diğerleri etkilenmez, sunucu düşmez. Başarısız kayıt için sayaç +1 ve üstel
//    geri çekilme (publish_attempts / next_attempt_at) yazılır: kalıcı hatalı (zehirli) kayıt her tikte yeniden denenip LIMIT sırasını tıkamaz,
//    log şişmez (yalnız 1. ve son başarısızlık loglanır); 10. başarısızlıktan sonra otomatik denenmez (elle yayın ucu çalışır).
//  - Ardından bekleyen e-posta varsa kuyruk ARKA PLANDA tetiklenir (tik beklemez).
//  - ANNOUNCEMENT_SCHEDULER_DISABLED=1 ile (testler) hiç başlamaz.

import { pool } from '../db.js';
import { failStaleRows, hasPendingEmails, kickEmailQueue, resumeEmailQueue, stopEmailQueue } from './announcement_email_queue.js';
import { MAX_PUBLISH_ATTEMPTS } from './announcement_common.js';
import { purgeStaleEmailHashes } from './announcement_email_queue.js';
import { ANNOUNCEMENT_LOCK_JOBS, acquireSessionLock } from './announcement_lock.js';
import { publishDueAnnouncement, recordPublishFailure } from './announcement_service.js';
import { hasPendingPush } from './push_outbox.js';
import { kickPushQueue } from './push_worker.js';

export const SCHEDULER_INTERVAL_MS = 30 * 1000;
export const SCHEDULER_FIRST_TICK_DELAY_MS = 5 * 1000;
export const SCHEDULER_LOCK_JOB = ANNOUNCEMENT_LOCK_JOBS.scheduler;
const HASH_PURGE_INTERVAL_MS = 60 * 60 * 1000;
export const MAX_PUBLISH_PER_TICK = 20;

/** Test / QA için değiştirilebilir bağımlılıklar. */
export const schedulerHooks = {
  publishDue: (args) => publishDueAnnouncement(args),
  recordFailure: (args) => recordPublishFailure(args),
  purgeHashes: () => purgeStaleEmailHashes(),
  closeStaleEmails: () => failStaleRows(pool),
  hasPendingEmails: () => hasPendingEmails(),
  kickEmailQueue: () => kickEmailQueue(),
  // Faz 3b-B telefon bildirimi: push kapalı / yapılandırılmamışsa hasPendingPush sorgusuz false döner.
  hasPendingPush: () => hasPendingPush(),
  kickPushQueue: () => kickPushQueue(),
};

let intervalTimer = null;
let firstTickTimer = null;
let tickPromise = null;
let stopped = false;
let lastPurgeAt = 0;

/** Test yardımcısı: durdurma işaretlerini (zamanlayıcı + e-posta kuyruğu) sıfırlar; zamanlayıcıyı BAŞLATMAZ. */
export function resetSchedulerState() {
  stopped = false;
  lastPurgeAt = 0;
  resumeEmailQueue();
}

export function isSchedulerDisabled(env = process.env) {
  const value = String(env.ANNOUNCEMENT_SCHEDULER_DISABLED ?? '').trim().toLowerCase();
  return value === '1' || value === 'true' || value === 'yes';
}

async function doTick() {
  const summary = { locked: false, published: 0, skipped: 0, failed: 0 };
  let lock = null;
  try {
    lock = await acquireSessionLock(SCHEDULER_LOCK_JOB);
    if (!lock) {
      summary.locked = true;
      return summary;
    }
    const due = await pool.query(
      `
        SELECT id, site_code
        FROM announcements
        WHERE status = 'scheduled' AND publish_at <= NOW()
          AND publish_attempts < $2 AND (next_attempt_at IS NULL OR next_attempt_at <= NOW())
        ORDER BY publish_at, id
        LIMIT $1
      `,
      [MAX_PUBLISH_PER_TICK, MAX_PUBLISH_ATTEMPTS],
    );
    for (const row of due.rows ?? []) {
      if (stopped) {
        break;
      }
      try {
        const result = await schedulerHooks.publishDue({ id: Number(row.id), siteCode: Number(row.site_code) });
        if (result?.published) {
          summary.published += 1;
        } else {
          summary.skipped += 1;
        }
      } catch (error) {
        summary.failed += 1;
        const code = error?.code || error?.message || 'hata';
        const attempts = await schedulerHooks.recordFailure({ id: Number(row.id), siteCode: Number(row.site_code), code });
        // Log oran sınırlı: yalnız ilk ve son (otomatik denemenin bırakıldığı) başarısızlık; aradakiler sayaçta.
        if (attempts <= 1 || attempts >= MAX_PUBLISH_ATTEMPTS) {
          // eslint-disable-next-line no-console
          console.error(`[announcement-scheduler] yayin basarisiz (id=${row.id}, deneme=${attempts}):`, code);
        }
      }
    }
  } catch (error) {
    summary.failed += 1;
    // eslint-disable-next-line no-console
    console.error('[announcement-scheduler] tik basarisiz:', error?.code || error?.message || 'hata');
  } finally {
    if (lock) {
      await lock.release().catch(() => {});
    }
  }
  // Eski adres özetleri saatte en çok bir kez temizlenir (gizlilik; hata tiki bozmaz).
  if (!stopped && Date.now() - lastPurgeAt >= HASH_PURGE_INTERVAL_MS) {
    lastPurgeAt = Date.now();
    try {
      await schedulerHooks.purgeHashes();
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[announcement-scheduler] ozet temizligi basarisiz:', error?.code || error?.message || 'hata');
    }
  }
  // Sahipsiz bekleyen e-postalar (geri çekilmiş duyurunun satırları, tükenmiş denemeler) kuyruk turu tetiklenmese de her tikte kapatılır:
  // düz adres DB'de sonsuza dek kalmaz. Kendi kilidi gerekmez (taze talepli satırlara dokunmaz); hata tiki bozmaz.
  if (!stopped) {
    try {
      await schedulerHooks.closeStaleEmails();
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[announcement-scheduler] sahipsiz e-posta kapatma basarisiz:', error?.code || error?.message || 'hata');
    }
  }
  // E-posta kuyruğu: yayınlar bittikten ve zamanlayıcı kilidi açıldıktan sonra arka planda (kendi tek-çalışan kilidi vardır).
  try {
    if (!stopped && (await schedulerHooks.hasPendingEmails())) {
      void schedulerHooks.kickEmailQueue();
    }
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[announcement-scheduler] kuyruk kontrolu basarisiz:', error?.code || error?.message || 'hata');
  }
  // Telefon bildirimi kuyruğu (Faz 3b-B): bekleyen varsa arka planda (kendi tek-çalışan kilidi, push_worker.js); push hazır değilse sorgu bile yok.
  try {
    if (!stopped && (await schedulerHooks.hasPendingPush())) {
      void schedulerHooks.kickPushQueue();
    }
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[announcement-scheduler] push kuyruk kontrolu basarisiz:', error?.code || error?.message || 'hata');
  }
  return summary;
}

/** Bir zamanlayıcı tikini çalıştırır (çakışan tik beklenen tikin sonucunu paylaşır). Hata fırlatmaz. */
export function runSchedulerTick() {
  if (!tickPromise) {
    tickPromise = doTick().finally(() => {
      tickPromise = null;
    });
  }
  return tickPromise;
}

/**
 * Zamanlayıcıyı başlatır. Kapalıysa (ANNOUNCEMENT_SCHEDULER_DISABLED) ya da zaten çalışıyorsa null / mevcut tutamaç döner.
 * @returns {{ stop: Function, intervalMs: number } | null}
 */
export function startAnnouncementScheduler({ intervalMs = SCHEDULER_INTERVAL_MS, env = process.env } = {}) {
  if (isSchedulerDisabled(env)) {
    return null;
  }
  if (!intervalTimer) {
    stopped = false;
    resumeEmailQueue();
    intervalTimer = setInterval(() => void runSchedulerTick(), intervalMs);
    intervalTimer.unref?.();
    firstTickTimer = setTimeout(() => {
      firstTickTimer = null;
      void runSchedulerTick();
    }, Math.min(SCHEDULER_FIRST_TICK_DELAY_MS, intervalMs));
    firstTickTimer.unref?.();
  }
  return { stop: stopAnnouncementScheduler, intervalMs };
}

/** Zamanlayıcıyı ve e-posta kuyruğunu durdurur; çalışan tikin / turun bitmesini en çok `timeoutMs` bekler. */
export async function stopAnnouncementScheduler({ timeoutMs = 5000 } = {}) {
  stopped = true;
  if (intervalTimer) {
    clearInterval(intervalTimer);
    intervalTimer = null;
  }
  if (firstTickTimer) {
    clearTimeout(firstTickTimer);
    firstTickTimer = null;
  }
  const pending = [tickPromise, stopEmailQueue()].filter(Boolean);
  if (pending.length === 0) {
    return;
  }
  let timeout = null;
  try {
    await Promise.race([
      Promise.allSettled(pending),
      new Promise((resolve) => {
        timeout = setTimeout(resolve, timeoutMs);
      }),
    ]);
  } finally {
    clearTimeout(timeout);
  }
}
