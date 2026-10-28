// İki kasa (İşletme / Yatırım ve Demirbaş Fon): kasa bakiyeleri, kasa hareket dökümü ve kasalar arası aktarım (ters aktarımla düzeltme).
//
// Sözleşme: docs/PLATFORM_FINANS_KASALAR.md. Kasa bir BAKİYEDİR; fiziksel hesapların (finance_accounts) üstünde mantıksal bir ayrımdır.
//  - Kasa bakiyesi = açılış + dağıtılmış tahsilatlar - giderler ± aktarımlar (+ hesap düzeltme hareketleri, İşletme'ye). Açılış: hesapların açılış bakiyeleri İşletme'ye, Fon'a 0.
//  - Tahsilatlar `allocateFunds` (finance_funds.js; TEK saf işlev) ile kasalara dağıtılır; YALNIZ bir kasa / banka hesabına eşlenmiş (collection hareketi olan) tahsilatlar sayılır
//    (eşlenmemişler `unassigned_payments` olarak ayrı raporlanır). Henüz borca dağıtılmamış ödeme AVANSTIR ve iki kasaya da yazılmaz.
//  - DEĞİŞMEZ: İşletme + Fon + avans = tüm hesapların toplam bakiyesi (`difference_minor` = 0). Güncel (bugünkü) dağıtım esas alınır: sonradan ters çevrilmiş tahsilat / iptal
//    edilmiş gider hiçbir kasayı etkilemez; bu yüzden geçmiş bir `to` tarihli görünümde fiziksel hesap toplamıyla fark çıkabilir (fiziksel hesap hareketleri kendi tarihindedir).
//  - Kasa aktarımı (finance_fund_transfers) EKLEMELİDİR; düzeltme yalnız TERS aktarımla (yönler yer değiştirir). Fiziksel hesap hareketi doğurmaz.
//  - Okuma uçları tek REPEATABLE READ READ ONLY anlık görüntüde çalışır (withReportSnapshot). Yazmalar withFinanceTransaction: sites KEY SHARE -> finance_post advisory -> users(işlem yapan) -> finans satırları.
//  - Audit `details` yalnız kasa adı / tutar / dönem / kimlik içerir (açıklama ve neden metni ASLA).

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { fingerprintOf, objectOf, queryDate, queryInt } from './finance_4b_common.js';
import { assertWritableDate, resolveOpenPeriod } from './finance_4b_guard.js';
import { countUnassignedPayments, loadAccountPolicy } from './finance_accounts.js';
import { idempotencyConflict, invalidBody, invalidQuery, normalizeFreeText, parseIdempotencyKey, periodLabel, parseIsoDate, requireMinor, today } from './finance_common.js';
import {
  FUND_LABELS,
  FUND_SHORT_LABELS,
  allocateFunds,
  fundTransferAlreadyReversed,
  fundTransferNotFound,
  fundTransferNotReversible,
  isFund,
  loadFundLedger,
  parseFundField,
} from './finance_funds.js';
import { PlatformError } from './errors.js';
import { minorToNumber, toBigInt } from './finance_money.js';
import { withReportSnapshot } from './finance_reports.js';
import { lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { apartmentLabel, parsePositiveId, toIso } from './people_common.js';

export const MAX_FUND_TRANSFER_MINOR = 1_000_000_000_000;
export const FUND_MOVEMENT_TYPES = Object.freeze(['opening', 'collection', 'expense', 'transfer_in', 'transfer_out', 'adjustment']);

const fundNotFound = () => new PlatformError(404, 'FUND_NOT_FOUND', 'Hesap bulunamadı (İşletme Projesi (Aidat) Hesabı veya Yatırım ve Demirbaş (Fon) Hesabı olmalıdır).');

// --- Sorgu ayrıştırma ---------------------------------------------------------------------------------------------------------------------------

/** `from` / `to` (YYYY-MM-DD; isteğe bağlı). `to` yoksa bugün. from > to ise 400 INVALID_QUERY. */
export function parseFundsQuery(query = {}, now = new Date()) {
  const from = queryDate(query.from);
  const to = queryDate(query.to) ?? today(now);
  if (from !== null && from > to) {
    throw invalidQuery();
  }
  return { from, to };
}

export function parseMovementsQuery(query = {}, now = new Date()) {
  return {
    ...parseFundsQuery(query, now),
    limit: queryInt(query.limit, { min: 1, max: 200, fallback: 50 }),
    offset: queryInt(query.offset, { min: 0, max: 1_000_000, fallback: 0 }),
  };
}

// --- Kasa defteri (olaylar) ---------------------------------------------------------------------------------------------------------------------

const zeroFund = () => ({ opening: 0n, collections: 0n, expenses: 0n, transfersIn: 0n, transfersOut: 0n, adjustments: 0n });

/**
 * Sitenin kasa olayları (TÜM tarihler; tarih süzgeci okuma anında): { events, movementTotals, mappedPayments, paidByPayment }.
 * Olay: { fund, type, date, amount (BigInt, kasaya etkisi), refId, label, apartmentId?, accountId?, accountName?, category? }.
 */
export async function loadFundBook(db, siteCode) {
  const groups = await loadFundLedger(db, siteCode);
  const mappedResult = await db.query(`SELECT ledger_entry_id FROM account_movements WHERE site_code = $1 AND kind = 'collection' AND ledger_entry_id IS NOT NULL`, [siteCode]);
  const mapped = new Set((mappedResult.rows ?? []).map((row) => Number(row.ledger_entry_id)));
  const events = [];
  const mappedPayments = [];
  const allocationEvents = [];
  for (const [key, entries] of groups) {
    if (!entries.some((entry) => mapped.has(entry.id))) {
      continue; // bu hesapta eşlenmiş tahsilat yoksa kasaya hiçbir katkısı yok
    }
    const apartmentId = Number(key.split(':')[0]);
    const allocation = allocateFunds(entries);
    for (const payment of allocation.payments.values()) {
      if (mapped.has(payment.id)) mappedPayments.push({ id: payment.id, date: payment.date, amount: payment.amount, apartmentId });
    }
    for (const event of allocation.events) {
      if (mapped.has(event.paymentId)) allocationEvents.push({ ...event, apartmentId });
    }
  }
  // aynı tahsilatın aynı gün aynı kasaya olan parçaları tek satırda toplanır
  // (alacak iadesi olayları kasaya tahsilat DEĞİLDİR: avansı düşürür, aşağıdaki `paidByPayment` yoluyla avans hesabına girer)
  const grouped = new Map();
  for (const event of allocationEvents) {
    if (event.refund === true) continue;
    const id = `${event.paymentId}|${event.date}|${event.fund}`;
    const current = grouped.get(id);
    if (current) current.amount += event.amount;
    else grouped.set(id, { fund: event.fund, type: 'collection', date: event.date, amount: event.amount, refId: event.paymentId, label: null, apartmentId: event.apartmentId });
  }
  events.push(...grouped.values());
  const paidByPayment = new Map();
  for (const event of allocationEvents) {
    paidByPayment.set(event.paymentId, [...(paidByPayment.get(event.paymentId) ?? []), event]);
  }

  const movements = await db.query(
    `
      SELECT m.id, m.kind, m.amount_minor::TEXT AS amount_minor, to_char(m.movement_date, 'YYYY-MM-DD') AS movement_date, m.account_id, a.name AS account_name,
             o.kind AS original_kind
      FROM account_movements m
      INNER JOIN finance_accounts a ON a.id = m.account_id
      LEFT JOIN account_movements o ON o.id = m.reverses_movement_id
      WHERE m.site_code = $1
    `,
    [siteCode],
  );
  const movementTotals = [];
  for (const row of movements.rows ?? []) {
    const amount = toBigInt(row.amount_minor);
    movementTotals.push({ date: row.movement_date, amount });
    if (row.kind === 'opening') {
      events.push({ fund: 'operating', type: 'opening', date: row.movement_date, amount, refId: Number(row.id), label: row.account_name, accountId: Number(row.account_id), accountName: row.account_name });
    } else if (row.kind === 'adjustment' || (row.kind === 'reversal' && row.original_kind === 'adjustment')) {
      events.push({ fund: 'operating', type: 'adjustment', date: row.movement_date, amount, refId: Number(row.id), label: row.account_name, accountId: Number(row.account_id), accountName: row.account_name });
    }
  }

  const expenses = await db.query(
    `
      SELECT e.id, e.amount_minor::TEXT AS amount_minor, to_char(e.expense_date, 'YYYY-MM-DD') AS expense_date, COALESCE(e.fund, ec.fund, 'operating') AS fund,
             e.category_name, e.description, e.account_id
      FROM expenses e
      LEFT JOIN expense_categories ec ON ec.id = e.category_id
      WHERE e.site_code = $1 AND NOT EXISTS (SELECT 1 FROM expense_voids v WHERE v.expense_id = e.id)
    `,
    [siteCode],
  );
  for (const row of expenses.rows ?? []) {
    events.push({
      fund: row.fund === 'capital' ? 'capital' : 'operating',
      type: 'expense',
      date: row.expense_date,
      amount: -toBigInt(row.amount_minor),
      refId: Number(row.id),
      label: row.description,
      category: row.category_name,
      accountId: Number(row.account_id),
    });
  }

  const transfers = await db.query(
    `SELECT id, from_fund, to_fund, amount_minor::TEXT AS amount_minor, to_char(transfer_date, 'YYYY-MM-DD') AS transfer_date, description, reverses_transfer_id FROM finance_fund_transfers WHERE site_code = $1`,
    [siteCode],
  );
  for (const row of transfers.rows ?? []) {
    const amount = toBigInt(row.amount_minor);
    const label = row.reverses_transfer_id ? 'Ters aktarım' : row.description ?? 'Hesaplar arası aktarım';
    events.push({ fund: row.from_fund, type: 'transfer_out', date: row.transfer_date, amount: -amount, refId: Number(row.id), label });
    events.push({ fund: row.to_fund, type: 'transfer_in', date: row.transfer_date, amount, refId: Number(row.id), label });
  }
  return { events, movementTotals, mappedPayments, paidByPayment };
}

/** Kasa özeti (saf): aralık [from, to] için kasa bazında kalemler, avans ve fiziksel hesap toplamı. */
export function summarizeBook(book, { from, to }) {
  const funds = { operating: zeroFund(), capital: zeroFund() };
  for (const event of book.events) {
    if (event.date > to) continue;
    const entry = funds[event.fund];
    if (event.type === 'opening') {
      entry.opening += event.amount;
    } else if (from !== null && event.date < from) {
      entry.opening += event.amount;
    } else if (event.type === 'collection') {
      entry.collections += event.amount;
    } else if (event.type === 'expense') {
      entry.expenses += -event.amount;
    } else if (event.type === 'transfer_in') {
      entry.transfersIn += event.amount;
    } else if (event.type === 'transfer_out') {
      entry.transfersOut += -event.amount;
    } else if (event.type === 'adjustment') {
      entry.adjustments += event.amount;
    }
  }
  // avans (to tarihi itibarıyla): eşlenmiş tahsilatın, olay tarihi <= to olan dağıtımlar düşüldükten sonra kalanı
  let advance = 0n;
  for (const payment of book.mappedPayments) {
    if (payment.date > to) continue;
    let applied = 0n;
    for (const event of book.paidByPayment.get(payment.id) ?? []) {
      if (event.date <= to) applied += event.amount;
    }
    advance += payment.amount - applied;
  }
  let accountsTotal = 0n;
  for (const movement of book.movementTotals) {
    if (movement.date <= to) accountsTotal += movement.amount;
  }
  const balanceOf = (entry) => entry.opening + entry.collections - entry.expenses + entry.transfersIn - entry.transfersOut + entry.adjustments;
  return { funds, advance, accountsTotal, balanceOf };
}

function fundBody(fund, entry, balanceOf) {
  const balance = balanceOf(entry);
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
    balance_minor: minorToNumber(balance),
    negative_balance: balance < 0n,
  };
}

