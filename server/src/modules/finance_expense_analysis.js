// Gider analizi ve gelecek yıl tahmini (R1): GET reports/expense-analysis?to=YYYY-MM&window=1|3|6|12&increase_bp=0..10000.
//
// Net gider = gider - iptal (aylık gelir-gider raporuyla AYNI birleşim: dönem = gider/iptal dönemi). Değişmez kural: her ay için rutin + beklenmedik = gelir-gider
// raporundaki expense_minor. Tür: expense_natures kaydı, yoksa kategori varsayılanı (derived). Gelir = net tahsilat (computeIncomeExpense.collected).
// Tahmin tabanı son 12 TAM ay; n = tabanda ilk gider ayından bu yana geçen ay sayısı (1..12); yıllığa çevirme X*12/n; artış YALNIZ rutine uygulanır; yuvarlama yarım yukarı.
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Gider analizi ve tahmin (R1)".

import { queryMonth } from './finance_4b_common.js';
import { addMonths, currentPeriod, invalidQuery, periodLabel } from './finance_common.js';
import { derivedNatureSql } from './finance_expense_nature.js';
import { computeIncomeExpense, rateBp, reportHeader, withReportSnapshot } from './finance_reports.js';
import { minorToNumber } from './finance_money.js';
import { getRule } from './platform_rules.js';

export const ANALYSIS_WINDOWS = Object.freeze([1, 3, 6, 12]);
export const FORECAST_RULE_KEY = 'forecast.default_increase_bp';

/** BigInt bölme, yarım yukarı (paydası pozitif): floor((2a + b) / 2b). */
export function divRound(numerator, denominator) {
  const num = 2n * numerator + denominator;
  const den = 2n * denominator;
  let q = num / den;
  if (num % den !== 0n && num < 0n) q -= 1n;
  return q;
}

/** Değişim (baz puan, işaretli): önceki <= 0 ise null. */
export function changeBp(current, previous) {
  if (previous <= 0n) return null;
  return Number(divRound((current - previous) * 10000n, previous));
}

export function parseAnalysisQuery(query = {}, now = new Date()) {
  const current = currentPeriod(now);
  const to = queryMonth(query.to) ?? current;
  if (to > current) throw invalidQuery();
  const rawWindow = query.window === undefined || query.window === '' ? 3 : Number(query.window);
  if (!ANALYSIS_WINDOWS.includes(rawWindow)) throw invalidQuery();
  let increaseBp = null;
  if (query.increase_bp !== undefined && query.increase_bp !== '') {
    const value = Number(query.increase_bp);
    if (!Number.isInteger(value) || value < 0 || value > 10000) throw invalidQuery();
    increaseBp = value;
  }
  return { to, window: rawWindow, increaseBp, current };
}

/**
 * Saf tahmin. rows: [{ category_name, routine, unexpected }] (BigInt, taban toplamları), n: 0..12, bp: 0..10000.
 * @returns {null | { items: object[], totals: object }}
 */
export function buildForecast(rows, n, bp) {
  if (n <= 0) return null;
  const items = [];
  let total = 0n;
  let totalRoutine = 0n;
  let totalUnexpected = 0n;
  let baseRoutine = 0n;
  for (const row of rows) {
    const annualRoutine = divRound(row.routine * 12n, BigInt(n));
    const annualUnexpected = divRound(row.unexpected * 12n, BigInt(n));
    const forecastRoutine = divRound(annualRoutine * BigInt(10000 + bp), 10000n);
    const forecast = forecastRoutine + annualUnexpected;
    items.push({
      category_name: row.category_name,
      base_routine_minor: minorToNumber(row.routine),
      base_unexpected_minor: minorToNumber(row.unexpected),
      annual_routine_minor: minorToNumber(annualRoutine),
      annual_unexpected_minor: minorToNumber(annualUnexpected),
      forecast_routine_minor: minorToNumber(forecastRoutine),
      forecast_minor: minorToNumber(forecast),
    });
    total += forecast;
    totalRoutine += forecastRoutine;
    totalUnexpected += annualUnexpected;
    baseRoutine += row.routine;
  }
  items.sort((a, b) => b.forecast_minor - a.forecast_minor || a.category_name.localeCompare(b.category_name, 'tr'));
  return {
    items,
    totals: {
      base_routine_minor: minorToNumber(baseRoutine),
      forecast_routine_minor: minorToNumber(totalRoutine),
      unexpected_annual_minor: minorToNumber(totalUnexpected),
      forecast_minor: minorToNumber(total),
    },
  };
}

