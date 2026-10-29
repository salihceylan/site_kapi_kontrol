// Dönemsel finans rapor paketi (aylık / 3 aylık / yıllık): iki Hesap (İşletme Projesi (Aidat) / Yatırım ve Demirbaş (Fon)) için dönem başı bakiye, tahsilat, gider kalemleri,
// aktarım / düzeltme ve dönem sonu bakiye + dönem sonu borçlu özeti.
//
// Sözleşme: docs/PLATFORM_FINANS_KASALAR.md "Dönemsel rapor". Rakamlar kasa özetiyle (finance_funds_service.summarizeBook) AYNI saf işlevden gelir; yeni bir hesap kuralı YOKTUR:
//   dönem sonu = dönem başı + tahsilat - gider + aktarım giriş - aktarım çıkış + düzeltme  (her Hesap için; aylık kırılımların toplamı dönem toplamına eşittir).
// Tek `REPEATABLE READ, READ ONLY` işlemde hesaplanır (bölümler birbirini tutar); bir bölüm başarısızsa BÜTÜN yanıt hatadır. PARA BigInt. Kişi verisi İÇERMEZ: borçlu özeti yalnız adet ve
// tutardır (ad, daire etiketi yok). Rapor noter onaylı karar defterinin yerine geçmez (REPORT_FOOTER).

import { lastDayOfMonth, monthTitle, queryMonth } from './finance_4b_common.js';
import { countUnassignedPayments, loadAccountPolicy } from './finance_accounts.js';
import { currentPeriod, periodLabel, today } from './finance_common.js';
import { FUNDS, FUND_LABELS, FUND_SHORT_LABELS } from './finance_funds.js';
import { loadFundBook, summarizeBook } from './finance_funds_service.js';
import { AGING_BUCKETS } from './finance_m1.js';
import { minorToNumber } from './finance_money.js';
import { computeAging, parseRangeQuery, reportHeader, withReportSnapshot } from './finance_reports.js';

/** Diğer kategorisi: kategori adı olmayan gider olayı (eski kayıt) bu adla toplanır. */
const UNCATEGORIZED = 'Diğer';

/**
 * Sorgu: `from` / `to` ('YYYY-MM'; isteğe bağlı). `to` yoksa içinde bulunulan ay; `from` yoksa `to`'nun yılının ocağı. Gelecek `to` bugünün ayına çekilir (gelecekte tahsilat / gider yoktur).
 * Kapsam en çok 36 ay ve en çok 5 yıl öncesi (parseRangeQuery). @returns {{ from: string, to: string, months: string[], startDate: string, endDate: string }}
 */
export function parsePeriodQuery(query = {}, now = new Date()) {
  const current = currentPeriod(now);
  let to = queryMonth(query.to) ?? current;
  if (to > current) {
    to = current;
  }
  const from = queryMonth(query.from) ?? `${to.slice(0, 4)}-01-01`;
  const range = parseRangeQuery({ from, to }, now);
  const lastDay = lastDayOfMonth(range.to);
  const todayIso = today(now);
  return { from: range.from, to: range.to, months: range.months, startDate: range.from, endDate: lastDay < todayIso ? lastDay : todayIso };
}

const emptyMonth = () => ({ collections: 0n, expenses: 0n });

/**
 * Kasa defterinden (loadFundBook çıktısı) dönem özeti (SAF; DB yok). Her Hesap için: dönem başı, tahsilat, gider, aktarım, düzeltme, dönem sonu, gider kalemleri (kategori) ve aylık kırılım.
 * Aylık / kalem toplamları, özetle AYNI olay süzgecinden (tarih aralığı + tür) geçer; bu yüzden toplamları dönem toplamına eşittir.
 */
export function summarizePeriod(book, { startDate, endDate, months }) {
  const summary = summarizeBook(book, { from: startDate, to: endDate });
  const funds = {};
  for (const fund of FUNDS) {
    const entry = summary.funds[fund];
    const closing = summary.balanceOf(entry);
    funds[fund] = {
      opening: entry.opening,
      collections: entry.collections,
      expenses: entry.expenses,
      transfersIn: entry.transfersIn,
      transfersOut: entry.transfersOut,
      adjustments: entry.adjustments,
      closing,
      categories: new Map(),
      months: new Map(months.map((month) => [periodLabel(month), emptyMonth()])),
    };
  }
  for (const event of book.events) {
    if (event.date < startDate || event.date > endDate || (event.type !== 'collection' && event.type !== 'expense')) {
      continue;
    }
    const target = funds[event.fund];
    const row = target?.months.get(event.date.slice(0, 7));
    if (!row) {
      continue;
    }
    if (event.type === 'collection') {
      row.collections += event.amount;
    } else {
      const total = -event.amount;
      row.expenses += total;
      const name = event.category && String(event.category).trim() !== '' ? event.category : UNCATEGORIZED;
      target.categories.set(name, (target.categories.get(name) ?? 0n) + total);
    }
  }
  return { funds, advance: summary.advance, accountsTotal: summary.accountsTotal };
}