/** GET finance/funds?from=&to= -> iki kasa (açılış, tahsilat, gider, aktarım, bakiye), avans, fiziksel hesap toplamı ve fark. */
export async function getFundSummary(siteCode, query = {}, now = new Date(), db = pool) {
  const range = parseFundsQuery(query, now);
  return withReportSnapshot(siteCode, async (client) => {
    const book = await loadFundBook(client, siteCode);
    const summary = summarizeBook(book, range);
    const policy = await loadAccountPolicy(client, siteCode);
    const unassigned = await countUnassignedPayments(client, siteCode, policy.earliestOpening);
    const operating = summary.balanceOf(summary.funds.operating);
    const capital = summary.balanceOf(summary.funds.capital);
    const difference = summary.accountsTotal - (operating + capital + summary.advance);
    return {
      currency: 'TRY',
      from: range.from,
      to: range.to,
      has_accounts: policy.total > 0,
      funds: {
        operating: fundBody('operating', summary.funds.operating, summary.balanceOf),
        capital: fundBody('capital', summary.funds.capital, summary.balanceOf),
      },
      // henüz borca dağıtılmamış (eşlenmiş) ödeme: iki kasaya da yazılmaz
      advance_minor: minorToNumber(summary.advance),
      // fiziksel kasa / banka hesaplarının toplam bakiyesi; değişmez: İşletme + Fon + avans = toplam (difference_minor 0)
      accounts_total_minor: minorToNumber(summary.accountsTotal),
      difference_minor: minorToNumber(difference),
      balanced: difference === 0n,
      unassigned_payments: unassigned,
    };
  }, db);
}

