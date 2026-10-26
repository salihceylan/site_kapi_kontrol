// Aidat ve Finans (Faz 4a) uçları.
//
//   Tanımlar     GET/POST   /manager/sites/:siteCode/finance/definitions            PATCH .../definitions/:id
//                POST       /manager/sites/:siteCode/finance/definitions/:id/preview | /post
//   Ek borç      POST       /manager/sites/:siteCode/finance/charges/preview | /charges
//   Hesaplar     GET        /manager/sites/:siteCode/finance/balances               GET .../apartments/:apartmentId/account
//   Tahsilat     POST       /manager/sites/:siteCode/finance/payments
//   Düzeltme     POST       /manager/sites/:siteCode/finance/entries/:id/reverse | /correct
//   Dönemler     GET        /manager/sites/:siteCode/finance/periods                POST .../periods/:period/close | /reopen (yalnız süper)
//   Özet         GET        /manager/sites/:siteCode/finance/summary
//   Sakin        GET        /app/my-finance
//
// Yetki (finance_access.js): yazma = yönetici/süper; okuma = yönetici/süper + BOARD_MEMBER (salt okunur); STAFF/sakin 403 FORBIDDEN_ROLE; başka site
// 403 FORBIDDEN_SITE; `finance` modülü kapalıysa 403 MODULE_DISABLED. Yeniden açma yalnız süper kullanıcı. Kurul yanıtından yönetici adları çıkarılır.
// Sözleşme: docs/PLATFORM_FINANS.md. Hata gövdesi: { error, code }. Hız sınırları: yazma 120/saat, okuma 1200/saat, sakin 600/saat (kullanıcı başına).

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { resolveFinanceAccess } from './finance_access.js';
import { redactFinanceForBoard } from './finance_common.js';
import {
  closePeriod,
  correctPayment,
  listPeriods,
  recordPayment,
  reopenPeriod,
  reverseEntry,
} from './finance_ledger_service.js';
import { getApartmentAccount, getMyFinance, getSummary, listBalances } from './finance_read_service.js';
import {
  createDefinition,
  listDefinitions,
  postCharge,
  postDefinition,
  previewCharge,
  previewDefinition,
  updateDefinition,
} from './finance_service.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';

export const financeRouter = express.Router();

// Yazma uçları: kullanıcı başına 120/saat (sözleşme). IP kuralı NAT arkasındaki birçok yöneticiyi toplu kilitlemesin diye geniştir.
export const financeWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla finans işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Okuma ve önizleme uçları: kullanıcı başına 1200/saat.
export const financeReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Sakin "Borcum": kullanıcı başına 600/saat.
export const financeResidentLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 600, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

export const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});
export const canSeeManagerFields = (access) => access.kind === 'super' || access.kind === 'manager';

/**
 * Yönetici sarmalayıcı: yetki + site + modül -> iş -> JSON. `write`: yalnız yönetici/süper; `superOnly`: yalnız süper kullanıcı.
 * `run` { status?, body } döndürür. Kurul yanıtından yönetici adları çıkarılır.
 */
export function managerHandler({ context, fallback, write = false, superOnly = false }, run) {
  return async (req, res) => {
    try {
      const access = await resolveFinanceAccess(req, res, { write, superOnly });
      if (!access) {
        return undefined;
      }
      const { status = 200, body } = await run({ req, access });
      return res.status(status).json(canSeeManagerFields(access) ? body : redactFinanceForBoard(body));
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

export const BASE = '/manager/sites/:siteCode/finance';

// --- Tanımlar ---------------------------------------------------------------------------------------------

financeRouter.get(
  `${BASE}/definitions`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_definitions_list', fallback: 'Tanımlar yüklenemedi.' }, async ({ req, access }) => ({
    body: await listDefinitions(access.siteCode, req.query),
  })),
);

financeRouter.post(
  `${BASE}/definitions`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_definition_create', fallback: 'Tanım kaydedilemedi.', write: true }, async ({ req, access }) => ({
    status: 201,
    body: await createDefinition({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser }),
  })),
);

financeRouter.patch(
  `${BASE}/definitions/:id`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_definition_update', fallback: 'Tanım güncellenemedi.', write: true }, async ({ req, access }) => ({
    body: await updateDefinition({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser }),
  })),
);

financeRouter.post(
  `${BASE}/definitions/:id/preview`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_definition_preview', fallback: 'Önizleme hazırlanamadı.', write: true }, async ({ req, access }) => ({
    body: await previewDefinition({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req) }),
  })),
);

financeRouter.post(
  `${BASE}/definitions/:id/post`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_definition_post', fallback: 'Borçlandırma yapılamadı.', write: true }, async ({ req, access }) => {
    const result = await postDefinition({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return {
      status: result.replayed ? 200 : 201,
      body: { run: result.run, entries_count: result.entries_count, skipped_count: result.skipped_count, redistributed: result.redistributed },
    };
  }),
);

