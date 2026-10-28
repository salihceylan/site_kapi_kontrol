// İş Takibi (arıza, bakım, talep) uçları.
//
//   Yönetim  GET   /manager/sites/:siteCode/work-items            (liste + süzgeç + sayaçlar)    GET .../work-items/assignees    GET .../work-items/report
//            GET   .../work-items/:id                              PATCH .../work-items/:id       (durum / öncelik / atama / hedef tarih)
//            POST  .../work-items/:id/comments                     (internal | public yorum)
//            POST  .../work-items/:id/attachments                  PUT / GET .../attachments/:attId/content    DELETE .../attachments/:attId   (fotoğraf ekleri, 047)
//            GET   /manager/sites/:siteCode/work-categories        POST / PATCH /:id / DELETE /:id  (kategoriler, 100; yazma YALNIZ yönetici / süper, kullanılmış kategori silinmez pasife alınır)
//            GET   .../work-items/:id ve PUT .../content yanıtları yönetim görünümünde `photo_warnings` taşıyabilir (aynı fotoğraf başka kayıtta da var, 100; yalnız uyarı)
//   Sakin    GET/POST /app/work-items      GET /app/work-items/:id      POST /app/work-items/:id/cancel | /comments | /seen      GET /app/work-categories?site_code= (etkin kategoriler)
//            POST /app/work-items/:id/attachments      PUT / GET /app/work-items/:id/attachments/:attId/content      DELETE /app/work-items/:id/attachments/:attId
//
// Yetki: yönetici / süper / görevli (STAFF: yalnız kendine atanmış veya atanmamış) yazar; BOARD_MEMBER salt okur (iç yorum ve sakin iletişim bilgisi yok; fotoğrafı
// görür / indirir, ekleyemez / silemez); sakin yalnız KENDİ taleplerini görür. Performans raporu yalnız yönetici / süper / kurul (görevli 403). `work_tracking` modülü
// kapalıysa 403 MODULE_DISABLED. Sözleşme: docs/PLATFORM_IS_TAKIBI.md. Hata gövdesi { error, code }.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { resolveWorkAccess } from './work_tracking_access.js';
import { MAX_BODY_BYTES, bodyTooLarge, forbiddenRole } from './work_tracking_common.js';
import { addWorkItemComment, getWorkItemDetail, listAssignees, listWorkItems, updateWorkItem } from './work_tracking_service.js';
import { addMyComment, cancelMyWorkItem, createWorkItem, getMyWorkItem, listMyWorkItems, markMyWorkItemSeen } from './work_tracking_resident.js';
import { ATTACHMENT_MAX_BYTES } from './work_attachments_common.js';
import { createAttachment, deleteAttachment, managerScope, residentScope } from './work_attachments_service.js';
import { receiveAttachmentContent, sendAttachmentContent } from './work_attachments_upload.js';
import { isClientAborted } from './document_upload.js';
import { buildWorkReport } from './work_tracking_report.js';
import { listMyWorkCategories, listWorkCategories } from './work_categories_read.js';
import { createWorkCategory, deleteWorkCategory, updateWorkCategory } from './work_categories_service.js';

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

// Fotoğraf içeriği yükleme (PUT): kullanıcı başına 60/saat + IP başına 600/saat (kimlikli ama büyük gövde; kayıt açma ayrıca DB düzeyinde saatte 30 ile sınırlıdır).
export const workAttachmentUploadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 60, key: userKey },
    { windowMs: HOUR_MS, max: 600, key: ipKey },
  ],
  message: 'Çok fazla fotoğraf yükleme denemesi. Biraz sonra tekrar deneyin.',
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
  if (error?.code === 'WORK_ITEM_RATE_LIMITED' || error?.code === 'WORK_ATTACHMENT_RATE_LIMITED') {
    res.setHeader('Retry-After', String(error.extra?.retry_after_seconds ?? 3600));
  } else if (error?.code === 'UPLOAD_BUSY' || error?.code === 'DOWNLOAD_BUSY') {
    res.setHeader('Retry-After', '5');
  }
}

/**
 * İstemci gövdeyi hâlâ gönderirken erken hata yanıtı (belgelerle aynı): Content-Length yok ya da fotoğraf sınırından büyükse gövdenin okunmasını BEKLEMEDEN
 * bağlantı kapatılır. Küçük gövdeler Node tarafından boşaltılır (keep-alive korunur).
 */
