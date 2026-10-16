// İstemci hata raporlarının 90 gün sonra silinmesi: sunucu açılışında başlayan, unref'li zamanlayıcı (server.js).
//
// Çoklu süreç: her tik purgeOldReports() çağırır; o da transaction düzeyinde pg_try_advisory_xact_lock (iki-int anahtar) alır, kilit başka
// süreçteyse tik ATLANIR (çift çalışma yok). İş idempotenttir (süre dolmuş satırlar silinir). CLIENT_ERROR_PURGE_DISABLED=1 ile kapalı.

import { purgeOldReports } from './client_error_service.js';

export const PURGE_INTERVAL_MS = 6 * 60 * 60 * 1000;
export const PURGE_FIRST_DELAY_MS = 90 * 1000;

export function isPurgeDisabled(env = process.env) {
  const value = String(env.CLIENT_ERROR_PURGE_DISABLED ?? '').trim().toLowerCase();
  return value === '1' || value === 'true' || value === 'yes';
}

let intervalTimer = null;
let firstTimer = null;
let running = null;

/** Tek bir silme turu; hata fırlatmaz (sunucuyu düşürmez). */
export function runClientErrorPurge(purge = purgeOldReports) {
  if (!running) {
    running = Promise.resolve()
      .then(() => purge())
      .then((result) => {
        if (result.deleted > 0) {
          // eslint-disable-next-line no-console
          console.log(`[client-errors] ${result.deleted} suresi dolmus rapor silindi.`);
        }
        return result;
      })
      .catch((error) => {
        // eslint-disable-next-line no-console
        console.error('[client-errors] silme turu basarisiz:', error?.code || error?.message || 'hata');
        return { skipped: false, deleted: 0, failed: true };
      })
      .finally(() => {
        running = null;
      });
  }
  return running;
}

/** @returns {{ stop: Function } | null} kapalıysa / zaten çalışıyorsa null */
export function startClientErrorPurge({ env = process.env, intervalMs = PURGE_INTERVAL_MS, firstDelayMs = PURGE_FIRST_DELAY_MS, purge } = {}) {
  if (isPurgeDisabled(env) || intervalTimer) {
    return null;
  }
  intervalTimer = setInterval(() => void runClientErrorPurge(purge), intervalMs);
  intervalTimer.unref?.();
  firstTimer = setTimeout(() => {
    firstTimer = null;
    void runClientErrorPurge(purge);
  }, Math.min(firstDelayMs, intervalMs));
  firstTimer.unref?.();
  return { stop: stopClientErrorPurge };
}

export async function stopClientErrorPurge() {
  if (intervalTimer) {
    clearInterval(intervalTimer);
    intervalTimer = null;
  }
  if (firstTimer) {
    clearTimeout(firstTimer);
    firstTimer = null;
  }
  if (running) {
    await running.catch(() => {});
  }
}
