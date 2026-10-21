// Finans > Grafikler (yönetici ve kurul): son N ay için tek, salt okunur özet seri.
// GET /manager/sites/:siteCode/finance/reports/charts?months=12 (varsayılan 12, 1..24).
//
// Tek `REPEATABLE READ READ ONLY` işlemi (withReportSnapshot): aylık gelir-gider ve aidat tahsilatı (computeIncomeExpense, "Aylık özet" raporuyla AYNI
// sorgu), ay sonu kasa + banka toplam bakiyesi (computeCashPosition ile aynı hesap kuralı), gider kategorileri toplamı ve bugünkü yaşlandırma
// (computeAging, "Gecikmiş borçlar" raporuyla aynı M1). Kiracı ve ev sahibi hesapları TOPLANIR. Para tamsayı kuruş; kişi adı içermez.
// Hesabı olmayan ayda `cash_balance_minor` null'dır (0 değil: "hesap yok" ile "bakiye sıfır" ayrımı).
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Grafikler".

import { lastDayOfMonth, queryInt } from './finance_4b_common.js';
import { addMonths, currentPeriod, periodLabel, today } from './finance_common.js';
import { minorToNumber, toBigInt } from './finance_money.js';
import { computeAging, computeIncomeExpense, rateBp, reportHeader, withReportSnapshot } from './finance_reports.js';

export const CHART_MONTHS_DEFAULT = 12;
export const CHART_MONTHS_MAX = 24;

const asBig = (value) => toBigInt(value ?? '0');

/** months sorgusu: boşsa 12; sayı değilse 400 INVALID_QUERY; 24'ten büyükse 24'e sabitlenir. 'YYYY-MM-01' ay listesi (eskiden yeniye). */
export function parseChartsQuery(query = {}, now = new Date()) {
  const count = queryInt(query?.months, { min: 1, max: CHART_MONTHS_MAX, fallback: CHART_MONTHS_DEFAULT });
  const to = currentPeriod(now);
  const months = [];
  for (let index = count - 1; index >= 0; index -= 1) {
    months.push(addMonths(to, -index));
  }
  return { months, count };
}

/** Her ayın sonundaki (içinde bulunulan ayda bugünkü) tarih. Gelecek tarih sorgulanmaz. */
export function chartAsOfDates(months, todayDate) {
  return months.map((period) => {
    const end = lastDayOfMonth(period);
    return end > todayDate ? todayDate : end;
  });
}

/**
 * Ay sonu kasa + banka toplam bakiyesi. Kural computeCashPosition ile aynıdır: açılış tarihi <= T olan hesapların, hareket tarihi <= T olan hareketlerinin toplamı.
 * Dönen: ay başına { balance (BigInt|null), accountCount }; o tarihte hiç hesap yoksa balance null.
 */
export async function computeCashBalances(db, siteCode, dates) {
  const result = await db.query(
    `
      SELECT to_char(g.d, 'YYYY-MM-DD') AS as_of,
        (SELECT COUNT(*)::INTEGER FROM finance_accounts a WHERE a.site_code = $1 AND a.opening_date <= g.d) AS account_count,
        (SELECT COALESCE(SUM(m.amount_minor), 0)::TEXT
           FROM finance_accounts a INNER JOIN account_movements m ON m.account_id = a.id
          WHERE a.site_code = $1 AND a.opening_date <= g.d AND m.movement_date <= g.d) AS balance
      FROM unnest($2::DATE[]) AS g(d)
      ORDER BY g.d
    `,
    [siteCode, dates],
  );
  const byDate = new Map((result.rows ?? []).map((row) => [row.as_of, row]));
  return dates.map((date) => {
    const row = byDate.get(date);
    const accountCount = Number(row?.account_count ?? 0);
    return { accountCount, balance: accountCount === 0 ? null : asBig(row?.balance) };
  });
}