function guardUnreadBody(req, res) {
  const declared = Number(req.headers['content-length']);
  if (!Number.isFinite(declared) || declared > ATTACHMENT_MAX_BYTES) {
    res.setHeader('Connection', 'close');
  }
}

/** PUT .../content ortak gövdesi: yetki çözümü çağıranındır (sakin / yönetim). */
async function uploadHandler(req, res, { context, scope }) {
  try {
    const result = await receiveAttachmentContent(req, { scope, rawId: req.params.id, rawAttId: req.params.attId, actor: req.authUser });
    return res.status(200).json(result);
  } catch (error) {
    if (isClientAborted(error)) {
      return undefined; // istemci kopmuş: yanıt yazılacak yer yok (geçici dosya silindi)
    }
    setRetryAfter(res, error);
    return respondError(res, context, error, 'Fotoğraf yüklenemedi.');
  }
}

/** GET .../content ortak gövdesi. */
async function downloadHandler(req, res, { context, scope }) {
  try {
    await sendAttachmentContent(req, res, { scope, rawId: req.params.id, rawAttId: req.params.attId });
    return undefined;
  } catch (error) {
    setRetryAfter(res, error);
    if (res.headersSent) {
      res.destroy();
      return undefined;
    }
    return respondError(res, context, error, 'Fotoğraf indirilemedi.');
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

// `/report` da `/:id`den ÖNCE. Yalnız yönetici / süper / kurul (görevli 403 FORBIDDEN_ROLE; kurul salt okur, rapor okumadır).
workTrackingRouter.get(
  `${BASE}/report`,
  authRequired,
  workItemReadLimiter,
  managerHandler({ context: 'work_items_report', fallback: 'Rapor hazırlanamadı.' }, async ({ req, access }) => {
    if (access.kind === 'staff') {
      throw forbiddenRole();
    }
    return { body: await buildWorkReport(access.siteCode, req.query) };
  }),
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

// Fotoğraf ekleri (047): kurul yalnız görür / indirir (GET); ekleme / silme yazma kapısından geçer (kurul 403).
workTrackingRouter.post(
  `${BASE}/:id/attachments`,
  authRequired,
  workItemWriteLimiter,
  managerHandler({ context: 'work_items_attachment_create', fallback: 'Fotoğraf kaydedilemedi.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: await createAttachment({ scope: managerScope(access), rawId: req.params.id, actor: req.authUser, body: bodyOf(req) }),
  })),
);

/** Ham uçlar (PUT / GET içerik) için yetki çözümü: Express 4 async hatayı yakalamaz, DB hatası burada yanıta çevrilir. Hata yazıldıysa null. */
async function managerAccessOrRespond(req, res, { write, context, fallback }) {
  try {
    return await resolveWorkAccess(req, res, { write });
  } catch (error) {
    respondError(res, context, error, fallback);
    return null;
  }
}

workTrackingRouter.put(`${BASE}/:id/attachments/:attId/content`, authRequired, workAttachmentUploadLimiter, async (req, res) => {
  guardUnreadBody(req, res);
  const access = await managerAccessOrRespond(req, res, { write: true, context: 'work_items_attachment_upload', fallback: 'Fotoğraf yüklenemedi.' });
  if (!access) {
    return undefined;
  }
  return uploadHandler(req, res, { context: 'work_items_attachment_upload', scope: managerScope(access) });
});

workTrackingRouter.get(`${BASE}/:id/attachments/:attId/content`, authRequired, workItemReadLimiter, async (req, res) => {
  const access = await managerAccessOrRespond(req, res, { write: false, context: 'work_items_attachment_download', fallback: 'Fotoğraf indirilemedi.' });
  if (!access) {
    return undefined;
  }
  return downloadHandler(req, res, { context: 'work_items_attachment_download', scope: managerScope(access) });
});

workTrackingRouter.delete(
  `${BASE}/:id/attachments/:attId`,
  authRequired,
  workItemWriteLimiter,
  managerHandler({ context: 'work_items_attachment_delete', fallback: 'Fotoğraf silinemedi.', write: true }, async ({ req, access }) => ({
    body: await deleteAttachment({ scope: managerScope(access), rawId: req.params.id, rawAttId: req.params.attId, actor: req.authUser }),
  })),
);

// --- Kategoriler (100) -------------------------------------------------------------------------------------------
// Okuma: yönetici / süper / görevli / kurul (kurul ve görevli adları görür; kullanım sayısı yalnız yönetici / süper listesinde). Yazma: YALNIZ yönetici / süper (görevli 403).
// Silme: kullanılmış kategori silinmez, pasife alınır (bkz. work_categories_service.js).

const CATEGORY_BASE = '/manager/sites/:siteCode/work-categories';

/** Kategori yazımı yalnız site yöneticisi / süper kullanıcı içindir (görevli yazma kapısını geçer ama burada 403 alır). */
function requireCategoryManager(access) {
  if (!access.canManage) {
    throw forbiddenRole();
  }
}

workTrackingRouter.get(
  CATEGORY_BASE,
  authRequired,
  workItemReadLimiter,
  managerHandler({ context: 'work_categories_list', fallback: 'Kategoriler yüklenemedi.' }, async ({ req, access }) => ({
    body: await listWorkCategories(access.siteCode, req.query, { withCount: access.canManage }),
  })),
);

workTrackingRouter.post(
  CATEGORY_BASE,
  authRequired,
  workItemWriteLimiter,
  managerHandler({ context: 'work_categories_create', fallback: 'Kategori kaydedilemedi.', write: true }, async ({ req, access }) => {
    requireCategoryManager(access);
    return { status: 201, body: await createWorkCategory({ siteCode: access.siteCode, actor: req.authUser, body: bodyOf(req) }) };
  }),
);

workTrackingRouter.patch(
  `${CATEGORY_BASE}/:id`,
  authRequired,
  workItemWriteLimiter,
  managerHandler({ context: 'work_categories_update', fallback: 'Kategori güncellenemedi.', write: true }, async ({ req, access }) => {
    requireCategoryManager(access);
    return { body: await updateWorkCategory({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, body: bodyOf(req) }) };
  }),
);

workTrackingRouter.delete(
  `${CATEGORY_BASE}/:id`,
  authRequired,
  workItemWriteLimiter,
  managerHandler({ context: 'work_categories_delete', fallback: 'Kategori silinemedi.', write: true }, async ({ req, access }) => {
    requireCategoryManager(access);
    return { body: await deleteWorkCategory({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser }) };
  }),
);

// --- Sakin -------------------------------------------------------------------------------------------------------

// Sakin talep formu: sitenin ETKİN kategorileri (site_code zorunlu; o sitede aktif sakin olmalı).
workTrackingRouter.get(
  '/app/work-categories',
  authRequired,
  workItemReadLimiter,
  appHandler({ context: 'my_work_categories', fallback: 'Kategoriler yüklenemedi.' }, (req) => listMyWorkCategories(req.authUser, req.query)),
);

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

// Fotoğraf ekleri (047): sakin yalnız KENDİ talebine (ve hâlâ aktif sakinken) ekler / siler; kendi talebindeki tüm hazır fotoğrafları görür.
workTrackingRouter.post(
  '/app/work-items/:id/attachments',
  authRequired,
  workItemWriteLimiter,
  appHandler({ context: 'my_work_item_attachment_create', fallback: 'Fotoğraf kaydedilemedi.', status: 201 }, (req) =>
    createAttachment({ scope: residentScope(req.authUser), rawId: req.params.id, actor: req.authUser, body: bodyOf(req) }),
  ),
);

workTrackingRouter.put('/app/work-items/:id/attachments/:attId/content', authRequired, workAttachmentUploadLimiter, async (req, res) => {
  guardUnreadBody(req, res);
  let scope;
  try {
    scope = residentScope(req.authUser);
  } catch (error) {
    return respondError(res, 'my_work_item_attachment_upload', error, 'Fotoğraf yüklenemedi.');
  }
  return uploadHandler(req, res, { context: 'my_work_item_attachment_upload', scope });
});

workTrackingRouter.get('/app/work-items/:id/attachments/:attId/content', authRequired, workItemReadLimiter, async (req, res) => {
  let scope;
  try {
    scope = residentScope(req.authUser);
  } catch (error) {
    return respondError(res, 'my_work_item_attachment_download', error, 'Fotoğraf indirilemedi.');
  }
  return downloadHandler(req, res, { context: 'my_work_item_attachment_download', scope });
});

workTrackingRouter.delete(
  '/app/work-items/:id/attachments/:attId',
  authRequired,
  workItemWriteLimiter,
  appHandler({ context: 'my_work_item_attachment_delete', fallback: 'Fotoğraf silinemedi.' }, (req) =>
    deleteAttachment({ scope: residentScope(req.authUser), rawId: req.params.id, rawAttId: req.params.attId, actor: req.authUser }),
  ),
);
