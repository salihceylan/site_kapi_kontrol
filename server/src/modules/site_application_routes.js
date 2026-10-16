// Site yöneticisi olma (site başvurusu) uçları.
//
//   Başvuran (authRequired; yalnız KENDİ kayıtları)
//     POST /membership/site-applications                 başvuru oluştur (yalnız individual / apartment_owner)
//     GET  /membership/site-applications/mine           { pending, items }
//     POST /membership/site-applications/:id/cancel     kendi bekleyen başvurusunu iptal et
//   Süper kullanıcı (requireSuperUser)
//     GET  /admin/site-applications?status=&q=&limit=&offset=     { items, total }
//     GET  /admin/site-applications/summary                       { pending }
//     GET  /admin/site-applications/:id                           Application (süper ek alanlarıyla)
//     POST /admin/site-applications/:id/approve | /reject
//     GET/PUT /admin/platform-settings/site-onboarding
//
// Sözleşme: docs/PLATFORM_SITE_BASVURUSU.md. Hata gövdesi: { error: "<Türkçe mesaj>", code: "<KOD>" }.
// `setup-site` (anlık kurulum) membership_routes.js'tedir; bireysel için artık 409 APPLICATION_REQUIRED döner.

import express from 'express';
import { authRequired, requireSuperUser } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { parseId } from '../utils/ids.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import {
  approveSiteApplication,
  cancelMyApplication,
  createSiteApplication,
  getAdminApplication,
  getPendingSummary,
  getSiteOnboardingSettings,
  listAdminApplications,
  listMyApplications,
  rejectSiteApplication,
  setSiteOnboardingMode,
} from './site_application_service.js';
import { APPLICATION_NOT_FOUND_BODY } from './site_application_common.js';
import { siteApplicationConsents } from './legal_consent_service.js';

export const siteApplicationRouter = express.Router();

// Yazma uçları (başvuru, iptal, onay, ret, ayar): kullanıcı başına 30/saat (sözleşme). Her başvuru süper kullanıcılara e-posta ve audit
// satırı üretir; döngüyle başvur/iptal ile gelen kutusu ve denetim kaydı şişirilmesin. IP kuralı NAT arkasındakileri toplu kilitlemesin diye geniştir.
export const siteApplicationWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 30, key: userKey },
    { windowMs: HOUR_MS, max: 300, key: ipKey },
  ],
  message: 'Çok fazla site başvurusu işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Okuma uçları (başvuru durumu ~30 sn'de bir yoklanır = 120/saat/cihaz; rozet özeti benzer): kullanıcı başına 1500/saat.
