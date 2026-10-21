// Dekont bildirimi uçları (066; Dalga 2 / 2B). server.js `app.use(paymentNoticeRouter)`. Sözleşme: docs/PLATFORM_FINANS_DEKONT.md.
//
// Sakin (`finance` açık + 2A'da notices_enabled açık; aksi 403 PAYMENT_NOTICES_DISABLED):
//   POST /app/my-finance/payment-notices                 {apartment_id, amount_minor, paid_on, sender_name?, sender_iban?, description?, note?, origin?, file{name,size,content_type}, idempotency_key} -> 201 {notice, upload}
//   PUT  /app/my-finance/payment-notices/:id/content     ham gövde (application/octet-stream, Content-Length = file.size) -> pending
//   GET  /app/my-finance/payment-notices[?apartment_id=] -> {items, pending_total_minor, unseen_count}     GET .../:id/file     POST .../:id/withdraw     POST .../seen
// Yönetici / süper (kurul ve görevli 403; başka site 403):
//   GET  .../finance/payment-notices[?status=&apartment_id=&before_id=]  GET .../summary  GET .../:id  GET .../:id/file
//   POST .../finance/payment-notices (elden giriş)  PUT .../:id/content  POST .../:id/approve | link | reject  POST .../bulk-approve | bulk-reject {ids}

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { resolveFinanceAccess } from './finance_access.js';
import { bodyOf, financeReadLimiter, financeResidentLimiter, financeWriteLimiter, managerHandler, BASE } from './finance_routes.js';
import { isClientAborted } from './document_upload.js';
import { NOTICE_MAX_BYTES } from './payment_notice_common.js';
import {
  approveNotice,
  bulkDecide,
  createManagerNotice,
  createMyNotice,
  getNoticeDetail,
  linkNotice,
  listMyNotices,
  listNotices,
  markMyNoticesSeen,
  noticeSummary,
  rejectNotice,
  withdrawMyNotice,
} from './payment_notice_service.js';
import { receiveNoticeContent, sendNoticeFile } from './payment_notice_upload.js';
import { respondError } from './route_helpers.js';
import { parsePositiveId } from './people_common.js';

export const paymentNoticeRouter = express.Router();

const MINE = '/app/my-finance/payment-notices';
const MGR = `${BASE}/payment-notices`;

const userCodeOf = (req) => parsePositiveId(req.authUser?.user_code ?? req.authUser?.userCode ?? req.authUser?.id);

function setRetryAfter(res, error) {
  const seconds = error?.extra?.retry_after_seconds;
  if (Number.isFinite(seconds)) res.setHeader('Retry-After', String(seconds));
}

/** Gövde büyükse ya da Content-Length yoksa bağlantı yanıttan sonra kapatılır (gövdenin okunması beklenmez). */
function guardUnreadBody(req, res) {
  const declared = Number(req.headers['content-length']);
  if (!Number.isFinite(declared) || declared > NOTICE_MAX_BYTES) res.setHeader('Connection', 'close');
}