// --- Ek borç ----------------------------------------------------------------------------------------------

financeRouter.post(
  `${BASE}/charges/preview`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_charge_preview', fallback: 'Önizleme hazırlanamadı.', write: true }, async ({ req, access }) => ({
    body: await previewCharge({ siteCode: access.siteCode, body: bodyOf(req) }),
  })),
);

financeRouter.post(
  `${BASE}/charges`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_charge_post', fallback: 'Ek borç eklenemedi.', write: true }, async ({ req, access }) => {
    const result = await postCharge({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser });
    return {
      status: result.replayed ? 200 : 201,
      body: {
        run: result.run,
        entries_count: result.entries_count,
        skipped_count: result.skipped_count,
        redistributed: result.redistributed,
        definition: result.definition,
      },
    };
  }),
);

// --- Hesaplar ---------------------------------------------------------------------------------------------

financeRouter.get(
  `${BASE}/balances`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_balances', fallback: 'Bakiyeler yüklenemedi.' }, async ({ req, access }) => ({
    body: await listBalances(access.siteCode, req.query),
  })),
);

financeRouter.get(
  `${BASE}/apartments/:apartmentId/account`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_account', fallback: 'Ekstre yüklenemedi.' }, async ({ req, access }) => ({
    body: await getApartmentAccount(access.siteCode, req.params.apartmentId, req.query),
  })),
);

financeRouter.get(
  `${BASE}/summary`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_summary', fallback: 'Özet yüklenemedi.' }, async ({ access }) => ({
    body: await getSummary(access.siteCode),
  })),
);

// --- Tahsilat ve düzeltme ---------------------------------------------------------------------------------

financeRouter.post(
  `${BASE}/payments`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_payment', fallback: 'Tahsilat kaydedilemedi.', write: true }, async ({ req, access }) => {
    const result = await recordPayment({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser });
    return {
      status: result.replayed ? 200 : 201,
      body: {
        entry: result.entry,
        balance_minor: result.balance_minor,
        account_balance_minor: result.account_balance_minor ?? null,
        receipt: result.receipt ?? null,
        movement_id: result.movement_id ?? null,
        // Kasa dagitimi (docs/PLATFORM_FINANS_KASALAR.md 5): bu tahsilatin su anki dagitimi
        fund_split: result.fund_split ?? null,
      },
    };
  }),
);

financeRouter.post(
  `${BASE}/entries/:id/reverse`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_reverse', fallback: 'Kayıt iptal edilemedi.', write: true }, async ({ req, access }) => {
    const result = await reverseEntry({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return { status: result.replayed ? 200 : 201, body: { entry: result.entry, balance_minor: result.balance_minor } };
  }),
);

financeRouter.post(
  `${BASE}/entries/:id/correct`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_correct', fallback: 'Tahsilat düzeltilemedi.', write: true }, async ({ req, access }) => {
    const result = await correctPayment({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return {
      status: result.replayed ? 200 : 201,
      body: {
        reversal: result.reversal,
        entry: result.entry,
        balance_minor: result.balance_minor,
        account_balance_minor: result.account_balance_minor ?? null,
        receipt: result.receipt ?? null,
        movement_id: result.movement_id ?? null,
        // Kasa dagitimi (docs/PLATFORM_FINANS_KASALAR.md 5): bu tahsilatin su anki dagitimi
        fund_split: result.fund_split ?? null,
      },
    };
  }),
);

// --- Dönemler ---------------------------------------------------------------------------------------------

financeRouter.get(
  `${BASE}/periods`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_periods', fallback: 'Dönemler yüklenemedi.' }, async ({ access }) => ({
    body: await listPeriods(access.siteCode),
  })),
);

financeRouter.post(
  `${BASE}/periods/:period/close`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_period_close', fallback: 'Dönem kapatılamadı.', write: true }, async ({ req, access }) => ({
    body: await closePeriod({ siteCode: access.siteCode, rawPeriod: req.params.period, actor: req.authUser }),
  })),
);

financeRouter.post(
  `${BASE}/periods/:period/reopen`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_period_reopen', fallback: 'Dönem yeniden açılamadı.', superOnly: true }, async ({ req, access }) => ({
    body: await reopenPeriod({ siteCode: access.siteCode, rawPeriod: req.params.period, actor: req.authUser }),
  })),
);

// --- Sakin ------------------------------------------------------------------------------------------------

financeRouter.get('/app/my-finance', authRequired, financeResidentLimiter, async (req, res) => {
  try {
    return res.status(200).json(await getMyFinance(req.authUser));
  } catch (error) {
    return respondError(res, 'my_finance', error, 'Borç bilgileriniz yüklenemedi.');
  }
});