export const siteApplicationReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1500, key: userKey },
    { windowMs: HOUR_MS, max: 40000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

// ---------------------------------------------------------------------------
// Başvuran
// ---------------------------------------------------------------------------

siteApplicationRouter.post('/membership/site-applications', authRequired, siteApplicationWriteLimiter, async (req, res) => {
  try {
    const application = await createSiteApplication({ actor: req.authUser, body: bodyOf(req), consents: siteApplicationConsents });
    return res.status(201).json({ application });
  } catch (error) {
    return respondError(res, 'create_site_application', error, 'Site başvurusu oluşturulamadı.');
  }
});

siteApplicationRouter.get('/membership/site-applications/mine', authRequired, siteApplicationReadLimiter, async (req, res) => {
  try {
    return res.status(200).json(await listMyApplications(req.authUser?.userCode ?? req.authUser?.user_code ?? req.authUser?.id));
  } catch (error) {
    return respondError(res, 'my_site_applications', error, 'Site başvurularınız yüklenemedi.');
  }
});

siteApplicationRouter.post(
  '/membership/site-applications/:id/cancel',
  authRequired,
  siteApplicationWriteLimiter,
  async (req, res) => {
    try {
      const applicationId = parseId(req.params.id);
      if (applicationId === null) {
        return res.status(404).json(APPLICATION_NOT_FOUND_BODY);
      }
      const application = await cancelMyApplication({ applicationId, actor: req.authUser });
      return res.status(200).json({ application });
    } catch (error) {
      return respondError(res, 'cancel_site_application', error, 'Site başvurusu iptal edilemedi.');
    }
  },
);

// ---------------------------------------------------------------------------
// Süper kullanıcı
// ---------------------------------------------------------------------------

siteApplicationRouter.get('/admin/site-applications', authRequired, requireSuperUser, siteApplicationReadLimiter, async (req, res) => {
  try {
    const page = await listAdminApplications({
      status: req.query.status,
      q: req.query.q,
      limit: req.query.limit,
      offset: req.query.offset,
    });
    return res.status(200).json(page);
  } catch (error) {
    return respondError(res, 'admin_list_site_applications', error, 'Site başvuruları yüklenemedi.');
  }
});

// /summary, /:id'den ÖNCE tanımlanır.
siteApplicationRouter.get(
  '/admin/site-applications/summary',
  authRequired,
  requireSuperUser,
  siteApplicationReadLimiter,
  async (_req, res) => {
    try {
      return res.status(200).json(await getPendingSummary());
    } catch (error) {
      return respondError(res, 'admin_site_applications_summary', error, 'Başvuru özeti yüklenemedi.');
    }
  },
);

siteApplicationRouter.get(
  '/admin/site-applications/:id',
  authRequired,
  requireSuperUser,
  siteApplicationReadLimiter,
  async (req, res) => {
    try {
      const applicationId = parseId(req.params.id);
      if (applicationId === null) {
        return res.status(404).json(APPLICATION_NOT_FOUND_BODY);
      }
      return res.status(200).json(await getAdminApplication(applicationId));
    } catch (error) {
      return respondError(res, 'admin_get_site_application', error, 'Site başvurusu yüklenemedi.');
    }
  },
);

siteApplicationRouter.post(
  '/admin/site-applications/:id/approve',
  authRequired,
  requireSuperUser,
  siteApplicationWriteLimiter,
  async (req, res) => {
    try {
      const applicationId = parseId(req.params.id);
      if (applicationId === null) {
        return res.status(404).json(APPLICATION_NOT_FOUND_BODY);
      }
      const result = await approveSiteApplication({ applicationId, note: bodyOf(req).note, actor: req.authUser });
      return res.status(200).json(result);
    } catch (error) {
      return respondError(res, 'approve_site_application', error, 'Site başvurusu onaylanamadı.');
    }
  },
);

siteApplicationRouter.post(
  '/admin/site-applications/:id/reject',
  authRequired,
  requireSuperUser,
  siteApplicationWriteLimiter,
  async (req, res) => {
    try {
      const applicationId = parseId(req.params.id);
      if (applicationId === null) {
        return res.status(404).json(APPLICATION_NOT_FOUND_BODY);
      }
      const application = await rejectSiteApplication({ applicationId, reason: bodyOf(req).reason, actor: req.authUser });
      return res.status(200).json({ application });
    } catch (error) {
      return respondError(res, 'reject_site_application', error, 'Site başvurusu reddedilemedi.');
    }
  },
);

siteApplicationRouter.get(
  '/admin/platform-settings/site-onboarding',
  authRequired,
  requireSuperUser,
  siteApplicationReadLimiter,
  async (_req, res) => {
    try {
      return res.status(200).json(await getSiteOnboardingSettings());
    } catch (error) {
      return respondError(res, 'get_site_onboarding', error, 'Platform ayarı yüklenemedi.');
    }
  },
);

siteApplicationRouter.put(
  '/admin/platform-settings/site-onboarding',
  authRequired,
  requireSuperUser,
  siteApplicationWriteLimiter,
  async (req, res) => {
    try {
      return res.status(200).json(await setSiteOnboardingMode({ mode: bodyOf(req).mode, actor: req.authUser }));
    } catch (error) {
      return respondError(res, 'set_site_onboarding', error, 'Platform ayarı güncellenemedi.');
    }
  },
);