/** Geciken borç yaşlandırması (bugün itibarıyla, iki hesap toplamı): 0-30, 31-60, 61-90, 90+ gün. Vadesi gelmemiş borç dahil değildir. */
export function summarizeAging(rows) {
  const sum = { d0_30: 0n, d31_60: 0n, d61_90: 0n, d91_plus: 0n };
  let debtors = 0;
  for (const row of rows) {
    sum.d0_30 += row.buckets.d0_30;
    sum.d31_60 += row.buckets.d31_60;
    sum.d61_90 += row.buckets.d61_90;
    sum.d91_plus += row.buckets.d91_180 + row.buckets.d181_365 + row.buckets.d366_plus;
    if (row.overdue > 0n) {
      debtors += 1;
    }
  }
  return { sum, debtors, total: sum.d0_30 + sum.d31_60 + sum.d61_90 + sum.d91_plus };
}

/** Son N ayın gider kategorileri toplamı (yalnız pozitif net toplam; iptalle sıfırlanan / negatif kategori pastayı bozmasın), büyükten küçüğe. */
export function categoryTotals(rows) {
  const byCategory = new Map();
  for (const row of rows) {
    for (const cat of row.categories) {
      byCategory.set(cat.category_name, (byCategory.get(cat.category_name) ?? 0n) + cat.total);
    }
  }
  return [...byCategory.entries()]
    .filter(([, total]) => total > 0n)
    .sort((a, b) => (a[1] === b[1] ? a[0].localeCompare(b[0], 'tr') : a[1] > b[1] ? -1 : 1))
    .map(([category_name, total]) => ({ category_name, total_minor: minorToNumber(total) }));
}

/** GET reports/charts gövdesi. */
export async function financeChartsReport(siteCode, query = {}, now = new Date()) {
  const { months } = parseChartsQuery(query, now);
  const todayDate = today(now);
  const dates = chartAsOfDates(months, todayDate);
  return withReportSnapshot(siteCode, async (client) => {
    const header = await reportHeader(client, siteCode, now);
    const rows = await computeIncomeExpense(client, siteCode, months);
    const cash = await computeCashBalances(client, siteCode, dates);
    const agingRows = await computeAging(client, siteCode, todayDate);
    const aging = summarizeAging(agingRows);
    let charged = 0n;
    let lateFee = 0n;
    let collected = 0n;
    let expense = 0n;
    const monthRows = rows.map((row, index) => {
      charged += row.charged;
      lateFee += row.lateFee;
      collected += row.collected;
      expense += row.expense;
      return {
        period: periodLabel(row.period),
        charged_minor: minorToNumber(row.charged),
        late_fee_minor: minorToNumber(row.lateFee),
        collected_minor: minorToNumber(row.collected),
        expense_minor: minorToNumber(row.expense),
        collection_rate_bp: rateBp(row.collected, row.charged + row.lateFee),
        cash_balance_minor: cash[index].balance === null ? null : minorToNumber(cash[index].balance),
        cash_account_count: cash[index].accountCount,
      };
    });
    return {
      ...header,
      from: periodLabel(months[0]),
      to: periodLabel(months[months.length - 1]),
      months: monthRows,
      totals: {
        charged_minor: minorToNumber(charged),
        late_fee_minor: minorToNumber(lateFee),
        collected_minor: minorToNumber(collected),
        expense_minor: minorToNumber(expense),
        collection_rate_bp: rateBp(collected, charged + lateFee),
      },
      expense_by_category: categoryTotals(rows),
      aging: {
        as_of: todayDate,
        d0_30_minor: minorToNumber(aging.sum.d0_30),
        d31_60_minor: minorToNumber(aging.sum.d31_60),
        d61_90_minor: minorToNumber(aging.sum.d61_90),
        d91_plus_minor: minorToNumber(aging.sum.d91_plus),
        total_overdue_minor: minorToNumber(aging.total),
        debtor_count: aging.debtors,
      },
    };
  });
}
