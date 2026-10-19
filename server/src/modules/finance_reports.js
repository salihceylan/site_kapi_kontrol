// Finans raporları (Faz 4b Ö5): borç/alacak yaşlandırma, aylık gelir-gider, kasa durumu, daire ekstresi ve yönetim kurulu özet raporu.
//
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Ö5". Bileşik raporlar TEK `REPEATABLE READ, READ ONLY` işleminde hesaplanır (bölümler birbirini tutar); bir bölüm başarısızsa
// BÜTÜN yanıt 5xx'tir (kısmi sıfır dönmez: hata ASLA "borç yok / 0" demez). `statement_timeout` (FINANCE_REPORT_STATEMENT_TIMEOUT_MS, 20 sn) ve site başına eşzamanlılık
// sınırı (FINANCE_REPORT_MAX_CONCURRENT_PER_SITE, 2; aşılırsa 503 REPORT_BUSY + Retry-After). Tarihli model: `as_of` geçmiş olabilir (kapalı ay verisi değişmez).
// Rapor altbilgisi: bu belgeler noter onaylı karar defteri / yasal defterlerin yerine geçmez. Kişi adı yalnız aging / ekstre / dışa aktarmada (yönetici + kurul liste
// okuması, 4a bakiye listesi gibi); kurul ÖZET raporu kişi adı İÇERMEZ. PARA BigInt; kayan nokta yok.

import { pool } from '../db.js';
import { recordAudit } from './audit_service.js';
import { reportBusy, STATEMENT_ROW_LIMIT, queryDate, queryEnum, queryInt, queryMonth, statementTooLarge, lastDayOfMonth, monthTitle } from './finance_4b_common.js';
import { loadAccountPolicy } from './finance_accounts.js';
import { AGING_BUCKETS, bucketSumSql, m1Ctes } from './finance_m1.js';
import {
  addMonths,
  apartmentNotFound,
  assertNotTooOld,
  currentPeriod,
  invalidBody,
  latestClosedPeriod,
  mapEntryRow,
  parseAccountQuery,
  periodLabel,
  redactEntryForResident,
  today,
} from './finance_common.js';
import { ENTRY_SELECT } from './finance_ledger_service.js';
import { minorToNumber, toBigInt } from './finance_money.js';
import { enabledFinanceSites, loadResidentLedger, loadVisibleApartments, overdueOf, residentSinceOf } from './finance_read_service.js';
import { prepareResidentLedger, residentEntryOf, residentView } from './finance_resident_view.js';
import { apartmentLabel, parsePositiveId } from './people_common.js';

export const REPORT_FOOTER = 'Bu rapor noter onaylı karar defteri/yasal defterlerin yerine geçmez.';
const INT32_MAX = 2147483647;

// --- Tek snapshot + eşzamanlılık ---------------------------------------------------------------------------------------------------------------

const inFlight = new Map();

const envInt = (name, fallback) => {
  const value = Number(process.env[name]);
  return Number.isSafeInteger(value) && value > 0 ? value : fallback;
};

// Eşzamanlılık "yuvası" türleri (site başına AYRI sayaç): yönetici raporları, ağır önizlemeler (tazminat / hatırlatma) ve sakin ekstresi birbirinin yuvasını tüketemez.
const SLOT_LIMITS = Object.freeze({
  report: () => envInt('FINANCE_REPORT_MAX_CONCURRENT_PER_SITE', 2),
  preview: () => envInt('FINANCE_PREVIEW_MAX_CONCURRENT_PER_SITE', 2),
  resident: () => envInt('FINANCE_RESIDENT_STATEMENT_MAX_CONCURRENT_PER_SITE', 8),
});

/**
 * Rapor işlemi: site başına eşzamanlılık sınırı, REPEATABLE READ READ ONLY, statement_timeout. `work(client)` sonucunu döndürür; hata olursa BÜTÜN rapor hatadır.
 * Yuva, bağlantı ALINAMASA da (havuz zaman aşımı / DB yeniden başlıyor) HER yolda bırakılır (R10 P1-5: sızan sayaç site raporlarını kalıcı 503 yapıyordu).
 * @param {{ slot?: 'report'|'preview'|'resident' }} [options]
 */
export async function withReportSnapshot(siteCode, work, db = pool, { slot = 'report' } = {}) {
  const max = SLOT_LIMITS[slot]();
  const key = slot === 'report' ? String(siteCode) : `${slot}:${siteCode}`;
  if ((inFlight.get(key) ?? 0) >= max) {
    throw reportBusy();
  }
  inFlight.set(key, (inFlight.get(key) ?? 0) + 1);
  let client = null;
  let began = false;
  try {
    client = await db.connect();
    await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    began = true;
    await client.query(`SET LOCAL statement_timeout = ${envInt('FINANCE_REPORT_STATEMENT_TIMEOUT_MS', 20000)}`);
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    if (began) {
      try {
        await client.query('ROLLBACK');
      } catch (_rollbackError) {
        // bağlantı zaten kopmuş olabilir
      }
    }
    throw error;
  } finally {
    client?.release();
    const left = (inFlight.get(key) ?? 1) - 1;
    if (left <= 0) {
      inFlight.delete(key);
    } else {
      inFlight.set(key, left);
    }
  }
}

/** Test yardımcısı: devam eden rapor sayaçları. */
export const reportConcurrency = () => Object.fromEntries(inFlight.entries());