const sortedCategories = (map) =>
  [...map.entries()]
    .filter(([, total]) => total !== 0n)
    .sort((a, b) => (a[1] === b[1] ? a[0].localeCompare(b[0], 'tr') : a[1] > b[1] ? -1 : 1))
    .map(([category_name, total]) => ({ category_name, total_minor: minorToNumber(total) }));

function fundBody(fund, entry) {
  return {
    fund,
    fund_label: FUND_LABELS[fund],
    fund_short_label: FUND_SHORT_LABELS[fund],
    opening_minor: minorToNumber(entry.opening),
    collections_minor: minorToNumber(entry.collections),
    expenses_minor: minorToNumber(entry.expenses),
    transfers_in_minor: minorToNumber(entry.transfersIn),
    transfers_out_minor: minorToNumber(entry.transfersOut),
    adjustments_minor: minorToNumber(entry.adjustments),
    closing_minor: minorToNumber(entry.closing),
    change_minor: minorToNumber(entry.closing - entry.opening),
    negative_balance: entry.closing < 0n,
    expense_by_category: sortedCategories(entry.categories),
  };
}

/** Dönem sonu borçlu özeti (kişi verisiz): adet + vadesi geçmiş toplam + yaşlandırma kovaları. */
export function debtorSummary(aging, asOf) {
  const debtors = aging.filter((row) => row.overdue > 0n);
  let total = 0n;
  for (const row of debtors) {
    total += row.overdue;
  }
  return {
    as_of: asOf,
    apartment_count: aging.length,
    debtor_count: debtors.length,
    total_overdue_minor: minorToNumber(total),
    aging: AGING_BUCKETS.map((bucket) => ({
      bucket,
      count: aging.filter((row) => row.buckets[bucket] > 0n).length,
      total_minor: minorToNumber(aging.reduce((acc, row) => acc + row.buckets[bucket], 0n)),
    })),
  };
}

/** Rapor gövdesi (ekran, dışa aktarma ve testler ortak). `db` bir rapor işlemi bağlantısıdır (withReportSnapshot). */
export async function computePeriodReport(db, siteCode, filters, now = new Date()) {
  const header = await reportHeader(db, siteCode, now);
  const book = await loadFundBook(db, siteCode);
  const period = summarizePeriod(book, filters);
  const policy = await loadAccountPolicy(db, siteCode);
  const unassigned = await countUnassignedPayments(db, siteCode, policy.earliestOpening, filters.to);
  const aging = await computeAging(db, siteCode, filters.endDate);

  const totals = { opening: 0n, collections: 0n, expenses: 0n, transfersIn: 0n, transfersOut: 0n, adjustments: 0n, closing: 0n };
  for (const fund of FUNDS) {
    for (const key of Object.keys(totals)) {
      totals[key] += period.funds[fund][key];
    }
  }
  const monthsBody = filters.months.map((month) => {
    const label = periodLabel(month);
    const row = { period: label };
    let collections = 0n;
    let expenses = 0n;
    for (const fund of FUNDS) {
      const part = period.funds[fund].months.get(label) ?? emptyMonth();
      row[fund] = { collections_minor: minorToNumber(part.collections), expenses_minor: minorToNumber(part.expenses), net_minor: minorToNumber(part.collections - part.expenses) };
      collections += part.collections;
      expenses += part.expenses;
    }
    return { ...row, collections_minor: minorToNumber(collections), expenses_minor: minorToNumber(expenses), net_minor: minorToNumber(collections - expenses) };
  });

  const difference = period.accountsTotal - (totals.closing + period.advance);
  const warnings = [];
  for (const fund of FUNDS) {
    if (period.funds[fund].closing < 0n) {
      warnings.push({ code: 'NEGATIVE_BALANCE', fund });
    }
  }
  if (unassigned.count > 0) {
    warnings.push({ code: 'UNASSIGNED_PAYMENTS', count: unassigned.count, total_minor: unassigned.total_minor });
  }
  if (policy.total === 0) {
    warnings.push({ code: 'NO_ACCOUNTS' });
  }

  return {
    ...header,
    from: periodLabel(filters.from),
    to: periodLabel(filters.to),
    period_title: filters.from === filters.to ? monthTitle(filters.from) : `${monthTitle(filters.from)} - ${monthTitle(filters.to)}`,
    start_date: filters.startDate,
    end_date: filters.endDate,
    has_accounts: policy.total > 0,
    funds: { operating: fundBody('operating', period.funds.operating), capital: fundBody('capital', period.funds.capital) },
    totals: {
      opening_minor: minorToNumber(totals.opening),
      collections_minor: minorToNumber(totals.collections),
      expenses_minor: minorToNumber(totals.expenses),
      transfers_in_minor: minorToNumber(totals.transfersIn),
      transfers_out_minor: minorToNumber(totals.transfersOut),
      adjustments_minor: minorToNumber(totals.adjustments),
      closing_minor: minorToNumber(totals.closing),
      change_minor: minorToNumber(totals.closing - totals.opening),
    },
    months: monthsBody,
    advance_minor: minorToNumber(period.advance),
    reconciliation: {
      accounts_total_minor: minorToNumber(period.accountsTotal),
      difference_minor: minorToNumber(difference),
      balanced: difference === 0n,
    },
    unassigned_payments: { count: unassigned.count, total_minor: unassigned.total_minor },
    debtors: debtorSummary(aging, filters.endDate),
    warnings,
  };
}

