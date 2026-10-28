// Geri bildirim uçları (103). Sözleşme: docs/PLATFORM_GERI_BILDIRIM.md.
//
//   Gönderen  POST /app/feedback                                          (gövde: message, screen_name, screen_route, site_code?, app_version?, platform?, attachments?[])
//             PUT  /app/feedback/:id/attachments/:attId/content            (ham gövde; ek kaydı POST yanıtından gelir)
//   Yönetici  GET  /manager/sites/:siteCode/feedback                       (site yöneticisi + süper kullanıcı; kurul / görevli / sakin 403)
//             GET  /manager/sites/:siteCode/feedback/:id/attachments/:attId/content
//   Sahip     GET  /admin/feedback                                         (yalnız süper kullanıcı; ?site_code=&cursor=&limit=)
//             GET  /admin/feedback/:id/attachments/:attId/content
//
// Ekler iş takibi fotoğraf eki gibi iki adımlıdır (kayıt açılırken üstveri, sonra ham gövde PUT). K11: en çok 4 dosya, dosya başı 5 MB, toplam 20 MB; sınır aşımı 400.
// Hata gövdesi { error, code }. Modül kapısı YOKTUR (platform düzeyi özellik); her kimliği doğrulanmış aktif kullanıcı gönderebilir.

import express from 'express';
import { authRequired, requireSuperUser } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, resolveManagedSite, respondError, userKey } from './route_helpers.js';
import { isClientAborted } from './document_upload.js';
import { bodyTooLarge } from './work_tracking_common.js';
import { FEEDBACK_ATTACHMENT_MAX_BYTES, FEEDBACK_MAX_BODY_BYTES } from './feedback_common.js';
import { createFeedback, listFeedback } from './feedback_service.js';
import { receiveFeedbackContent, sendFeedbackContent } from './feedback_upload.js';

export const feedbackRouter = express.Router();

// Gönderme (POST): kullanıcı başına 20/saat + IP başına 200/saat. Ayrıca DB düzeyinde saatte 5 kayıt ve 24 saatte 100 MB ek sınırı vardır.
export const feedbackWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 20, key: userKey },
    { windowMs: HOUR_MS, max: 200, key: ipKey },
  ],
  message: 'Çok fazla geri bildirim isteği. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Ek içeriği yükleme (PUT): kullanıcı başına 60/saat + IP başına 600/saat.
export const feedbackUploadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 60, key: userKey },
    { windowMs: HOUR_MS, max: 600, key: ipKey },
  ],
  message: 'Çok fazla dosya yükleme denemesi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Okuma (liste / indirme): kullanıcı başına 1200/saat + IP başına 12000/saat.
export const feedbackReadLimiter = createRuleLimiter({
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
  const declared = Number(req.headers['content-length']);
  const size = Number.isFinite(declared) && declared > 0 ? declared : Buffer.byteLength(JSON.stringify(req.body ?? {}));
  if (size > FEEDBACK_MAX_BODY_BYTES) {
    throw bodyTooLarge();
  }
}

function setRetryAfter(res, error) {
  if (error?.code === 'FEEDBACK_RATE_LIMITED' || error?.code === 'FEEDBACK_QUOTA_EXCEEDED') {
    res.setHeader('Retry-After', String(error.extra?.retry_after_seconds ?? 3600));
  } else if (error?.code === 'UPLOAD_BUSY' || error?.code === 'DOWNLOAD_BUSY') {
    res.setHeader('Retry-After', '5');
  }
}

/** İstemci gövdeyi hâlâ gönderirken erken hata yanıtı: Content-Length yok ya da sınırdan büyükse gövdenin okunmasını BEKLEMEDEN bağlantı kapatılır. */
function guardUnreadBody(req, res) {
  const declared = Number(req.headers['content-length']);
  if (!Number.isFinite(declared) || declared > FEEDBACK_ATTACHMENT_MAX_BYTES) {
    res.setHeader('Connection', 'close');
  }
}

// --- Gönderen ---------------------------------------------------------------------------------------------------------

feedbackRouter.post('/app/feedback', authRequired, feedbackWriteLimiter, async (req, res) => {
  try {
    assertBodySize(req);
    return res.status(201).json(await createFeedback({ actor: req.authUser, body: bodyOf(req) }));
  } catch (error) {
    setRetryAfter(res, error);
    return respondError(res, 'feedback_create', error, 'Geri bildirim kaydedilemedi.');
  }
});

feedbackRouter.put('/app/feedback/:id/attachments/:attId/content', authRequired, feedbackUploadLimiter, async (req, res) => {
  guardUnreadBody(req, res);
  try {
    const result = await receiveFeedbackContent(req, { rawId: req.params.id, rawAttId: req.params.attId, actor: req.authUser });
    return res.status(200).json(result);
  } catch (error) {
    if (isClientAborted(error)) {
      return undefined; // istemci kopmuş: yanıt yazılacak yer yok (geçici dosya silindi)
    }
    setRetryAfter(res, error);
    return respondError(res, 'feedback_upload', error, 'Dosya yüklenemedi.');
  }
});

// --- Yönetici ---------------------------------------------------------------------------------------------------------

feedbackRouter.get('/manager/sites/:siteCode/feedback', authRequired, feedbackReadLimiter, async (req, res) => {
  try {
    const siteCode = await resolveManagedSite(req, res);
    if (siteCode === null) {
      return undefined;
    }
    res.setHeader('Cache-Control', 'no-store');
    return res.status(200).json(await listFeedback({ siteCode, query: req.query }));
  } catch (error) {
    return respondError(res, 'feedback_site_list', error, 'Geri bildirimler yüklenemedi.');
  }
});

feedbackRouter.get('/manager/sites/:siteCode/feedback/:id/attachments/:attId/content', authRequired, feedbackReadLimiter, async (req, res) => {
  try {
    const siteCode = await resolveManagedSite(req, res);
    if (siteCode === null) {
      return undefined;
    }
    await sendFeedbackContent(req, res, { siteCode, rawId: req.params.id, rawAttId: req.params.attId });
    return undefined;
  } catch (error) {
    setRetryAfter(res, error);
    if (res.headersSent) {
      res.destroy();
      return undefined;
    }
    return respondError(res, 'feedback_site_download', error, 'Dosya indirilemedi.');
  }
});

// --- Platform sahibi (süper kullanıcı) ------------------------------------------------------------------------------

feedbackRouter.get('/admin/feedback', authRequired, requireSuperUser, feedbackReadLimiter, async (req, res) => {
  try {
    res.setHeader('Cache-Control', 'no-store');
    return res.status(200).json(await listFeedback({ siteCode: null, query: req.query }));
  } catch (error) {
    return respondError(res, 'feedback_admin_list', error, 'Geri bildirimler yüklenemedi.');
  }
});

feedbackRouter.get('/admin/feedback/:id/attachments/:attId/content', authRequired, requireSuperUser, feedbackReadLimiter, async (req, res) => {
  try {
    await sendFeedbackContent(req, res, { siteCode: null, rawId: req.params.id, rawAttId: req.params.attId });
    return undefined;
  } catch (error) {
    setRetryAfter(res, error);
    if (res.headersSent) {
      res.destroy();
      return undefined;
    }
    return respondError(res, 'feedback_admin_download', error, 'Dosya indirilemedi.');
  }
});
