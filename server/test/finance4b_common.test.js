// Finans Faz 4b ortak yardımcılar (saf, DB'siz): gün sayıları, Türkçe para biçimi, hata kodu tablosu, sorgu ayrıştırıcıları, rapor yardımcıları.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import * as common from '../src/modules/finance_4b_common.js';
import { AGING_BUCKETS, bucketSumSql, m1Ctes, m1Remainders } from '../src/modules/finance_m1.js';
import { percentCell, slugify } from '../src/modules/finance_export_tables.js';
import { rateBp, sortAging, agingTotals, parseAgingQuery, parseRangeQuery, parseStatementQuery, parseBoardSummaryQuery } from '../src/modules/finance_reports.js';

const throwsCode = (fn, code) => assert.throws(fn, (error) => error.code === code, code);
const NOW = new Date('2026-10-16T09:00:00Z');

describe('gün sayıları ve ay yardımcıları (UTC takvim)', () => {
  it('dayNumber / isoOfDay gidiş-dönüş; ay sonu ve ay uzunluğu (şubat, artık yıl)', () => {
    assert.equal(common.dayNumber('1970-01-01'), 0);
    assert.equal(common.dayNumber('1970-01-02'), 1);
    for (const iso of ['2026-10-16', '2028-02-29', '2000-01-01', '2099-12-31']) assert.equal(common.isoOfDay(common.dayNumber(iso)), iso);
    assert.equal(common.lastDayOfMonth('2026-02-01'), '2026-02-28');
    assert.equal(common.lastDayOfMonth('2028-02-01'), '2028-02-29');
    assert.equal(common.lastDayOfMonth('2026-12-01'), '2026-12-31');
    assert.equal(common.daysInMonth('2026-02-01'), 28);
    assert.equal(common.daysInMonth('2028-02-01'), 29);
    assert.equal(common.daysInMonth('2026-04-01'), 30);
    assert.equal(common.daysInMonth('2026-10-01'), 31);
    assert.equal(common.monthTitle('2026-09-01'), 'Eylül 2026');
  });
});

describe('formatMinor (Türkçe, BigInt, kayan nokta yok)', () => {
  it('binlik nokta, virgüllü iki ondalık, eksi işaret, sıfır, çok büyük tutar', () => {
    assert.equal(common.formatMinor(0), '0,00');
    assert.equal(common.formatMinor(5), '0,05');
    assert.equal(common.formatMinor(125000n), '1.250,00');
    assert.equal(common.formatMinor(-33000), '-330,00');
    assert.equal(common.formatMinor(100000000099n), '1.000.000.000,99');
    assert.equal(common.formatMinor(9007199254740993n), '90.071.992.547.409,93');
  });
});

