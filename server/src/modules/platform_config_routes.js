// Süper kullanıcı platform ayarları + platform hizmetleri yönlendiricisi (server.js tek satırla bağlar).
//
//   GET /admin/platform-config     { app, support, legal }     (yalnız super_user; ayarsız metin "", ayarsız boolean false)
//   PUT /admin/platform-config     kısmi güncelleme (gönderilen alanlar); 400 VALIDATION_FAILED { fields } / INVALID_VERSION_RANGE
//
// Sözleşme: docs/PLATFORM_SATISA_HAZIRLIK.md (1.2). Denetim kaydı yalnız DEĞİŞEN anahtar adlarını taşır (değer yok).
//
// `platformServicesRouter`: yasal belgeler (legal_routes), uygulama yapılandırması (app_config_routes), istemci hata raporu
// (client_error_routes) ve bu dosyadaki ayar uçları tek yönlendiricide birleşir.

import express from 'express';
import { authRequired, requireSuperUser } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { appConfigRouter } from './app_config_routes.js';
import { clientErrorRouter } from './client_error_routes.js';
import { legalRouter } from './legal_routes.js';
import { readPlatformConfig, updatePlatformConfig } from './platform_config_service.js';
import { platformRulesRouter } from './platform_rules_routes.js';
import { managementCompanyRouter } from './management_company_routes.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';

export const platformConfigRouter = express.Router();

export const platformConfigReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 600, key: userKey },
    { windowMs: HOUR_MS, max: 20000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Yazma: her gerçek değişiklik kalıcı audit satırı üretir; kullanıcı başına 60/saat.
export const platformConfigWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 60, key: userKey },
    { windowMs: HOUR_MS, max: 300, key: ipKey },
  ],
  message: 'Çok fazla ayar değişikliği. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

platformConfigRouter.get('/admin/platform-config', authRequired, requireSuperUser, platformConfigReadLimiter, async (_req, res) => {
  try {
    res.setHeader('Cache-Control', 'no-store');
    return res.status(200).json(await readPlatformConfig());
  } catch (error) {
    return respondError(res, 'get_platform_config', error, 'Platform ayarları yüklenemedi.');
  }
});

platformConfigRouter.put('/admin/platform-config', authRequired, requireSuperUser, platformConfigWriteLimiter, async (req, res) => {
  try {
    res.setHeader('Cache-Control', 'no-store');
    const { config } = await updatePlatformConfig({ body: req.body, actor: req.authUser });
    return res.status(200).json(config);
  } catch (error) {
    return respondError(res, 'put_platform_config', error, 'Platform ayarları güncellenemedi.');
  }
});

export const platformServicesRouter = express.Router();
platformServicesRouter.use(legalRouter);
platformServicesRouter.use(appConfigRouter);
platformServicesRouter.use(clientErrorRouter);
platformServicesRouter.use(platformConfigRouter);
// Kurallar tablosu (G11): /admin/rules, /manager/sites/:siteCode/rules (docs/PLATFORM_KURALLAR.md).
platformServicesRouter.use(platformRulesRouter);
// Yonetim firmasi, deneme suresi, ortaklik payi (Y1/Y2): docs/PLATFORM_YONETIM_FIRMASI.md.
platformServicesRouter.use(managementCompanyRouter);
