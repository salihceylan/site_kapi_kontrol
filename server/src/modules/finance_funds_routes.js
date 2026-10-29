// İki kasa (İşletme / Yatırım ve Demirbaş Fon) uçları (ayrı router; server.js `app.use(financeFundsRouter)`).
//
//   Kasalar     GET   /manager/sites/:siteCode/finance/funds                         iki kasa: açılış, tahsilat, gider, aktarım, bakiye + avans (from / to süzgeci)
//               GET   /manager/sites/:siteCode/finance/funds/:fund/movements         sayfalı kasa dökümü (fund: operating | capital)
//   Aktarım     GET   /manager/sites/:siteCode/finance/fund-transfers                kasalar arası aktarımlar
//               POST  /manager/sites/:siteCode/finance/fund-transfers                aktarım (kaynak kasa, hedef kasa, tutar, tarih)
//               POST  /manager/sites/:siteCode/finance/fund-transfers/:id/reverse    ters aktarım (düzeltme)
//
// Yetki (finance_access.js): okuma = yönetici/süper + BOARD_MEMBER (salt okunur); yazma = yönetici/süper; STAFF / sakin 403 FORBIDDEN_ROLE; başka site 403 FORBIDDEN_SITE.
// Finans TEMEL modüldür (Kural 25): MODULE_DISABLED tetiklenmez. Hata gövdesi { error, code }. Sözleşme: docs/PLATFORM_FINANS_KASALAR.md.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { resolveFinanceAccess } from './finance_access.js';
import { redactFinanceForBoard } from './finance_common.js';
import { createFundTransfer, getFundSummary, listFundMovements, listFundTransfers, reverseFundTransfer } from './finance_funds_service.js';
import { periodReport } from './finance_period_report.js';
import { BASE, bodyOf, canSeeManagerFields, financeReadLimiter, financeWriteLimiter, managerHandler } from './finance_routes.js';
import { HOUR_MS, respondError, userKey } from './route_helpers.js';

export const financeFundsRouter = express.Router();

// Kasa özeti ve dökümü sitenin tüm defterini okur (rapor sınıfı): kullanıcı başına 120/saat.
export const fundsReportLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 120, key: userKey }],
  message: 'Çok fazla hesap raporu isteği. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

/** Kasa rapor ucu: okuma yetkisi (kurul dahil), no-store, REPORT_BUSY için Retry-After. */
function fundsReadRoute(path, context, fallback, run) {
  financeFundsRouter.get(path, authRequired, financeReadLimiter, fundsReportLimiter, async (req, res) => {
    try {
      const access = await resolveFinanceAccess(req, res, { write: false });
      if (!access) {
        return undefined;
      }
      res.set('Cache-Control', 'no-store');
      const body = await run({ req, access });
      return res.status(200).json(canSeeManagerFields(access) ? body : redactFinanceForBoard(body));
    } catch (error) {
      if (error?.retryAfterSeconds) {
        res.set('Retry-After', String(error.retryAfterSeconds));
      }
      return respondError(res, context, error, fallback);
    }
  });
}

fundsReadRoute(`${BASE}/funds`, 'finance_funds_summary', 'Aidat ve Fon hesapları yüklenemedi.', async ({ req, access }) => getFundSummary(access.siteCode, req.query));
// Dönemsel rapor paketi (aylık / 3 aylık / yıllık): iki Hesap için dönem özeti + gider kalemleri + dönem sonu borçlu özeti (kişi verisi yok). ?from=YYYY-MM&to=YYYY-MM
fundsReadRoute(`${BASE}/reports/period`, 'finance_period_report', 'Dönem raporu hazırlanamadı.', async ({ req, access }) => periodReport(access.siteCode, req.query));
fundsReadRoute(`${BASE}/funds/:fund/movements`, 'finance_funds_movements', 'Hesap dökümü yüklenemedi.', async ({ req, access }) =>
  listFundMovements(access.siteCode, req.params.fund, req.query),
);

financeFundsRouter.get(
  `${BASE}/fund-transfers`,
  authRequired,
  financeReadLimiter,
  managerHandler({ context: 'finance_fund_transfers_list', fallback: 'Hesaplar arası aktarımlar yüklenemedi.' }, async ({ req, access }) => ({
    body: await listFundTransfers(access.siteCode, req.query),
  })),
);

financeFundsRouter.post(
  `${BASE}/fund-transfers`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_fund_transfer_create', fallback: 'Hesaplar arası aktarım kaydedilemedi.', write: true }, async ({ req, access }) => {
    const result = await createFundTransfer({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser });
    return { status: result.replayed ? 200 : 201, body: { transfer: result.transfer } };
  }),
);

financeFundsRouter.post(
  `${BASE}/fund-transfers/:id/reverse`,
  authRequired,
  financeWriteLimiter,
  managerHandler({ context: 'finance_fund_transfer_reverse', fallback: 'Hesaplar arası aktarım iptal edilemedi.', write: true }, async ({ req, access }) => {
    const result = await reverseFundTransfer({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return { status: result.replayed ? 200 : 201, body: { transfer: result.transfer, original: result.original } };
  }),
);