describe('hata kodu tablosu (sözleşme "Hata kodları")', () => {
  it('yeni kodların HTTP durumları ve kodları sözleşmedeki gibi', () => {
    const table = [
      [common.receiptNotFound(), 404, 'RECEIPT_NOT_FOUND'], [common.paymentReversed(), 409, 'PAYMENT_REVERSED'], [common.receiptAlreadyCancelled(), 409, 'RECEIPT_ALREADY_CANCELLED'], [common.receiptNotCancellable(), 409, 'RECEIPT_NOT_CANCELLABLE'],
      [common.lateFeeDisabled(), 409, 'LATE_FEE_DISABLED'], [common.lateFeeNotConfigured(), 409, 'LATE_FEE_NOT_CONFIGURED'], [common.lateFeePeriodNotClosed(), 409, 'LATE_FEE_PERIOD_NOT_CLOSED'], [common.lateFeePeriodNotEnded(), 409, 'LATE_FEE_PERIOD_NOT_ENDED'],
      [common.lateFeePeriodNotNext('2026-08'), 409, 'LATE_FEE_PERIOD_NOT_NEXT'], [common.lateFeeAlreadyPosted(), 409, 'LATE_FEE_ALREADY_POSTED'], [common.lateFeeRunNotFound(), 404, 'LATE_FEE_RUN_NOT_FOUND'], [common.lateFeeRunNotVoidable(), 409, 'LATE_FEE_RUN_NOT_VOIDABLE'],
      [common.periodHasLateFeeRun(), 409, 'PERIOD_HAS_LATE_FEE_RUN'], [common.legalApprovalRequired(), 409, 'LEGAL_APPROVAL_REQUIRED'], [common.noAccount(), 409, 'NO_ACCOUNT'], [common.accountNotFound(), 404, 'ACCOUNT_NOT_FOUND'],
      [common.accountInactive(), 409, 'ACCOUNT_INACTIVE'], [common.accountRequired(), 409, 'ACCOUNT_REQUIRED'], [common.accountLimitReached(), 409, 'ACCOUNT_LIMIT'], [common.accountNameTaken(), 409, 'ACCOUNT_NAME_TAKEN'],
      [common.beforeOpeningDate(), 409, 'BEFORE_OPENING_DATE'], [common.transferNotFound(), 404, 'TRANSFER_NOT_FOUND'], [common.transferAlreadyVoided(), 409, 'TRANSFER_ALREADY_VOIDED'], [common.reconciliationStale(), 409, 'RECONCILIATION_STALE'], [common.reconciliationOrder(), 409, 'RECONCILIATION_ORDER'],
      [common.periodHasUnassignedPayments(), 409, 'PERIOD_HAS_UNASSIGNED_PAYMENTS'], [common.expenseNotFound(), 404, 'EXPENSE_NOT_FOUND'], [common.expenseAlreadyVoided(), 409, 'EXPENSE_ALREADY_VOIDED'], [common.duplicateExpense(1), 409, 'DUPLICATE_EXPENSE'],
      [common.duplicateDocumentNo(1), 409, 'DUPLICATE_DOCUMENT_NO'], [common.categoryNotFound(), 404, 'CATEGORY_NOT_FOUND'], [common.categoryInactive(), 409, 'CATEGORY_INACTIVE'], [common.supplierNotFound(), 404, 'SUPPLIER_NOT_FOUND'],
      [common.documentsNotAvailable(), 409, 'DOCUMENTS_NOT_AVAILABLE'], [common.expenseDocumentLimit(), 409, 'EXPENSE_DOCUMENT_LIMIT'], [common.statementTooLarge(), 409, 'STATEMENT_TOO_LARGE'], [common.reportBusy(), 503, 'REPORT_BUSY'],
      [common.exportTooLarge(), 422, 'EXPORT_TOO_LARGE'], [common.remindersDisabled(), 409, 'REMINDERS_DISABLED'], [common.reminderDailyLimit(), 409, 'REMINDER_DAILY_LIMIT'], [common.noReminderRecipients(), 409, 'NO_REMINDER_RECIPIENTS'],
      [common.emailNotConfigured(), 409, 'EMAIL_NOT_CONFIGURED'], [common.reminderRunNotFound(), 404, 'REMINDER_RUN_NOT_FOUND'], [common.reminderRunNotCancellable(), 409, 'REMINDER_RUN_NOT_CANCELLABLE'], [common.settingsStale(), 409, 'SETTINGS_STALE'],
    ];
    for (const [error, status, code] of table) {
      assert.equal(error.statusCode, status, code);
      assert.equal(error.code, code);
      assert.ok(error.expose === true && typeof error.message === 'string' && error.message.length > 5);
      assert.equal(/[A-Z]{3,}_[A-Z]+/.test(error.message), false, `${code}: mesajda makine kodu / teknik ifade yok`);
    }
    assert.equal(common.lateFeePeriodNotNext('2026-08').extra.expected_period, '2026-08');
    assert.equal(common.duplicateExpense(7).extra.existing_expense_id, 7);
    assert.equal(common.reportBusy().retryAfterSeconds, 5);
  });

  it('sabitler: KMK sabiti 500 bp (aylık %5); hesap 20, kategori 100, tedarikçi 2000, dışa aktarma 20000, ekstre 5000, muaf 5000', () => {
    assert.equal(common.LATE_FEE_MAX_MONTHLY_BP, 500);
    assert.deepEqual([common.ACCOUNT_LIMIT, common.CATEGORY_LIMIT, common.SUPPLIER_LIMIT, common.EXPORT_ROW_LIMIT, common.STATEMENT_ROW_LIMIT, common.LATE_FEE_EXCLUDED_LIMIT, common.EXPENSE_DOCUMENT_LIMIT_PER_EXPENSE], [20, 100, 2000, 20000, 5000, 5000, 5]);
  });
});

