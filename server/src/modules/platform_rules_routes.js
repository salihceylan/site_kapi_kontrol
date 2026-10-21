// Kurallar tablosu uçları (karar G11; sözleşme docs/PLATFORM_KURALLAR.md). platform_config_routes.js'teki platformServicesRouter'a bağlanır (server.js değişmez).
//
//   GET /admin/rules[?site_code=]          (yalnız süper kullanıcı) platform ya da site görünümü; değiştirenin adı ve planlı değerler dahil
//   PUT /admin/rules                       (yalnız süper kullanıcı) kısmi yazma; 400 INVALID_BODY / VALIDATION_FAILED { fields, rule_codes }, 404 SITE_NOT_FOUND
//   GET /manager/sites/:siteCode/rules     (site yöneticisi kendi sitesi, süper kullanıcı her site) salt okunur; değiştirenin adı YOK
//
// Yanıtlar `Cache-Control: no-store`. Denetim kaydı yazma serviste (platform_rule.updated).

import express from 'express';
import { pool } from '../db.js';
import { authRequired, requireSiteManager, requireSuperUser } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { PlatformError } from './errors.js';
import { parsePositiveId, todayIso } from './people_common.js';
import { listRules, updateRules } from './platform_rules_service.js';
import { HOUR_MS, ipKey, resolveManagedSite, respondError, userKey } from './route_helpers.js';

export const platformRulesRouter = express.Router();

export const rulesReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 600, key: userKey },
    { windowMs: HOUR_MS, max: 20000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Yazma: her gerçek değişiklik kalıcı satır + denetim kaydı üretir; kullanıcı başına 60/saat.
export const rulesWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 60, key: userKey },
    { windowMs: HOUR_MS, max: 300, key: ipKey },
  ],
  message: 'Çok fazla kural değişikliği. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

/** ?site_code= : yoksa / boşsa null; geçersizse 400 INVALID_QUERY. */
function querySiteCode(raw) {
  if (raw === undefined || raw === null || String(raw).trim() === '') {
    return null;
  }
  const siteCode = parsePositiveId(String(raw).trim());
  if (siteCode === null) {
    throw new PlatformError(400, 'INVALID_QUERY', 'Site kodu geçersiz.');
  }
  return siteCode;
}

platformRulesRouter.get('/admin/rules', authRequired, requireSuperUser, rulesReadLimiter, async (req, res) => {
  try {
    res.setHeader('Cache-Control', 'no-store');
    const siteCode = querySiteCode(req.query.site_code);
    return res.status(200).json(await listRules(pool, { siteCode, onDate: todayIso(), includeNames: true, canEdit: true }));
  } catch (error) {
    return respondError(res, 'get_platform_rules', error, 'Kurallar yüklenemedi.');
  }
});

platformRulesRouter.put('/admin/rules', authRequired, requireSuperUser, rulesWriteLimiter, async (req, res) => {
  try {
    res.setHeader('Cache-Control', 'no-store');
    return res.status(200).json(await updateRules({ body: req.body, actor: req.authUser }));
  } catch (error) {
    return respondError(res, 'put_platform_rules', error, 'Kurallar kaydedilemedi.');
  }
});

platformRulesRouter.get('/manager/sites/:siteCode/rules', authRequired, requireSiteManager, rulesReadLimiter, async (req, res) => {
  try {
    res.setHeader('Cache-Control', 'no-store');
    const siteCode = await resolveManagedSite(req, res);
    if (siteCode === null) {
      return undefined;
    }
    return res.status(200).json(await listRules(pool, { siteCode, onDate: todayIso(), includeNames: false, canEdit: false }));
  } catch (error) {
    return respondError(res, 'get_site_rules', error, 'Kurallar yüklenemedi.');
  }
});
