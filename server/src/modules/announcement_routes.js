// Duyuru ve Bildirim (Faz 3a) uçları.
//
//   Yönetici  GET/POST   /manager/sites/:siteCode/announcements                 GET/PATCH/DELETE .../announcements/:id
//             POST       /manager/sites/:siteCode/announcements/preview-audience
//             GET        /manager/sites/:siteCode/announcements/:id/recipients
//             POST       /manager/sites/:siteCode/announcements/:id/publish | /withdraw
//   Sakin     GET        /app/announcements            GET /app/announcements/:id     POST /app/announcements/:id/read
//             POST       /app/announcements/read-all   GET /app/notifications/summary
//             GET/PUT    /app/notification-preferences
//
// Yetki (people_access.js ile AYNI): yazma = yönetici/süper; okuma = yönetici/süper + BOARD_MEMBER; STAFF/sakin 403 FORBIDDEN_ROLE; başka
// sitenin yöneticisi 403 FORBIDDEN_SITE. Kurul üyesi YALNIZ sayıları ve duyuru içeriğini görür: alıcı adları (recipients, preview) 403;
// yanıtlarında kullanıcı kodları ve oluşturan yönetici adı yoktur. Sözleşme: docs/PLATFORM_DUYURU.md. Hata gövdesi: { error, code }.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import {
  getMyAnnouncement,
  getNotificationPreferences,
  getNotificationSummary,
  listMyAnnouncements,
  markAllAnnouncementsRead,
  hideMyAnnouncement,
  restoreMyAnnouncement,
  markAnnouncementRead,
  setNotificationPreferences,
} from './announcement_inbox.js';
import { kickEmailQueue } from './announcement_email_queue.js';
import { kickPushQueue } from './push_worker.js';
import { redactForBoard } from './announcement_common.js';
import {
  createAnnouncement,
  deleteAnnouncement,
  getAnnouncementDetail,
  listAnnouncementRecipients,
  listAnnouncements,
  previewAnnouncementAudience,
  publishAnnouncement,
  updateAnnouncement,
  withdrawAnnouncement,
} from './announcement_service.js';
import { FORBIDDEN_ROLE_BODY, resolvePeopleAccess } from './people_access.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';

export const announcementRouter = express.Router();

/** Test için değiştirilebilir: yayından sonra e-posta / push kuyruğunu arka planda başlatır (yanıtı BEKLETMEZ). */
export const announcementRouteHooks = {
  kickEmailQueue: () => kickEmailQueue(),
  // Faz 3b-B: push kapalı / yapılandırılmamışsa sorgusuz hemen döner.
  kickPushQueue: () => kickPushQueue(),
};

// Yazma uçları (yönetici yazmaları + sakin okundu / tercih yazmaları): kullanıcı başına 120/saat (sözleşme).
export const announcementWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla duyuru işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Liste / ayrıntı / yönetici okuma: kullanıcı başına 1200/saat.
export const announcementReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Bildirim özeti (uygulama yoklar, ~20 sn = 180/saat/cihaz): kullanıcı başına 1500/saat. Dahili daire hesabı birkaç cihazda (4 x 180 = 720) ve
// sekme/arka plan yenilemeleriyle paylaşılabildiği için 600 yetmiyordu. IP sınırı 40000/saat: apartman / site NAT'ı ve CGNAT'ta onlarca
// hesap aynı IP'den çıkar (örn. 200 hesap x 180 = 36000); eski 12000 toplu 429 üretirdi. Kötüye kullanım yine kullanıcı sınırıyla yakalanır.
export const announcementSummaryLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1500, key: userKey },
    { windowMs: HOUR_MS, max: 40000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});
const canSeeManagerFields = (access) => access.kind === 'super' || access.kind === 'manager';

