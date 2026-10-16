// Uygulama yapılandırması (kimliksiz): GET /public/app-config. Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md (1.1).
//
// İstemci açılışta okur: en düşük desteklenen sürüm (zorunlu güncelleme), son sürüm, mağaza bağlantıları, bakım modu, destek iletişimi ve
// yasal onay zorunluluğu. Yanıt ÖNBELLEKSİZDİR (Cache-Control: no-store).
//
// SAVUNMACI: bu uç uygulamanın açılışını asla bozmamalıdır. Ayarlar okunamazsa (veritabanı kesintisi) güvenli varsayılanlarla 200 döner
// (bakım kapalı, sürüm kısıtı yok; ayrıntı yalnız kodla günlüğe). Yasal belgeler okunamazsa legal_enforced false olur.

import express from 'express';
import { pool } from '../db.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { loadLegalFiles, legalDir, resolveDocuments } from './legal_documents.js';
import { configFromRows, parseFlag, readPlatformConfig } from './platform_config_service.js';
import { HOUR_MS, ipKey } from './route_helpers.js';

export const appConfigRouter = express.Router();

export const DEFAULT_VERSION = '1.0.0';

// IP başına 1200/saat: her açılış / öne gelme bir istek; bir apartman (tek NAT IP'si) bile rahat sığar.
export const appConfigLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 1200, key: ipKey }],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
});

const orNull = (value) => (typeof value === 'string' && value !== '' ? value : null);

/**
 * Yapılandırma nesnesinden (readPlatformConfig çıktısı) sözleşmedeki yanıtı üretir. `legalEnforced`: zorunluluk açık VE onay istenen en az
 * bir TAMAMLANMIŞ belge var (aksi halde sunucu fiilen hiçbir şey zorlamaz).
 */
export function buildAppConfig(config, { legalEnforced = false, now = new Date() } = {}) {
  return {
    server_time: now.toISOString(),
    min_supported_version: orNull(config.app.min_supported_version) ?? DEFAULT_VERSION,
    latest_version: orNull(config.app.latest_version) ?? DEFAULT_VERSION,
    update_url_android: orNull(config.app.update_url_android),
    update_url_ios: orNull(config.app.update_url_ios),
    maintenance: {
      active: config.app.maintenance_active === true,
      message: orNull(config.app.maintenance_message),
    },
    support: {
      email: orNull(config.support.email),
      phone: orNull(config.support.phone),
      hours: orNull(config.support.hours),
      web_url: orNull(config.support.web_url),
    },
    legal_enforced: legalEnforced === true,
  };
}

async function legalEnforcedState(config) {
  if (!parseFlag(config.legal.enforce_consents)) {
    return false;
  }
  try {
    const docs = resolveDocuments(await loadLegalFiles(legalDir()), config.legal);
    return docs.some((doc) => doc.complete && doc.required_for.length > 0);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[app-config] yasal belgeler okunamadi:', error?.code || 'hata');
    return false;
  }
}

appConfigRouter.get('/public/app-config', appConfigLimiter, async (_req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  let config = configFromRows([]);
  try {
    config = await readPlatformConfig(pool);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[app-config] ayarlar okunamadi (varsayilanlarla yanit):', error?.code || 'hata');
  }
  // legalEnforcedState kendi hatasını yutar (false döner).
  return res.status(200).json(buildAppConfig(config, { legalEnforced: await legalEnforcedState(config) }));
});
