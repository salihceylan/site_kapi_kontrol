// Yönetici ana sayfası "Bu ay" özeti (G5): dört sayı, beş adımlı aylık döngü, dikkat satırları ve son beş para hareketi.
// GET /manager/sites/:siteCode/finance/home?month=YYYY-AA (varsayılan: bu ay, İstanbul). Salt okunur tek işlem (withReportSnapshot).
// Sözleşme: docs/PLATFORM_FINANS.md "Yönetici ana sayfası".

import { collectAttention, registerAttentionSource } from './attention_registry.js';
import { countUnassignedPayments, loadAccountPolicy } from './finance_accounts.js';
import { addMonths, currentPeriod, parsePeriod, periodLabel } from './finance_common.js';
import { cashTotals, computeAging, computeCashPosition, rateBp, withReportSnapshot } from './finance_reports.js';
import { minorToNumber, toBigInt } from './finance_money.js';
import { todayIso } from './people_common.js';

export const HOME_RECENT_LIMIT = 5;
export const HOME_RECENT_MONTHS = 3;

const asBig = (value) => toBigInt(value ?? '0');

// Bugün tek kaynak: hesaba eşlenmemiş tahsilatlar.
registerAttentionSource({
  key: 'unassigned_payments',
  module: 'finance',
  run: async (db, siteCode) => {
    const policy = await loadAccountPolicy(db, siteCode);
    return countUnassignedPayments(db, siteCode, policy.earliestOpening);
  },
});

/** month sorgusu: boşsa bu ay; geçersizse 400 INVALID_BODY. */
export function parseHomeMonth(query = {}, now = new Date()) {
  const raw = query?.month;
  if (raw === undefined || raw === null || raw === '') {
    return currentPeriod(now);
  }
  return parsePeriod(String(raw), 'Ay');
}

/** Borçlandırma adımı durumu (toplam 0 = setup). */
export function chargeStatus(total, posted) {
  if (total <= 0) {
    return 'setup';
  }
  if (posted >= total) {
    return 'done';
  }
  return posted > 0 ? 'partial' : 'todo';
}

async function loadNumbers(db, siteCode, period, today) {
  const ledger = await db.query(
    `
      SELECT
        COALESCE(SUM(amount_minor) FILTER (WHERE late_fee_run_id IS NULL AND COALESCE(source_kind, '') NOT IN ('opening', 'refund', 'liability_transfer') AND (kind = 'charge' OR (kind = 'reversal' AND amount_minor < 0))), 0)::TEXT AS charged,
        COALESCE(SUM(amount_minor) FILTER (WHERE late_fee_run_id IS NOT NULL AND (kind = 'charge' OR (kind = 'reversal' AND amount_minor < 0))), 0)::TEXT AS late_fee,
        (COALESCE(-SUM(amount_minor) FILTER (WHERE kind = 'payment' OR (kind = 'reversal' AND amount_minor > 0)), 0) - COALESCE(SUM(amount_minor) FILTER (WHERE source_kind = 'refund'), 0))::TEXT AS collected
      FROM ledger_entries WHERE site_code = $1 AND period = $2::DATE
    `,
    [siteCode, period],
  );
  const row = ledger.rows?.[0] ?? {};
  const charged = asBig(row.charged);
  const lateFee = asBig(row.late_fee);
  const collected = asBig(row.collected);
  const apartments = await db.query(`SELECT COUNT(*)::INTEGER AS n FROM apartments WHERE site_code = $1`, [siteCode]);
  const aging = await computeAging(db, siteCode, today);
  const position = await computeCashPosition(db, siteCode, today);
  return {
    numbers: {
      charged_minor: minorToNumber(charged),
      late_fee_minor: minorToNumber(lateFee),
      collected_minor: minorToNumber(collected),
      collection_rate_bp: rateBp(collected, charged + lateFee),
      overdue_apartment_count: aging.filter((item) => item.overdue > 0n).length,
      apartment_count: Number(apartments.rows?.[0]?.n ?? 0),
      cash_total_minor: position.accounts.length === 0 ? null : cashTotals(position.accounts).balance_minor,
      cash_account_count: position.accounts.length,
    },
    accountCount: position.accounts.length,
  };
}

