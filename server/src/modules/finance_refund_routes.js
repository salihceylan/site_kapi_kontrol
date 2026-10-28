// Alacak iadesi uçları (ayrı router; server.js `app.use(financeRefundRouter)`). Sözleşme: docs/PLATFORM_FINANS.md "Alacak iadesi".
//
// Sakin (yalnız KENDİ hesabı; başka daire 404):
//   POST /app/my-finance/refund-requests            { apartment_id, amount_minor, note?, idempotency_key } -> 201 { refund }
//   GET  /app/my-finance/refund-requests[?apartment_id=]  -> { items }
//   POST /app/my-finance/refund-requests/:id/cancel       (bekleyen talebi geri çek)
// Yönetici / süper (kurul yalnız OKUR, adsız; görevli ve sakin 403; başka site 403):
//   GET  /manager/sites/:siteCode/finance/refunds[?status=&apartment_id=&before_id=&limit=]   GET .../refunds/:id
//   POST .../finance/refunds                       { apartment_id, account_party, amount_minor, note?, idempotency_key }   (sakin adına talep)
//   POST .../finance/refunds/:id/approve           { pay_account_id, idempotency_key }
//   POST .../finance/refunds/:id/reject            { reason, idempotency_key }
//   POST .../finance/refunds/:id/reverse           { reason, idempotency_key }                (onaylı iadeyi geri al)
// Finans TEMEL modüldür (Kural 25). Hata gövdesi { error, code }.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import {
  approveRefund,
  cancelMyRefundRequest,
  createManagerRefundRequest,
  createMyRefundRequest,
  getRefund,
  listMyRefundRequests,
  listRefunds,
  rejectRefund,
  reverseRefund,
} from './finance_refunds.js';
import { BASE, bodyOf, financeReadLimiter, financeResidentLimiter, financeWriteLimiter, managerHandler } from './finance_routes.js';
import { respondError } from './route_helpers.js';

export const financeRefundRouter = express.Router();

const MINE = '/app/my-finance/refund-requests';
const MGR = `${BASE}/refunds`;

function residentHandler({ context, fallback, status = 200 }, run) {
  return async (req, res) => {
    try {
      const out = await run(req);
      return res.status(out?.replayed === true && status === 201 ? 200 : status).json(out);
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

// --- Sakin -----------------------------------------------------------------------------------------------------------------------------

financeRefundRouter.post(
  MINE,
  authRequired,
  financeResidentLimiter,
  residentHandler({ context: 'refund_request_create', fallback: 'İade talebi kaydedilemedi.', status: 201 }, (req) => createMyRefundRequest(req.authUser, bodyOf(req))),
);
financeRefundRouter.get(MINE, authRequired, financeResidentLimiter, residentHandler({ context: 'refund_request_list', fallback: 'İade talepleri yüklenemedi.' }, (req) => listMyRefundRequests(req.authUser, req.query ?? {})));
financeRefundRouter.post(
  `${MINE}/:id/cancel`,
  authRequired,
  financeResidentLimiter,
  residentHandler({ context: 'refund_request_cancel', fallback: 'İade talebi geri çekilemedi.' }, (req) => cancelMyRefundRequest(req.authUser, req.params.id)),
);

// --- Yönetici --------------------------------------------------------------------------------------------------------------------------

financeRefundRouter.get(
  MGR,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_refunds_list', fallback: 'İade talepleri yüklenemedi.' }, async ({ req, access }) => ({ body: await listRefunds(access.siteCode, req.query ?? {}) })),
);

financeRefundRouter.get(
  `${MGR}/:id`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_refund_detail', fallback: 'İade talebi yüklenemedi.' }, async ({ req, access }) => ({ body: await getRefund(access.siteCode, req.params.id) })),
);

financeRefundRouter.post(
  MGR,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_refund_create', fallback: 'İade talebi kaydedilemedi.', write: true }, async ({ req, access }) => {
    const result = await createManagerRefundRequest({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser });
    return { status: result.replayed ? 200 : 201, body: { refund: result.refund } };
  }),
);

financeRefundRouter.post(
  `${MGR}/:id/approve`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_refund_approve', fallback: 'İade onaylanamadı.', write: true }, async ({ req, access }) => {
    const result = await approveRefund({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return { status: result.replayed ? 200 : 201, body: { refund: result.refund } };
  }),
);

financeRefundRouter.post(
  `${MGR}/:id/reject`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_refund_reject', fallback: 'İade talebi reddedilemedi.', write: true }, async ({ req, access }) => {
    const result = await rejectRefund({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return { status: result.replayed ? 200 : 201, body: { refund: result.refund } };
  }),
);

financeRefundRouter.post(
  `${MGR}/:id/reverse`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_refund_reverse', fallback: 'İade geri alınamadı.', write: true }, async ({ req, access }) => {
    const result = await reverseRefund({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return { status: result.replayed ? 200 : 201, body: { refund: result.refund } };
  }),
);
