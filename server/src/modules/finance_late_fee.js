// Gecikme tazminatı (Faz 4b Ö2): önizleme + onaylı, ay zincirli toplu işlem; çalıştırma listesi / satırları; son çalıştırmanın iptali; sakin açıklaması.
//
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Ö2". KARAR: OTOMATİK DEĞİL — yönetici onaylı, önizlemeli; aylık; yalnız KAPALI ve BİTMİŞ ay için; varsayılan KAPALI ve ayrıca
// sistem düzeyinde hukuk onayı bayrağına (finance.legal_ok) bağlı. Hesap finance_late_fee_calc.js'te (saf, BigInt). Yeni kalemler `kind='charge'` + `late_fee_run_id` dolu
// + `definition_name='Gecikme tazminatı'`, AÇIK dönemde, entry_date = vade = bugün. Zincir: yalnız (son aktif çalıştırma + 1 ay) / ilk çalıştırmada başlangıç ayı;
// DB tetikleyicisi de zinciri, ayın kapalı ve bitmiş olmasını, satır toplamını koruma altına alır.
// KİLİT SIRASI: sites KEY SHARE -> finance_post -> apartments (id sırasıyla KEY SHARE) -> users -> finans satırları.

import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { actorFromAuthUser } from './audit_service.js';
import {
  LATE_FEE_EXCLUDED_LIMIT,
  LATE_FEE_NAME,
  daysInMonth,
  dayNumber,
  fingerprintOf,
  lastDayOfMonth,
  lateFeeAlreadyPosted,
  lateFeeDisabled,
  lateFeeNotConfigured,
  lateFeePeriodNotClosed,
  lateFeePeriodNotEnded,
  lateFeePeriodNotNext,
  lateFeeRunNotFound,
  lateFeeRunNotVoidable,
  legalApprovalRequired,
  monthTitle,
  objectOf,
  present,
  queryInt,
  sha256Hex,
} from './finance_4b_common.js';
import { resolveOpenPeriod } from './finance_4b_guard.js';
import {
  apartmentNotFound,
  currentPeriod,
  entryNotFound,
  idempotencyConflict,
  invalidBody,
  invalidTarget,
  normalizeFreeText,
  nothingToPost,
  parseIdempotencyKey,
  parsePeriod,
  periodLabel,
  previewStale,
  today,
} from './finance_common.js';
import { effectiveFund } from './finance_funds.js';
import { lateFeeForApartment } from './finance_late_fee_calc.js';
import { minorToNumber, toBigInt } from './finance_money.js';
import { withReportSnapshot } from './finance_reports.js';
import { enabledFinanceSites, loadVisibleAccounts, residentScopeSql, viewSinceOf } from './finance_read_service.js';
import { accountPartySql } from './finance_parties.js';
import { loadEffectiveSettings, loadLateFeeChainState, readLegalOk } from './finance_settings.js';
import { isPeriodClosed, lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { apartmentLabel, parsePositiveId, toIso } from './people_common.js';

const INT32_MAX = 2147483647;
// İki hesap (İP-1A): defter satırının (takma ad `l` / `le`) hesabı.
const LEDGER_ACCOUNT = accountPartySql('l');
const LEDGER_ACCOUNT_LE = accountPartySql('le');
const calculationTimeout = () => new PlatformError(503, 'CALCULATION_TIMEOUT', 'Hesaplama zaman aşımına uğradı. Biraz sonra tekrar deneyin.');

// --- Gövde ayrıştırma --------------------------------------------------------------------------------------------------------------------------

function parseExcluded(value) {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value) || value.length > LATE_FEE_EXCLUDED_LIMIT) {
    throw invalidTarget(`En fazla ${LATE_FEE_EXCLUDED_LIMIT} daire muaf tutulabilir.`);
  }
  const ids = new Set();
  for (const entry of value) {
    const id = parsePositiveId(entry);
    if (id === null) {
      throw invalidTarget('Muaf tutulacak daire geçersiz.');
    }
    ids.add(id);
  }
  return [...ids].sort((a, b) => a - b);
}

export function parsePreviewBody(body) {
  const input = objectOf(body);
  return { period: present(input.period) ? parsePeriod(input.period, 'Dönem') : null, excluded: parseExcluded(input.excluded_apartment_ids) };
}

