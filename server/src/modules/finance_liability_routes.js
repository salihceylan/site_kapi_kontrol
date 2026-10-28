// Kiracı borcunun malike devri uçları (ayrı router; server.js `app.use(financeLiabilityRouter)`). Sözleşme: docs/PLATFORM_FINANS.md "Kiracı borcunun malike devri".
//
//   Önizleme   GET   /manager/sites/:siteCode/finance/apartments/:apartmentId/liability-transfer/preview   kalemler, tazminat istisnası, toplam, önizleme özeti
//   Devir      POST  /manager/sites/:siteCode/finance/apartments/:apartmentId/liability-transfer           { expected_total_minor, expected_hash, reason, idempotency_key }
//   Geçmiş     GET   /manager/sites/:siteCode/finance/apartments/:apartmentId/liability-transfers          devirler ve geri almalar
//   Geri alma  POST  /manager/sites/:siteCode/finance/liability-transfers/:id/reverse                      { reason, idempotency_key }
//
// Yetki (finance_access.js): okuma = yönetici / süper + BOARD_MEMBER (salt okunur, adsız); YAZMA = yalnız yönetici / süper; STAFF ve sakin 403 FORBIDDEN_ROLE; başka site 403 FORBIDDEN_SITE.
// Finans TEMEL modüldür (Kural 25). Hata gövdesi { error, code }.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createLiabilityTransfer, listLiabilityTransfers, previewLiabilityTransfer, reverseLiabilityTransfer } from './finance_liability_service.js';
import { BASE, bodyOf, financeReadLimiter, financeWriteLimiter, managerHandler } from './finance_routes.js';

export const financeLiabilityRouter = express.Router();

const APARTMENT = `${BASE}/apartments/:apartmentId`;

financeLiabilityRouter.get(
  `${APARTMENT}/liability-transfer/preview`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_liability_preview', fallback: 'Devir önizlemesi hazırlanamadı.' }, async ({ req, access }) => ({
    body: await previewLiabilityTransfer(access.siteCode, req.params.apartmentId),
  })),
);

financeLiabilityRouter.post(
  `${APARTMENT}/liability-transfer`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_liability_transfer', fallback: 'Borç devredilemedi.', write: true }, async ({ req, access }) => {
    const result = await createLiabilityTransfer({ siteCode: access.siteCode, rawApartmentId: req.params.apartmentId, body: bodyOf(req), actor: req.authUser });
    return {
      status: result.replayed ? 200 : 201,
      body: { transfer: result.transfer, tenant_balance_minor: result.tenant_balance_minor, owner_balance_minor: result.owner_balance_minor },
    };
  }),
);

financeLiabilityRouter.get(
  `${APARTMENT}/liability-transfers`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_liability_list', fallback: 'Devir geçmişi yüklenemedi.' }, async ({ req, access }) => ({
    body: await listLiabilityTransfers(access.siteCode, req.params.apartmentId),
  })),
);

financeLiabilityRouter.post(
  `${BASE}/liability-transfers/:id/reverse`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_liability_reverse', fallback: 'Devir geri alınamadı.', write: true }, async ({ req, access }) => {
    const result = await reverseLiabilityTransfer({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return {
      status: result.replayed ? 200 : 201,
      body: { transfer: result.transfer, tenant_balance_minor: result.tenant_balance_minor, owner_balance_minor: result.owner_balance_minor },
    };
  }),
);
