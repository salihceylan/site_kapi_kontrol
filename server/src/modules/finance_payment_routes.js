// Ödeme bilgisi uçları (054; Dalga 2 / 2A). server.js `app.use(financePaymentRouter)`.
//
//   GET/PUT /manager/sites/:siteCode/finance/payment-settings              okuma: yönetici/süper/kurul (kurul IBAN'ı maskeli), yazma: yönetici/süper
//   PUT     /manager/sites/:siteCode/finance/accounts/:id/bank-details     {iban, payee_name} -> 201 yeni sürüm (aynı değer 200)
//   GET     /manager/sites/:siteCode/finance/payment-references?block_id=  daire kodları (kısa kod + bu ayın kodu)
//   GET     /app/my-finance/payment-info                                   sakin: ödeme bilgisi (TUTAR DÖNMEZ)
//
// Yetki ve modül denetimi finance_access.js ile aynıdır (STAFF/sakin 403, başka site 403, `finance` kapalıysa 403 MODULE_DISABLED).
// Sözleşme: docs/PLATFORM_FINANS_ODEME.md.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { BASE, bodyOf, canSeeManagerFields, financeReadLimiter, financeResidentLimiter, financeWriteLimiter, managerHandler } from './finance_routes.js';
import { getMyPaymentInfo, getPaymentSettings, listPaymentReferences, putBankDetails, putPaymentSettings } from './finance_payment_info.js';
import { respondError } from './route_helpers.js';

export const financePaymentRouter = express.Router();

financePaymentRouter.get(
  `${BASE}/payment-settings`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_payment_settings_get', fallback: 'Ödeme ayarları yüklenemedi.' }, async ({ access }) => ({
    body: await getPaymentSettings(access.siteCode, { full: canSeeManagerFields(access) }),
  })),
);

financePaymentRouter.put(
  `${BASE}/payment-settings`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_payment_settings_put', fallback: 'Ödeme ayarları kaydedilemedi.', write: true }, async ({ req, access }) => ({
    body: await putPaymentSettings({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser }),
  })),
);

financePaymentRouter.put(
  `${BASE}/accounts/:id/bank-details`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_bank_details_put', fallback: 'Banka bilgisi kaydedilemedi.', write: true }, async ({ req, access }) => {
    const result = await putBankDetails({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return { status: result.replayed ? 200 : 201, body: { replayed: result.replayed, bank: result.bank } };
  }),
);

financePaymentRouter.get(
  `${BASE}/payment-references`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_payment_references', fallback: 'Daire kodları yüklenemedi.' }, async ({ req, access }) => ({
    body: await listPaymentReferences(access.siteCode, req.query ?? {}),
  })),
);

financePaymentRouter.get('/app/my-finance/payment-info', authRequired, financeResidentLimiter, async (req, res) => {
  try {
    return res.status(200).json(await getMyPaymentInfo(req.authUser));
  } catch (error) {
    return respondError(res, 'my_payment_info', error, 'Ödeme bilgisi yüklenemedi.');
  }
});
