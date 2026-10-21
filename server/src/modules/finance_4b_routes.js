// Finans Faz 4b uçları (ayrı router; server.js `app.use(finance4bRouter)`).
//
//   Ayarlar        GET/PUT  /manager/sites/:siteCode/finance/settings
//   Makbuz         POST entries/:id/receipt | GET receipts, receipts/:id | POST receipts/:id/cancel, /print, receipts/verify
//   Kasa / banka   GET/POST accounts | PATCH accounts/:id | GET accounts/:id/movements | POST accounts/:id/adjustments
//                  GET/POST accounts/:id/reconciliations | POST accounts/assign-payments/preview, /commit
//                  GET/POST transfers | POST transfers/:id/void
//   Sakin          GET /app/my-finance/receipts, /app/my-finance/receipts/:id
//   Sistem         GET/PUT /admin/finance-legal-gate (yalnız süper kullanıcı)
//
// Yetki (finance_access.js): yazma = yönetici/süper; okuma = + kurul (salt okunur); STAFF/sakin 403; başka site 403; `finance` kapalıysa 403 MODULE_DISABLED.
// Önizleme / doğrulama uçları POST olduğundan `write: true` sayılır (kurul 403) — yalnız `receipts/verify` kurula açıktır (okuma). Hata gövdesi { error, code }.
// Sözleşme: docs/PLATFORM_FINANS_4B.md.

import express from 'express';
import { authRequired, requireSuperUser } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { resolveFinanceAccess } from './finance_access.js';
import { redactFinanceForBoard } from './finance_common.js';
import { BASE, bodyOf, canSeeManagerFields, financeReadLimiter, financeResidentLimiter, financeWriteLimiter, managerHandler } from './finance_routes.js';
import {
  commitAssignPayments,
  createAccount,
  createAdjustment,
  createReconciliation,
  createTransfer,
  listAccountMovements,
  listAccounts,
  listReconciliations,
  listTransfers,
  previewAssignPayments,
  updateAccount,
  voidTransfer,
} from './finance_accounts.js';
import {
  correctExpense,
  createCategory,
  createExpense,
  createSupplier,
  getExpense,
  listCategories,
  listExpenses,
  listSuppliers,
  redactSupplierForBoard,
  updateCategory,
  updateSupplier,
  voidExpense,
} from './finance_expenses.js';
import { createExpenseDocument, removeExpenseDocument, streamExpenseDocument, uploadExpenseDocumentContent } from './finance_expense_documents.js';
import {
  cancelReceipt,
  getMyReceipt,
  getReceipt,
  issueReceiptManually,
  listMyReceipts,
  listReceipts,
  printReceipt,
  verifyReceipt,
} from './finance_receipts.js';
import { buildExportEnvelope, exportFormatOf, recordExportAudit } from './finance_export_tables.js';
import { enforcementReport } from './finance_enforcement.js';
import { agingReport, boardSummaryReport, cashPositionReport, incomeExpenseReport, myStatement, statementReport } from './finance_reports.js';
import { kickFinanceReminderQueue } from './finance_reminder_queue.js';
import { addExclusion, cancelReminderRun, getReminderRun, listExclusions, listReminderRuns, previewReminders, removeExclusion, sendReminders } from './finance_reminders.js';
import { getMyLateFeeExplanation, listLateFeeRunLines, listLateFeeRuns, postLateFee, previewLateFee, voidLateFeeRun } from './finance_late_fee.js';
import { getSettings, readLegalOk, setLegalGate, updateSettings } from './finance_settings.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';

export const finance4bRouter = express.Router();

// Makbuz doğrulama: kullanıcı başına 60/saat (kod tahmini yavaşlatılır).
export const receiptVerifyLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 60, key: userKey }],
  message: 'Çok fazla doğrulama isteği. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const read = (context, fallback, run) => [authRequired, financeReadLimiter, managerHandler({ context, fallback }, run)];
const write = (context, fallback, run) => [authRequired, financeWriteLimiter, managerHandler({ context, fallback, write: true }, run)];
const preview = (context, fallback, run) => [authRequired, financeReadLimiter, managerHandler({ context, fallback, write: true }, run)];
const created = (result) => ({ status: result.replayed ? 200 : 201 });

// --- Ayarlar ---------------------------------------------------------------------------------------------------------------------------