async function reportHeader(db, siteCode, now = new Date()) {
  const site = await db.query(`SELECT name FROM sites WHERE site_code = $1`, [siteCode]);
  const closed = await db.query(`SELECT to_char(period, 'YYYY-MM-DD') AS period FROM finance_period_closures WHERE site_code = $1`, [siteCode]);
  const latest = latestClosedPeriod((closed.rows ?? []).map((row) => row.period));
  return {
    site: { name: site.rows?.[0]?.name ?? '' },
    generated_at: now.toISOString(),
    closed_through: latest === null ? null : periodLabel(latest),
    currency: 'TRY',
    footer: REPORT_FOOTER,
  };
}

const asBig = (value) => toBigInt(value ?? '0');

// --- Sorgu ayrıştırma -------------------------------------------------------------------------------------------------------------------------

function asOfOf(query, now) {
  const asOf = queryDate(query.as_of) ?? today(now);
  if (asOf > today(now)) {
    throw invalidBody('Tarih gelecek bir tarih olamaz.');
  }
  assertNotTooOld(asOf, 'Tarih', now);
  return asOf;
}

export function parseAgingQuery(query = {}, now = new Date()) {
  return {
    asOf: asOfOf(query, now),
    status: queryEnum(query.status, ['debtor', 'all'], 'debtor'),
    limit: queryInt(query.limit, { min: 1, max: 500, fallback: 200 }),
    offset: queryInt(query.offset, { min: 0, max: 100000, fallback: 0 }),
  };
}

const MAX_RANGE_MONTHS = 36;

export function parseRangeQuery(query = {}, now = new Date()) {
  const current = currentPeriod(now);
  const to = queryMonth(query.to) ?? current;
  const from = queryMonth(query.from) ?? addMonths(to, -11);
  if (from > to) {
    throw invalidBody('Dönem aralığı geçersiz.');
  }
  const months = [];
  for (let period = from; period <= to && months.length <= MAX_RANGE_MONTHS; period = addMonths(period, 1)) {
    months.push(period);
  }
  if (months.length > MAX_RANGE_MONTHS) {
    throw invalidBody(`Dönem aralığı en çok ${MAX_RANGE_MONTHS} ay olabilir.`);
  }
  assertNotTooOld(from, 'Başlangıç dönemi', now);
  return { from, to, months };
}

// --- 1. Yaşlandırma ---------------------------------------------------------------------------------------------------------------------------

const BUCKET_COLUMNS = ['d0_30', 'd31_60', 'd61_90', 'd91_180', 'd181_365', 'd366_plus'];

/** T itibarıyla tüm daireler için M1 kova toplamları (BigInt). Dışa aktarma ve ekran AYNI işlevi kullanır. */
export async function computeAging(db, siteCode, asOf) {
  const result = await db.query(
    `
      WITH ${m1Ctes('$1', '$2')},
      agg AS (
        SELECT rem.apartment_id, ${bucketSumSql('$2')}, SUM(rem.a) AS total_items
        FROM rem GROUP BY rem.apartment_id
      )
      SELECT
        a.id AS apartment_id, a.unit_label, b.block_name, b.sort_order AS block_sort, a.sort_order AS apt_sort, a.responsible_party,
        COALESCE(g.not_due, 0)::TEXT AS not_due, COALESCE(g.d0_30, 0)::TEXT AS d0_30, COALESCE(g.d31_60, 0)::TEXT AS d31_60, COALESCE(g.d61_90, 0)::TEXT AS d61_90,
        COALESCE(g.d91_180, 0)::TEXT AS d91_180, COALESCE(g.d181_365, 0)::TEXT AS d181_365, COALESCE(g.d366_plus, 0)::TEXT AS d366_plus,
        COALESCE(g.late_fee_outstanding, 0)::TEXT AS late_fee_outstanding,
        GREATEST(0, COALESCE(p.p, 0) - COALESCE(g.total_items, 0))::TEXT AS credit
      FROM apartments a
      INNER JOIN site_blocks b ON b.id = a.block_id
      LEFT JOIN agg g ON g.apartment_id = a.id
      LEFT JOIN pay p ON p.apartment_id = a.id
      WHERE a.site_code = $1 AND (a.is_active = TRUE OR g.apartment_id IS NOT NULL OR p.apartment_id IS NOT NULL)
      ORDER BY b.sort_order, a.sort_order, a.id
    `,
    [siteCode, asOf],
  );
  return (result.rows ?? []).map((row) => {
    const buckets = {
      not_due: asBig(row.not_due),
      d0_30: asBig(row.d0_30),
      d31_60: asBig(row.d31_60),
      d61_90: asBig(row.d61_90),
      d91_180: asBig(row.d91_180),
      d181_365: asBig(row.d181_365),
      d366_plus: asBig(row.d366_plus),
    };
    let overdue = 0n;
    for (const name of BUCKET_COLUMNS) {
      overdue += buckets[name];
    }
    return {
      apartmentId: Number(row.apartment_id),
      label: apartmentLabel(row.block_name, row.unit_label),
      blockName: row.block_name ?? null,
      blockSort: Number(row.block_sort),
      aptSort: Number(row.apt_sort),
      payerParty: row.responsible_party,
      buckets,
      overdue,
      credit: asBig(row.credit),
      lateFeeOutstanding: asBig(row.late_fee_outstanding),
    };
  });
}