async function loadNetRows(db, siteCode, first, last) {
  const result = await db.query(
    `
      SELECT period, category_name, nature, SUM(total)::TEXT AS total FROM (
        SELECT to_char(e.period, 'YYYY-MM-DD') AS period, e.category_name, e.amount_minor AS total,
               COALESCE(n.nature, ${derivedNatureSql('e')}) AS nature
        FROM expenses e LEFT JOIN expense_natures n ON n.expense_id = e.id
        WHERE e.site_code = $1 AND e.period BETWEEN $2::DATE AND $3::DATE
        UNION ALL
        SELECT to_char(v.period, 'YYYY-MM-DD'), e.category_name, -e.amount_minor, COALESCE(n.nature, ${derivedNatureSql('e')})
        FROM expense_voids v INNER JOIN expenses e ON e.id = v.expense_id LEFT JOIN expense_natures n ON n.expense_id = e.id
        WHERE v.site_code = $1 AND v.period BETWEEN $2::DATE AND $3::DATE
      ) x GROUP BY period, category_name, nature
    `,
    [siteCode, first, last],
  );
  return (result.rows ?? []).map((row) => ({ period: row.period, category_name: row.category_name, nature: row.nature, total: BigInt(row.total) }));
}

const monthsOf = (from, count) => Array.from({ length: count }, (_, i) => addMonths(from, i));

function sumWindow(rows, periods) {
  const set = new Set(periods);
  const byCategory = new Map();
  let routine = 0n;
  let unexpected = 0n;
  for (const row of rows) {
    if (!set.has(row.period)) continue;
    const entry = byCategory.get(row.category_name) ?? { routine: 0n, unexpected: 0n };
    if (row.nature === 'routine') {
      entry.routine += row.total;
      routine += row.total;
    } else {
      entry.unexpected += row.total;
      unexpected += row.total;
    }
    byCategory.set(row.category_name, entry);
  }
  return { byCategory, routine, unexpected, total: routine + unexpected };
}

/** GET reports/expense-analysis. Tek snapshot. */
export async function expenseAnalysisReport(siteCode, query = {}, now = new Date()) {
  const filters = parseAnalysisQuery(query, now);
  return withReportSnapshot(siteCode, (client) => computeExpenseAnalysis(client, siteCode, filters, now));
}

