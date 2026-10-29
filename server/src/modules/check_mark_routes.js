// Kontrol izi uçları (110, P2-20). server.js `app.use(checkMarkRouter)`. Sözleşme: docs/PLATFORM_FINANS_4B.md "Kontrol izi".
//
//   PUT    /manager/sites/:siteCode/finance/expenses/:id/check          -> "kontrol edildi" işareti koy   { id, checked_at, checked_by_name, replayed }
//   DELETE /manager/sites/:siteCode/finance/expenses/:id/check          -> işareti kaldır                  { id, checked_at: null, checked_by_name: null, replayed }
//   PUT    /manager/sites/:siteCode/finance/payment-notices/:id/check   (aynı, dekont bildirimi için)
//   DELETE /manager/sites/:siteCode/finance/payment-notices/:id/check
//
// Yetki (finance_access.js, write): YALNIZ yönetici / süper; kurul, görevli ve sakin 403 FORBIDDEN_ROLE, başka sitenin yöneticisi 403 FORBIDDEN_SITE;
// `finance` modülü kapalıysa 403 MODULE_DISABLED. Yetki gövdeden ve kayıttan ÖNCE denetlenir. Okuma için ayrı uç yoktur: iz, gider ve dekont
// ayrıntı / liste yanıtlarında `checked_at` + `checked_by_name` alanlarıyla gelir (kurula ad gösterilmez). Muhasebeci rolü AÇILMAZ.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { BASE, financeWriteLimiter, managerHandler } from './finance_routes.js';
import { clearCheckMark, setCheckMark } from './check_mark_service.js';

export const checkMarkRouter = express.Router();

const EXPENSE_PATH = `${BASE}/expenses/:id/check`;
const NOTICE_PATH = `${BASE}/payment-notices/:id/check`;

const handler = (kind, run, context, fallback) =>
  managerHandler({ context, fallback, write: true }, async ({ req, access }) => ({
    body: await run({ siteCode: access.siteCode, kind, rawId: req.params.id, actor: req.authUser }),
  }));

checkMarkRouter.put(EXPENSE_PATH, authRequired, financeWriteLimiter, handler('expense', setCheckMark, 'finance_expense_check_set', 'Kontrol işareti konamadı.'));
checkMarkRouter.delete(EXPENSE_PATH, authRequired, financeWriteLimiter, handler('expense', clearCheckMark, 'finance_expense_check_clear', 'Kontrol işareti kaldırılamadı.'));
checkMarkRouter.put(NOTICE_PATH, authRequired, financeWriteLimiter, handler('payment_notice', setCheckMark, 'payment_notice_check_set', 'Kontrol işareti konamadı.'));
checkMarkRouter.delete(NOTICE_PATH, authRequired, financeWriteLimiter, handler('payment_notice', clearCheckMark, 'payment_notice_check_clear', 'Kontrol işareti kaldırılamadı.'));