/** Daire kimlikleri için güncel malik / kiracı adları. */
export async function loadResidentNames(db, apartmentIds) {
  const names = new Map();
  if (apartmentIds.length === 0) {
    return names;
  }
  const result = await db.query(
    `
      SELECT r.apartment_id, r.relation, COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS name, r.id
      FROM apartment_residencies r
      INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE
      LEFT JOIN users u ON u.user_code = sp.user_code
      WHERE r.apartment_id = ANY($1::BIGINT[]) AND r.is_current = TRUE AND r.relation IN ('owner', 'tenant')
      ORDER BY r.apartment_id, r.id
    `,
    [apartmentIds],
  );
  for (const row of result.rows ?? []) {
    const entry = names.get(Number(row.apartment_id)) ?? { owner: null, tenant: null };
    if (entry[row.relation] === null) {
      entry[row.relation] = row.name;
    }
    names.set(Number(row.apartment_id), entry);
  }
  return names;
}

function agingItem(row, names) {
  const entry = {
    apartment_id: row.apartmentId,
    label: row.label,
    block_name: row.blockName,
    payer_party: row.payerParty,
    owner_name: names.get(row.apartmentId)?.owner ?? null,
    tenant_name: names.get(row.apartmentId)?.tenant ?? null,
  };
  for (const bucket of AGING_BUCKETS) {
    entry[`${bucket}_minor`] = minorToNumber(row.buckets[bucket]);
  }
  entry.credit_minor = minorToNumber(row.credit);
  entry.late_fee_outstanding_minor = minorToNumber(row.lateFeeOutstanding);
  entry.total_overdue_minor = minorToNumber(row.overdue);
  return entry;
}

export function sortAging(rows, status) {
  const list = status === 'debtor' ? rows.filter((row) => row.overdue > 0n) : [...rows];
  return list.sort((a, b) => (a.overdue === b.overdue ? a.blockSort - b.blockSort || a.aptSort - b.aptSort || a.apartmentId - b.apartmentId : a.overdue > b.overdue ? -1 : 1));
}

export function agingTotals(rows) {
  const totals = Object.fromEntries(AGING_BUCKETS.map((bucket) => [bucket, 0n]));
  let overdue = 0n;
  let credit = 0n;
  let lateFee = 0n;
  let debtors = 0;
  for (const row of rows) {
    for (const bucket of AGING_BUCKETS) {
      totals[bucket] += row.buckets[bucket];
    }
    overdue += row.overdue;
    credit += row.credit;
    lateFee += row.lateFeeOutstanding;
    if (row.overdue > 0n) {
      debtors += 1;
    }
  }
  const out = {};
  for (const bucket of AGING_BUCKETS) {
    out[`${bucket}_minor`] = minorToNumber(totals[bucket]);
  }
  out.total_overdue_minor = minorToNumber(overdue);
  out.credit_minor = minorToNumber(credit);
  out.late_fee_outstanding_minor = minorToNumber(lateFee);
  out.debtor_count = debtors;
  return out;
}

/** GET reports/aging. */
export async function agingReport(siteCode, query = {}, now = new Date()) {
  const filters = parseAgingQuery(query, now);
  return withReportSnapshot(siteCode, async (client) => {
    const header = await reportHeader(client, siteCode, now);
    const rows = await computeAging(client, siteCode, filters.asOf);
    const sorted = sortAging(rows, filters.status);
    const page = sorted.slice(filters.offset, filters.offset + filters.limit);
    const names = await loadResidentNames(client, page.map((row) => row.apartmentId));
    return {
      ...header,
      as_of: filters.asOf,
      buckets: [...AGING_BUCKETS],
      totals: agingTotals(rows),
      items: page.map((row) => agingItem(row, names)),
      total: sorted.length,
    };
  });
}

// --- 2. Aylık gelir-gider -------------------------------------------------------------------------------------------------------------------

/** Yüzde (baz puan, tamsayı) = pay * 10000 / payda; payda 0 ise null. BigInt (yarım yukarı). */
export function rateBp(numerator, denominator) {
  if (denominator <= 0n) {
    return null;
  }
  return Number((numerator * 20000n + denominator) / (denominator * 2n));
}

/** Aylık gelir-gider çekirdeği (ekran, dışa aktarma ve kurul özeti ortak). */
export async function computeIncomeExpense(db, siteCode, months) {
  const first = months[0];
  const last = months[months.length - 1];
  const ledger = await db.query(
    `
      SELECT to_char(period, 'YYYY-MM-DD') AS period,
        COALESCE(SUM(amount_minor) FILTER (WHERE late_fee_run_id IS NULL AND (kind = 'charge' OR (kind = 'reversal' AND amount_minor < 0))), 0)::TEXT AS charged,
        COALESCE(SUM(amount_minor) FILTER (WHERE late_fee_run_id IS NOT NULL AND (kind = 'charge' OR (kind = 'reversal' AND amount_minor < 0))), 0)::TEXT AS late_fee,
        COALESCE(-SUM(amount_minor) FILTER (WHERE kind = 'payment' OR (kind = 'reversal' AND amount_minor > 0)), 0)::TEXT AS collected
      FROM ledger_entries WHERE site_code = $1 AND period BETWEEN $2::DATE AND $3::DATE GROUP BY period
    `,
    [siteCode, first, last],
  );
  const expenses = await db.query(
    `
      SELECT period, category_name, SUM(total)::TEXT AS total FROM (
        SELECT to_char(e.period, 'YYYY-MM-DD') AS period, e.category_name, e.amount_minor AS total
        FROM expenses e WHERE e.site_code = $1 AND e.period BETWEEN $2::DATE AND $3::DATE
        UNION ALL
        SELECT to_char(v.period, 'YYYY-MM-DD'), e.category_name, -e.amount_minor
        FROM expense_voids v INNER JOIN expenses e ON e.id = v.expense_id
        WHERE v.site_code = $1 AND v.period BETWEEN $2::DATE AND $3::DATE
      ) x GROUP BY period, category_name
    `,
    [siteCode, first, last],
  );
  const ledgerByMonth = new Map((ledger.rows ?? []).map((row) => [row.period, row]));
  const catsByMonth = new Map();
  for (const row of expenses.rows ?? []) {
    const list = catsByMonth.get(row.period) ?? [];
    list.push({ category_name: row.category_name, total: asBig(row.total) });
    catsByMonth.set(row.period, list);
  }
  return months.map((period) => {
    const led = ledgerByMonth.get(period);
    const charged = asBig(led?.charged);
    const lateFee = asBig(led?.late_fee);
    const collected = asBig(led?.collected);
    const cats = (catsByMonth.get(period) ?? []).filter((c) => c.total !== 0n).sort((a, b) => a.category_name.localeCompare(b.category_name, 'tr'));
    let expense = 0n;
    for (const cat of cats) {
      expense += cat.total;
    }
    return { period, charged, lateFee, collected, expense, categories: cats };
  });
}