function residentHandler({ context, fallback, status = 200 }, run) {
  return async (req, res) => {
    try {
      return res.status(status).json(await run(req));
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

async function uploadHandler(req, res, { context, access = null }) {
  try {
    guardUnreadBody(req, res);
    const out = await receiveNoticeContent(req, { rawId: req.params.id, userCode: userCodeOf(req), siteCode: access?.siteCode ?? null, manager: access !== null });
    return res.status(200).json(out);
  } catch (error) {
    if (isClientAborted(error)) return undefined;
    setRetryAfter(res, error);
    return respondError(res, context, error, 'Dekont yüklenemedi.');
  }
}

async function downloadHandler(req, res, { context, access = null }) {
  try {
    await sendNoticeFile(req, res, {
      rawId: req.params.id,
      userCode: access ? null : userCodeOf(req),
      siteCode: access?.siteCode ?? null,
      actor: access ? req.authUser : null,
    });
    return undefined;
  } catch (error) {
    setRetryAfter(res, error);
    if (res.headersSent) {
      res.destroy();
      return undefined;
    }
    return respondError(res, context, error, 'Dekont indirilemedi.');
  }
}

// --- Sakin -------------------------------------------------------------------------------------------------

paymentNoticeRouter.post(
  MINE,
  authRequired,
  financeResidentLimiter,
  residentHandler({ context: 'payment_notice_create', fallback: 'Dekont bildirimi kaydedilemedi.', status: 201 }, (req) => createMyNotice(req.authUser, bodyOf(req))),
);
paymentNoticeRouter.get(MINE, authRequired, financeResidentLimiter, residentHandler({ context: 'payment_notice_list', fallback: 'Bildirimler yüklenemedi.' }, (req) => listMyNotices(req.authUser, req.query ?? {})));
paymentNoticeRouter.post(`${MINE}/seen`, authRequired, financeResidentLimiter, residentHandler({ context: 'payment_notice_seen', fallback: 'İşlem yapılamadı.' }, (req) => markMyNoticesSeen(req.authUser)));
paymentNoticeRouter.post(`${MINE}/:id/withdraw`, authRequired, financeResidentLimiter, residentHandler({ context: 'payment_notice_withdraw', fallback: 'Bildirim geri çekilemedi.' }, (req) => withdrawMyNotice(req.authUser, req.params.id)));
paymentNoticeRouter.put(`${MINE}/:id/content`, authRequired, financeResidentLimiter, (req, res) => uploadHandler(req, res, { context: 'payment_notice_upload' }));
paymentNoticeRouter.get(`${MINE}/:id/file`, authRequired, financeResidentLimiter, (req, res) => downloadHandler(req, res, { context: 'payment_notice_download' }));

// --- Yönetici ----------------------------------------------------------------------------------------------

const mgr = (context, fallback, run) => managerHandler({ context, fallback, write: true }, run);

paymentNoticeRouter.get(MGR, authRequired, financeReadLimiter, mgr('payment_notice_mgr_list', 'Dekontlar yüklenemedi.', async ({ req, access }) => ({ body: await listNotices(access.siteCode, req.query ?? {}) })));
paymentNoticeRouter.get(`${MGR}/summary`, authRequired, financeReadLimiter, mgr('payment_notice_summary', 'Özet yüklenemedi.', async ({ access }) => ({ body: await noticeSummary(access.siteCode) })));
paymentNoticeRouter.get(`${MGR}/:id`, authRequired, financeReadLimiter, mgr('payment_notice_detail', 'Dekont yüklenemedi.', async ({ req, access }) => ({ body: await getNoticeDetail(access.siteCode, req.params.id) })));
paymentNoticeRouter.post(
  MGR,
  authRequired,
  financeWriteLimiter,
  mgr('payment_notice_mgr_create', 'Kayıt oluşturulamadı.', async ({ req, access }) => {
    const out = await createManagerNotice(access.siteCode, req.authUser, bodyOf(req));
    return { status: out.replayed ? 200 : 201, body: out };
  }),
);
paymentNoticeRouter.post(`${MGR}/bulk-approve`, authRequired, financeWriteLimiter, mgr('payment_notice_bulk_approve', 'Toplu onay yapılamadı.', async ({ req, access }) => ({ body: await bulkDecide({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser, action: 'approve' }) })));
paymentNoticeRouter.post(`${MGR}/bulk-reject`, authRequired, financeWriteLimiter, mgr('payment_notice_bulk_reject', 'Toplu iptal yapılamadı.', async ({ req, access }) => ({ body: await bulkDecide({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser, action: 'reject' }) })));
paymentNoticeRouter.post(`${MGR}/:id/approve`, authRequired, financeWriteLimiter, mgr('payment_notice_approve', 'Onaylanamadı.', async ({ req, access }) => ({ body: await approveNotice({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser }) })));
paymentNoticeRouter.post(`${MGR}/:id/link`, authRequired, financeWriteLimiter, mgr('payment_notice_link', 'Bağlanamadı.', async ({ req, access }) => ({ body: await linkNotice({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser }) })));
paymentNoticeRouter.post(`${MGR}/:id/reject`, authRequired, financeWriteLimiter, mgr('payment_notice_reject', 'İptal edilemedi.', async ({ req, access }) => ({ body: await rejectNotice({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser }) })));

// Dosya uçları ham akış yazar; yetki çözümü managerHandler dışında yapılır (hata yanıtını resolveFinanceAccess yazar).
paymentNoticeRouter.put(`${MGR}/:id/content`, authRequired, financeWriteLimiter, async (req, res) => {
  const access = await resolveFinanceAccess(req, res, { write: true }).catch((error) => {
    respondError(res, 'payment_notice_mgr_upload', error, 'Dekont yüklenemedi.');
    return null;
  });
  if (!access) return undefined;
  return uploadHandler(req, res, { context: 'payment_notice_mgr_upload', access });
});
paymentNoticeRouter.get(`${MGR}/:id/file`, authRequired, financeReadLimiter, async (req, res) => {
  const access = await resolveFinanceAccess(req, res, { write: true }).catch((error) => {
    respondError(res, 'payment_notice_mgr_download', error, 'Dekont indirilemedi.');
    return null;
  });
  if (!access) return undefined;
  return downloadHandler(req, res, { context: 'payment_notice_mgr_download', access });
});