describe('sorgu / gövde ayrıştırıcıları', () => {
  it('queryDate / queryMonth / queryInt / queryEnum / queryBool / queryId: boş = varsayılan; geçersiz = 400 INVALID_QUERY', () => {
    assert.equal(common.queryDate(undefined), null);
    assert.equal(common.queryDate('2026-10-16'), '2026-10-16');
    for (const bad of ['2026-02-30', '2026-13-01', 'abc', '2026-1-1', '1999-01-01', '2101-01-01']) throwsCode(() => common.queryDate(bad), 'INVALID_QUERY');
    assert.equal(common.queryMonth('2026-09'), '2026-09-01');
    assert.equal(common.queryMonth('2026-09-01'), '2026-09-01');
    for (const bad of ['2026-00', '2026-13', '26-01', '2026-09-15']) throwsCode(() => common.queryMonth(bad), 'INVALID_QUERY');
    assert.equal(common.queryInt('15', { min: 1, max: 100, fallback: 5 }), 15);
    assert.equal(common.queryInt('5000', { min: 1, max: 100, fallback: 5 }), 100);
    assert.equal(common.queryInt(undefined, { min: 1, max: 100, fallback: 5 }), 5);
    for (const bad of ['0', '-1', 'x', '1.5']) throwsCode(() => common.queryInt(bad, { min: 1, max: 100, fallback: 5 }), 'INVALID_QUERY');
    assert.equal(common.queryEnum('voided', ['active', 'voided'], 'all'), 'voided');
    assert.equal(common.queryEnum(undefined, ['active'], 'all'), 'all');
    throwsCode(() => common.queryEnum('x', ['active'], 'all'), 'INVALID_QUERY');
    assert.equal(common.queryBool('true'), true);
    assert.equal(common.queryBool(undefined, false), false);
    throwsCode(() => common.queryBool('evet'), 'INVALID_QUERY');
    assert.equal(common.queryId('12'), 12);
    assert.equal(common.queryId(''), null);
    throwsCode(() => common.queryId('0'), 'INVALID_QUERY');
    assert.equal(common.requireId(5, 'Hesap'), 5);
    for (const bad of [0, -1, 'x', null, undefined, 1.5]) throwsCode(() => common.requireId(bad, 'Hesap'), 'INVALID_BODY');
    assert.equal(common.optionalId(undefined, 'Hesap'), null);
  });

  it('parmak izi: kararlı (anahtar sırasından bağımsız), içerik değişince değişir', () => {
    assert.equal(common.fingerprintOf({ b: 1, a: [2, 3] }), common.fingerprintOf({ a: [2, 3], b: 1 }));
    assert.notEqual(common.fingerprintOf({ a: 1 }), common.fingerprintOf({ a: 2 }));
    assert.match(common.fingerprintOf({}), /^[0-9a-f]{64}$/);
  });
});

describe('M1 (saf) ve SQL parçaları', () => {
  it('m1Remainders: en eski vadeden mahsup; artık ödeme alacak; tam / kısmi / hiç ödenmemiş', () => {
    const items = [{ amount: 100n }, { amount: 50n }, { amount: 70n }];
    assert.deepEqual(m1Remainders(items, 0n), { rem: [100n, 50n, 70n], credit: 0n });
    assert.deepEqual(m1Remainders(items, 120n), { rem: [0n, 30n, 70n], credit: 0n });
    assert.deepEqual(m1Remainders(items, 220n), { rem: [0n, 0n, 0n], credit: 0n });
    assert.deepEqual(m1Remainders(items, 300n), { rem: [0n, 0n, 0n], credit: 80n });
    assert.deepEqual(m1Remainders([], 5n), { rem: [], credit: 5n });
  });

  it('SQL: yalnız site satırları (site_code), tarihli model (entry_date <= T) ve ters kayıt koşulu; 7 kova + tazminat kalanı', () => {
    const sql = m1Ctes('$1', '$2');
    assert.match(sql, /l\.site_code = \$1 AND l\.kind = 'charge' AND l\.entry_date <= \$2::DATE/);
    assert.match(sql, /rv\.reverses_entry_id = l\.id AND rv\.entry_date <= \$2::DATE/);
    assert.match(sql, /ORDER BY COALESCE\(l\.due_date, l\.entry_date\), l\.id/);
    assert.match(sql, /LEAST\(i\.a, GREATEST\(0, i\.c - COALESCE\(p\.p, 0\)\)\)/);
    for (const bucket of AGING_BUCKETS) assert.match(bucketSumSql('$2'), new RegExp(`AS ${bucket}\\b`));
    assert.match(bucketSumSql('$2'), /late_fee_outstanding/);
    assert.match(m1Ctes('$1', '$2', ' AND l.apartment_id = ANY($3::BIGINT[])'), /l\.apartment_id = ANY\(\$3::BIGINT\[\]\)/);
  });
});