function incomeExpenseRow(row) {
  return {
    period: periodLabel(row.period),
    charged_minor: minorToNumber(row.charged),
    late_fee_minor: minorToNumber(row.lateFee),
    collected_minor: minorToNumber(row.collected),
    expense_minor: minorToNumber(row.expense),
    net_cash_minor: minorToNumber(row.collected - row.expense),
    collection_rate_bp: rateBp(row.collected, row.charged + row.lateFee),
    expense_by_category: row.categories.map((c) => ({ category_name: c.category_name, total_minor: minorToNumber(c.total) })),
  };
}

/** GET reports/income-expense. */
export async function incomeExpenseReport(siteCode, query = {}, now = new Date()) {
  const range = parseRangeQuery(query, now);
  return withReportSnapshot(siteCode, async (client) => {
    const header = await reportHeader(client, siteCode, now);
    const rows = await computeIncomeExpense(client, siteCode, range.months);
    const totals = rows.reduce(
      (acc, row) => ({ charged: acc.charged + row.charged, lateFee: acc.lateFee + row.lateFee, collected: acc.collected + row.collected, expense: acc.expense + row.expense }),
      { charged: 0n, lateFee: 0n, collected: 0n, expense: 0n },
    );
    const byCategory = new Map();
    for (const row of rows) {
      for (const cat of row.categories) {
        byCategory.set(cat.category_name, (byCategory.get(cat.category_name) ?? 0n) + cat.total);
      }
    }
    return {
      ...header,
      from: periodLabel(range.from),
      to: periodLabel(range.to),
      months: rows.map(incomeExpenseRow),
      totals: {
        charged_minor: minorToNumber(totals.charged),
        late_fee_minor: minorToNumber(totals.lateFee),
        collected_minor: minorToNumber(totals.collected),
        expense_minor: minorToNumber(totals.expense),
        net_cash_minor: minorToNumber(totals.collected - totals.expense),
        collection_rate_bp: rateBp(totals.collected, totals.charged + totals.lateFee),
      },
      expense_by_category: [...byCategory.entries()]
        .filter(([, total]) => total !== 0n)
        .sort((a, b) => a[0].localeCompare(b[0], 'tr'))
        .map(([category_name, total]) => ({ category_name, total_minor: minorToNumber(total) })),
    };
  });
}

// --- 3. Kasa durumu ---------------------------------------------------------------------------------------------------------------------------

export async function computeCashPosition(db, siteCode, asOf) {
  const result = await db.query(
    `
      SELECT
        a.id, a.name, a.kind, a.is_active, to_char(a.opening_date, 'YYYY-MM-DD') AS opening_date,
        COALESCE(SUM(m.amount_minor) FILTER (WHERE m.kind = 'opening'), 0)::TEXT AS opening,
        COALESCE(SUM(m.amount_minor) FILTER (WHERE m.kind = 'collection'), 0)::TEXT AS collections,
        COALESCE(SUM(m.amount_minor) FILTER (WHERE m.kind = 'expense'), 0)::TEXT AS expenses,
        COALESCE(SUM(m.amount_minor) FILTER (WHERE m.kind = 'transfer_in'), 0)::TEXT AS transfers_in,
        COALESCE(SUM(m.amount_minor) FILTER (WHERE m.kind = 'transfer_out'), 0)::TEXT AS transfers_out,
        COALESCE(SUM(m.amount_minor) FILTER (WHERE m.kind = 'adjustment'), 0)::TEXT AS adjustments,
        COALESCE(SUM(m.amount_minor) FILTER (WHERE m.kind = 'reversal'), 0)::TEXT AS reversals,
        COALESCE(SUM(m.amount_minor), 0)::TEXT AS balance,
        (SELECT json_build_object('as_of_date', to_char(r.as_of_date, 'YYYY-MM-DD'), 'difference_minor', r.difference_minor::TEXT, 'adjusted', r.adjustment_movement_id IS NOT NULL)
         FROM account_reconciliations r WHERE r.account_id = a.id AND r.as_of_date <= $2::DATE ORDER BY r.as_of_date DESC, r.id DESC LIMIT 1) AS last_reconciliation
      FROM finance_accounts a
      LEFT JOIN account_movements m ON m.account_id = a.id AND m.movement_date <= $2::DATE
      WHERE a.site_code = $1 AND a.opening_date <= $2::DATE
      GROUP BY a.id
      ORDER BY a.sort_order, a.id
    `,
    [siteCode, asOf],
  );
  const accounts = (result.rows ?? []).map((row) => ({
    id: Number(row.id),
    name: row.name,
    kind: row.kind,
    is_active: row.is_active === true,
    opening_minor: asBig(row.opening),
    collections_minor: asBig(row.collections),
    expenses_minor: asBig(row.expenses),
    transfers_in_minor: asBig(row.transfers_in),
    transfers_out_minor: asBig(row.transfers_out),
    adjustments_minor: asBig(row.adjustments),
    reversals_minor: asBig(row.reversals),
    balance_minor: asBig(row.balance),
    last_reconciliation: row.last_reconciliation
      ? { as_of_date: row.last_reconciliation.as_of_date, difference_minor: asBig(row.last_reconciliation.difference_minor), adjusted: row.last_reconciliation.adjusted === true }
      : null,
  }));
  const policy = await loadAccountPolicy(db, siteCode);
  const unassigned = await db.query(
    `
      SELECT COUNT(*)::INTEGER AS n, COALESCE(SUM(-l.amount_minor), 0)::TEXT AS total
      FROM ledger_entries l
      WHERE l.site_code = $1 AND l.kind = 'payment' AND $3::DATE IS NOT NULL AND l.period >= date_trunc('month', $3::DATE)::DATE AND l.entry_date >= $3::DATE AND l.entry_date <= $2::DATE
        AND NOT EXISTS (SELECT 1 FROM ledger_entries rv WHERE rv.reverses_entry_id = l.id)
        AND NOT EXISTS (SELECT 1 FROM account_movements m WHERE m.kind = 'collection' AND m.ledger_entry_id = l.id)
    `,
    [siteCode, asOf, policy.earliestOpening],
  );
  return { accounts, unassigned: { count: Number(unassigned.rows[0].n), total: asBig(unassigned.rows[0].total) } };
}