async function loadSteps(db, siteCode, period, accountCount, attentionTotal) {
  const next = addMonths(period, 1);
  const defs = await db.query(
    `
      SELECT COUNT(*)::INTEGER AS total,
             COUNT(*) FILTER (WHERE EXISTS (SELECT 1 FROM fee_runs r WHERE r.definition_id = d.id AND r.period = $2::DATE))::INTEGER AS posted
      FROM fee_definitions d
      WHERE d.site_code = $1 AND d.kind = 'recurring' AND d.is_active = TRUE AND d.start_period <= $2::DATE AND (d.end_period IS NULL OR d.end_period >= $2::DATE)
    `,
    [siteCode, period],
  );
  const total = Number(defs.rows?.[0]?.total ?? 0);
  const posted = Number(defs.rows?.[0]?.posted ?? 0);
  const first = await db.query(`SELECT MIN(posted_at) AS at FROM fee_runs WHERE site_code = $1 AND period = $2::DATE`, [siteCode, period]);
  const firstAt = first.rows?.[0]?.at ?? null;
  let notified = false;
  if (firstAt !== null) {
    const sent = await db.query(
      `
        SELECT (EXISTS (SELECT 1 FROM announcements WHERE site_code = $1 AND status = 'published' AND published_at >= $2::TIMESTAMPTZ)
             OR EXISTS (SELECT 1 FROM finance_reminder_runs WHERE site_code = $1 AND status = 'active' AND created_at >= $2::TIMESTAMPTZ)) AS ok
      `,
      [siteCode, firstAt],
    );
    notified = sent.rows?.[0]?.ok === true;
  }
  const expense = await db.query(
    `SELECT EXISTS (SELECT 1 FROM expenses e WHERE e.site_code = $1 AND e.period = $2::DATE AND NOT EXISTS (SELECT 1 FROM expense_voids v WHERE v.expense_id = e.id)) AS ok`,
    [siteCode, period],
  );
  const report = await db.query(
    `
      SELECT EXISTS (
        SELECT 1 FROM audit_log
        WHERE site_code = $1 AND created_at >= ($2::DATE)::TIMESTAMP AT TIME ZONE 'Europe/Istanbul'
          AND (action = 'export' OR (action = 'finance.report.viewed'
               AND COALESCE(NULLIF(details->>'from', ''), '0000-01') <= to_char($3::DATE - 1, 'YYYY-MM')
               AND COALESCE(NULLIF(details->>'to', ''), '9999-12') >= to_char($2::DATE, 'YYYY-MM')))
      ) AS ok
    `,
    [siteCode, period, next],
  );
  return [
    { key: 'charge', status: chargeStatus(total, posted), done: posted, total },
    { key: 'notify', status: notified ? 'done' : 'todo' },
    { key: 'match', status: accountCount === 0 ? 'setup' : attentionTotal > 0 ? 'todo' : 'done', pending: attentionTotal },
    { key: 'expense', status: expense.rows?.[0]?.ok === true ? 'done' : 'todo' },
    { key: 'report', status: report.rows?.[0]?.ok === true ? 'done' : 'todo' },
  ];
}

/** Son 3 ayın para hareketleri (tahsilat, tahsilat iptali, gider, gider iptali), en yeni 5. Kişi adı ve açıklama dönmez. */
async function loadRecent(db, siteCode, now) {
  const since = addMonths(currentPeriod(now), -(HOME_RECENT_MONTHS - 1));
  const label = `COALESCE(NULLIF(concat_ws(' - ', NULLIF(b.block_name, ''), a.unit_label), ''), '-')`;
  const result = await db.query(
    `
      (SELECT CASE WHEN l.kind = 'payment' THEN 'payment' ELSE 'payment_void' END AS kind, to_char(l.entry_date, 'YYYY-MM-DD') AS date,
              (-l.amount_minor)::TEXT AS amount, ${label} AS label, l.created_at AS at
       FROM ledger_entries l INNER JOIN apartments a ON a.id = l.apartment_id INNER JOIN site_blocks b ON b.id = a.block_id
       WHERE l.site_code = $1 AND l.period >= $2::DATE AND (l.kind = 'payment' OR (l.kind = 'reversal' AND l.amount_minor > 0))
       ORDER BY l.created_at DESC, l.id DESC LIMIT $3)
      UNION ALL
      (SELECT 'expense', to_char(e.expense_date, 'YYYY-MM-DD'), (-e.amount_minor)::TEXT, e.category_name, e.created_at
       FROM expenses e WHERE e.site_code = $1 AND e.period >= $2::DATE
       ORDER BY e.created_at DESC, e.id DESC LIMIT $3)
      UNION ALL
      (SELECT 'expense_void', to_char(v.voided_at AT TIME ZONE 'Europe/Istanbul', 'YYYY-MM-DD'), e.amount_minor::TEXT, e.category_name, v.voided_at
       FROM expense_voids v INNER JOIN expenses e ON e.id = v.expense_id
       WHERE v.site_code = $1 AND v.period >= $2::DATE
       ORDER BY v.voided_at DESC LIMIT $3)
      ORDER BY at DESC LIMIT $3
    `,
    [siteCode, since, HOME_RECENT_LIMIT],
  );
  return (result.rows ?? []).map((row) => ({ kind: row.kind, date: row.date, amount_minor: minorToNumber(row.amount), label: row.label }));
}

/** GET finance/home gövdesi. */
export async function getFinanceHome(siteCode, query = {}, now = new Date()) {
  const period = parseHomeMonth(query, now);
  const today = todayIso(now);
  return withReportSnapshot(siteCode, async (client) => {
    const { numbers, accountCount } = await loadNumbers(client, siteCode, period, today);
    const attention = await collectAttention(siteCode, client);
    const attentionTotal = attention.reduce((sum, item) => sum + item.count, 0);
    return {
      month: periodLabel(period),
      numbers,
      steps: await loadSteps(client, siteCode, period, accountCount, attentionTotal),
      attention,
      recent: await loadRecent(client, siteCode, now),
    };
  });
}