describe('rapor yardımcıları', () => {
  it('rateBp: yarım yukarı; payda 0 -> null; yüzde hücresi metin işlemiyle', () => {
    assert.equal(rateBp(1n, 3n), 3333);
    assert.equal(rateBp(2n, 3n), 6667);
    assert.equal(rateBp(1n, 2n), 5000);
    assert.equal(rateBp(0n, 5n), 0);
    assert.equal(rateBp(5n, 0n), null);
    assert.equal(rateBp(3n, 2n), 15000);
    assert.equal(percentCell(8345), 83.45);
    assert.equal(percentCell(5), 0.05);
    assert.equal(percentCell(0), 0);
    assert.equal(percentCell(null), null);
    assert.equal(percentCell(15000), 150);
  });

  it('slugify: ASCII, boşluk -> tire, Türkçe harfler; boş ad "site"', () => {
    assert.equal(slugify('Gül Sitesi'), 'gul-sitesi');
    assert.equal(slugify('İstanbul Çınar Ş.Ö.Ü'), 'istanbul-cinar-s-o-u');
    assert.equal(slugify('   '), 'site');
    assert.equal(slugify(null), 'site');
    assert.ok(slugify('x'.repeat(100)).length <= 40);
  });

  it('sortAging / agingTotals: toplam gecikmişe göre azalan; borçlu süzgeci; toplamlar BigInt', () => {
    const mk = (id, overdue, credit = 0n) => ({ apartmentId: id, blockSort: 1, aptSort: id, label: `D${id}`, buckets: { not_due: 0n, d0_30: overdue, d31_60: 0n, d61_90: 0n, d91_180: 0n, d181_365: 0n, d366_plus: 0n }, overdue, credit, lateFeeOutstanding: 0n });
    const rows = [mk(1, 0n, 50n), mk(2, 300n), mk(3, 700n), mk(4, 300n)];
    assert.deepEqual(sortAging(rows, 'debtor').map((r) => r.apartmentId), [3, 2, 4]);
    assert.deepEqual(sortAging(rows, 'all').map((r) => r.apartmentId), [3, 2, 4, 1]);
    const totals = agingTotals(rows);
    assert.equal(totals.total_overdue_minor, 1300);
    assert.equal(totals.credit_minor, 50);
    assert.equal(totals.debtor_count, 3);
    assert.equal(totals.d0_30_minor, 1300);
  });

  it('rapor sorguları: as_of geçmiş olabilir ama gelecek / 5 yıldan eski 400; aralık <= 36 ay, ters aralık 400; ekstre varsayılan yıl başı..bugün', () => {
    assert.equal(parseAgingQuery({}, NOW).asOf, '2026-10-16');
    assert.equal(parseAgingQuery({ as_of: '2026-01-31', status: 'all' }, NOW).status, 'all');
    throwsCode(() => parseAgingQuery({ as_of: '2026-10-17' }, NOW), 'INVALID_BODY');
    throwsCode(() => parseAgingQuery({ as_of: '2019-01-01' }, NOW), 'INVALID_BODY');
    throwsCode(() => parseAgingQuery({ status: 'x' }, NOW), 'INVALID_QUERY');
    const range = parseRangeQuery({ from: '2026-01', to: '2026-10' }, NOW);
    assert.equal(range.months.length, 10);
    assert.equal(range.months[0], '2026-01-01');
    assert.equal(parseRangeQuery({}, NOW).months.length, 12, 'varsayılan: son 12 ay');
    assert.equal(parseRangeQuery({ from: '2023-11', to: '2026-10' }, NOW).months.length, 36);
    throwsCode(() => parseRangeQuery({ from: '2023-10', to: '2026-10' }, NOW), 'INVALID_BODY');
    throwsCode(() => parseRangeQuery({ from: '2026-10', to: '2026-01' }, NOW), 'INVALID_BODY');
    assert.deepEqual(parseStatementQuery({}, NOW), { from: '2026-01-01', to: '2026-10-16' });
    assert.deepEqual(parseStatementQuery({ from: '2025-03-01', to: '2025-04-01' }, NOW), { from: '2025-03-01', to: '2025-04-01' });
    throwsCode(() => parseStatementQuery({ from: '2026-05-01', to: '2026-04-01' }, NOW), 'INVALID_QUERY');
    assert.equal(parseBoardSummaryQuery({ include_debtor_list: 'true' }, NOW).includeDebtorList, true);
    assert.equal(parseBoardSummaryQuery({}, NOW).includeDebtorList, false);
    throwsCode(() => parseBoardSummaryQuery({ include_debtor_list: 'evet' }, NOW), 'INVALID_BODY');
  });
});