function accountPositionRow(account) {
  return {
    id: account.id,
    name: account.name,
    kind: account.kind,
    is_active: account.is_active,
    opening_minor: minorToNumber(account.opening_minor),
    collections_minor: minorToNumber(account.collections_minor),
    expenses_minor: minorToNumber(account.expenses_minor),
    transfers_in_minor: minorToNumber(account.transfers_in_minor),
    transfers_out_minor: minorToNumber(account.transfers_out_minor),
    adjustments_minor: minorToNumber(account.adjustments_minor),
    reversals_minor: minorToNumber(account.reversals_minor),
    balance_minor: minorToNumber(account.balance_minor),
    negative_balance: account.balance_minor < 0n,
    last_reconciliation: account.last_reconciliation
      ? { as_of_date: account.last_reconciliation.as_of_date, difference_minor: minorToNumber(account.last_reconciliation.difference_minor), adjusted: account.last_reconciliation.adjusted }
      : null,
  };
}

export function cashTotals(accounts) {
  const keys = ['opening_minor', 'collections_minor', 'expenses_minor', 'transfers_in_minor', 'transfers_out_minor', 'adjustments_minor', 'reversals_minor', 'balance_minor'];
  const totals = Object.fromEntries(keys.map((key) => [key, 0n]));
  for (const account of accounts) {
    for (const key of keys) {
      totals[key] += account[key];
    }
  }
  return Object.fromEntries(keys.map((key) => [key, minorToNumber(totals[key])]));
}

/** GET reports/cash-position. */
export async function cashPositionReport(siteCode, query = {}, now = new Date()) {
  const asOf = asOfOf(query, now);
  return withReportSnapshot(siteCode, async (client) => {
    const header = await reportHeader(client, siteCode, now);
    const position = await computeCashPosition(client, siteCode, asOf);
    return {
      ...header,
      as_of: asOf,
      accounts: position.accounts.map(accountPositionRow),
      totals: cashTotals(position.accounts),
      unassigned_payments: { count: position.unassigned.count, total_minor: minorToNumber(position.unassigned.total) },
      warnings: position.accounts.filter((a) => a.balance_minor < 0n).map((a) => ({ code: 'NEGATIVE_BALANCE', account_id: a.id })),
    };
  });
}

// --- 4. Daire ekstresi -----------------------------------------------------------------------------------------------------------------------

export function parseStatementQuery(query = {}, now = new Date()) {
  const todayIso = today(now);
  const parsed = parseAccountQuery({ from: query.from, to: query.to });
  const from = parsed.from ?? `${todayIso.slice(0, 4)}-01-01`;
  const to = parsed.to ?? todayIso;
  if (from > to) {
    throw invalidBody('Tarih aralığı geçersiz.');
  }
  return { from, to };
}

/** Sakin ekstresinin hesaplandığı defter satırı sınırı (yönetici ekstresi STATEMENT_ROW_LIMIT). */
const RESIDENT_STATEMENT_ROW_LIMIT = 2000;

/**
 * Sakin ekstresi çekirdeği. Yönetici ekstresiyle AYNI gövde biçimi; fark: satırlar sakin kapsamındaki görünen satırlardır, açılış /
 * kapanış / kayan bakiye / vadesi geçmiş tutar sakin kapsamı ve mahsup kuralıyla hesaplanır (finance_resident_view.residentView).
 * Bir tahsilat bu ekstrede gösterilmeyen daha eski bir borca mahsup edildiyse satır toplamı kapanışa eşit olmaz; o zaman
 * `offset_note` true döner ve istemci bunu açıklar. `visible_from` ('YYYY-MM') yalnız kapsam dışında kayıt varsa dolar.
 */