finance4bRouter.get(`${BASE}/settings`, ...read('finance_settings_get', 'Ayarlar yüklenemedi.', async ({ access }) => ({ body: await getSettings(access.siteCode) })));
finance4bRouter.put(
  `${BASE}/settings`,
  ...write('finance_settings_put', 'Ayarlar kaydedilemedi.', async ({ req, access }) => ({
    body: await updateSettings({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser }),
  })),
);

// --- Makbuz ----------------------------------------------------------------------------------------------------------------------------

finance4bRouter.post(
  `${BASE}/entries/:id/receipt`,
  ...write('finance_receipt_issue', 'Makbuz düzenlenemedi.', async ({ req, access }) => {
    const result = await issueReceiptManually({ siteCode: access.siteCode, rawEntryId: req.params.id, actor: req.authUser });
    return { status: result.created ? 201 : 200, body: { receipt: result.receipt } };
  }),
);
finance4bRouter.get(`${BASE}/receipts`, ...read('finance_receipts_list', 'Makbuzlar yüklenemedi.', async ({ req, access }) => ({ body: await listReceipts(access.siteCode, req.query) })));
// receipts/verify, receipts/:id'den ÖNCE tanımlanır (POST yolları ayrı olsa da okunabilirlik için).
finance4bRouter.post(
  `${BASE}/receipts/verify`,
  authRequired,
  financeReadLimiter,
  receiptVerifyLimiter,
  managerHandler({ context: 'finance_receipt_verify', fallback: 'Makbuz doğrulanamadı.' }, async ({ req, access }) => ({
    body: await verifyReceipt({ siteCode: access.siteCode, body: bodyOf(req) }),
  })),
);
finance4bRouter.get(`${BASE}/receipts/:id`, ...read('finance_receipt_get', 'Makbuz yüklenemedi.', async ({ req, access }) => ({ body: await getReceipt(access.siteCode, req.params.id) })));
finance4bRouter.post(
  `${BASE}/receipts/:id/cancel`,
  ...write('finance_receipt_cancel', 'Makbuz iptal edilemedi.', async ({ req, access }) => {
    const result = await cancelReceipt({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return { ...created(result), body: { cancellation: result.cancellation, receipt: result.receipt } };
  }),
);
finance4bRouter.post(
  `${BASE}/receipts/:id/print`,
  ...write('finance_receipt_print', 'Basım kaydedilemedi.', async ({ req, access }) => {
    const result = await printReceipt({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return { body: { copy_number: result.copy_number, is_original: result.is_original, receipt: result.receipt } };
  }),
);

// --- Kasa / banka -----------------------------------------------------------------------------------------------------------------------

finance4bRouter.get(`${BASE}/accounts`, ...read('finance_accounts_list', 'Hesaplar yüklenemedi.', async ({ access }) => ({ body: await listAccounts(access.siteCode) })));
finance4bRouter.post(
  `${BASE}/accounts`,
  ...write('finance_account_create', 'Hesap oluşturulamadı.', async ({ req, access }) => {
    const result = await createAccount({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser });
    return { ...created(result), body: { account: result.account } };
  }),
);
// Toplu eşleme: sabit yollar `accounts/:id` desenlerinden ÖNCE.
finance4bRouter.post(
  `${BASE}/accounts/assign-payments/preview`,
  ...preview('finance_assign_preview', 'Önizleme hazırlanamadı.', async ({ req, access }) => ({
    body: await previewAssignPayments({ siteCode: access.siteCode, body: bodyOf(req) }),
  })),
);
finance4bRouter.post(
  `${BASE}/accounts/assign-payments/commit`,
  ...write('finance_assign_commit', 'Tahsilatlar eşlenemedi.', async ({ req, access }) => {
    const result = await commitAssignPayments({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser });
    return { ...created(result), body: { count: result.count, total_minor: result.total_minor, replayed: result.replayed } };
  }),
);
finance4bRouter.patch(
  `${BASE}/accounts/:id`,
  ...write('finance_account_update', 'Hesap güncellenemedi.', async ({ req, access }) => ({
    body: await updateAccount({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser }),
  })),
);
finance4bRouter.get(
  `${BASE}/accounts/:id/movements`,
  ...read('finance_account_movements', 'Hareketler yüklenemedi.', async ({ req, access }) => ({
    body: await listAccountMovements(access.siteCode, req.params.id, req.query),
  })),
);
finance4bRouter.post(
  `${BASE}/accounts/:id/adjustments`,
  ...write('finance_account_adjust', 'Düzeltme kaydedilemedi.', async ({ req, access }) => {
    const result = await createAdjustment({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return { ...created(result), body: { movement: result.movement, balance_minor: result.balance_minor } };
  }),
);
finance4bRouter.get(
  `${BASE}/accounts/:id/reconciliations`,
  ...read('finance_reconciliations_list', 'Mutabakatlar yüklenemedi.', async ({ req, access }) => ({
    body: await listReconciliations(access.siteCode, req.params.id),
  })),
);
finance4bRouter.post(
  `${BASE}/accounts/:id/reconciliations`,
  ...write('finance_reconciliation_create', 'Mutabakat kaydedilemedi.', async ({ req, access }) => {
    const result = await createReconciliation({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return { ...created(result), body: { reconciliation: result.reconciliation } };
  }),
);

finance4bRouter.get(`${BASE}/transfers`, ...read('finance_transfers_list', 'Aktarımlar yüklenemedi.', async ({ req, access }) => ({ body: await listTransfers(access.siteCode, req.query) })));
finance4bRouter.post(
  `${BASE}/transfers`,
  ...write('finance_transfer_create', 'Aktarım kaydedilemedi.', async ({ req, access }) => {
    const result = await createTransfer({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser });
    return { ...created(result), body: { transfer: result.transfer, movements: result.movements } };
  }),
);
finance4bRouter.post(
  `${BASE}/transfers/:id/void`,
  ...write('finance_transfer_void', 'Aktarım iptal edilemedi.', async ({ req, access }) => {
    const result = await voidTransfer({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return { ...created(result), body: { transfer: result.transfer, movements: result.movements } };
  }),
);

// --- Gider ------------------------------------------------------------------------------------------------------------------------------

// Belge içerik yükleme: kullanıcı başına 30/saat + IP başına 300/saat (BELGELER A7 ile aynı).
export const expenseUploadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 30, key: userKey },
    { windowMs: HOUR_MS, max: 300, key: ipKey },
  ],
  message: 'Çok fazla dosya yükleme isteği. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

finance4bRouter.get(
  `${BASE}/expense-categories`,
  ...read('finance_categories_list', 'Kategoriler yüklenemedi.', async ({ req, access }) => ({ body: await listCategories(access.siteCode, req.query) })),
);
finance4bRouter.post(
  `${BASE}/expense-categories`,
  ...write('finance_category_create', 'Kategori eklenemedi.', async ({ req, access }) => ({
    status: 201,
    body: await createCategory({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser }),
  })),
);
finance4bRouter.patch(
  `${BASE}/expense-categories/:id`,
  ...write('finance_category_update', 'Kategori güncellenemedi.', async ({ req, access }) => ({
    body: await updateCategory({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser }),
  })),
);
finance4bRouter.get(
  `${BASE}/suppliers`,
  ...read('finance_suppliers_list', 'Tedarikçiler yüklenemedi.', async ({ req, access }) => {
    const body = await listSuppliers(access.siteCode, req.query);
    return { body: canSeeManagerFields(access) ? body : { ...body, items: body.items.map(redactSupplierForBoard) } };
  }),
);
finance4bRouter.post(
  `${BASE}/suppliers`,
  ...write('finance_supplier_create', 'Tedarikçi eklenemedi.', async ({ req, access }) => ({
    status: 201,
    body: await createSupplier({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser }),
  })),
);
finance4bRouter.patch(
  `${BASE}/suppliers/:id`,
  ...write('finance_supplier_update', 'Tedarikçi güncellenemedi.', async ({ req, access }) => ({
    body: await updateSupplier({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser }),
  })),
);

finance4bRouter.post(
  `${BASE}/expenses`,
  ...write('finance_expense_create', 'Gider kaydedilemedi.', async ({ req, access }) => {
    const result = await createExpense({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser });
    return { ...created(result), body: { expense: result.expense, movement: result.movement, account_balance_minor: result.account_balance_minor } };
  }),
);
finance4bRouter.get(`${BASE}/expenses`, ...read('finance_expenses_list', 'Giderler yüklenemedi.', async ({ req, access }) => ({ body: await listExpenses(access.siteCode, req.query) })));
finance4bRouter.get(`${BASE}/expenses/:id`, ...read('finance_expense_get', 'Gider yüklenemedi.', async ({ req, access }) => ({ body: await getExpense(access.siteCode, req.params.id) })));
finance4bRouter.post(
  `${BASE}/expenses/:id/void`,
  ...write('finance_expense_void', 'Gider iptal edilemedi.', async ({ req, access }) => {
    const result = await voidExpense({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return { ...created(result), body: { expense: result.expense, account_balance_minor: result.account_balance_minor } };
  }),
);
finance4bRouter.post(
  `${BASE}/expenses/:id/correct`,
  ...write('finance_expense_correct', 'Gider düzeltilemedi.', async ({ req, access }) => {
    const result = await correctExpense({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return { ...created(result), body: { voided: result.voided, expense: result.expense } };
  }),
);

// Belge eki (BELGELER boru hattı; katman yoksa 409 DOCUMENTS_NOT_AVAILABLE).
finance4bRouter.post(
  `${BASE}/expenses/:id/documents`,
  ...write('finance_expense_document_create', 'Belge eklenemedi.', async ({ req, access }) => {
    const result = await createExpenseDocument({ siteCode: access.siteCode, rawExpenseId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return { ...created(result), body: { document: result.document, upload: result.upload } };
  }),
);
finance4bRouter.put(`${BASE}/expenses/:id/documents/:docId/content`, authRequired, expenseUploadLimiter, async (req, res) => {
  try {
    const access = await resolveFinanceAccess(req, res, { write: true });
    if (!access) {
      return undefined;
    }
    const result = await uploadExpenseDocumentContent({
      siteCode: access.siteCode,
      rawExpenseId: req.params.id,
      rawDocumentId: req.params.docId,
      req,
      actor: req.authUser,
    });
    return res.status(200).json(result);
  } catch (error) {
    return respondError(res, 'finance_expense_document_upload', error, 'Belge yüklenemedi.');
  }
});
finance4bRouter.get(`${BASE}/expenses/:id/documents/:docId/download`, authRequired, financeReadLimiter, async (req, res) => {
  try {
    const access = await resolveFinanceAccess(req, res, {});
    if (!access) {
      return undefined;
    }
    return await streamExpenseDocument({
      siteCode: access.siteCode,
      rawExpenseId: req.params.id,
      rawDocumentId: req.params.docId,
      res,
      userCode: req.authUser?.user_code ?? req.authUser?.id ?? null,
    });
  } catch (error) {
    if (res.headersSent) {
      res.destroy();
      return undefined;
    }
    return respondError(res, 'finance_expense_document_download', error, 'Belge indirilemedi.');
  }
});
finance4bRouter.delete(
  `${BASE}/expenses/:id/documents/:docId`,
  ...write('finance_expense_document_remove', 'Belge kaldırılamadı.', async ({ req, access }) => ({
    body: await removeExpenseDocument({ siteCode: access.siteCode, rawExpenseId: req.params.id, rawDocumentId: req.params.docId, body: bodyOf(req), actor: req.authUser }),
  })),
);

// --- Gecikme tazminatı -----------------------------------------------------------------------------------------------------------------------

finance4bRouter.post(
  `${BASE}/late-fee/preview`,
  ...preview('finance_late_fee_preview', 'Önizleme hazırlanamadı.', async ({ req, access }) => ({ body: await previewLateFee({ siteCode: access.siteCode, body: bodyOf(req) }) })),
);
finance4bRouter.post(
  `${BASE}/late-fee/post`,
  ...write('finance_late_fee_post', 'Gecikme tazminatı hesaplanamadı.', async ({ req, access }) => {
    const result = await postLateFee({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser });
    return { ...created(result), body: { run: result.run, entries_count: result.entries_count } };
  }),
);
finance4bRouter.get(`${BASE}/late-fee/runs`, ...read('finance_late_fee_runs', 'Çalıştırmalar yüklenemedi.', async ({ req, access }) => ({ body: await listLateFeeRuns(access.siteCode, req.query) })));
finance4bRouter.get(
  `${BASE}/late-fee/runs/:id/lines`,
  ...read('finance_late_fee_lines', 'Satırlar yüklenemedi.', async ({ req, access }) => ({ body: await listLateFeeRunLines(access.siteCode, req.params.id, req.query) })),
);
finance4bRouter.post(
  `${BASE}/late-fee/runs/:id/void`,
  ...write('finance_late_fee_void', 'Çalıştırma iptal edilemedi.', async ({ req, access }) => {
    const result = await voidLateFeeRun({ siteCode: access.siteCode, rawId: req.params.id, body: bodyOf(req), actor: req.authUser });
    return { ...created(result), body: { run: result.run, reversed_count: result.reversed_count, reversed_total_minor: result.reversed_total_minor } };
  }),
);

// --- Borç hatırlatma ---------------------------------------------------------------------------------------------------------------------------

// Hatırlatma gönderimi: kullanıcı başına 5/saat.
export const reminderSendLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 5, key: userKey }],
  message: 'Çok fazla hatırlatma gönderimi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

finance4bRouter.get(`${BASE}/reminders/exclusions`, ...read('finance_reminder_exclusions', 'Muafiyetler yüklenemedi.', async ({ access }) => ({ body: await listExclusions(access.siteCode) })));
finance4bRouter.put(
  `${BASE}/reminders/exclusions/:apartmentId`,
  ...write('finance_reminder_exclusion_add', 'Muafiyet kaydedilemedi.', async ({ req, access }) => ({
    body: await addExclusion({ siteCode: access.siteCode, rawApartmentId: req.params.apartmentId, body: bodyOf(req), actor: req.authUser }),
  })),
);
finance4bRouter.delete(
  `${BASE}/reminders/exclusions/:apartmentId`,
  ...write('finance_reminder_exclusion_remove', 'Muafiyet kaldırılamadı.', async ({ req, access }) => ({
    body: await removeExclusion({ siteCode: access.siteCode, rawApartmentId: req.params.apartmentId, actor: req.authUser }),
  })),
);
finance4bRouter.post(
  `${BASE}/reminders/preview`,
  ...preview('finance_reminder_preview', 'Önizleme hazırlanamadı.', async ({ req, access }) => ({ body: await previewReminders({ siteCode: access.siteCode, body: bodyOf(req) }) })),
);
finance4bRouter.post(
  `${BASE}/reminders/send`,
  authRequired,
  financeWriteLimiter,
  reminderSendLimiter,
  managerHandler({ context: 'finance_reminder_send', fallback: 'Hatırlatma gönderilemedi.', write: true }, async ({ req, access }) => {
    const result = await sendReminders({ siteCode: access.siteCode, body: bodyOf(req), actor: req.authUser });
    if (!result.replayed) {
      void kickFinanceReminderQueue();
    }
    return { ...created(result), body: { run: result.run } };
  }),
);
finance4bRouter.get(`${BASE}/reminders/runs`, ...read('finance_reminder_runs', 'Çalıştırmalar yüklenemedi.', async ({ req, access }) => ({ body: await listReminderRuns(access.siteCode, req.query) })));
finance4bRouter.get(`${BASE}/reminders/runs/:id`, ...read('finance_reminder_run', 'Çalıştırma yüklenemedi.', async ({ req, access }) => ({ body: await getReminderRun(access.siteCode, req.params.id) })));
finance4bRouter.post(
  `${BASE}/reminders/runs/:id/cancel`,
  ...write('finance_reminder_cancel', 'Çalıştırma iptal edilemedi.', async ({ req, access }) => ({
    body: await cancelReminderRun({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser }),
  })),
);

// --- Raporlar ve dışa aktarma ---------------------------------------------------------------------------------------------------------------

// Ağır rapor uçları ayrıca 120/saat; dışa aktarma 30/saat (kullanıcı başına).
export const reportLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 120, key: userKey }],
  message: 'Çok fazla rapor isteği. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});
export const exportLimiter = createRuleLimiter({
  rules: [{ windowMs: HOUR_MS, max: 30, key: userKey }],
  message: 'Çok fazla dışa aktarma isteği. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

/** Rapor ucu: okuma yetkisi (kurul dahil) ya da yalnız yönetici (dışa aktarma); no-store; REPORT_BUSY için Retry-After. */
function reportRoute(path, context, fallback, { limiters = [reportLimiter], managerOnly = false }, run) {
  finance4bRouter.get(path, authRequired, financeReadLimiter, ...limiters, async (req, res) => {
    try {
      const access = await resolveFinanceAccess(req, res, { write: managerOnly });
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

reportRoute(`${BASE}/reports/aging`, 'finance_report_aging', 'Rapor hazırlanamadı.', {}, async ({ req, access }) => agingReport(access.siteCode, req.query));
reportRoute(`${BASE}/reports/enforcement`, 'finance_report_enforcement', 'İcra dökümü hazırlanamadı.', { managerOnly: true }, async ({ req, access }) => enforcementReport(access.siteCode, req.query));
reportRoute(`${BASE}/reports/income-expense`, 'finance_report_income_expense', 'Rapor hazırlanamadı.', {}, async ({ req, access }) => incomeExpenseReport(access.siteCode, req.query));
reportRoute(`${BASE}/reports/cash-position`, 'finance_report_cash', 'Rapor hazırlanamadı.', {}, async ({ req, access }) => cashPositionReport(access.siteCode, req.query));
reportRoute(`${BASE}/reports/board-summary`, 'finance_report_board', 'Rapor hazırlanamadı.', {}, async ({ req, access }) =>
  boardSummaryReport(access.siteCode, req.query, { canListDebtors: canSeeManagerFields(access), actor: req.authUser }),
);
reportRoute(`${BASE}/apartments/:id/statement`, 'finance_report_statement', 'Ekstre hazırlanamadı.', {}, async ({ req, access }) =>
  statementReport(access.siteCode, req.params.id, req.query),
);
reportRoute(`${BASE}/exports/:kind`, 'finance_export', 'Dışa aktarma hazırlanamadı.', { limiters: [exportLimiter], managerOnly: true }, async ({ req, access }) => {
  const envelope = await buildExportEnvelope(access.siteCode, req.params.kind, req.query);
  await recordExportAudit({ siteCode: access.siteCode, kind: req.params.kind, rowCount: envelope.row_count, format: exportFormatOf(req.query), query: req.query, actor: req.authUser });
  return envelope;
});

// --- Sakin ------------------------------------------------------------------------------------------------------------------------------

finance4bRouter.get('/app/my-finance/entries/:entryId/late-fee', authRequired, financeResidentLimiter, async (req, res) => {
  try {
    res.set('Cache-Control', 'no-store');
    return res.status(200).json(await getMyLateFeeExplanation(req.authUser, req.params.entryId));
  } catch (error) {
    return respondError(res, 'my_finance_late_fee', error, 'Açıklama yüklenemedi.');
  }
});
finance4bRouter.get('/app/my-finance/apartments/:id/statement', authRequired, financeResidentLimiter, async (req, res) => {
  try {
    res.set('Cache-Control', 'no-store');
    return res.status(200).json(await myStatement(req.authUser, req.params.id, req.query));
  } catch (error) {
    if (error?.retryAfterSeconds) {
      res.set('Retry-After', String(error.retryAfterSeconds));
    }
    return respondError(res, 'my_finance_statement', error, 'Ekstre yüklenemedi.');
  }
});
finance4bRouter.get('/app/my-finance/receipts', authRequired, financeResidentLimiter, async (req, res) => {
  try {
    res.set('Cache-Control', 'no-store');
    return res.status(200).json(await listMyReceipts(req.authUser, req.query));
  } catch (error) {
    return respondError(res, 'my_finance_receipts', error, 'Makbuzlarınız yüklenemedi.');
  }
});
finance4bRouter.get('/app/my-finance/receipts/:id', authRequired, financeResidentLimiter, async (req, res) => {
  try {
    res.set('Cache-Control', 'no-store');
    return res.status(200).json(await getMyReceipt(req.authUser, req.params.id));
  } catch (error) {
    return respondError(res, 'my_finance_receipt', error, 'Makbuz yüklenemedi.');
  }
});

// --- Sistem: hukuk onayı bayrağı (yalnız süper kullanıcı) ---------------------------------------------------------------------------------

finance4bRouter.get('/admin/finance-legal-gate', authRequired, requireSuperUser, async (_req, res) => {
  try {
    return res.status(200).json({ legal_ok: await readLegalOk() });
  } catch (error) {
    return respondError(res, 'finance_legal_gate_get', error, 'Hukuk onayı bilgisi yüklenemedi.');
  }
});
finance4bRouter.put('/admin/finance-legal-gate', authRequired, requireSuperUser, async (req, res) => {
  try {
    return res.status(200).json(await setLegalGate({ enabled: bodyOf(req).legal_ok, actor: req.authUser }));
  } catch (error) {
    return respondError(res, 'finance_legal_gate_put', error, 'Hukuk onayı kaydedilemedi.');
  }
});