async function loadApartmentLabels(db, siteCode) {
  const result = await db.query(`SELECT a.id, a.unit_label, b.block_name FROM apartments a INNER JOIN site_blocks b ON b.id = a.block_id WHERE a.site_code = $1`, [siteCode]);
  return new Map((result.rows ?? []).map((row) => [Number(row.id), apartmentLabel(row.block_name, row.unit_label)]));
}

const TYPE_ORDER = { opening: 0, collection: 1, expense: 2, transfer_in: 3, transfer_out: 4, adjustment: 5 };

/** GET finance/funds/:fund/movements?from=&to=&limit=&offset= -> sayfalı kasa dökümü (yeni -> eski). */
export async function listFundMovements(siteCode, rawFund, query = {}, now = new Date(), db = pool) {
  if (!isFund(rawFund)) {
    throw fundNotFound();
  }
  const range = parseMovementsQuery(query, now);
  return withReportSnapshot(siteCode, async (client) => {
    const book = await loadFundBook(client, siteCode);
    const summary = summarizeBook(book, { from: null, to: range.to });
    const labels = await loadApartmentLabels(client, siteCode);
    const inRange = book.events
      .filter((event) => event.fund === rawFund && event.date <= range.to && (range.from === null || event.date >= range.from))
      .sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : TYPE_ORDER[a.type] - TYPE_ORDER[b.type] || b.refId - a.refId));
    const page = inRange.slice(range.offset, range.offset + range.limit);
    return {
      fund: rawFund,
      fund_label: FUND_LABELS[rawFund],
      fund_short_label: FUND_SHORT_LABELS[rawFund],
      currency: 'TRY',
      from: range.from,
      to: range.to,
      balance_minor: minorToNumber(summary.balanceOf(summary.funds[rawFund])),
      total: inRange.length,
      limit: range.limit,
      offset: range.offset,
      items: page.map((event) => ({
        key: `${event.type}:${event.refId}:${event.date}`,
        type: event.type,
        date: event.date,
        amount_minor: minorToNumber(event.amount),
        label: event.type === 'collection' ? (labels.get(event.apartmentId) ?? null) : (event.label ?? null),
        apartment: event.type === 'collection' ? { id: event.apartmentId, label: labels.get(event.apartmentId) ?? null } : null,
        account: event.accountId ? { id: event.accountId, name: event.accountName ?? null } : null,
        category: event.category ?? null,
        ref_id: event.refId,
      })),
    };
  }, db);
}