export async function computeResidentStatement(db, siteCode, apartmentId, range, since, now = new Date()) {
  const apartment = await db.query(
    `SELECT a.id, a.unit_label, b.block_name, a.responsible_party FROM apartments a INNER JOIN site_blocks b ON b.id = a.block_id WHERE a.id = $1 AND a.site_code = $2`,
    [apartmentId, siteCode],
  );
  if (!apartment.rows?.[0]) {
    throw apartmentNotFound();
  }
  // Sakin ekstresi dairenin TÜM defterinden hesaplanır (kayan bakiye her satırda yeniden dökülür): sınır yönetici ekstresinden düşüktür ve
  // sorgu sınırın bir fazlasıyla kesilir (büyük defter olay döngüsünü uzun süre meşgul etmesin).
  const rows = await loadResidentLedger(db, [siteCode], [apartmentId], { limit: RESIDENT_STATEMENT_ROW_LIMIT + 1 });
  if (rows.length > RESIDENT_STATEMENT_ROW_LIMIT) {
    throw statementTooLarge();
  }
  const todayIso = today(now);
  const entries = prepareResidentLedger(rows.map(residentEntryOf));
  const current = residentView(entries, { since, today: todayIso });
  const inRange = rows.filter((row) => row.entry_date >= range.from && row.entry_date <= range.to && current.visibleIds.has(Number(row.id)));
  const openingBalance = residentView(entries, { since, today: todayIso, before: range.from }).balance;
  const closingBalance = residentView(entries, { since, today: todayIso, upTo: { date: range.to, id: Number.MAX_SAFE_INTEGER } }).balance;
  const totals = { charged: 0n, lateFee: 0n, paid: 0n, reversed: 0n };
  let rowSum = 0n;
  const items = inRange.map((row) => {
    const amount = asBig(row.amount_minor);
    rowSum += amount;
    if (row.kind === 'charge') {
      if (row.late_fee_run_id === null || row.late_fee_run_id === undefined) totals.charged += amount;
      else totals.lateFee += amount;
    } else if (row.kind === 'payment') {
      totals.paid += -amount;
    } else {
      totals.reversed += amount;
    }
    const running = residentView(entries, { since, today: todayIso, upTo: { date: row.entry_date, id: Number(row.id) } }).balance;
    return { ...mapEntryRow(row), running_balance_minor: minorToNumber(running) };
  });
  const record = apartment.rows[0];
  return {
    apartment: { id: Number(record.id), label: apartmentLabel(record.block_name, record.unit_label), block_name: record.block_name ?? null, responsible_party: record.responsible_party },
    from: range.from,
    to: range.to,
    opening_balance_minor: minorToNumber(openingBalance),
    closing_balance_minor: minorToNumber(closingBalance),
    items,
    totals: { charged_minor: minorToNumber(totals.charged), late_fee_minor: minorToNumber(totals.lateFee), paid_minor: minorToNumber(totals.paid), reversed_minor: minorToNumber(totals.reversed) },
    overdue_minor: minorToNumber(current.overdue),
    visible_from: current.hiddenCount > 0 ? since.slice(0, 7) : null,
    offset_note: openingBalance + rowSum !== closingBalance,
  };
}

/** Ekstre çekirdeği (yönetici ve sakin aynı gövdeyi kullanır). */
export async function computeStatement(db, siteCode, apartmentId, range, now = new Date()) {
  const apartment = await db.query(
    `SELECT a.id, a.unit_label, b.block_name, a.responsible_party FROM apartments a INNER JOIN site_blocks b ON b.id = a.block_id WHERE a.id = $1 AND a.site_code = $2`,
    [apartmentId, siteCode],
  );
  if (!apartment.rows?.[0]) {
    throw apartmentNotFound();
  }
  const count = await db.query(
    `SELECT COUNT(*)::INTEGER AS n FROM ledger_entries WHERE site_code = $1 AND apartment_id = $2 AND entry_date BETWEEN $3::DATE AND $4::DATE`,
    [siteCode, apartmentId, range.from, range.to],
  );
  if (Number(count.rows[0].n) > STATEMENT_ROW_LIMIT) {
    throw statementTooLarge();
  }
  const opening = await db.query(`SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS s FROM ledger_entries WHERE site_code = $1 AND apartment_id = $2 AND entry_date < $3::DATE`, [
    siteCode,
    apartmentId,
    range.from,
  ]);
  const entries = await db.query(
    `${ENTRY_SELECT} WHERE l.site_code = $1 AND l.apartment_id = $2 AND l.entry_date BETWEEN $3::DATE AND $4::DATE ORDER BY l.entry_date, l.id`,
    [siteCode, apartmentId, range.from, range.to],
  );
  const sums = await db.query(
    `
      SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS balance, COALESCE(SUM(amount_minor) FILTER (WHERE due_date > $3::DATE), 0)::TEXT AS not_due
      FROM ledger_entries WHERE site_code = $1 AND apartment_id = $2
    `,
    [siteCode, apartmentId, today(now)],
  );
  const openingBalance = asBig(opening.rows[0].s);
  let running = openingBalance;
  const totals = { charged: 0n, lateFee: 0n, paid: 0n, reversed: 0n };
  const items = (entries.rows ?? []).map((row) => {
    const amount = asBig(row.amount_minor);
    running += amount;
    if (row.kind === 'charge') {
      if (row.late_fee_run_id === null || row.late_fee_run_id === undefined) totals.charged += amount;
      else totals.lateFee += amount;
    } else if (row.kind === 'payment') {
      totals.paid += -amount;
    } else {
      totals.reversed += amount;
    }
    return { ...mapEntryRow(row), running_balance_minor: minorToNumber(running) };
  });
  const row = apartment.rows[0];
  return {
    apartment: { id: Number(row.id), label: apartmentLabel(row.block_name, row.unit_label), block_name: row.block_name ?? null, responsible_party: row.responsible_party },
    from: range.from,
    to: range.to,
    opening_balance_minor: minorToNumber(openingBalance),
    closing_balance_minor: minorToNumber(running),
    items,
    totals: { charged_minor: minorToNumber(totals.charged), late_fee_minor: minorToNumber(totals.lateFee), paid_minor: minorToNumber(totals.paid), reversed_minor: minorToNumber(totals.reversed) },
    overdue_minor: minorToNumber(overdueOf(sums.rows[0].balance, sums.rows[0].not_due)),
  };
}

