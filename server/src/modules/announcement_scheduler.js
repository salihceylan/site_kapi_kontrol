// Duyuru zamanlayıcısı: zamanı gelen `scheduled` duyuruları yayınlar ve e-posta kuyruğunu sürer.
//
// Sözleşme: docs/PLATFORM_DUYURU.md ("Zamanlayıcı").
//  - startAnnouncementScheduler() sunucu açılışında (server.js) başlar; 30 sn'de bir tikler; setInterval unref'lidir (süreci tutmaz) ve
//    stopAnnouncementScheduler() ile temiz durur (kapanışta çalışan tikin bitmesi beklenir).
//  - Süreçler arası TEK ÇALIŞAN: pg_try_advisory_lock (announcement_lock.js). Kilit başka yerdeyse tik atlanır.
//  - Her tikte en çok 20 duyuru yayınlanır (yayınlayan "Sistem"); kitle 0 ise duyuru yine `published` olur (recipient_count 0).
//    Her duyuru kendi transaction'ındadır: biri başarısız olursa (loglanır) diğerleri etkilenmez, sunucu düşmez.
//  - Ardından bekleyen e-posta varsa kuyruk ARKA PLANDA tetiklenir (tik beklemez).
//  - ANNOUNCEMENT_SCHEDULER_DISABLED=1 ile (testler) hiç başlamaz.

import { pool } from '../db.js';
import { hasPendingEmails, kickEmailQueue, resumeEmailQueue, stopEmailQueue } from './announcement_email_queue.js';
import { acquireSessionLock } from './announcement_lock.js';
import { publishDueAnnouncement } from './announcement_service.js';

export const SCHEDULER_INTERVAL_MS = 30 * 1000;
export const SCHEDULER_FIRST_TICK_DELAY_MS = 5 * 1000;
export const SCHEDULER_LOCK_KEY = 'announcement_scheduler';
export const MAX_PUBLISH_PER_TICK = 20;

/** Test / QA için değiştirilebilir bağımlılıklar. */
export const schedulerHooks = {
  publishDue: (args) => publishDueAnnouncement(args),
  hasPendingEmails: () => hasPendingEmails(),
  kickEmailQueue: () => kickEmailQueue(),
};

let intervalTimer = null;
let firstTickTimer = null;
let tickPromise = null;
let stopped = false;

/** Test yardımcısı: durdurma işaretlerini (zamanlayıcı + e-posta kuyruğu) sıfırlar; zamanlayıcıyı BAŞLATMAZ. */
export function resetSchedulerState() {
  stopped = false;
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
    lock = await acquireSessionLock(SCHEDULER_LOCK_KEY);
    if (!lock) {
      summary.locked = true;
      return summary;
    }
    const due = await pool.query(
      `
        SELECT id, site_code
        FROM announcements
        WHERE status = 'scheduled' AND publish_at <= NOW()
        ORDER BY publish_at, id
        LIMIT $1
      `,
      [MAX_PUBLISH_PER_TICK],
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
        // eslint-disable-next-line no-console
        console.error(`[announcement-scheduler] yayin basarisiz (id=${row.id}):`, error?.code || error?.message || 'hata');
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
  // E-posta kuyruğu: yayınlar bittikten ve zamanlayıcı kilidi açıldıktan sonra arka planda (kendi tek-çalışan kilidi vardır).
  try {
    if (!stopped && (await schedulerHooks.hasPendingEmails())) {
      void schedulerHooks.kickEmailQueue();
    }
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[announcement-scheduler] kuyruk kontrolu basarisiz:', error?.code || error?.message || 'hata');
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