// --- Dışa aktarma (CSV / XLSX ham zarf satırları; dosyayı İSTEMCİ üretir) ------------------------------------------------------------------------

const BUCKET_LABEL = Object.freeze({
  not_due: 'Vadesi gelmemiş',
  d0_30: '0-30 gün',
  d31_60: '31-60 gün',
  d61_90: '61-90 gün',
  d91_180: '91-180 gün',
  d181_365: '181-365 gün',
  d366_plus: '366 gün ve üzeri',
});

export const PERIOD_EXPORT_COLUMNS = Object.freeze([
  { key: 'bolum', label: 'Bölüm', type: 'text' },
  { key: 'hesap', label: 'Hesap', type: 'text' },
  { key: 'kalem', label: 'Kalem', type: 'text' },
  { key: 'donem', label: 'Dönem', type: 'text' },
  { key: 'adet', label: 'Adet', type: 'number', scale: 0 },
  { key: 'tutar', label: 'Tutar', type: 'money' },
]);

/** Rapor gövdesi (computePeriodReport) -> dışa aktarma satırları [bölüm, hesap, kalem, dönem, adet, tutar]. Ekranla AYNI rakamlar (ikinci bir hesap yok). */
export function periodExportRows(report) {
  const rows = [];
  const summaryItems = (part) => [
    ['Dönem başı bakiye', part.opening_minor],
    ['Tahsilat', part.collections_minor],
    ['Gider', part.expenses_minor],
    ['Aktarım (giriş)', part.transfers_in_minor],
    ['Aktarım (çıkış)', part.transfers_out_minor],
    ['Düzeltme', part.adjustments_minor],
    ['Dönem sonu bakiye', part.closing_minor],
  ];
  for (const fund of FUNDS) {
    const part = report.funds[fund];
    for (const [label, amount] of summaryItems(part)) {
      rows.push(['Özet', part.fund_short_label, label, report.period_title, null, amount]);
    }
  }
  for (const [label, amount] of summaryItems(report.totals)) {
    rows.push(['Özet', 'Toplam (iki hesap)', label, report.period_title, null, amount]);
  }
  for (const fund of FUNDS) {
    const part = report.funds[fund];
    for (const category of part.expense_by_category) {
      rows.push(['Gider kalemi', part.fund_short_label, category.category_name, report.period_title, null, category.total_minor]);
    }
  }
  for (const month of report.months) {
    for (const fund of FUNDS) {
      const label = report.funds[fund].fund_short_label;
      rows.push(['Aylık', label, 'Tahsilat', month.period, null, month[fund].collections_minor]);
      rows.push(['Aylık', label, 'Gider', month.period, null, month[fund].expenses_minor]);
    }
  }
  rows.push(['Borçlu özeti', '', 'Vadesi geçmiş borç', report.debtors.as_of, report.debtors.debtor_count, report.debtors.total_overdue_minor]);
  for (const bucket of report.debtors.aging) {
    rows.push(['Borçlu özeti', '', BUCKET_LABEL[bucket.bucket] ?? bucket.bucket, report.debtors.as_of, bucket.count, bucket.total_minor]);
  }
  return rows;
}

/** GET reports/period. */
export async function periodReport(siteCode, query = {}, now = new Date()) {
  const filters = parsePeriodQuery(query, now);
  return withReportSnapshot(siteCode, (client) => computePeriodReport(client, siteCode, filters, now));
}