/** GET apartments/:id/statement. */
export async function statementReport(siteCode, rawApartmentId, query = {}, now = new Date()) {
  const apartmentId = parsePositiveId(rawApartmentId);
  if (apartmentId === null) {
    throw apartmentNotFound();
  }
  const range = parseStatementQuery(query, now);
  return withReportSnapshot(siteCode, async (client) => {
    const header = await reportHeader(client, siteCode, now);
    return { ...header, ...(await computeStatement(client, siteCode, apartmentId, range, now)) };
  });
}

/** Sakin: GET /app/my-finance/apartments/:id/statement (yalnız F2.05 kuralıyla borcu görebildiği daire; yönetici serbest metinleri çıkarılır). */
export async function myStatement(authUser, rawApartmentId, query = {}, now = new Date()) {
  const apartmentId = parsePositiveId(rawApartmentId);
  const userCode = parsePositiveId(authUser?.user_code ?? authUser?.userCode ?? authUser?.id, INT32_MAX);
  if (apartmentId === null || userCode === null) {
    throw apartmentNotFound();
  }
  const visible = await loadVisibleApartments(pool, userCode);
  const enabled = await enabledFinanceSites(pool, [...new Set(visible.map((row) => Number(row.site_code)))]);
  const target = visible.find((row) => Number(row.apartment_id) === apartmentId && enabled.has(Number(row.site_code)));
  if (!target) {
    throw apartmentNotFound();
  }
  const range = parseStatementQuery(query, now);
  const siteCode = Number(target.site_code);
  return withReportSnapshot(
    siteCode,
    async (client) => {
      const header = await reportHeader(client, siteCode, now);
      // Sakin kapsamı + mahsup kuralı (computeResidentStatement); yönetici ekstresi (computeStatement) değişmez.
      const body = await computeResidentStatement(client, siteCode, apartmentId, range, residentSinceOf(target, today(now)), now);
      return { ...header, ...body, items: body.items.map((entry) => ({ ...redactEntryForResident(entry), running_balance_minor: entry.running_balance_minor })) };
    },
    pool,
    { slot: 'resident' },
  );
}

// --- 5. Yönetim kurulu özet raporu ------------------------------------------------------------------------------------------------------------

export function parseBoardSummaryQuery(query = {}, now = new Date()) {
  const range = parseRangeQuery(query, now);
  const include = query.include_debtor_list === undefined ? false : String(query.include_debtor_list).trim();
  if (include !== false && include !== 'true' && include !== 'false') {
    throw invalidBody('Borçlu listesi seçeneği geçersiz.');
  }
  return { ...range, includeDebtorList: include === 'true' };
}