export function parsePostBody(body) {
  const input = objectOf(body);
  if (!present(input.period)) {
    throw invalidBody('Dönem zorunludur.');
  }
  const count = input.expected_apartment_count;
  if (typeof count !== 'number' || !Number.isInteger(count) || count < 0 || count > 100000) {
    throw invalidBody('Beklenen daire sayısı geçersiz.');
  }
  if (typeof input.expected_total_minor !== 'number' || !Number.isSafeInteger(input.expected_total_minor) || input.expected_total_minor < 0) {
    throw invalidBody('Beklenen toplam geçersiz.');
  }
  if (typeof input.expected_hash !== 'string' || !/^[0-9a-f]{64}$/.test(input.expected_hash)) {
    throw invalidBody('Önizleme özeti (expected_hash) zorunludur; önizlemeyi yenileyin.');
  }
  if (input.record_empty !== undefined && input.record_empty !== null && typeof input.record_empty !== 'boolean') {
    throw invalidBody('Boş ay kaydı seçeneği geçersiz (evet veya hayır olmalıdır).');
  }
  return {
    period: parsePeriod(input.period, 'Dönem'),
    excluded: parseExcluded(input.excluded_apartment_ids),
    recordEmpty: input.record_empty === true,
    expectedTotal: input.expected_total_minor,
    expectedCount: count,
    expectedHash: input.expected_hash,
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

export function parseVoidBody(body) {
  const input = objectOf(body);
  return {
    reason: normalizeFreeText(input.reason, { label: 'Neden', max: 200, required: true }),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

// --- Plan ----------------------------------------------------------------------------------------------------------------------------------

async function loadApartments(db, siteCode, { lock }) {
  const result = await db.query(
    `
      SELECT a.id, a.unit_label, b.block_name, b.sort_order AS block_sort, a.sort_order AS apt_sort, a.responsible_party, a.is_active
      FROM apartments a INNER JOIN site_blocks b ON b.id = a.block_id
      WHERE a.site_code = $1
      ORDER BY a.id
      ${lock ? 'FOR KEY SHARE OF a' : ''}
    `,
    [siteCode],
  );
  return (result.rows ?? []).map((row) => ({
    id: Number(row.id),
    label: apartmentLabel(row.block_name, row.unit_label),
    blockName: row.block_name ?? null,
    payerParty: row.responsible_party,
    isActive: row.is_active === true,
    blockSort: Number(row.block_sort),
    aptSort: Number(row.apt_sort),
  }));
}

/**
 * Aya kadar (entry_date <= p2) tüm defter satırları, daire başına ve daire içinde HESAP başına gruplanmış (İP-1A: tazminat hesap bazında; 052 öncesi satırın
 * hesabı payer_party'den türetilir); gün sayıları SQL'de tamsayıya çevrilir. Dönüş: daire kimliği -> { owner: satırlar[], tenant: satırlar[] }.
 */
async function loadLedgerRows(db, siteCode, p2Iso) {
  const result = await db.query(
    `
      SELECT l.id, l.apartment_id, l.kind, l.amount_minor::TEXT AS amount, (l.entry_date - DATE '1970-01-01') AS entry_day,
             CASE WHEN l.due_date IS NULL THEN NULL ELSE (l.due_date - DATE '1970-01-01') END AS due_day,
             (l.late_fee_run_id IS NOT NULL) AS late_fee, l.reverses_entry_id, ${LEDGER_ACCOUNT} AS account_party,
             l.fund, l.source_kind, l.definition_id, fd.charge_party AS def_charge_party, fd.kind AS def_kind
      FROM ledger_entries l
      LEFT JOIN fee_definitions fd ON fd.id = l.definition_id
      WHERE l.site_code = $1 AND l.entry_date <= $2::DATE
      ORDER BY l.apartment_id, l.id
    `,
    [siteCode, p2Iso],
  );
  const byApartment = new Map();
  for (const row of result.rows ?? []) {
    const key = Number(row.apartment_id);
    let accounts = byApartment.get(key);
    if (!accounts) {
      accounts = { owner: [], tenant: [] };
      byApartment.set(key, accounts);
    }
    const list = accounts[row.account_party === 'tenant' ? 'tenant' : 'owner'];
    list.push({
      id: Number(row.id),
      kind: row.kind,
      amount: toBigInt(row.amount),
      entryDay: Number(row.entry_day),
      dueDay: row.due_day === null ? null : Number(row.due_day),
      lateFee: row.late_fee === true,
      reversesId: row.reverses_entry_id === null ? null : Number(row.reverses_entry_id),
      // Kasa: borcun (etkin) kasasi; 080 oncesi satirda tanimdan turetilir
      fund: effectiveFund({ ...row, amount_minor: row.amount }) ?? 'operating',
    });
  }
  return byApartment;
}

export function settingsParams(settings) {
  return {
    rate_bp: settings.late_fee_rate_bp,
    method: settings.late_fee_method,
    grace_days: settings.late_fee_grace_days,
    settings_version: settings.settings_version,
  };
}

/**
 * preview_hash = sha256('v1' + ayar anlık görüntüsü + dönem + sıralı apartment_id:amount_minor:payer_party[:hesap] + muaf kümesi). İP-1A: satır hesap başınadır
 * (aynı dairenin iki hesabı iki satır); hesap özete girer.
 */
export function planHashOf({ params, period, lines, excluded }) {
  return sha256Hex(
    `v1|${params.rate_bp}|${params.method}|${params.grace_days}|${params.settings_version}|${period}|${lines
      .map((line) => `${line.apartmentId}:${line.amount}:${line.payerParty}${line.accountParty === undefined ? '' : `:${line.accountParty}`}`)
      .join(',')}|${excluded.join(',')}`,
  );
}

/**
 * Tazminat planı. lock: yazma yolunda daire satırları id sırasıyla FOR KEY SHARE kilitlenir. Kilit yoksa salt okuma.
 * @returns {Promise<{ lines, waived, inactiveSkipped, zeroCount, total, hash, window }>}
 */
export async function computeLateFeePlan(db, siteCode, { period, settings, excluded, lock = false }) {
  const params = settingsParams(settings);
  const periodEnd = lastDayOfMonth(period);
  const divisor = settings.late_fee_method === 'daily_30' ? 30 : daysInMonth(period);
  const p1 = dayNumber(period);
  const p2 = dayNumber(periodEnd);
  let apartments;
  let ledger;
  try {
    apartments = await loadApartments(db, siteCode, { lock });
    ledger = await loadLedgerRows(db, siteCode, periodEnd);
  } catch (error) {
    if (error?.code === '57014') {
      throw calculationTimeout();
    }
    throw error;
  }
  const excludedSet = new Set(excluded);
  const knownIds = new Set(apartments.map((apt) => apt.id));
  for (const id of excluded) {
    if (!knownIds.has(id)) {
      throw invalidTarget('Muaf tutulacak daire bu siteye ait değil.');
    }
  }
  const lines = [];
  const waived = [];
  const inactiveSkipped = [];
  let zeroCount = 0;
  for (const apt of apartments) {
    const accounts = ledger.get(apt.id);
    if (!accounts) {
      continue;
    }
    if (!apt.isActive) {
      // Pasif dairenin herhangi bir hesabı borçluysa listelenir (hesaplanmaz).
      const indebted = ['owner', 'tenant'].some((party) => accounts[party].reduce((acc, row) => acc + row.amount, 0n) > 0n);
      if (indebted) {
        inactiveSkipped.push({ apartment_id: apt.id, label: apt.label });
      }
      continue;
    }
    // İki hesap (İP-1A): tazminat HESAP BAZINDA (her hesabın kendi mahsubu); aynı dairenin iki hesabı iki satır olabilir. Muafiyet daire başınadır.
    for (const party of ['owner', 'tenant']) {
      const rows = accounts[party];
      if (rows.length === 0) {
        continue;
      }
      const result = lateFeeForApartment(rows, { p1, p2, graceDays: settings.late_fee_grace_days, rateBp: settings.late_fee_rate_bp, divisor });
      if (result.base === 0n) {
        continue;
      }
      if (result.fee === 0n) {
        zeroCount += 1;
        continue;
      }
      if (excludedSet.has(apt.id)) {
        waived.push({ apartment_id: apt.id, label: apt.label, account_party: party, computed_minor: minorToNumber(result.fee) });
        continue;
      }
      lines.push({
        apartmentId: apt.id,
        accountParty: party,
        label: apt.label,
        blockName: apt.blockName,
        payerParty: apt.payerParty,
        blockSort: apt.blockSort,
        aptSort: apt.aptSort,
        amount: result.fee,
        baseDay: result.base,
        peak: result.peak,
        breakdown: result.breakdown,
        fund: result.fund,
      });
    }
  }
  let total = 0n;
  for (const line of lines) {
    total += line.amount;
  }
  return {
    lines,
    waived,
    inactiveSkipped,
    zeroCount,
    total,
    hash: planHashOf({ params, period, lines, excluded }),
    window: { from: period, to: periodEnd, days: p2 - p1 + 1 },
    params,
  };
}

const mapPlanLine = (line) => ({
  apartment_id: line.apartmentId,
  // İki hesap (İP-1A): tazminatın yazılacağı hesap
  account_party: line.accountParty ?? null,
  label: line.label,
  block_name: line.blockName,
  payer_party: line.payerParty,
  amount_minor: minorToNumber(line.amount),
  base_day_minor: minorToNumber(line.baseDay),
  peak_overdue_minor: minorToNumber(line.peak),
  breakdown: line.breakdown.map((part) => ({ from: part.from, to: part.to, overdue_minor: minorToNumber(part.overdue) })),
});

/** Yayın kuralları: engel kodları (önizleme `blockers`, onay yolu ilk engeli hata olarak fırlatır). */
async function evaluateBlockers(db, siteCode, period, settings, chain, now) {
  const blockers = [];
  if (!settings.late_fee_enabled) blockers.push('LATE_FEE_DISABLED');
  if (!(await readLegalOk(db))) blockers.push('LEGAL_APPROVAL_REQUIRED');
  if (chain.nextPeriod === null) {
    blockers.push('LATE_FEE_NOT_CONFIGURED');
    return blockers;
  }
  if (period !== chain.nextPeriod) {
    const posted = await db.query(`SELECT 1 FROM late_fee_runs WHERE site_code = $1 AND period = $2::DATE AND status = 'active' LIMIT 1`, [siteCode, period]);
    blockers.push(posted.rows?.[0] ? 'LATE_FEE_ALREADY_POSTED' : 'LATE_FEE_PERIOD_NOT_NEXT');
  }
  if (!(await isPeriodClosed(db, siteCode, period))) blockers.push('LATE_FEE_PERIOD_NOT_CLOSED');
  if (lastDayOfMonth(period) >= today(now)) blockers.push('LATE_FEE_PERIOD_NOT_ENDED');
  return blockers;
}

const BLOCKER_ERRORS = {
  LATE_FEE_DISABLED: () => lateFeeDisabled(),
  LEGAL_APPROVAL_REQUIRED: () => legalApprovalRequired(),
  LATE_FEE_NOT_CONFIGURED: () => lateFeeNotConfigured(),
  LATE_FEE_ALREADY_POSTED: () => lateFeeAlreadyPosted(),
  LATE_FEE_PERIOD_NOT_CLOSED: () => lateFeePeriodNotClosed(),
  LATE_FEE_PERIOD_NOT_ENDED: () => lateFeePeriodNotEnded(),
};

/**
 * POST late-fee/preview (YAZMAZ). Ağır hesap: site başına eşzamanlılık yuvası ('preview'), tek REPEATABLE READ READ ONLY anlık görüntü ve statement_timeout altında
 * (sayfa kayması yok; aşırı yük REPORT_BUSY 503).
 */
export async function previewLateFee({ siteCode, body, now = new Date() }, db = pool) {
  const input = parsePreviewBody(body);
  return withReportSnapshot(siteCode, (client) => previewLateFeeIn(client, { siteCode, input, now }), db, { slot: 'preview' });
}

async function previewLateFeeIn(db, { siteCode, input, now }) {
  const settings = await loadEffectiveSettings(db, siteCode);
  const chain = await loadLateFeeChainState(db, siteCode, settings);
  const period = input.period ?? chain.nextPeriod;
  const expected = chain.nextPeriod;
  const base = {
    expected_period: expected === null ? null : periodLabel(expected),
    settings: { rate_bp: settings.late_fee_rate_bp, method: settings.late_fee_method, grace_days: settings.late_fee_grace_days, settings_version: settings.settings_version },
    currency: 'TRY',
  };
  if (period === null) {
    return { ...base, empty: false, period: null, window: null, total_minor: 0, apartment_count: 0, lines: [], waived: [], inactive_skipped: [], zero_amount_count: 0, preview_hash: null, can_post: false, blockers: ['LATE_FEE_NOT_CONFIGURED'] };
  }
  const blockers = await evaluateBlockers(db, siteCode, period, settings, chain, now);
  const plan = await computeLateFeePlan(db, siteCode, { period, settings, excluded: input.excluded });
  // Satır yoksa (kimse geç ödemedi / hepsi muaf): `empty: true`; `can_post` diğer engellere bağlıdır. Zincir bu ayı "işaret çalıştırması" (record_empty) ile geçer; aksi halde sıradaki
  // aylar kilitlenirdi (R10 P1-4).
  return {
    ...base,
    empty: plan.lines.length === 0,
    period: periodLabel(period),
    window: plan.window,
    total_minor: minorToNumber(plan.total),
    apartment_count: plan.lines.length,
    lines: plan.lines.map(mapPlanLine),
    waived: plan.waived,
    inactive_skipped: plan.inactiveSkipped,
    zero_amount_count: plan.zeroCount,
    preview_hash: plan.hash,
    can_post: blockers.length === 0,
    blockers,
  };
}

// --- Okuma ---------------------------------------------------------------------------------------------------------------------------------

function mapRunRow(row) {
  const total = toBigInt(row.total_minor);
  return {
    id: Number(row.id),
    period: periodLabel(row.period),
    status: row.status,
    total_minor: minorToNumber(total),
    net_total_minor: minorToNumber(total - toBigInt(row.reversed ?? '0')),
    apartment_count: Number(row.apartment_count),
    empty: Number(row.apartment_count) === 0,
    waived_count: Number(row.waived_count ?? 0),
    params: row.params,
    posted_at: toIso(row.posted_at),
    posted_by_name: row.posted_by_name ?? null,
    voided_at: toIso(row.voided_at),
    voided_by_name: row.voided_by_name ?? null,
  };
}

const RUN_SELECT = `
  SELECT
    r.id, to_char(r.period, 'YYYY-MM-DD') AS period, r.status, r.total_minor::TEXT AS total_minor, r.apartment_count, cardinality(r.waived_apartment_ids) AS waived_count,
    r.params, r.posted_at, pu.full_name AS posted_by_name, r.voided_at, vu.full_name AS voided_by_name, r.preview_hash, r.request_fingerprint, r.void_reason, r.voided_by,
    (SELECT COALESCE(SUM(ln.amount_minor), 0)::TEXT FROM late_fee_run_lines ln
      WHERE ln.run_id = r.id AND EXISTS (SELECT 1 FROM ledger_entries rv WHERE rv.reverses_entry_id = ln.ledger_entry_id)) AS reversed
  FROM late_fee_runs r
  LEFT JOIN users pu ON pu.user_code = r.posted_by
  LEFT JOIN users vu ON vu.user_code = r.voided_by
`;

/** GET late-fee/runs -> { items, total, next_period, voidable_run_id }. */
export async function listLateFeeRuns(siteCode, query = {}, db = pool) {
  const limit = queryInt(query.limit, { min: 1, max: 200, fallback: 50 });
  const offset = queryInt(query.offset, { min: 0, max: 100000, fallback: 0 });
  const settings = await loadEffectiveSettings(db, siteCode);
  const chain = await loadLateFeeChainState(db, siteCode, settings);
  const total = await db.query(`SELECT COUNT(*)::INTEGER AS n FROM late_fee_runs WHERE site_code = $1`, [siteCode]);
  const result = await db.query(`${RUN_SELECT} WHERE r.site_code = $1 ORDER BY r.period DESC, r.id DESC LIMIT $2 OFFSET $3`, [siteCode, limit, offset]);
  return {
    items: (result.rows ?? []).map(mapRunRow),
    total: Number(total.rows[0].n),
    next_period: chain.nextPeriod === null ? null : periodLabel(chain.nextPeriod),
    voidable_run_id: chain.lastRunId,
  };
}

/** GET late-fee/runs/:id/lines. */
export async function listLateFeeRunLines(siteCode, rawId, query = {}, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw lateFeeRunNotFound();
  }
  const limit = queryInt(query.limit, { min: 1, max: 500, fallback: 100 });
  const offset = queryInt(query.offset, { min: 0, max: 100000, fallback: 0 });
  const run = await db.query(`SELECT id FROM late_fee_runs WHERE id = $1 AND site_code = $2`, [id, siteCode]);
  if (!run.rows?.[0]) {
    throw lateFeeRunNotFound();
  }
  const total = await db.query(`SELECT COUNT(*)::INTEGER AS n FROM late_fee_run_lines WHERE run_id = $1`, [id]);
  const result = await db.query(
    `
      SELECT ln.apartment_id, ln.apartment_label, ln.amount_minor::TEXT AS amount, ln.base_day_minor::TEXT AS base_day, ln.peak_overdue_minor::TEXT AS peak, ln.breakdown, ln.ledger_entry_id,
             EXISTS (SELECT 1 FROM ledger_entries rv WHERE rv.reverses_entry_id = ln.ledger_entry_id) AS reversed,
             (SELECT ${LEDGER_ACCOUNT_LE} FROM ledger_entries le WHERE le.id = ln.ledger_entry_id) AS account_party
      FROM late_fee_run_lines ln WHERE ln.run_id = $1 ORDER BY ln.apartment_id, ln.ledger_entry_id LIMIT $2 OFFSET $3
    `,
    [id, limit, offset],
  );
  return {
    items: (result.rows ?? []).map((row) => ({
      apartment_id: Number(row.apartment_id),
      label: row.apartment_label,
      amount_minor: minorToNumber(row.amount),
      base_day_minor: minorToNumber(row.base_day),
      peak_overdue_minor: minorToNumber(row.peak),
      breakdown: (row.breakdown ?? []).map((part) => ({ from: part.from, to: part.to, overdue_minor: part.overdue_minor })),
      ledger_entry_id: Number(row.ledger_entry_id),
      reversed: row.reversed === true,
      account_party: row.account_party ?? null,
    })),
    total: Number(total.rows[0].n),
  };
}

// --- Onay (post) -------------------------------------------------------------------------------------------------------------------------

const postFingerprint = (input) => fingerprintOf({ v: 1, kind: 'late_fee_post', period: input.period, excluded: input.excluded, record_empty: input.recordEmpty });

async function findRunByKey(db, siteCode, key) {
  const result = await db.query(`${RUN_SELECT} WHERE r.site_code = $1 AND r.idempotency_key = $2`, [siteCode, key]);
  return result.rows?.[0] ?? null;
}

/** POST late-fee/post -> { replayed, run, entries_count }. */
export async function postLateFee({ siteCode, body, actor, now = new Date() }) {
  const input = parsePostBody(body);
  const actorInfo = actorFromAuthUser(actor);
  const fingerprint = postFingerprint(input);
  return withFinanceTransaction(siteCode, async (client) => {
    const replay = await findRunByKey(client, siteCode, input.idempotencyKey);
    if (replay) {
      if (replay.request_fingerprint !== fingerprint) {
        throw idempotencyConflict();
      }
      return { replayed: true, run: mapRunRow(replay), entries_count: Number(replay.apartment_count) };
    }
    const settings = await loadEffectiveSettings(client, siteCode);
    const chain = await loadLateFeeChainState(client, siteCode, settings);
    const blockers = await evaluateBlockers(client, siteCode, input.period, settings, chain, now);
    if (blockers.length > 0) {
      const code = blockers[0];
      if (code === 'LATE_FEE_PERIOD_NOT_NEXT') {
        throw lateFeePeriodNotNext(chain.nextPeriod === null ? null : periodLabel(chain.nextPeriod));
      }
      throw BLOCKER_ERRORS[code]();
    }
    const plan = await computeLateFeePlan(client, siteCode, { period: input.period, settings, excluded: input.excluded, lock: true });
    const marker = plan.lines.length === 0;
    if (marker && !input.recordEmpty) {
      throw nothingToPost();
    }
    if (!marker && input.recordEmpty) {
      // yönetici "bu ay tazminat yok" diye onayladı, ama kilit altında yeniden hesapta satır çıktı
      throw previewStale({ total_minor: minorToNumber(plan.total), apartment_count: plan.lines.length, preview_hash: plan.hash });
    }
    if (plan.total !== BigInt(input.expectedTotal) || plan.lines.length !== input.expectedCount || plan.hash !== input.expectedHash) {
      throw previewStale({ total_minor: minorToNumber(plan.total), apartment_count: plan.lines.length, preview_hash: plan.hash });
    }
    await lockActorRow(client, actorInfo);
    const openPeriod = await resolveOpenPeriod(client, siteCode, now);
    const todayIsoDate = today(now);
    const inserted = await client.query(
      `
        INSERT INTO late_fee_runs (
          site_code, period, params, total_minor, apartment_count, waived_apartment_ids, inactive_skipped_count, zero_amount_count, preview_hash, idempotency_key,
          request_fingerprint, posted_by
        )
        VALUES ($1, $2::DATE, $3::JSONB, $4::BIGINT, $5, $6::BIGINT[], $7, $8, $9, $10, $11, $12)
        RETURNING id
      `,
      [
        siteCode,
        input.period,
        JSON.stringify(plan.params),
        plan.total.toString(),
        plan.lines.length,
        input.excluded,
        plan.inactiveSkipped.length,
        plan.zeroCount,
        plan.hash,
        input.idempotencyKey,
        fingerprint,
        actorInfo.userCode,
      ],
    );
    const runId = Number(inserted.rows[0].id);
    const lines = [...plan.lines].sort((a, b) => a.apartmentId - b.apartmentId || (a.accountParty < b.accountParty ? -1 : a.accountParty > b.accountParty ? 1 : 0));
    if (marker) {
      // İŞARET ÇALIŞTIRMASI: tutarsız ve satırsız (DB: total_minor = 0 = apartment_count); defter satırı YAZILMAZ, zincir bu ayı geçmiş sayar.
      await recordFinanceAudit(client, actor, 'finance.latefee.posted', siteCode, runId, {
        period: periodLabel(input.period),
        total_minor: 0,
        apartment_count: 0,
        waived_count: input.excluded.length,
        rate_bp: plan.params.rate_bp,
        method: plan.params.method,
        grace_days: plan.params.grace_days,
        empty: true,
      });
      return { replayed: false, run: mapRunRow(await findRunById(client, siteCode, runId)), entries_count: 0 };
    }
    const written = await client.query(
      `
        INSERT INTO ledger_entries (
          site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, definition_name, description, late_fee_run_id, payer_party, created_by,
          account_party, fund
        )
        SELECT $1, t.apartment_id, 'charge', t.amount, $2::DATE, $3::DATE, $3::DATE, $4::TEXT, $5::TEXT, $6, t.payer, $7, t.account, t.fund
        FROM unnest($8::BIGINT[], $9::BIGINT[], $10::TEXT[], $11::TEXT[], $12::TEXT[]) AS t(apartment_id, amount, payer, account, fund)
        ORDER BY t.apartment_id, t.account
        RETURNING id, apartment_id, account_party
      `,
      [
        siteCode,
        openPeriod,
        todayIsoDate,
        LATE_FEE_NAME,
        `${monthTitle(input.period)} gecikme tazminatı`,
        runId,
        actorInfo.userCode,
        lines.map((line) => String(line.apartmentId)),
        lines.map((line) => line.amount.toString()),
        lines.map((line) => line.payerParty),
        lines.map((line) => line.accountParty),
        // Kasa: tazminatin kasasi = vadesi gecen anaparanin agirlikli oldugu kasa (docs/PLATFORM_FINANS_KASALAR.md 2)
        lines.map((line) => line.fund ?? 'operating'),
      ],
    );
    if (written.rowCount !== lines.length) {
      throw new Error(`tazminat satir sayisi uyusmuyor (${written.rowCount} / ${lines.length})`);
    }
    const lineKey = (apartmentId, accountParty) => `${apartmentId}:${accountParty}`;
    const entryByLine = new Map(written.rows.map((row) => [lineKey(Number(row.apartment_id), row.account_party), Number(row.id)]));
    await client.query(
      `
        INSERT INTO late_fee_run_lines (run_id, site_code, apartment_id, apartment_label, amount_minor, base_day_minor, peak_overdue_minor, breakdown, ledger_entry_id, account_party)
        SELECT $1, $2, t.apartment_id, t.label, t.amount, t.base_day, t.peak, t.breakdown::JSONB, t.entry_id, t.account
        FROM unnest($3::BIGINT[], $4::TEXT[], $5::BIGINT[], $6::BIGINT[], $7::BIGINT[], $8::TEXT[], $9::BIGINT[], $10::TEXT[]) AS t(apartment_id, label, amount, base_day, peak, breakdown, entry_id, account)
      `,
      [
        runId,
        siteCode,
        lines.map((line) => String(line.apartmentId)),
        lines.map((line) => line.label),
        lines.map((line) => line.amount.toString()),
        lines.map((line) => line.baseDay.toString()),
        lines.map((line) => line.peak.toString()),
        lines.map((line) => JSON.stringify(line.breakdown.map((part) => ({ from: part.from, to: part.to, overdue_minor: minorToNumber(part.overdue) })))),
        lines.map((line) => String(entryByLine.get(lineKey(line.apartmentId, line.accountParty)))),
        lines.map((line) => line.accountParty),
      ],
    );
    await recordFinanceAudit(client, actor, 'finance.latefee.posted', siteCode, runId, {
      period: periodLabel(input.period),
      total_minor: minorToNumber(plan.total),
      apartment_count: plan.lines.length,
      waived_count: input.excluded.length,
      rate_bp: plan.params.rate_bp,
      method: plan.params.method,
      grace_days: plan.params.grace_days,
    });
    return { replayed: false, run: mapRunRow(await findRunById(client, siteCode, runId)), entries_count: plan.lines.length };
  });
}

async function findRunById(db, siteCode, id) {
  const result = await db.query(`${RUN_SELECT} WHERE r.id = $1 AND r.site_code = $2`, [id, siteCode]);
  return result.rows?.[0] ?? null;
}

// --- İptal (void) ----------------------------------------------------------------------------------------------------------------------------

/** POST late-fee/runs/:id/void -> { replayed, run, reversed_count, reversed_total_minor }. Yalnız SON aktif çalıştırma. */
export async function voidLateFeeRun({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw lateFeeRunNotFound();
  }
  const input = parseVoidBody(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const run = await findRunById(client, siteCode, id);
    if (!run) {
      throw lateFeeRunNotFound();
    }
    const replay = await client.query(
      `
        SELECT l.id, l.reverses_entry_id, l.reversal_reason FROM ledger_entries l
        WHERE l.site_code = $1 AND l.idempotency_key = $2
      `,
      [siteCode, input.idempotencyKey],
    );
    if (replay.rows?.[0]) {
      const original = await client.query(`SELECT late_fee_run_id FROM ledger_entries WHERE id = $1`, [Number(replay.rows[0].reverses_entry_id)]);
      if (Number(original.rows?.[0]?.late_fee_run_id) !== id || (replay.rows[0].reversal_reason ?? null) !== input.reason) {
        throw idempotencyConflict();
      }
      // ÖZGÜN yanıtla aynı sayılar: o çağrının yazdığı ters kayıtlar anahtarlı ilk satırla AYNI işlemde (created_at) yazılmıştır
      const original1 = await client.query(
        `
          SELECT COUNT(*)::INTEGER AS n, COALESCE(SUM(-amount_minor), 0)::TEXT AS total
          FROM ledger_entries
          WHERE site_code = $1 AND late_fee_run_id = $2 AND kind = 'reversal' AND created_at = (SELECT created_at FROM ledger_entries WHERE id = $3)
        `,
        [siteCode, id, Number(replay.rows[0].id)],
      );
      return { replayed: true, run: mapRunRow(run), reversed_count: Number(original1.rows[0].n), reversed_total_minor: minorToNumber(toBigInt(original1.rows[0].total)) };
    }
    // Tüm satırlar daha önce tek tek ters kaydedildiyse iptal HİÇ defter satırı yazmaz, anahtar kaydedilemez: aynı çalıştırmayı aynı kullanıcının aynı nedenle iptal etmesi
    // tekrar sayılır (200); farklı neden / kullanıcı / hâlâ aktif olmayan çalıştırma 409 LATE_FEE_RUN_NOT_VOIDABLE (R10 P2-3).
    if (run.status === 'voided' && run.void_reason === input.reason && actorInfo.userCode !== null && Number(run.voided_by) === actorInfo.userCode) {
      return { replayed: true, run: mapRunRow(run), reversed_count: 0, reversed_total_minor: 0 };
    }
    const last = await client.query(`SELECT id FROM late_fee_runs WHERE site_code = $1 AND status = 'active' ORDER BY period DESC LIMIT 1`, [siteCode]);
    if (run.status !== 'active' || Number(last.rows?.[0]?.id) !== id) {
      throw lateFeeRunNotVoidable();
    }
    // KİLİT SIRASI: daire satırları (id sırasıyla) -> kullanıcı -> finans satırları
    await client.query(
      `SELECT a.id FROM apartments a WHERE a.id IN (SELECT apartment_id FROM late_fee_run_lines WHERE run_id = $1) ORDER BY a.id FOR KEY SHARE OF a`,
      [id],
    );
    await lockActorRow(client, actorInfo);
    const openPeriod = await resolveOpenPeriod(client, siteCode, now);
    const reversed = await client.query(
      `
        INSERT INTO ledger_entries (
          site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, definition_name, payer_party, reverses_entry_id, reversal_reason, late_fee_run_id,
          idempotency_key, created_by, account_party, fund
        )
        SELECT l.site_code, l.apartment_id, 'reversal', -l.amount_minor, $2::DATE, $3::DATE, l.due_date, l.definition_name, l.payer_party, l.id, $4, l.late_fee_run_id,
               CASE WHEN ROW_NUMBER() OVER (ORDER BY l.apartment_id, l.id) = 1 THEN $5 ELSE NULL END, $6, ${LEDGER_ACCOUNT}, l.fund
        FROM ledger_entries l
        INNER JOIN late_fee_run_lines ln ON ln.ledger_entry_id = l.id
        WHERE ln.run_id = $1 AND NOT EXISTS (SELECT 1 FROM ledger_entries rv WHERE rv.reverses_entry_id = l.id)
        ORDER BY l.apartment_id, l.id
        RETURNING amount_minor::TEXT AS amount
      `,
      [id, openPeriod, today(now), input.reason, input.idempotencyKey, actorInfo.userCode],
    );
    let reversedTotal = 0n;
    for (const row of reversed.rows) {
      reversedTotal += toBigInt(row.amount);
    }
    await client.query(`UPDATE late_fee_runs SET status = 'voided', voided_by = $2, voided_at = NOW(), void_reason = $3 WHERE id = $1 AND status = 'active'`, [
      id,
      actorInfo.userCode,
      input.reason,
    ]);
    await recordFinanceAudit(client, actor, 'finance.latefee.voided', siteCode, id, {
      period: run.period.slice(0, 7),
      reversed_count: reversed.rowCount,
      reversed_total_minor: minorToNumber(-reversedTotal),
    });
    return {
      replayed: false,
      run: mapRunRow(await findRunById(client, siteCode, id)),
      reversed_count: reversed.rowCount,
      reversed_total_minor: minorToNumber(-reversedTotal),
    };
  });
}

// --- Sakin açıklaması ------------------------------------------------------------------------------------------------------------------------

/**
 * GET /app/my-finance/entries/:entryId/late-fee: kalem çağıranın görünümlerinden birinin (İP-1A: kendi hesabı ya da `both` dairede malike salt okunur
 * kiracı hesabı) tazminat kalemi olmalı (aksi 404).
 */
export async function getMyLateFeeExplanation(authUser, rawEntryId, db = pool) {
  const entryId = parsePositiveId(rawEntryId);
  const userCode = parsePositiveId(authUser?.user_code ?? authUser?.userCode ?? authUser?.id, INT32_MAX);
  if (entryId === null || userCode === null) {
    throw entryNotFound();
  }
  const visible = await loadVisibleAccounts(db, userCode);
  const enabled = await enabledFinanceSites(db, [...new Set(visible.map((row) => Number(row.site_code)))]);
  const views = visible
    .filter((row) => enabled.has(Number(row.site_code)))
    .flatMap((row) => row.views.map((view) => ({ apartmentId: Number(row.apartment_id), accountParty: view.account_party, since: viewSinceOf(view, today()) })));
  if (views.length === 0) {
    throw entryNotFound();
  }
  // Sakin kapsamı: kalemin hesaplandığı ay sakinin taşınma ayından önceyse kalem yoktur (404; residentScopeSql); kalem görünümün HESABINDA olmalı.
  const result = await db.query(
    `
      SELECT to_char(r.period, 'YYYY-MM-DD') AS period, r.params, ln.amount_minor::TEXT AS amount, ln.base_day_minor::TEXT AS base_day, ln.breakdown
      FROM unnest($2::BIGINT[], $3::TEXT[], $4::DATE[]) AS vis(apartment_id, account_party, since)
      INNER JOIN ledger_entries l ON l.apartment_id = vis.apartment_id AND ${LEDGER_ACCOUNT} = vis.account_party
      INNER JOIN late_fee_run_lines ln ON ln.ledger_entry_id = l.id
      INNER JOIN late_fee_runs r ON r.id = ln.run_id
      WHERE l.id = $1 AND l.kind = 'charge' AND l.late_fee_run_id IS NOT NULL AND ${residentScopeSql('l', 'vis.since')}
      LIMIT 1
    `,
    [entryId, views.map((view) => view.apartmentId), views.map((view) => view.accountParty), views.map((view) => view.since)],
  );
  const row = result.rows?.[0];
  if (!row) {
    throw entryNotFound();
  }
  return {
    period: periodLabel(row.period),
    rate_bp: Number(row.params.rate_bp),
    method: row.params.method,
    grace_days: Number(row.params.grace_days),
    amount_minor: minorToNumber(row.amount),
    base_day_minor: minorToNumber(row.base_day),
    segments: (row.breakdown ?? []).map((part) => ({ from: part.from, to: part.to, overdue_minor: part.overdue_minor })),
  };
}

void apartmentNotFound;
void currentPeriod;
