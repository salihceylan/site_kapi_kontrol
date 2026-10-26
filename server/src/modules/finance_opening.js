// Devir bakiyesi (F4): yüklemeler, ayrıntı ve YÜKLEME BAZINDA geri alma. Yazma (yükleme) toplu yükleme altyapısındadır (bulk_import_service: imports/opening_balances).
//
// Geri alma: defter yalnız eklemelidir; yükleme satırlarının her biri için (zaten ters kaydı olmayanlar) açık ayda, bugünün tarihiyle `reversal` yazılır.
// Hesap (account_party) asıl kayıttan gelir. Tek geri alma: aynı anahtarla tekrar 200 (replayed), farklı anahtarla 409 OPENING_ALREADY_REVERTED.
// Kilit sırası finance_tx ile aynı: sites -> finance_post -> apartments (id sırasıyla) -> kullanıcı -> defter / finance_opening_reverts / audit.

import { actorFromAuthUser } from './audit_service.js';
import { PlatformError } from './errors.js';
import { IDEMPOTENCY_KEY_PATTERN } from './bulk_import_body.js';
import { REASON_MAX, invalidBody, normalizeFreeText, periodLabel, today } from './finance_common.js';
import { resolveOpenPeriod } from './finance_4b_guard.js';
import { pool } from '../db.js';
import { lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';

const runNotFound = () => new PlatformError(404, 'OPENING_RUN_NOT_FOUND', 'Devir yüklemesi bulunamadı.');
const alreadyReverted = () => new PlatformError(409, 'OPENING_ALREADY_REVERTED', 'Bu devir yüklemesi zaten geri alınmış.');
const changed = (extra) => new PlatformError(409, 'OPENING_CHANGED', 'Devir kayıtları değişti. Ayrıntıyı yenileyip tekrar inceleyin.', extra);

const isoOf = (value) => (value instanceof Date ? value.toISOString() : new Date(value).toISOString());

function parseRunId(raw) {
  const id = Number(raw);
  return Number.isSafeInteger(id) && id > 0 ? id : null;
}

function mapRun(row) {
  const counts = row.counts && typeof row.counts === 'object' ? row.counts : {};
  const plan = counts.plan ?? {};
  return {
    id: Number(row.id),
    created_at: isoOf(row.created_at),
    cutover_date: counts.cutover_date ?? null,
    row_count: Number(row.row_count),
    entry_count: Number(plan.opening_add ?? 0),
    total_minor: Number(plan.total_minor ?? 0),
    reverted: row.reverted_at !== null && row.reverted_at !== undefined,
    reverted_at: row.reverted_at ? isoOf(row.reverted_at) : null,
    reversed_count: row.reversed_count === null || row.reversed_count === undefined ? null : Number(row.reversed_count),
  };
}

/** GET finance/opening-balances -> { runs }. */
export async function listOpeningRuns(siteCode) {
  const result = await pool.query(
    `
      SELECT r.id, r.created_at, r.row_count, r.counts, v.reverted_at, v.reversed_count
      FROM bulk_import_runs r
      LEFT JOIN finance_opening_reverts v ON v.run_id = r.id
      WHERE r.site_code = $1 AND r.kind = 'opening_balances'
      ORDER BY r.id DESC
      LIMIT 100
    `,
    [siteCode],
  );
  return { runs: result.rows.map(mapRun) };
}

async function loadRun(db, siteCode, runId) {
  const result = await db.query(
    `
      SELECT r.id, r.created_at, r.row_count, r.counts, v.reverted_at, v.reversed_count, v.idempotency_key
      FROM bulk_import_runs r
      LEFT JOIN finance_opening_reverts v ON v.run_id = r.id
      WHERE r.id = $1 AND r.site_code = $2 AND r.kind = 'opening_balances'
    `,
    [runId, siteCode],
  );
  return result.rows[0] ?? null;
}

const ACTIVE_SQL = `
  FROM ledger_entries l
  WHERE l.site_code = $1 AND l.source_kind = 'opening' AND l.source_id = $2 AND l.kind = 'charge'
    AND NOT EXISTS (SELECT 1 FROM ledger_entries r WHERE r.reverses_entry_id = l.id)
`;

/** GET finance/opening-balances/:runId -> geri alma önizlemesi (ters kaydı yazılacak satırlar, tek tek iptaller, sonradan tahsilat / gecikme tazminatı). */
export async function getOpeningRun(siteCode, rawRunId, db = pool) {
  const runId = parseRunId(rawRunId);
  const run = runId === null ? null : await loadRun(db, siteCode, runId);
  if (!run) throw runNotFound();
  const active = await db.query(`SELECT COUNT(*)::INT AS n, COALESCE(SUM(l.amount_minor), 0)::TEXT AS total ${ACTIVE_SQL}`, [siteCode, runId]);
  const all = await db.query(
    `SELECT COUNT(*)::INT AS n FROM ledger_entries WHERE site_code = $1 AND source_kind = 'opening' AND source_id = $2 AND kind = 'charge'`,
    [siteCode, runId],
  );
  const cutover = run.counts?.cutover_date ?? null;
  const later = await db.query(
    `
      SELECT COUNT(DISTINCT l.apartment_id)::INT AS paid_apartments
      ${ACTIVE_SQL}
        AND EXISTS (SELECT 1 FROM ledger_entries p WHERE p.site_code = l.site_code AND p.apartment_id = l.apartment_id AND p.kind = 'payment'
                    AND p.entry_date >= $3::DATE AND NOT EXISTS (SELECT 1 FROM ledger_entries pr WHERE pr.reverses_entry_id = p.id))
    `,
    [siteCode, runId, cutover ?? '1900-01-01'],
  );
  const late = await db.query(
    `
      SELECT COUNT(*)::INT AS n
      FROM ledger_entries f
      WHERE f.site_code = $1 AND f.late_fee_run_id IS NOT NULL AND f.kind = 'charge' AND f.entry_date >= $3::DATE
        AND f.apartment_id IN (SELECT l.apartment_id ${ACTIVE_SQL})
    `,
    [siteCode, runId, cutover ?? '1900-01-01'],
  );
  const total = Number(all.rows[0].n);
  const activeCount = Number(active.rows[0].n);
  return {
    run: mapRun(run),
    revert: {
      entries_to_reverse: run.reverted_at ? 0 : activeCount,
      total_minor: run.reverted_at ? 0 : Number(active.rows[0].total),
      individually_cancelled: Math.max(0, total - activeCount),
      apartments_with_later_payments: Number(later.rows[0].paid_apartments),
      late_fee_entries_after: Number(late.rows[0].n),
    },
  };
}

function parseRevertInput(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw invalidBody('İstek gövdesi bir nesne olmalıdır.');
  const reason = normalizeFreeText(body.reason, { label: 'Neden', max: REASON_MAX, required: true });
  if (typeof body.idempotency_key !== 'string' || !IDEMPOTENCY_KEY_PATTERN.test(body.idempotency_key)) {
    throw invalidBody('idempotency_key zorunludur (8-64 karakter; küçük harf, rakam, tire).');
  }
  if (!Number.isSafeInteger(body.expected_count) || body.expected_count < 0) throw invalidBody('expected_count zorunludur.');
  if (!Number.isSafeInteger(body.expected_total_minor) || body.expected_total_minor < 0) throw invalidBody('expected_total_minor zorunludur.');
  return { reason, key: body.idempotency_key, count: body.expected_count, total: body.expected_total_minor };
}

/** POST finance/opening-balances/:runId/revert -> { replayed, reversed_count, reversed_total_minor }. */
export async function revertOpeningRun({ siteCode, rawRunId, body, actor, now = new Date() }) {
  const runId = parseRunId(rawRunId);
  if (runId === null) throw runNotFound();
  const input = parseRevertInput(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const run = await loadRun(client, siteCode, runId);
    if (!run) throw runNotFound();
    if (run.reverted_at) {
      if (run.idempotency_key === input.key) {
        return { replayed: true, reversed_count: Number(run.reversed_count), reversed_total_minor: null };
      }
      throw alreadyReverted();
    }
    const dup = await client.query(`SELECT 1 FROM finance_opening_reverts WHERE site_code = $1 AND idempotency_key = $2`, [siteCode, input.key]);
    if (dup.rows[0]) throw new PlatformError(409, 'IDEMPOTENCY_CONFLICT', 'Bu işlem anahtarı başka bir geri alma için kullanılmış.');
    const apartments = await client.query(`SELECT DISTINCT l.apartment_id ${ACTIVE_SQL} ORDER BY l.apartment_id`, [siteCode, runId]);
    const ids = apartments.rows.map((row) => Number(row.apartment_id));
    if (ids.length > 0) {
      await client.query(`SELECT id FROM apartments WHERE id = ANY($1::BIGINT[]) AND site_code = $2 ORDER BY id FOR KEY SHARE`, [ids, siteCode]);
    }
    await lockActorRow(client, actorInfo);
    const openPeriod = await resolveOpenPeriod(client, siteCode, now);
    const inserted = await client.query(
      `
        INSERT INTO ledger_entries (
          site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, definition_name, payer_party, account_party,
          reverses_entry_id, reversal_reason, created_by, source_kind, source_id, fund
        )
        SELECT l.site_code, l.apartment_id, 'reversal', -l.amount_minor, $3::DATE, $4::DATE, l.due_date, l.definition_name, l.payer_party,
               COALESCE(l.account_party, CASE WHEN l.payer_party = 'tenant' THEN 'tenant' ELSE 'owner' END), l.id, $5::TEXT, $6::INTEGER, 'opening', $2::BIGINT, l.fund
        ${ACTIVE_SQL}
        ORDER BY l.id
        RETURNING amount_minor
      `,
      [siteCode, runId, openPeriod, today(now), input.reason, actorInfo.userCode],
    );
    const count = inserted.rows.length;
    const total = inserted.rows.reduce((sum, row) => sum + -Number(row.amount_minor), 0);
    if (count !== input.count || total !== input.total) {
      throw changed({ entries_to_reverse: count, total_minor: total });
    }
    await client.query(
      `INSERT INTO finance_opening_reverts (run_id, site_code, reversed_count, reversed_total_minor, idempotency_key, reverted_by) VALUES ($1, $2, $3, $4, $5, $6)`,
      [runId, siteCode, count, total, input.key, actorInfo.userCode],
    );
    await recordFinanceAudit(client, actor, 'finance.opening.reverted', siteCode, runId, {
      run_id: runId,
      reversed_count: count,
      reversed_total_minor: total,
      period: periodLabel(openPeriod),
    });
    return { replayed: false, reversed_count: count, reversed_total_minor: total };
  });
}
