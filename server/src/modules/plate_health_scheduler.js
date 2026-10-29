// Plaka Tanıma A3 arka plan işi (drive_health_scheduler.js deseni):
//  1) kopukluk uyarısı: kenar PC / kamera kırmızı eşiği (site ayarı) aştıysa yöneticilere uyarı (saatte en çok 1: plate_alert_state, kalıcı sınırlayıcı),
//  2) bakım: "içeride" zaman aşımı (site ayarı, varsayılan 24 saat) aşan araçlar otomatik düşer ve denetim kaydına iz bırakılır.
// Tik başına bir tur; bir sitedeki hata diğerlerini durdurmaz. PM2 tek kopya; sınırlayıcı atomik olduğundan çift süreç de uyarıyı iki kez göndermez.
// PLATE_HEALTH_DISABLED=1 ile kapalı; zamanlayıcı süreci açık tutmaz (unref).

import { pool } from '../db.js';
import { isModuleEnabled } from './module_service.js';
import { PLATE_RECOGNITION_MODULE } from './plate_recognition_common.js';
import { checkEdgeHealth, expireStalePresence } from './plate_notify.js';

export const PLATE_TICK_INTERVAL_MS = 5 * 60 * 1000;
const FIRST_DELAY_MS = 90 * 1000;

export const plateHealthHooks = {
  /** Kenar istemcisi en az bir kez haber vermiş siteler. */
  listSites: async (db = pool) => {
    const result = await db.query(`SELECT DISTINCT site_code FROM plate_edge_clients WHERE is_active AND revoked_at IS NULL AND last_seen_at IS NOT NULL ORDER BY site_code`);
    return result.rows.map((row) => Number(row.site_code));
  },
  moduleEnabled: (siteCode) => isModuleEnabled(siteCode, PLATE_RECOGNITION_MODULE),
  checkEdgeHealth: (siteCode, nowMs) => checkEdgeHealth(pool, siteCode, nowMs),
  expireStalePresence: () => expireStalePresence(pool),
};

let timer = null;
let firstTimer = null;
let tickPromise = null;
let stopped = false;

export function isPlateHealthDisabled(env = process.env) {
  return ['1', 'true', 'yes'].includes(String(env.PLATE_HEALTH_DISABLED ?? '').trim().toLowerCase());
}

function logFailure(step, error) {
  // eslint-disable-next-line no-console
  console.error(`[plate-health] ${step} basarisiz:`, error?.code || error?.message || 'hata');
}

/** Tek tur. Dönüş: { sites, alerted, expired } (test ve günlük için). */
export async function runPlateHealthTick({ hooks = plateHealthHooks, nowMs = Date.now() } = {}) {
  const summary = { sites: 0, alerted: 0, expired: 0 };
  let sites = [];
  try {
    sites = await hooks.listSites();
  } catch (error) {
    logFailure('site listesi', error);
  }
  for (const siteCode of sites) {
    if (stopped) break;
    try {
      if (!(await hooks.moduleEnabled(siteCode))) continue;
      summary.sites += 1;
      const out = await hooks.checkEdgeHealth(siteCode, nowMs);
      if (out?.alerted) summary.alerted += 1;
    } catch (error) {
      logFailure(`site ${siteCode} kopukluk`, error);
    }
  }
  try {
    summary.expired = Number(await hooks.expireStalePresence()) || 0;
  } catch (error) {
    logFailure('icerisi zaman asimi', error);
  }
  return summary;
}

export function runPlateHealthTickOnce() {
  if (!tickPromise) {
    tickPromise = runPlateHealthTick()
      .catch((error) => logFailure('tik', error))
      .finally(() => {
        tickPromise = null;
      });
  }
  return tickPromise;
}

export function startPlateHealth({ intervalMs = PLATE_TICK_INTERVAL_MS, firstDelayMs = FIRST_DELAY_MS, env = process.env } = {}) {
  if (isPlateHealthDisabled(env) || timer || firstTimer) return null;
  stopped = false;
  firstTimer = setTimeout(() => {
    firstTimer = null;
    void runPlateHealthTickOnce();
    timer = setInterval(() => void runPlateHealthTickOnce(), intervalMs);
    timer.unref?.();
  }, firstDelayMs);
  firstTimer.unref?.();
  return { stop: stopPlateHealth, intervalMs };
}

export async function stopPlateHealth() {
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