/** Yayından sonra e-posta kuyruğunu tetikler (hata yanıtı bozmaz; kuyruk kendi başına dayanıklıdır). */
function afterWrite(detail) {
  if (detail && detail.status === 'published' && detail.send_email === true && detail.stats?.email?.pending > 0) {
    try {
      void Promise.resolve(announcementRouteHooks.kickEmailQueue()).catch(() => {});
    } catch (_error) {
      // tetikleme hatası yayını bozmaz; zamanlayıcı tikinde kuyruk sürer
    }
  }
  if (detail && detail.status === 'published') {
    try {
      void Promise.resolve(announcementRouteHooks.kickPushQueue()).catch(() => {});
    } catch (_error) {
      // tetikleme hatası yayını bozmaz; zamanlayıcı tikinde (hasPendingPush) push kuyruğu sürer
    }
  }
}

/**
 * Yönetici sarmalayıcı: yetki + site doğrulaması -> iş -> JSON. `write`: yalnız yönetici/süper; `allowBoard: false`: kurul üyesi 403.
 * Kurul yanıtı kullanıcı kodlarından ve oluşturan adından arındırılır.
 */
function managerHandler({ context, fallback, write = false, allowBoard = true }, run) {
  return async (req, res) => {
    try {
      const access = await resolvePeopleAccess(req, res, { write });
      if (!access) {
        return undefined;
      }
      if (!allowBoard && access.kind === 'board') {
        return res.status(403).json(FORBIDDEN_ROLE_BODY);
      }
      const { status = 200, body } = await run({ req, access });
      return res.status(status).json(canSeeManagerFields(access) ? body : redactForBoard(body));
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

function appHandler({ context, fallback, status = 200 }, run) {
  return async (req, res) => {
    try {
      return res.status(status).json(await run(req));
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

// --- Yönetici ---------------------------------------------------------------------------------------------

const BASE = '/manager/sites/:siteCode/announcements';

announcementRouter.get(
  BASE,
  authRequired,
  announcementReadLimiter,
  managerHandler({ context: 'announcements_list', fallback: 'Duyurular yüklenemedi.' }, async ({ req, access }) => ({
    body: await listAnnouncements(access.siteCode, req.query),
  })),
);

announcementRouter.post(
  `${BASE}/preview-audience`,
  authRequired,
  announcementReadLimiter,
  managerHandler(
    { context: 'announcements_preview', fallback: 'Kitle önizlemesi yüklenemedi.', allowBoard: false },
    async ({ req, access }) => ({ body: await previewAnnouncementAudience(access.siteCode, bodyOf(req)) }),
  ),
);

announcementRouter.post(
  BASE,
  authRequired,
  announcementWriteLimiter,
  managerHandler({ context: 'announcements_create', fallback: 'Duyuru kaydedilemedi.', write: true }, async ({ req, access }) => {
    const detail = await createAnnouncement({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser });
    afterWrite(detail);
    return { status: 201, body: detail };
  }),
);

announcementRouter.get(
  `${BASE}/:id`,
  authRequired,
  announcementReadLimiter,
  managerHandler({ context: 'announcements_get', fallback: 'Duyuru yüklenemedi.' }, async ({ req, access }) => ({
    body: await getAnnouncementDetail(access.siteCode, req.params.id),
  })),
);

announcementRouter.get(
  `${BASE}/:id/recipients`,
  authRequired,
  announcementReadLimiter,
  managerHandler(
    { context: 'announcements_recipients', fallback: 'Alıcılar yüklenemedi.', allowBoard: false },
    async ({ req, access }) => ({ body: await listAnnouncementRecipients(access.siteCode, req.params.id, req.query) }),
  ),
);

announcementRouter.patch(
  `${BASE}/:id`,
  authRequired,
  announcementWriteLimiter,
  managerHandler({ context: 'announcements_update', fallback: 'Duyuru güncellenemedi.', write: true }, async ({ req, access }) => {
    const detail = await updateAnnouncement({
      siteCode: access.siteCode,
      id: req.params.id,
      body: bodyOf(req),
      actor: req.authUser,
    });
    afterWrite(detail);
    return { body: detail };
  }),
);

announcementRouter.post(
  `${BASE}/:id/publish`,
  authRequired,
  announcementWriteLimiter,
  managerHandler({ context: 'announcements_publish', fallback: 'Duyuru yayınlanamadı.', write: true }, async ({ req, access }) => {
    const detail = await publishAnnouncement({ siteCode: access.siteCode, id: req.params.id, actor: req.authUser });
    afterWrite(detail);
    return { body: detail };
  }),
);

announcementRouter.post(
  `${BASE}/:id/withdraw`,
  authRequired,
  announcementWriteLimiter,
  managerHandler({ context: 'announcements_withdraw', fallback: 'Duyuru geri çekilemedi.', write: true }, async ({ req, access }) => ({
    body: await withdrawAnnouncement({ siteCode: access.siteCode, id: req.params.id, actor: req.authUser }),
  })),
);

announcementRouter.delete(
  `${BASE}/:id`,
  authRequired,
  announcementWriteLimiter,
  managerHandler({ context: 'announcements_delete', fallback: 'Duyuru silinemedi.', write: true }, async ({ req, access }) => ({
    body: await deleteAnnouncement({ siteCode: access.siteCode, id: req.params.id, actor: req.authUser }),
  })),
);

// --- Sakin ------------------------------------------------------------------------------------------------

announcementRouter.get(
  '/app/announcements',
  authRequired,
  announcementReadLimiter,
  appHandler({ context: 'my_announcements', fallback: 'Duyurular yüklenemedi.' }, (req) => listMyAnnouncements(req.authUser, req.query)),
);

announcementRouter.post(
  '/app/announcements/read-all',
  authRequired,
  announcementWriteLimiter,
  appHandler({ context: 'my_announcements_read_all', fallback: 'Duyurular okundu olarak işaretlenemedi.' }, (req) =>
    markAllAnnouncementsRead(req.authUser, bodyOf(req)),
  ),
);

announcementRouter.get(
  '/app/announcements/:id',
  authRequired,
  announcementReadLimiter,
  appHandler({ context: 'my_announcement', fallback: 'Duyuru yüklenemedi.' }, (req) => getMyAnnouncement(req.authUser, req.params.id)),
);

announcementRouter.delete(
  '/app/announcements/:id',
  authRequired,
  announcementWriteLimiter,
  appHandler({ context: 'my_announcement_hide', fallback: 'Duyuru listenizden kaldırılamadı.' }, (req) =>
    hideMyAnnouncement(req.authUser, req.params.id),
  ),
);

announcementRouter.post(
  '/app/announcements/:id/restore',
  authRequired,
  announcementWriteLimiter,
  appHandler({ context: 'my_announcement_restore', fallback: 'Duyuru geri alınamadı.' }, (req) =>
    restoreMyAnnouncement(req.authUser, req.params.id),
  ),
);

announcementRouter.post(
  '/app/announcements/:id/read',
  authRequired,
  announcementWriteLimiter,
  appHandler({ context: 'my_announcement_read', fallback: 'Duyuru okundu olarak işaretlenemedi.' }, (req) =>
    markAnnouncementRead(req.authUser, req.params.id),
  ),
);

announcementRouter.get(
  '/app/notifications/summary',
  authRequired,
  announcementSummaryLimiter,
  appHandler({ context: 'notification_summary', fallback: 'Bildirim özeti yüklenemedi.' }, (req) => getNotificationSummary(req.authUser)),
);

announcementRouter.get(
  '/app/notification-preferences',
  authRequired,
  announcementReadLimiter,
  appHandler({ context: 'notification_preferences', fallback: 'Bildirim tercihleri yüklenemedi.' }, (req) =>
    getNotificationPreferences(req.authUser),
  ),
);

announcementRouter.put(
  '/app/notification-preferences',
  authRequired,
  announcementWriteLimiter,
  appHandler({ context: 'notification_preferences_update', fallback: 'Bildirim tercihleri kaydedilemedi.' }, (req) =>
    setNotificationPreferences(req.authUser, bodyOf(req)),
  ),
);