/** GET reports/board-summary. includeDebtorList yalnız yönetici / süper için uygulanır (kurulda yok sayılır; çağıran denetler). */
export async function boardSummaryReport(siteCode, query = {}, { canListDebtors = false, actor = null, now = new Date() } = {}) {
  const filters = parseBoardSummaryQuery(query, now);
  const wantList = filters.includeDebtorList && canListDebtors;
  const body = await withReportSnapshot(siteCode, async (client) => {
    const header = await reportHeader(client, siteCode, now);
    const months = await computeIncomeExpense(client, siteCode, filters.months);
    const totals = months.reduce(
      (acc, row) => ({ charged: acc.charged + row.charged, lateFee: acc.lateFee + row.lateFee, collected: acc.collected + row.collected, expense: acc.expense + row.expense }),
      { charged: 0n, lateFee: 0n, collected: 0n, expense: 0n },
    );
    const byCategory = new Map();
    for (const row of months) {
      for (const cat of row.categories) {
        byCategory.set(cat.category_name, (byCategory.get(cat.category_name) ?? 0n) + cat.total);
      }
    }
    const endDay = lastDayOfMonth(filters.to);
    const asOf = endDay < today(now) ? endDay : today(now);
    const aging = await computeAging(client, siteCode, asOf);
    const agingSummary = AGING_BUCKETS.map((bucket) => ({
      bucket,
      count: aging.filter((row) => row.buckets[bucket] > 0n).length,
      total_minor: minorToNumber(aging.reduce((acc, row) => acc + row.buckets[bucket], 0n)),
    }));
    const debtTotal = aging.reduce((acc, row) => acc + row.overdue, 0n);
    const debtors = aging.filter((row) => row.overdue > 0n);
    const activeCount = aging.length;
    const top = await client.query(
      `
        SELECT e.category_name, to_char(e.expense_date, 'YYYY-MM-DD') AS expense_date, e.amount_minor::TEXT AS amount
        FROM expenses e
        WHERE e.site_code = $1 AND e.expense_date BETWEEN $2::DATE AND $3::DATE AND NOT EXISTS (SELECT 1 FROM expense_voids v WHERE v.expense_id = e.id)
        ORDER BY e.amount_minor DESC, e.id LIMIT 5
      `,
      [siteCode, filters.from, endDay],
    );
    const position = await computeCashPosition(client, siteCode, today(now));
    const lateFee = await client.query(
      `
        SELECT
          COUNT(*)::INTEGER AS runs,
          COALESCE(SUM(cardinality(r.waived_apartment_ids)), 0)::INTEGER AS waived,
          COALESCE(SUM(r.total_minor), 0)::TEXT AS total,
          COALESCE(SUM((
            SELECT COALESCE(SUM(ln.amount_minor), 0) FROM late_fee_run_lines ln
            WHERE ln.run_id = r.id AND EXISTS (SELECT 1 FROM ledger_entries rv WHERE rv.reverses_entry_id = ln.ledger_entry_id)
          )), 0)::TEXT AS reversed
        FROM late_fee_runs r
        WHERE r.site_code = $1 AND r.period BETWEEN $2::DATE AND $3::DATE AND r.status = 'active'
      `,
      [siteCode, filters.from, filters.to],
    );
    const reminders = await client.query(
      `
        SELECT COUNT(*) FILTER (WHERE i.email_status = 'sent')::INTEGER AS sent
        FROM finance_reminder_runs r INNER JOIN finance_reminder_items i ON i.run_id = r.id
        WHERE r.site_code = $1 AND r.created_at >= $2::DATE AND r.created_at < ($3::DATE + 1)
      `,
      [siteCode, filters.from, endDay],
    );
    const closedThrough = header.closed_through;
    const currentMonth = periodLabel(currentPeriod(now));
    const warnings = [];
    const lastRangeMonth = periodLabel(filters.to);
    if (lastRangeMonth < currentMonth && (closedThrough === null || closedThrough < lastRangeMonth)) {
      warnings.push({ code: 'UNCLOSED_PAST_PERIODS' });
    }
    for (const account of position.accounts) {
      if (account.last_reconciliation && account.last_reconciliation.difference_minor !== 0n && !account.last_reconciliation.adjusted) {
        warnings.push({ code: 'RECONCILIATION_DIFFERENCE', account_id: account.id, difference_minor: minorToNumber(account.last_reconciliation.difference_minor) });
      }
      if (account.balance_minor < 0n) {
        warnings.push({ code: 'NEGATIVE_BALANCE', account_id: account.id });
      }
    }
    if (position.unassigned.count > 0) {
      warnings.push({ code: 'UNASSIGNED_PAYMENTS', count: position.unassigned.count, total_minor: minorToNumber(position.unassigned.total) });
    }
    const result = {
      ...header,
      from: periodLabel(filters.from),
      to: periodLabel(filters.to),
      period_title: `${monthTitle(filters.from)} - ${monthTitle(filters.to)}`,
      collection: {
        charged_minor: minorToNumber(totals.charged),
        late_fee_minor: minorToNumber(totals.lateFee),
        collected_minor: minorToNumber(totals.collected),
        collection_rate_bp: rateBp(totals.collected, totals.charged + totals.lateFee),
      },
      receivables: {
        as_of: asOf,
        total_overdue_minor: minorToNumber(debtTotal),
        debtor_count: debtors.length,
        debtor_ratio_bp: rateBp(BigInt(debtors.length), BigInt(activeCount)),
        aging: agingSummary,
      },
      expenses: {
        total_minor: minorToNumber(totals.expense),
        by_category: [...byCategory.entries()]
          .filter(([, total]) => total !== 0n)
          .sort((a, b) => (a[1] === b[1] ? a[0].localeCompare(b[0], 'tr') : a[1] > b[1] ? -1 : 1))
          .map(([category_name, total]) => ({ category_name, total_minor: minorToNumber(total) })),
        top_items: (top.rows ?? []).map((row) => ({ category_name: row.category_name, expense_date: row.expense_date, amount_minor: minorToNumber(row.amount) })),
      },
      cash: {
        accounts: position.accounts.map((a) => ({ id: a.id, name: a.name, kind: a.kind, balance_minor: minorToNumber(a.balance_minor), last_reconciliation: a.last_reconciliation ? { as_of_date: a.last_reconciliation.as_of_date, difference_minor: minorToNumber(a.last_reconciliation.difference_minor), adjusted: a.last_reconciliation.adjusted === true } : null })),
        total_balance_minor: cashTotals(position.accounts).balance_minor,
        unassigned_payments: { count: position.unassigned.count, total_minor: minorToNumber(position.unassigned.total) },
      },
      late_fee: { run_count: Number(lateFee.rows[0].runs), total_minor: minorToNumber(asBig(lateFee.rows[0].total) - asBig(lateFee.rows[0].reversed)), waived_count: Number(lateFee.rows[0].waived) },
      reminders: { sent_count: Number(reminders.rows[0].sent) },
      warnings,
    };
    if (wantList) {
      result.debtor_list = sortAging(aging, 'debtor')
        .slice(0, 10)
        .map((row) => ({ label: row.label, total_overdue_minor: minorToNumber(row.overdue) }));
    }
    return result;
  });
  if (wantList) {
    await recordAudit(pool, { actor, action: 'finance.report.debtor_list', siteCode, targetType: 'finance', targetId: String(siteCode), details: { include_debtor_list: true } });
  }
  return body;
}
