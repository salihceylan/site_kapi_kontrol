// Deneme erişim kodu uçları (P2-27, karar K10). Sözleşme: docs/PLATFORM_DENEME_ERISIMI.md.
//
//   Açık   POST   /auth/trial-access { code }                                  -> { token, user, trial }  (72 saatlik, demo siteye kilitli oturum)
//   Yönetim (süper kullanıcı VEYA o sitenin yöneticisi; deneme oturumu 403):
//          GET    /manager/sites/:siteCode/trial-access                         -> { site_code, is_demo, session_hours, items }
//          PUT    /manager/sites/:siteCode/trial-access/demo { enabled }        (YALNIZ süper kullanıcı) siteyi demo olarak işaretle / kaldır
//          POST   /manager/sites/:siteCode/trial-access/codes { note?, valid_days? } -> 201 { code, item }  (düz kod YALNIZ burada, bir kez)
//          DELETE /manager/sites/:siteCode/trial-access/codes/:id               -> { item }  (kodu iptal eder; süren oturum da biter)
//
// KABA KUVVET: kod ~59 bit rastgeledir; ayrıca /auth/trial-access IP başına 15 dakikada 10 / saatte 30 deneme ve TÜM kaynaklardan saatte
// 120 deneme ile sınırlıdır (dağıtık deneme de saatte en çok 120 tahmin). Başarılı / başarısız her deneme sayılır.
import express from 'express';
import { authRequired, requireSiteManager, requireSuperUser } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, resolveManagedSite, respondError, userKey } from './route_helpers.js';
import { createTrialCode, getTrialAccessView, redeemTrialCode, revokeTrialCode, setDemoSite } from './trial_access_service.js';
import { TRIAL_SESSION_HOURS } from './trial_access_common.js';

export const trialAccessRouter = express.Router();

const MINUTE_MS = 60 * 1000;

export const redeemLimiter = createRuleLimiter({
  rules: [
    { windowMs: 15 * MINUTE_MS, max: 10, key: ipKey },
    { windowMs: HOUR_MS, max: 30, key: ipKey },
    { windowMs: HOUR_MS, max: 120, key: () => 'trial-redeem-global' },
  ],
  message: 'Çok fazla deneme kodu girişi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

export const trialAdminLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 60, key: userKey },
    { windowMs: HOUR_MS, max: 240, key: ipKey },
  ],
  message: 'Çok fazla deneme kodu işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

/** Yönetim uçları deneme oturumuna KAPALIDIR (kendini çoğaltma yok): erişim ilkesi zaten reddeder, burada ikinci kat. */
function rejectTrialSession(req, res) {
  if (req.authUser?.trial) {
    res.status(403).json({ error: 'Bu işlem deneme hesabında kullanılamaz.', code: 'TRIAL_ACTION_DENIED' });
    return true;
  }
  return false;
}

function adminHandler({ context, fallback, status = 200 }, run) {
  return async (req, res) => {
    try {
      if (rejectTrialSession(req, res)) {
        return undefined;
      }
      const siteCode = await resolveManagedSite(req, res);
      if (siteCode === null) {
        return undefined;
      }
      res.setHeader('Cache-Control', 'no-store');
      return res.status(status).json(await run({ req, siteCode }));
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

trialAccessRouter.post('/auth/trial-access', redeemLimiter, async (req, res) => {
  try {
    const raw = bodyOf(req).code;
    if (typeof raw !== 'string' || raw.trim() === '') {
      return res.status(400).json({ error: 'Deneme kodunu girin.', code: 'INVALID_BODY' });
    }
    const result = await redeemTrialCode({ code: raw });
    res.setHeader('Cache-Control', 'no-store');
    return res.status(200).json(result);
  } catch (error) {
    return respondError(res, 'trial_access_redeem', error, 'Deneme kodu ile giriş yapılamadı.');
  }
});

trialAccessRouter.get(
  '/manager/sites/:siteCode/trial-access',
  authRequired,
  requireSiteManager,
  adminHandler({ context: 'trial_access_view', fallback: 'Deneme erişimi yüklenemedi.' }, ({ siteCode }) => getTrialAccessView({ siteCode })),
);

trialAccessRouter.put(
  '/manager/sites/:siteCode/trial-access/demo',
  authRequired,
  requireSuperUser,
  trialAdminLimiter,
  adminHandler({ context: 'trial_access_demo', fallback: 'Demo site ayarı kaydedilemedi.' }, ({ req, siteCode }) =>
    setDemoSite({ siteCode, enabled: bodyOf(req).enabled, actor: req.authUser }),
  ),
);

trialAccessRouter.post(
  '/manager/sites/:siteCode/trial-access/codes',
  authRequired,
  requireSiteManager,
  trialAdminLimiter,
  adminHandler({ context: 'trial_access_create', fallback: 'Deneme kodu üretilemedi.', status: 201 }, async ({ req, siteCode }) => {
    const body = bodyOf(req);
    const created = await createTrialCode({ siteCode, note: body.note, validDays: body.valid_days, actor: req.authUser });
    return { ...created, session_hours: TRIAL_SESSION_HOURS };
  }),
);

trialAccessRouter.delete(
  '/manager/sites/:siteCode/trial-access/codes/:id',
  authRequired,
  requireSiteManager,
  trialAdminLimiter,
  adminHandler({ context: 'trial_access_revoke', fallback: 'Deneme kodu iptal edilemedi.' }, ({ req, siteCode }) =>
    revokeTrialCode({ siteCode, id: req.params.id, actor: req.authUser }),
  ),
);
