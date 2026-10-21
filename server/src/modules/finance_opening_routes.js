// Devir bakiyesi uçları (F4). Yükleme: POST /manager/sites/:siteCode/imports/opening_balances/preview|commit (toplu yükleme altyapısı).
//
//   GET   /manager/sites/:siteCode/finance/opening-balances              yüklemeler ve durumları
//   GET   /manager/sites/:siteCode/finance/opening-balances/:runId       geri alma önizlemesi
//   POST  /manager/sites/:siteCode/finance/opening-balances/:runId/revert  { reason, idempotency_key, expected_count, expected_total_minor }
//
// Yetki: finance_routes.managerHandler (yazma yönetici/süper, okuma + kurul; modül kapalıysa 403 MODULE_DISABLED; başka site 403/404).

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { BASE, bodyOf, financeReadLimiter, financeWriteLimiter, managerHandler } from './finance_routes.js';
import { getOpeningRun, listOpeningRuns, revertOpeningRun } from './finance_opening.js';

export const financeOpeningRouter = express.Router();

financeOpeningRouter.get(
  `${BASE}/opening-balances`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_opening_list', fallback: 'Devir yüklemeleri alınamadı.' }, async ({ access }) => ({
    body: await listOpeningRuns(access.siteCode),
  })),
);

financeOpeningRouter.get(
  `${BASE}/opening-balances/:runId`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_opening_detail', fallback: 'Devir yüklemesi alınamadı.' }, async ({ req, access }) => ({
    body: await getOpeningRun(access.siteCode, req.params.runId),
  })),
);

financeOpeningRouter.post(
  `${BASE}/opening-balances/:runId/revert`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_opening_revert', fallback: 'Devir geri alınamadı.', write: true }, async ({ req, access }) => {
    const body = await revertOpeningRun({ siteCode: access.siteCode, rawRunId: req.params.runId, body: bodyOf(req), actor: req.authUser });
    return { status: body.replayed ? 200 : 201, body };
  }),
);
