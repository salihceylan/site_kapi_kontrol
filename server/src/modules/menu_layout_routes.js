// Site menü yerleşimi uçları (K8, P1-16): site başına "kompakt menü" kümesi.
//
//   GET    /manager/sites/:siteCode/menu-layout   (requireSiteManager + hasSiteManagementAccess; süper kullanıcı her site)
//   PUT    /manager/sites/:siteCode/menu-layout   gövde { compact_modules: ["finance", ...] }  (aynı yetki; kümenin kendisi, modül açıp kapatmaz)
//   DELETE /manager/sites/:siteCode/menu-layout   varsayılana (yönetim türü önerilerinden türetilen küme) döner
//
// Sözleşme: docs/PLATFORM_MENU_KATMANI.md. YETENEK (modül açık/kapalı) bu uçlarla DEĞİŞMEZ: temel modüller her sitede açık kalır ve kapatılamaz.
// Kümenin istemciye ulaşan hâli `GET /app/my-modules` site nesnesindeki `menu_layout` alanıdır (module_service.js).
// Hata gövdesi: { error: "<Türkçe mesaj>", code: "<KOD>" }.

import express from 'express';
import { authRequired, requireSiteManager } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { getSiteMenuLayoutView, resetSiteMenuLayout, saveSiteMenuLayout } from './menu_layout_service.js';
import { HOUR_MS, SITE_NOT_FOUND_BODY, ipKey, resolveManagedSite, respondError, userKey } from './route_helpers.js';

export const menuLayoutRouter = express.Router();

// Her gerçek değişiklik audit_log'a kalıcı satır ekler (silinemez): döngüyle sınırsız satır üretilemesin. Normal kullanım saatte birkaç değişikliktir.
export const menuLayoutLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 60, key: userKey },
    { windowMs: HOUR_MS, max: 300, key: ipKey },
  ],
  message: 'Çok fazla menü değişikliği. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

async function respondWithView(res, siteCode) {
  const view = await getSiteMenuLayoutView(siteCode);
  if (!view) {
    return res.status(404).json(SITE_NOT_FOUND_BODY);
  }
  return res.status(200).json(view);
}

menuLayoutRouter.get('/manager/sites/:siteCode/menu-layout', authRequired, requireSiteManager, async (req, res) => {
  try {
    const siteCode = await resolveManagedSite(req, res);
    if (siteCode === null) {
      return undefined;
    }
    return await respondWithView(res, siteCode);
  } catch (error) {
    return respondError(res, 'get_menu_layout', error, 'Menü düzeni yüklenemedi.');
  }
});

menuLayoutRouter.put(
  '/manager/sites/:siteCode/menu-layout',
  authRequired,
  requireSiteManager,
  menuLayoutLimiter,
  async (req, res) => {
    try {
      const siteCode = await resolveManagedSite(req, res);
      if (siteCode === null) {
        return undefined;
      }
      const body = req.body && typeof req.body === 'object' ? req.body : {};
      await saveSiteMenuLayout({ siteCode, compactModules: body.compact_modules, actor: req.authUser });
      return await respondWithView(res, siteCode);
    } catch (error) {
      return respondError(res, 'set_menu_layout', error, 'Menü düzeni kaydedilemedi.');
    }
  },
);

menuLayoutRouter.delete(
  '/manager/sites/:siteCode/menu-layout',
  authRequired,
  requireSiteManager,
  menuLayoutLimiter,
  async (req, res) => {
    try {
      const siteCode = await resolveManagedSite(req, res);
      if (siteCode === null) {
        return undefined;
      }
      await resetSiteMenuLayout({ siteCode, actor: req.authUser });
      return await respondWithView(res, siteCode);
    } catch (error) {
      return respondError(res, 'reset_menu_layout', error, 'Menü düzeni sıfırlanamadı.');
    }
  },
);
