// İş Takibi (arıza, bakım, talep) uçları.
//
//   Yönetim  GET   /manager/sites/:siteCode/work-items            (liste + süzgeç + sayaçlar)    GET .../work-items/assignees
//            GET   .../work-items/:id                              PATCH .../work-items/:id       (durum / öncelik / atama / hedef tarih)
//            POST  .../work-items/:id/comments                     (internal | public yorum)
//   Sakin    GET/POST /app/work-items      GET /app/work-items/:id      POST /app/work-items/:id/cancel | /comments | /seen
//
// Yetki: yönetici / süper / görevli (STAFF: yalnız kendine atanmış veya atanmamış) yazar; BOARD_MEMBER salt okur (iç yorum ve sakin iletişim bilgisi yok); sakin yalnız
// KENDİ taleplerini görür. `work_tracking` modülü kapalıysa 403 MODULE_DISABLED. Sözleşme: docs/PLATFORM_IS_TAKIBI.md. Hata gövdesi { error, code }.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { resolveWorkAccess } from './work_tracking_access.js';
import { MAX_BODY_BYTES, bodyTooLarge } from './work_tracking_common.js';
import { addWorkItemComment, getWorkItemDetail, listAssignees, listWorkItems, updateWorkItem } from './work_tracking_service.js';
import { addMyComment, cancelMyWorkItem, createWorkItem, getMyWorkItem, listMyWorkItems, markMyWorkItemSeen } from './work_tracking_resident.js';

export const workTrackingRouter = express.Router();

// Yazma (talep aç, yorum, iptal, durum / atama): kullanıcı başına 120/saat + IP başına 1200/saat. Talep AÇMA için ayrıca DB düzeyinde saatlik sınır vardır (varsayılan 20).
export const workItemWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla iş takibi işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Okuma (liste / ayrıntı / görüldü): kullanıcı başına 1200/saat + IP başına 12000/saat.
export const workItemReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

/** Gövde yazan uçlarda kaba boyut sınırı (16 KB): alanlar kısadır; büyük gövde 413 BODY_TOO_LARGE. */
function assertBodySize(req) {
  if (req.method === 'GET') return;
  const declared = Number(req.headers['content-length']);
  const size = Number.isFinite(declared) && declared > 0 ? declared : Buffer.byteLength(JSON.stringify(req.body ?? {}));
  if (size > MAX_BODY_BYTES) {
    throw bodyTooLarge();
  }
}

function setRetryAfter(res, error) {
  if (error?.code === 'WORK_ITEM_RATE_LIMITED') {
    res.setHeader('Retry-After', String(error.extra?.retry_after_seconds ?? 3600));
  }
}

/** Yönetim sarmalayıcı: yetki + modül -> iş -> JSON. `write: true`: kurul üyesi 403. */
function managerHandler({ context, fallback, write = false }, run) {
  return async (req, res) => {
    try {
      assertBodySize(req);
      const access = await resolveWorkAccess(req, res, { write });
      if (!access) {
        return undefined;
      }
      const { status = 200, body } = await run({ req, access });
      return res.status(status).json(body);
    } catch (error) {
      setRetryAfter(res, error);
      return respondError(res, context, error, fallback);
    }
  };
}

function appHandler({ context, fallback, status = 200 }, run) {
  return async (req, res) => {
    try {
      assertBodySize(req);
      return res.status(status).json(await run(req));
    } catch (error) {
      setRetryAfter(res, error);
      return respondError(res, context, error, fallback);
    }
  };
}

// --- Yönetim -----------------------------------------------------------------------------------------------------

const BASE = '/manager/sites/:siteCode/work-items';

workTrackingRouter.get(
  BASE,
  authRequired,
  workItemReadLimiter,
  managerHandler({ context: 'work_items_list', fallback: 'Talepler yüklenemedi.' }, async ({ req, access }) => ({
    body: await listWorkItems(access.siteCode, req.query, access),
  })),
);

// `/assignees` `/:id`den ÖNCE tanımlanır (yoksa :id = "assignees" olurdu).
workTrackingRouter.get(
  `${BASE}/assignees`,
  authRequired,
  workItemReadLimiter,
  managerHandler({ context: 'work_items_assignees', fallback: 'Atanabilir kişiler yüklenemedi.', write: true }, async ({ access }) => ({
    body: await listAssignees(access.siteCode, access),
  })),
);

workTrackingRouter.get(
  `${BASE}/:id`,
  authRequired,
  workItemReadLimiter,
  managerHandler({ context: 'work_items_get', fallback: 'Talep yüklenemedi.' }, async ({ req, access }) => ({
    body: await getWorkItemDetail(access.siteCode, req.params.id, access),
  })),
);

workTrackingRouter.patch(
  `${BASE}/:id`,
  authRequired,
  workItemWriteLimiter,
  managerHandler({ context: 'work_items_update', fallback: 'Talep güncellenemedi.', write: true }, async ({ req, access }) => ({
    body: await updateWorkItem({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, access, body: bodyOf(req) }),
  })),
);

workTrackingRouter.post(
  `${BASE}/:id/comments`,
  authRequired,
  workItemWriteLimiter,
  managerHandler({ context: 'work_items_comment', fallback: 'Yorum kaydedilemedi.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: await addWorkItemComment({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, access, body: bodyOf(req) }),
  })),
);

// --- Sakin -------------------------------------------------------------------------------------------------------

workTrackingRouter.get(
  '/app/work-items',
  authRequired,
  workItemReadLimiter,
  appHandler({ context: 'my_work_items', fallback: 'Talepleriniz yüklenemedi.' }, (req) => listMyWorkItems(req.authUser, req.query)),
);

workTrackingRouter.post(
  '/app/work-items',
  authRequired,
  workItemWriteLimiter,
  appHandler({ context: 'my_work_item_create', fallback: 'Talep kaydedilemedi.', status: 201 }, (req) =>
    createWorkItem({ actor: req.authUser, body: bodyOf(req) }),
  ),
);

workTrackingRouter.get(
  '/app/work-items/:id',
  authRequired,
  workItemReadLimiter,
  appHandler({ context: 'my_work_item', fallback: 'Talep yüklenemedi.' }, (req) => getMyWorkItem(req.authUser, req.params.id)),
);

workTrackingRouter.post(
  '/app/work-items/:id/cancel',
  authRequired,
  workItemWriteLimiter,
  appHandler({ context: 'my_work_item_cancel', fallback: 'Talep iptal edilemedi.' }, (req) => cancelMyWorkItem({ actor: req.authUser, rawId: req.params.id })),
);

workTrackingRouter.post(
  '/app/work-items/:id/comments',
  authRequired,
  workItemWriteLimiter,
  appHandler({ context: 'my_work_item_comment', fallback: 'Yorum kaydedilemedi.', status: 201 }, (req) =>
    addMyComment({ actor: req.authUser, rawId: req.params.id, body: bodyOf(req) }),
  ),
);

workTrackingRouter.post(
  '/app/work-items/:id/seen',
  authRequired,
  workItemReadLimiter,
  appHandler({ context: 'my_work_item_seen', fallback: 'İşlem tamamlanamadı.' }, (req) => markMyWorkItemSeen(req.authUser, req.params.id)),
);