// --- Kasalar arası aktarım ----------------------------------------------------------------------------------------------------------------------

/** POST fund-transfers gövdesi. */
export function parseFundTransfer(body, now = new Date()) {
  const input = objectOf(body);
  const fromFund = parseFundField(input.from_fund, 'Kaynak hesap');
  const toFund = parseFundField(input.to_fund, 'Hedef hesap');
  if (fromFund === null || toFund === null) {
    throw invalidBody('Kaynak ve hedef hesap zorunludur (İşletme Projesi (Aidat) Hesabı veya Yatırım ve Demirbaş (Fon) Hesabı).');
  }
  if (fromFund === toFund) {
    throw invalidBody('Kaynak ve hedef hesap aynı olamaz.');
  }
  const transferDate = parseIsoDate(input.transfer_date, 'Aktarım tarihi');
  if (transferDate > today(now)) {
    throw invalidBody('Aktarım tarihi gelecek bir tarih olamaz.');
  }
  return {
    fromFund,
    toFund,
    amountMinor: requireMinor(input.amount_minor, 'Tutar', { min: 1, max: MAX_FUND_TRANSFER_MINOR }),
    transferDate,
    description: normalizeFreeText(input.description, { label: 'Açıklama', max: 200 }),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

export function parseFundTransferReverse(body) {
  const input = objectOf(body);
  return {
    reason: normalizeFreeText(input.reason, { label: 'Neden', max: 200, required: true }),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

export function parseTransfersListQuery(query = {}) {
  const from = queryDate(query.from);
  const to = queryDate(query.to);
  if (from !== null && to !== null && from > to) {
    throw invalidQuery();
  }
  let beforeId = null;
  if (query.before_id !== undefined && query.before_id !== null && String(query.before_id).trim() !== '') {
    beforeId = parsePositiveId(String(query.before_id).trim());
    if (beforeId === null) {
      throw invalidQuery();
    }
  }
  return { from, to, beforeId, limit: queryInt(query.limit, { min: 1, max: 200, fallback: 50 }) };
}

const transferFingerprint = (input) =>
  fingerprintOf({ v: 1, kind: 'fund_transfer', from: input.fromFund, to: input.toFund, amount: input.amountMinor, date: input.transferDate, description: input.description });

const reverseFingerprint = (id, input) => fingerprintOf({ v: 1, kind: 'fund_transfer_reverse', of: id, reason: input.reason });

const TRANSFER_SELECT = `
  SELECT
    t.id, t.from_fund, t.to_fund, t.amount_minor::TEXT AS amount_minor, to_char(t.transfer_date, 'YYYY-MM-DD') AS transfer_date, to_char(t.period, 'YYYY-MM-DD') AS period,
    t.description, t.reverses_transfer_id, rv.id AS reversed_by_transfer_id, t.reversal_reason, t.created_at, t.request_fingerprint, t.idempotency_key,
    u.full_name AS created_by_name
  FROM finance_fund_transfers t
  LEFT JOIN finance_fund_transfers rv ON rv.reverses_transfer_id = t.id
  LEFT JOIN users u ON u.user_code = t.created_by
`;

export function mapFundTransfer(row) {
  return {
    id: Number(row.id),
    from_fund: row.from_fund,
    to_fund: row.to_fund,
    amount_minor: minorToNumber(row.amount_minor),
    transfer_date: row.transfer_date,
    period: periodLabel(row.period),
    description: row.description ?? null,
    reverses_transfer_id: row.reverses_transfer_id === null || row.reverses_transfer_id === undefined ? null : Number(row.reverses_transfer_id),
    reversed_by_transfer_id: row.reversed_by_transfer_id === null || row.reversed_by_transfer_id === undefined ? null : Number(row.reversed_by_transfer_id),
    reversal_reason: row.reversal_reason ?? null,
    created_by_name: row.created_by_name ?? null,
    created_at: toIso(row.created_at),
  };
}

async function loadTransferRow(db, siteCode, id) {
  const result = await db.query(`${TRANSFER_SELECT} WHERE t.id = $1 AND t.site_code = $2`, [id, siteCode]);
  return result.rows?.[0] ?? null;
}

async function findTransferByKey(db, siteCode, key) {
  const result = await db.query(`${TRANSFER_SELECT} WHERE t.site_code = $1 AND t.idempotency_key = $2`, [siteCode, key]);
  return result.rows?.[0] ?? null;
}

/** POST fund-transfers -> { replayed, transfer }. Tarih AÇIK ayda olmalı (409 PERIOD_CLOSED); aynı anahtar + aynı gövde = aynı kayıt (200). */
export async function createFundTransfer({ siteCode, body, actor, now = new Date() }) {
  const input = parseFundTransfer(body, now);
  const actorInfo = actorFromAuthUser(actor);
  const fingerprint = transferFingerprint(input);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const existing = await findTransferByKey(client, siteCode, input.idempotencyKey);
    if (existing) {
      if (existing.request_fingerprint !== fingerprint) {
        throw idempotencyConflict();
      }
      return { replayed: true, transfer: mapFundTransfer(existing) };
    }
    const period = await assertWritableDate(client, siteCode, input.transferDate, 'Aktarım tarihi', now);
    const inserted = await client.query(
      `
        INSERT INTO finance_fund_transfers (site_code, from_fund, to_fund, amount_minor, transfer_date, period, description, idempotency_key, request_fingerprint, created_by)
        VALUES ($1, $2, $3, $4::BIGINT, $5::DATE, $6::DATE, $7, $8, $9, $10)
        RETURNING id
      `,
      [siteCode, input.fromFund, input.toFund, String(input.amountMinor), input.transferDate, period, input.description, input.idempotencyKey, fingerprint, actorInfo.userCode],
    );
    const id = Number(inserted.rows[0].id);
    await recordFinanceAudit(client, actor, 'finance.fund_transfer.created', siteCode, id, {
      from_fund: input.fromFund,
      to_fund: input.toFund,
      amount_minor: input.amountMinor,
      period: periodLabel(period),
    });
    return { replayed: false, transfer: mapFundTransfer(await loadTransferRow(client, siteCode, id)) };
  });
}

/** POST fund-transfers/:id/reverse -> { replayed, transfer (ters aktarım), original }. Ters aktarım AÇIK ayda bugünün tarihiyle yazılır; bir aktarımın tek ters aktarımı olur. */
export async function reverseFundTransfer({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw fundTransferNotFound();
  }
  const input = parseFundTransferReverse(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const original = await loadTransferRow(client, siteCode, id);
    if (!original) {
      throw fundTransferNotFound();
    }
    const existing = await findTransferByKey(client, siteCode, input.idempotencyKey);
    if (existing) {
      if (existing.request_fingerprint !== reverseFingerprint(id, input) || Number(existing.reverses_transfer_id) !== id) {
        throw idempotencyConflict();
      }
      return { replayed: true, transfer: mapFundTransfer(existing), original: mapFundTransfer(original) };
    }
    if (original.reverses_transfer_id !== null && original.reverses_transfer_id !== undefined) {
      throw fundTransferNotReversible();
    }
    if (original.reversed_by_transfer_id !== null && original.reversed_by_transfer_id !== undefined) {
      throw fundTransferAlreadyReversed();
    }
    const openPeriod = await resolveOpenPeriod(client, siteCode, now);
    let insertedId;
    try {
      const inserted = await client.query(
        `
          INSERT INTO finance_fund_transfers (
            site_code, from_fund, to_fund, amount_minor, transfer_date, period, reverses_transfer_id, reversal_reason, idempotency_key, request_fingerprint, created_by
          )
          VALUES ($1, $2, $3, $4::BIGINT, $5::DATE, $6::DATE, $7, $8, $9, $10, $11)
          RETURNING id
        `,
        [siteCode, original.to_fund, original.from_fund, original.amount_minor, today(now), openPeriod, id, input.reason, input.idempotencyKey, reverseFingerprint(id, input), actorInfo.userCode],
      );
      insertedId = Number(inserted.rows[0].id);
    } catch (error) {
      if (error?.code === '23505' && String(error?.constraint ?? '') === 'uq_finance_fund_transfers_reverses') {
        throw fundTransferAlreadyReversed();
      }
      throw error;
    }
    await recordFinanceAudit(client, actor, 'finance.fund_transfer.reversed', siteCode, insertedId, {
      reversed_transfer_id: id,
      from_fund: original.to_fund,
      to_fund: original.from_fund,
      amount_minor: minorToNumber(original.amount_minor),
      period: periodLabel(openPeriod),
    });
    return {
      replayed: false,
      transfer: mapFundTransfer(await loadTransferRow(client, siteCode, insertedId)),
      original: mapFundTransfer(await loadTransferRow(client, siteCode, id)),
    };
  });
}

/** GET fund-transfers?from=&to=&limit=&before_id= -> { items (yeni -> eski), next_before_id }. */
export async function listFundTransfers(siteCode, query = {}, db = pool) {
  const filters = parseTransfersListQuery(query);
  const params = [siteCode];
  const clauses = ['t.site_code = $1'];
  if (filters.from !== null) {
    params.push(filters.from);
    clauses.push(`t.transfer_date >= $${params.length}::DATE`);
  }
  if (filters.to !== null) {
    params.push(filters.to);
    clauses.push(`t.transfer_date <= $${params.length}::DATE`);
  }
  if (filters.beforeId !== null) {
    params.push(filters.beforeId);
    clauses.push(`t.id < $${params.length}`);
  }
  params.push(filters.limit + 1);
  const result = await db.query(`${TRANSFER_SELECT} WHERE ${clauses.join(' AND ')} ORDER BY t.id DESC LIMIT $${params.length}`, params);
  const rows = result.rows ?? [];
  const page = rows.slice(0, filters.limit);
  return { items: page.map(mapFundTransfer), next_before_id: rows.length > filters.limit && page.length > 0 ? Number(page[page.length - 1].id) : null };
}
