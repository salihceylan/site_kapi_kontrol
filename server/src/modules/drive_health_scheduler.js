// Drive arka plan zamanlayıcısı (P2-2 / P2-17 / P2-18; D3 "günlük sağlık denetimi"): bağlı sitelerde
//  1) bekleyen dosyaları (artan bekleme süresi gelmiş olanları) Drive'a göndermeyi dener — gönderim SHA-256 doğrulamalıdır, doğrulanamayan dosya kuyrukta kalır, hiçbiri silinmez (K6),
//  2) sağlık denetimi yapar: erişim belirtecini yeniler (izin geri alınmışsa bağlantı 'error' olur + yönetici uyarısı), Google hesap kotasını çeker (about.get), %90'da yönetici uyarısı düşer.
// Sağlık denetimi site başına en çok HEALTH_CHECK_INTERVAL_MS'de bir (6 saat; başarısız denemeden sonra 30 dk bekler), gönderim her tikte (5 dk) yalnız vakti gelmiş bekleyen varsa çalışır.
// PM2 tek kopya (instances: 1; ecosystem.config.cjs): aynı site için gönderimler zaten süreç içinde sıraya dizilir. DRIVE_HEALTH_DISABLED=1 ile kapalı; zamanlayıcı süreci açık tutmaz (unref).

import { pool } from '../db.js';
import { HEALTH_CHECK_INTERVAL_MS, driveConfig } from './drive_common.js';
import { driveService } from './drive_service.js';

export const DRIVE_TICK_INTERVAL_MS = 5 * 60 * 1000;
const FIRST_DELAY_MS = 2 * 60 * 1000;
/** Başarısız sağlık denetimi sonrası aynı siteye yeniden gitmeden önce beklenen süre (Google'ı yormamak için). */
const HEALTH_RETRY_MS = 30 * 60 * 1000;

export const driveHealthHooks = {
  configured: () => driveConfig().configured,
  /** Bağlı siteler: { site_code, due_files (vakti gelmiş bekleyen var mı), health_due (son başarılı denetim eski mi / hiç yok) }. */
  listSites: async (intervalMs) => {
    const result = await pool.query(
      `SELECT c.site_code,
              EXISTS (SELECT 1 FROM drive_pending_uploads p WHERE p.site_code = c.site_code AND p.next_attempt_at <= NOW()) AS due_files,
              (c.health_checked_at IS NULL OR c.health_checked_at < NOW() - make_interval(secs => $1::double precision)) AS health_due
         FROM site_drive_connections c WHERE c.status = 'connected' ORDER BY c.site_code`,
      [intervalMs / 1000],
    );
    return result.rows.map((row) => ({ siteCode: Number(row.site_code), dueFiles: row.due_files === true, healthDue: row.health_due === true }));
  },
  flush: (siteCode) => driveService.flushPending(siteCode),
  checkHealth: (siteCode) => driveService.checkHealth(siteCode),
};

const lastAttempt = new Map(); // siteCode -> ms (başarısız sağlık denetimi sonrası bekleme)
let timer = null;
let firstTimer = null;
let tickPromise = null;
let stopped = false;

export function isDriveHealthDisabled(env = process.env) {
  return ['1', 'true', 'yes'].includes(String(env.DRIVE_HEALTH_DISABLED ?? '').trim().toLowerCase());
}

function logFailure(siteCode, step, error) {
  // eslint-disable-next-line no-console
  console.error(`[drive-health] site ${siteCode} ${step} basarisiz:`, error?.code || error?.message || 'hata');
}

/**
 * Tek tur. Bir sitedeki hata diğer siteleri durdurmaz; Drive yapılandırılmamışsa hiçbir şey yapılmaz.
 * Dönüş: { sites, flushed, checked } (test ve günlük için).
 */
export async function runDriveHealthTick({ hooks = driveHealthHooks, nowMs = Date.now(), intervalMs = HEALTH_CHECK_INTERVAL_MS } = {}) {
  const summary = { sites: 0, flushed: 0, checked: 0 };
  if (!hooks.configured()) return summary;
  const sites = await hooks.listSites(intervalMs);
  for (const site of sites) {
    if (stopped) break;
    summary.sites += 1;
    // Gönderim ve sağlık denetimi birbirinden bağımsız denenir: biri patlasa da diğeri (ve sonraki siteler) çalışır.
    if (site.dueFiles) {
      try {
        const out = await hooks.flush(site.siteCode);
        summary.flushed += Number(out?.sent) || 0;
      } catch (error) {
        logFailure(site.siteCode, 'gonderim', error);
      }
    }
    if (site.healthDue && nowMs - (lastAttempt.get(site.siteCode) ?? 0) >= HEALTH_RETRY_MS) {
      lastAttempt.set(site.siteCode, nowMs);
      try {
        const out = await hooks.checkHealth(site.siteCode);
        if (out?.checked) {
          summary.checked += 1;
          lastAttempt.delete(site.siteCode);
        }
      } catch (error) {
        logFailure(site.siteCode, 'saglik denetimi', error);
      }
    }
  }
  return summary;
}

export function runDriveHealthTickOnce() {
  if (!tickPromise) {
    tickPromise = runDriveHealthTick()
      .catch((error) => {
        // eslint-disable-next-line no-console
        console.error('[drive-health] tik basarisiz:', error?.code || error?.message || 'hata');
      })
      .finally(() => {
        tickPromise = null;
      });
  }
  return tickPromise;
}

export function startDriveHealth({ intervalMs = DRIVE_TICK_INTERVAL_MS, firstDelayMs = FIRST_DELAY_MS, env = process.env } = {}) {
  if (isDriveHealthDisabled(env) || timer || firstTimer) return null;
  stopped = false;
  firstTimer = setTimeout(() => {
    firstTimer = null;
    void runDriveHealthTickOnce();
    timer = setInterval(() => void runDriveHealthTickOnce(), intervalMs);
    timer.unref?.();
  }, firstDelayMs);
  firstTimer.unref?.();
  return { stop: stopDriveHealth, intervalMs };
}

export async function stopDriveHealth() {
  stopped = true;
  if (firstTimer) {
    clearTimeout(firstTimer);
    firstTimer = null;
  }
  if (timer) {
    clearInterval(timer);
    timer = null;
  }
  if (tickPromise) await tickPromise.catch(() => {});
}