/** Çekirdek (ekran ve dışa aktarma ortak); çağıran snapshot işlemini açar. */
export async function computeExpenseAnalysis(client, siteCode, filters, now = new Date()) {
  const size = filters.window;
  const windowFrom = addMonths(filters.to, -(size - 1));
  const prevFrom = addMonths(windowFrom, -size);
  const prevTo = addMonths(windowFrom, -1);
  // tahmin tabanı: son 12 TAM ay (bu ay tamamlanmadı: taban önceki ayda biter)
  const baseEnd = filters.to < filters.current ? filters.to : addMonths(filters.current, -1);
  const baseFrom = addMonths(baseEnd, -11);
  const first = [prevFrom, baseFrom].sort()[0];
  {
    const header = await reportHeader(client, siteCode, now);
    const rows = await loadNetRows(client, siteCode, first, filters.to);
    const windowPeriods = monthsOf(windowFrom, size);
    const income = await computeIncomeExpense(client, siteCode, windowPeriods);
    const incomeBy = new Map(income.map((m) => [m.period, m.collected]));

    const months = windowPeriods.map((period) => {
      const w = sumWindow(rows, [period]);
      return {
        period: periodLabel(period),
        income_minor: minorToNumber(incomeBy.get(period) ?? 0n),
        expense_minor: minorToNumber(w.total),
        routine_minor: minorToNumber(w.routine),
        unexpected_minor: minorToNumber(w.unexpected),
        by_category: [...w.byCategory.entries()]
          .map(([name, v]) => ({ category_name: name, routine_minor: minorToNumber(v.routine), unexpected_minor: minorToNumber(v.unexpected), total_minor: minorToNumber(v.routine + v.unexpected) }))
          .filter((c) => c.total_minor !== 0 || c.routine_minor !== 0 || c.unexpected_minor !== 0)
          .sort((a, b) => a.category_name.localeCompare(b.category_name, 'tr')),
      };
    });
    const cur = sumWindow(rows, windowPeriods);
    const prev = sumWindow(rows, monthsOf(prevFrom, size));
    let incomeTotal = 0n;
    for (const m of income) incomeTotal += m.collected;

    const names = new Set([...cur.byCategory.keys(), ...prev.byCategory.keys()]);
    const byCategory = [...names]
      .map((name) => {
        const c = cur.byCategory.get(name) ?? { routine: 0n, unexpected: 0n };
        const p = prev.byCategory.get(name) ?? { routine: 0n, unexpected: 0n };
        const total = c.routine + c.unexpected;
        const prevTotal = p.routine + p.unexpected;
        return {
          category_name: name,
          routine_minor: minorToNumber(c.routine),
          unexpected_minor: minorToNumber(c.unexpected),
          total_minor: minorToNumber(total),
          share_bp: rateBp(total, cur.total),
          previous_total_minor: minorToNumber(prevTotal),
          change_bp: changeBp(total, prevTotal),
        };
      })
      .filter((c) => c.total_minor !== 0 || c.previous_total_minor !== 0)
      .sort((a, b) => b.total_minor - a.total_minor || a.category_name.localeCompare(b.category_name, 'tr'));

    const derived = await client.query(
      `SELECT COUNT(*)::INTEGER AS n FROM expenses e WHERE e.site_code = $1 AND e.period BETWEEN $2::DATE AND $3::DATE
         AND NOT EXISTS (SELECT 1 FROM expense_natures n WHERE n.expense_id = e.id) AND NOT EXISTS (SELECT 1 FROM expense_voids v WHERE v.expense_id = e.id)`,
      [siteCode, windowFrom, filters.to],
    );

    // tahmin
    let bp = filters.increaseBp;
    let increaseSource = 'request';
    if (bp === null) {
      try {
        bp = Number(await getRule(client, FORECAST_RULE_KEY, { siteCode }));
        increaseSource = 'rule';
      } catch (_error) {
        bp = 0;
        increaseSource = 'default';
      }
      if (!Number.isInteger(bp) || bp < 0 || bp > 10000) bp = 0;
    }
    const basePeriods = monthsOf(baseFrom, 12);
    const activeBase = rows.filter((r) => basePeriods.includes(r.period) && r.total !== 0n).map((r) => r.period).sort();
    const n = activeBase.length === 0 ? 0 : 12 - basePeriods.indexOf(activeBase[0]);
    const base = sumWindow(rows, basePeriods);
    const forecastRows = [...base.byCategory.entries()].map(([name, v]) => ({ category_name: name, routine: v.routine, unexpected: v.unexpected }));
    const built = buildForecast(forecastRows, n, bp);

    return {
      ...header,
      to: periodLabel(filters.to),
      window: size,
      months,
      totals: {
        income_minor: minorToNumber(incomeTotal),
        expense_minor: minorToNumber(cur.total),
        routine_minor: minorToNumber(cur.routine),
        unexpected_minor: minorToNumber(cur.unexpected),
      },
      previous: {
        from: periodLabel(prevFrom),
        to: periodLabel(prevTo),
        expense_minor: minorToNumber(prev.total),
        routine_minor: minorToNumber(prev.routine),
        unexpected_minor: minorToNumber(prev.unexpected),
        change_bp: changeBp(cur.total, prev.total),
      },
      by_category: byCategory,
      classification: { derived_count: Number(derived.rows?.[0]?.n ?? 0) },
      forecast:
        built === null
          ? null
          : {
              base: { from: periodLabel(baseFrom), to: periodLabel(baseEnd), months: n },
              increase_bp: bp,
              increase_source: increaseSource,
              note: n < 12 ? `Veri ${n} aylık; yıllığa çevrilerek hesaplandı.` : null,
              items: built.items,
              totals: built.totals,
            },
    };
  }
}

/** Dışa aktarma: aylık satırlar (ay x kategori). */
export function analysisExportRows(report) {
  const out = [];
  for (const m of report.months) {
    const incomeMinor = m.income_minor;
    if (m.by_category.length === 0) {
      out.push([`${m.period}-01`, '', 0, 0, 0, incomeMinor]);
    }
    m.by_category.forEach((c, i) => out.push([`${m.period}-01`, c.category_name, c.routine_minor, c.unexpected_minor, c.total_minor, i === 0 ? incomeMinor : 0]));
  }
  return out;
}
