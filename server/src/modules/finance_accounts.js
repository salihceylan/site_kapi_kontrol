// Kasa / banka hesapları (Faz 4b Ö4): hesaplar, hareketler, aktarımlar, düzeltme hareketleri, mutabakat ve tahsilat-hesap eşleme.
//
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Ö4". MODEL: hesap bakiyesi YALNIZ `account_movements` toplamıdır (tek doğruluk kaynağı); açılış 0 değilse `opening`
// hareketi yazılır. Hareketler değişmezdir (DB tetikleyicisi): düzeltme = ayna hareket (`reversal`), AÇIK ayda bugünün tarihiyle. Tahsilat↔hesap eşleme:
// `payments` gövdesindeki `account_id` AYNI işlemde `collection` hareketini yazar; hesap yoksa 4a davranışı aynen kalır.
// KİLİT SIRASI: sites KEY SHARE -> finance_post advisory -> apartments -> users(işlem yapan) -> hesap satırları (id sırasıyla) -> finans satırları.

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import {
  ACCOUNT_LIMIT,
  accountInactive,
  allAccountsInactive,
  reconciliationOrder,
  accountLimitReached,
  accountNameTaken,
  accountNotFound,
  accountRequired,
  beforeOpeningDate,
  fingerprintOf,
  objectOf,
  periodHasUnassignedPayments,
  present,
  queryDate,
  queryId,
  queryInt,
  reconciliationStale,
  requireId,
  sha256Hex,
  transferAlreadyVoided,
  transferNotFound,
} from './finance_4b_common.js';
import { assertWritableDate, earliestWritableDate, resolveOpenPeriod } from './finance_4b_guard.js';
import {
  idempotencyConflict,
  invalidBody,
  normalizeFreeText,
  parseBooleanFlag,
  parseIdempotencyKey,
  parseIsoDate,
  periodClosed,
  periodOfDate,
  previewStale,
  requireMinor,
  today,
} from './finance_common.js';
import { minorToNumber, toBigInt } from './finance_money.js';
import { isPeriodClosed, lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { parsePositiveId } from './people_common.js';

export const ACCOUNT_KINDS = Object.freeze(['cash', 'bank']);
export const ADJUSTMENT_REASONS = Object.freeze(['bank_fee', 'bank_interest', 'cash_count', 'other']);
export const MAX_ACCOUNT_AMOUNT = 1_000_000_000_000;
const PAYMENT_METHODS = ['cash', 'transfer', 'cheque'];

// --- Yardımcılar (ledger_service ve gider modülü de kullanır) ------------------------------------------------------------------------------

/** Hesap satırlarını id sırasıyla FOR KEY SHARE kilitler ve döndürür (kilit sırası kuralı). Eksik / başka site hesabı 404. */
export async function lockAccountRows(client, siteCode, ids, { forUpdate = false } = {}) {
  const unique = [...new Set(ids)].sort((a, b) => a - b);
  if (unique.length === 0) {
    return new Map();
  }
  const result = await client.query(
    `
      SELECT id, name, kind, note, is_active, sort_order, to_char(opening_date, 'YYYY-MM-DD') AS opening_date, opening_balance_minor::TEXT AS opening_balance_minor
      FROM finance_accounts
      WHERE site_code = $1 AND id = ANY($2::BIGINT[])
      ORDER BY id
      ${forUpdate ? 'FOR UPDATE' : 'FOR KEY SHARE'}
    `,
    [siteCode, unique],
  );
  const rows = new Map((result.rows ?? []).map((row) => [Number(row.id), row]));
  for (const id of unique) {
    if (!rows.has(id)) {
      throw accountNotFound();
    }
  }
  return rows;
}

/** Sitenin hesap durumu: toplam / etkin sayısı ve EN ERKEN açılış tarihi. */
export async function loadAccountPolicy(db, siteCode) {
  const result = await db.query(
    `
      SELECT COUNT(*)::INTEGER AS total, (COUNT(*) FILTER (WHERE is_active))::INTEGER AS active, to_char(MIN(opening_date), 'YYYY-MM-DD') AS earliest
      FROM finance_accounts WHERE site_code = $1
    `,
    [siteCode],
  );
  const row = result.rows[0];
  return { total: Number(row.total), active: Number(row.active), earliestOpening: row.earliest ?? null };
}

/**
 * Tahsilatın yazılacağı hesabı çözer ve kilitler. `accountId` yoksa: tarihte (opening_date <= entry_date) açık bir ETKİN hesap varsa 409 ACCOUNT_REQUIRED, yoksa null
 * (Faz 4a davranışı / açılıştan önceki tarihli tahsilat). Verilmişse: bu siteye ait, etkin, opening_date <= entry_date olmalı.
 */
export async function resolvePaymentAccount(client, siteCode, { accountId, entryDate }) {
  if (accountId === null || accountId === undefined) {
    const required = await client.query(
      `SELECT bool_or(is_active) AS has_active FROM finance_accounts WHERE site_code = $1 AND opening_date <= $2::DATE HAVING COUNT(*) > 0`,
      [siteCode, entryDate],
    );
    if (required.rows?.[0]) {
      // Tarihte açık hesap VARSA hesap zorunludur; hepsi PASİFSE hesapsız tahsilat kabul edilmez (eşlenmemiş kalır ve ay kapatılamazdı): önce bir hesap yeniden etkinleştirilmeli.
      throw required.rows[0].has_active === true ? accountRequired() : allAccountsInactive();
    }
    return null;
  }
  const rows = await lockAccountRows(client, siteCode, [accountId]);
  const account = rows.get(accountId);
  if (account.is_active !== true) {
    throw accountInactive();
  }
  if (entryDate < account.opening_date) {
    throw beforeOpeningDate();
  }
  return { id: accountId, name: account.name };
}

/** Tahsilat hareketi (+tutar). movement_date = tahsilat tarihi, dönem = tahsilat ayı (çağıran AÇIK olduğunu doğrulamıştır). */
export async function insertCollectionMovement(client, { siteCode, accountId, amountMinor, entryDate, ledgerEntryId, actorUserCode, idempotencyKey = null }) {
  const inserted = await client.query(
    `
      INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, ledger_entry_id, idempotency_key, created_by)
      VALUES ($1, $2, 'collection', $3::BIGINT, $4::DATE, $5::DATE, $6, $7, $8)
      RETURNING id
    `,
    [siteCode, accountId, String(amountMinor), entryDate, periodOfDate(entryDate), ledgerEntryId, idempotencyKey, actorUserCode],
  );
  return Number(inserted.rows[0].id);
}

/** Ödemenin eşlenmiş `collection` hareketi (varsa): { id, account_id, amount_minor(text), reversed }. */
export async function findCollectionMovement(db, ledgerEntryId) {
  const result = await db.query(
    `
      SELECT m.id, m.account_id, m.amount_minor::TEXT AS amount_minor, to_char(m.movement_date, 'YYYY-MM-DD') AS movement_date,
             EXISTS (SELECT 1 FROM account_movements r WHERE r.reverses_movement_id = m.id) AS reversed
      FROM account_movements m WHERE m.kind = 'collection' AND m.ledger_entry_id = $1
    `,
    [ledgerEntryId],
  );
  return result.rows?.[0] ?? null;
}

/** Hareketin ayna kaydını yazar (AÇIK ayda, bugünün tarihiyle). Aynayı yazılan hareketin kimliğini döndürür. */
async function insertMirrorMovement(client, { siteCode, movement, openPeriod, todayIsoDate, note = null, idempotencyKey = null, actorUserCode }) {
  const inserted = await client.query(
    `
      INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, reverses_movement_id, note, idempotency_key, created_by)
      VALUES ($1, $2, 'reversal', $3::BIGINT, $4::DATE, $5::DATE, $6, $7, $8, $9)
      RETURNING id
    `,
    [siteCode, Number(movement.account_id), String(-toBigInt(movement.amount_minor)), todayIsoDate, openPeriod, Number(movement.id), note, idempotencyKey, actorUserCode],
  );
  return Number(inserted.rows[0].id);
}

/**
 * Ödeme ters çevrilirken / düzeltilirken eşlenmiş `collection` hareketinin AYNASI. Eşlenmemiş ya da zaten aynalanmışsa null.
 * Hesap satırı önce kilitlenir (kilit sırası).
 */
export async function mirrorCollectionForEntry(client, { siteCode, entryId, openPeriod, todayIsoDate, actorUserCode }) {
  const movement = await findCollectionMovement(client, entryId);
  if (!movement || movement.reversed) {
    return null;
  }
  await lockAccountRows(client, siteCode, [Number(movement.account_id)]);
  const mirrorId = await insertMirrorMovement(client, { siteCode, movement, openPeriod, todayIsoDate, actorUserCode });
  return { account_id: Number(movement.account_id), movement_id: Number(movement.id), mirror_id: mirrorId };
}

/**
 * Hesaba eşlenmemiş tahsilat: ters kaydı olmayan, entry_date >= sitedeki EN ERKEN hesap açılış tarihi olan ve `collection` hareketi bulunmayan ödeme.
 * `upToPeriod` verilirse yalnız o dönem ve öncesi (ay kapatma engeli).
 */
const UNASSIGNED_WHERE = `
  l.site_code = $1 AND l.kind = 'payment' AND l.period >= $2::DATE AND l.entry_date >= $3::DATE
  AND l.source_kind IS DISTINCT FROM 'opening'
  AND NOT EXISTS (SELECT 1 FROM ledger_entries rv WHERE rv.reverses_entry_id = l.id)
  AND NOT EXISTS (SELECT 1 FROM account_movements m WHERE m.kind = 'collection' AND m.ledger_entry_id = l.id)
`;

export async function countUnassignedPayments(db, siteCode, earliestOpening, upToPeriod = null) {
  if (earliestOpening === null) {
    return { count: 0, total_minor: 0 };
  }
  const result = await db.query(
    `
      SELECT COUNT(*)::INTEGER AS n, COALESCE(SUM(-l.amount_minor), 0)::TEXT AS total
      FROM ledger_entries l
      WHERE ${UNASSIGNED_WHERE} AND ($4::DATE IS NULL OR l.period <= $4::DATE)
    `,
    [siteCode, periodOfDate(earliestOpening), earliestOpening, upToPeriod],
  );
  return { count: Number(result.rows[0].n), total_minor: minorToNumber(result.rows[0].total) };
}

/** Ay kapatma engeli: P içinde / öncesinde eşlenmemiş tahsilat varsa 409 PERIOD_HAS_UNASSIGNED_PAYMENTS. */
export async function assertNoUnassignedPayments(client, siteCode, periodIso) {
  const policy = await loadAccountPolicy(client, siteCode);
  const unassigned = await countUnassignedPayments(client, siteCode, policy.earliestOpening, periodIso);
  if (unassigned.count > 0) {
    throw periodHasUnassignedPayments({ count: unassigned.count, total_minor: unassigned.total_minor });
  }
}

// --- Hesap listesi ------------------------------------------------------------------------------------------------------------------------

function mapAccountRow(row) {
  const balance = minorToNumber(row.balance ?? '0');
  return {
    id: Number(row.id),
    name: row.name,
    kind: row.kind,
    note: row.note ?? null,
    opening_balance_minor: minorToNumber(row.opening_balance_minor),
    opening_date: row.opening_date,
    balance_minor: balance,
    negative_balance: balance < 0,
    is_active: row.is_active === true,
    sort_order: Number(row.sort_order),
    last_reconciliation:
      row.rec_as_of === null || row.rec_as_of === undefined
        ? null
        : { as_of_date: row.rec_as_of, difference_minor: minorToNumber(row.rec_difference), adjusted: row.rec_adjusted === true },
  };
}

const ACCOUNT_LIST_SELECT = `
  SELECT
    a.id, a.name, a.kind, a.note, a.is_active, a.sort_order, to_char(a.opening_date, 'YYYY-MM-DD') AS opening_date,
    a.opening_balance_minor::TEXT AS opening_balance_minor,
    COALESCE((SELECT SUM(m.amount_minor) FROM account_movements m WHERE m.site_code = a.site_code AND m.account_id = a.id), 0)::TEXT AS balance,
    rec.as_of AS rec_as_of, rec.diff::TEXT AS rec_difference, rec.adjusted AS rec_adjusted
  FROM finance_accounts a
  LEFT JOIN LATERAL (
    SELECT to_char(r.as_of_date, 'YYYY-MM-DD') AS as_of, r.difference_minor AS diff, (r.adjustment_movement_id IS NOT NULL) AS adjusted
    FROM account_reconciliations r WHERE r.account_id = a.id ORDER BY r.as_of_date DESC, r.id DESC LIMIT 1
  ) rec ON TRUE
`;

/** GET accounts -> { items, total_balance_minor, unassigned_payments }. */
export async function listAccounts(siteCode, db = pool) {
  const result = await db.query(`${ACCOUNT_LIST_SELECT} WHERE a.site_code = $1 ORDER BY a.sort_order, a.id`, [siteCode]);
  const items = (result.rows ?? []).map(mapAccountRow);
  const policy = await loadAccountPolicy(db, siteCode);
  const unassigned = await countUnassignedPayments(db, siteCode, policy.earliestOpening);
  let total = 0n;
  for (const item of items) {
    total += BigInt(item.balance_minor);
  }
  return { items, total_balance_minor: minorToNumber(total), unassigned_payments: unassigned };
}

async function loadAccount(db, siteCode, id) {
  const result = await db.query(`${ACCOUNT_LIST_SELECT} WHERE a.site_code = $1 AND a.id = $2`, [siteCode, id]);
  return result.rows?.[0] ? mapAccountRow(result.rows[0]) : null;
}

// --- Hesap oluşturma / güncelleme ------------------------------------------------------------------------------------------------------

export function parseAccountCreate(body, now = new Date()) {
  const input = objectOf(body);
  const openingDate = parseIsoDate(input.opening_date, 'Açılış tarihi');
  if (openingDate > today(now)) {
    throw invalidBody('Açılış tarihi gelecek bir tarih olamaz.');
  }
  if (!ACCOUNT_KINDS.includes(input.kind)) {
    throw invalidBody('Hesap türü geçersiz (kasa veya banka).');
  }
  return {
    name: normalizeFreeText(input.name, { label: 'Hesap adı', max: 60, required: true }),
    kind: input.kind,
    note: normalizeFreeText(input.note, { label: 'Not', max: 200 }),
    openingBalanceMinor: requireMinor(input.opening_balance_minor ?? 0, 'Açılış bakiyesi', { min: -MAX_ACCOUNT_AMOUNT, max: MAX_ACCOUNT_AMOUNT }),
    openingDate,
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

const sameName = (a, b) => a.toLocaleLowerCase('tr-TR') === b.toLocaleLowerCase('tr-TR');

/** POST accounts -> { replayed, account }. En çok 20 hesap; ad tekil; açılış bakiyesi 0 değilse `opening` hareketi. */
export async function createAccount({ siteCode, body, actor, now = new Date() }) {
  const input = parseAccountCreate(body, now);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const replay = await client.query(`SELECT id, name, kind, note, opening_date::TEXT AS opening_date, opening_balance_minor::TEXT AS opening_balance_minor FROM finance_accounts WHERE site_code = $1 AND idempotency_key = $2`, [
      siteCode,
      input.idempotencyKey,
    ]);
    if (replay.rows?.[0]) {
      const row = replay.rows[0];
      if (
        !sameName(row.name, input.name) ||
        row.kind !== input.kind ||
        BigInt(row.opening_balance_minor) !== BigInt(input.openingBalanceMinor) ||
        row.opening_date !== input.openingDate ||
        (row.note ?? null) !== (input.note ?? null)
      ) {
        throw idempotencyConflict();
      }
      return { replayed: true, account: await loadAccount(client, siteCode, Number(row.id)) };
    }
    const earliest = await earliestWritableDate(client, siteCode, now);
    if (input.openingDate < earliest) {
      throw periodClosed();
    }
    const policy = await loadAccountPolicy(client, siteCode);
    if (policy.total >= ACCOUNT_LIMIT) {
      throw accountLimitReached();
    }
    const taken = await client.query(`SELECT 1 FROM finance_accounts WHERE site_code = $1 AND lower(name) = lower($2)`, [siteCode, input.name]);
    if (taken.rows?.[0]) {
      throw accountNameTaken();
    }
    const inserted = await client.query(
      `
        INSERT INTO finance_accounts (site_code, name, kind, note, opening_date, opening_balance_minor, sort_order, idempotency_key, created_by)
        VALUES ($1, $2, $3, $4, $5::DATE, $6::BIGINT, $7, $8, $9)
        RETURNING id
      `,
      [siteCode, input.name, input.kind, input.note, input.openingDate, String(input.openingBalanceMinor), policy.total, input.idempotencyKey, actorInfo.userCode],
    );
    const id = Number(inserted.rows[0].id);
    if (input.openingBalanceMinor !== 0) {
      await client.query(
        `
          INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, created_by)
          VALUES ($1, $2, 'opening', $3::BIGINT, $4::DATE, $5::DATE, $6)
        `,
        [siteCode, id, String(input.openingBalanceMinor), input.openingDate, periodOfDate(input.openingDate), actorInfo.userCode],
      );
    }
    await recordFinanceAudit(client, actor, 'finance.account.created', siteCode, id, {
      kind: input.kind,
      opening_balance_minor: input.openingBalanceMinor,
      opening_date: input.openingDate,
    });
    return { replayed: false, account: await loadAccount(client, siteCode, id) };
  });
}

export function parseAccountPatch(body) {
  const input = objectOf(body);
  const patch = {};
  const fields = [];
  if (present(input.name)) {
    patch.name = normalizeFreeText(input.name, { label: 'Hesap adı', max: 60, required: true });
    fields.push('name');
  }
  if (Object.prototype.hasOwnProperty.call(input, 'note')) {
    patch.note = normalizeFreeText(input.note, { label: 'Not', max: 200 });
    fields.push('note');
  }
  if (Object.prototype.hasOwnProperty.call(input, 'is_active')) {
    patch.isActive = parseBooleanFlag(input.is_active, 'Aktiflik');
    if (typeof input.is_active !== 'boolean') {
      throw invalidBody('Aktiflik değeri geçersiz (evet veya hayır olmalıdır).');
    }
    fields.push('is_active');
  }
  if (present(input.sort_order)) {
    if (typeof input.sort_order !== 'number' || !Number.isInteger(input.sort_order) || input.sort_order < 0 || input.sort_order > 10000) {
      throw invalidBody('Sıra değeri geçersiz.');
    }
    patch.sortOrder = input.sort_order;
    fields.push('sort_order');
  }
  for (const key of Object.keys(input)) {
    if (!['name', 'note', 'is_active', 'sort_order'].includes(key)) {
      throw invalidBody('Hesabın açılış bilgileri değiştirilemez.');
    }
  }
  if (fields.length === 0) {
    throw invalidBody('Güncellenecek bir alan gönderilmedi.');
  }
  return { patch, fields };
}

/** PATCH accounts/:id -> hesap. Açılış bilgileri DEĞİŞMEZ (DB tetikleyicisi). Pasifleştirme serbest (yanıt bakiyeyi taşır; istemci uyarır). */
export async function updateAccount({ siteCode, rawId, body, actor }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw accountNotFound();
  }
  const { patch, fields } = parseAccountPatch(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const rows = await lockAccountRows(client, siteCode, [id], { forUpdate: true });
    const current = rows.get(id);
    if (patch.name !== undefined && !sameName(patch.name, current.name)) {
      const taken = await client.query(`SELECT 1 FROM finance_accounts WHERE site_code = $1 AND lower(name) = lower($2) AND id <> $3`, [siteCode, patch.name, id]);
      if (taken.rows?.[0]) {
        throw accountNameTaken();
      }
    }
    await client.query(
      `
        UPDATE finance_accounts
        SET name = $3, note = $4, is_active = $5, sort_order = $6, updated_at = NOW()
        WHERE id = $1 AND site_code = $2
      `,
      [
        id,
        siteCode,
        patch.name ?? current.name,
        fields.includes('note') ? patch.note : current.note,
        patch.isActive ?? current.is_active,
        patch.sortOrder ?? current.sort_order,
      ],
    );
    await recordFinanceAudit(client, actor, 'finance.account.updated', siteCode, id, { fields });
    return { account: await loadAccount(client, siteCode, id) };
  });
}

// --- Hareket listesi -------------------------------------------------------------------------------------------------------------------

export function parseMovementsQuery(query = {}) {
  const from = queryDate(query.from);
  const to = queryDate(query.to);
  if (from !== null && to !== null && from > to) {
    throw invalidBody('Tarih aralığı geçersiz.');
  }
  return { from, to, limit: queryInt(query.limit, { min: 1, max: 200, fallback: 50 }), beforeId: queryId(query.before_id) };
}

function mapMovementRow(row) {
  return {
    id: Number(row.id),
    kind: row.kind,
    amount_minor: minorToNumber(row.amount_minor),
    movement_date: row.movement_date,
    period: row.period,
    label: row.label ?? null,
    reverses_movement_id: row.reverses_movement_id === null || row.reverses_movement_id === undefined ? null : Number(row.reverses_movement_id),
    reversed_by_movement_id: row.reversed_by_movement_id === null || row.reversed_by_movement_id === undefined ? null : Number(row.reversed_by_movement_id),
    reason_code: row.reason_code ?? null,
    note: row.note ?? null,
  };
}

const MOVEMENT_SELECT = `
  SELECT
    m.id, m.kind, m.amount_minor::TEXT AS amount_minor, to_char(m.movement_date, 'YYYY-MM-DD') AS movement_date, to_char(m.period, 'YYYY-MM-DD') AS period,
    m.reverses_movement_id, rv.id AS reversed_by_movement_id, m.reason_code, m.note,
    CASE
      WHEN m.kind = 'collection' THEN (SELECT b.block_name || ' - ' || a.unit_label FROM ledger_entries l INNER JOIN apartments a ON a.id = l.apartment_id INNER JOIN site_blocks b ON b.id = a.block_id WHERE l.id = m.ledger_entry_id)
      WHEN m.kind = 'expense' THEN (SELECT e.description FROM expenses e WHERE e.id = m.expense_id)
      WHEN m.kind IN ('transfer_out', 'transfer_in') THEN (SELECT fa.name FROM account_transfers t INNER JOIN finance_accounts fa ON fa.id = CASE WHEN m.kind = 'transfer_out' THEN t.to_account_id ELSE t.from_account_id END WHERE t.id = m.transfer_id)
      ELSE NULL
    END AS label
  FROM account_movements m
  LEFT JOIN account_movements rv ON rv.reverses_movement_id = m.id
`;

/** GET accounts/:id/movements -> { account, balance_minor, items, next_before_id }. */
export async function listAccountMovements(siteCode, rawId, query = {}, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw accountNotFound();
  }
  const filters = parseMovementsQuery(query);
  const account = await loadAccount(db, siteCode, id);
  if (!account) {
    throw accountNotFound();
  }
  const params = [siteCode, id];
  const clauses = ['m.site_code = $1', 'm.account_id = $2'];
  if (filters.from !== null) {
    params.push(filters.from);
    clauses.push(`m.movement_date >= $${params.length}::DATE`);
  }
  if (filters.to !== null) {
    params.push(filters.to);
    clauses.push(`m.movement_date <= $${params.length}::DATE`);
  }
  if (filters.beforeId !== null) {
    params.push(filters.beforeId);
    clauses.push(
      `(m.movement_date, m.id) < (SELECT c.movement_date, c.id FROM account_movements c WHERE c.id = $${params.length} AND c.site_code = $1 AND c.account_id = $2)`,
    );
  }
  params.push(filters.limit + 1);
  const result = await db.query(`${MOVEMENT_SELECT} WHERE ${clauses.join(' AND ')} ORDER BY m.movement_date DESC, m.id DESC LIMIT $${params.length}`, params);
  const rows = result.rows ?? [];
  const page = rows.slice(0, filters.limit);
  return {
    account: { id: account.id, name: account.name, kind: account.kind, is_active: account.is_active },
    balance_minor: account.balance_minor,
    negative_balance: account.negative_balance,
    items: page.map(mapMovementRow),
    next_before_id: rows.length > filters.limit && page.length > 0 ? Number(page[page.length - 1].id) : null,
  };
}

async function loadMovement(db, siteCode, id) {
  const result = await db.query(`${MOVEMENT_SELECT} WHERE m.id = $1 AND m.site_code = $2`, [id, siteCode]);
  return result.rows?.[0] ? mapMovementRow(result.rows[0]) : null;
}

// --- Düzeltme hareketi --------------------------------------------------------------------------------------------------------------------

export function parseAdjustment(body, now = new Date()) {
  const input = objectOf(body);
  const amount = requireMinor(input.amount_minor, 'Tutar', { min: -MAX_ACCOUNT_AMOUNT, max: MAX_ACCOUNT_AMOUNT });
  if (amount === 0) {
    throw invalidBody('Tutar sıfır olamaz.');
  }
  if (!ADJUSTMENT_REASONS.includes(input.reason_code)) {
    throw invalidBody('Düzeltme nedeni geçersiz.');
  }
  const note = normalizeFreeText(input.note, { label: 'Not', max: 200, required: input.reason_code === 'other' });
  const movementDate = parseIsoDate(input.movement_date, 'Hareket tarihi');
  if (movementDate > today(now)) {
    throw invalidBody('Hareket tarihi gelecek bir tarih olamaz.');
  }
  return { amountMinor: amount, reasonCode: input.reason_code, note, movementDate, idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }) };
}

async function findMovementByKey(db, siteCode, key) {
  const result = await db.query(`SELECT id, account_id, kind, amount_minor::TEXT AS amount_minor, to_char(movement_date, 'YYYY-MM-DD') AS movement_date, reverses_movement_id, transfer_id, reason_code, note FROM account_movements WHERE site_code = $1 AND idempotency_key = $2`, [
    siteCode,
    key,
  ]);
  return result.rows?.[0] ?? null;
}

/** POST accounts/:id/adjustments -> { replayed, movement, balance_minor }. */
export async function createAdjustment({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw accountNotFound();
  }
  const input = parseAdjustment(body, now);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const rows = await lockAccountRows(client, siteCode, [id]);
    const account = rows.get(id);
    const existing = await findMovementByKey(client, siteCode, input.idempotencyKey);
    if (existing) {
      if (
        existing.kind !== 'adjustment' ||
        Number(existing.account_id) !== id ||
        BigInt(existing.amount_minor) !== BigInt(input.amountMinor) ||
        existing.movement_date !== input.movementDate ||
        existing.reason_code !== input.reasonCode ||
        (existing.note ?? null) !== (input.note ?? null)
      ) {
        throw idempotencyConflict();
      }
      return { replayed: true, movement: await loadMovement(client, siteCode, Number(existing.id)), balance_minor: (await loadAccount(client, siteCode, id)).balance_minor };
    }
    const period = await assertWritableDate(client, siteCode, input.movementDate, 'Hareket tarihi', now);
    if (account.is_active !== true) {
      throw accountInactive();
    }
    if (input.movementDate < account.opening_date) {
      throw beforeOpeningDate();
    }
    const inserted = await client.query(
      `
        INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, reason_code, note, idempotency_key, created_by)
        VALUES ($1, $2, 'adjustment', $3::BIGINT, $4::DATE, $5::DATE, $6, $7, $8, $9)
        RETURNING id
      `,
      [siteCode, id, String(input.amountMinor), input.movementDate, period, input.reasonCode, input.note, input.idempotencyKey, actorInfo.userCode],
    );
    const movementId = Number(inserted.rows[0].id);
    await recordFinanceAudit(client, actor, 'finance.account.adjusted', siteCode, movementId, {
      account_id: id,
      amount_minor: input.amountMinor,
      reason_code: input.reasonCode,
    });
    return { replayed: false, movement: await loadMovement(client, siteCode, movementId), balance_minor: (await loadAccount(client, siteCode, id)).balance_minor };
  });
}

// --- Aktarım ----------------------------------------------------------------------------------------------------------------------------

export function parseTransfer(body, now = new Date()) {
  const input = objectOf(body);
  const fromId = requireId(input.from_account_id, 'Kaynak hesap');
  const toId = requireId(input.to_account_id, 'Hedef hesap');
  if (fromId === toId) {
    throw invalidBody('Kaynak ve hedef hesap aynı olamaz.');
  }
  const transferDate = parseIsoDate(input.transfer_date, 'Aktarım tarihi');
  if (transferDate > today(now)) {
    throw invalidBody('Aktarım tarihi gelecek bir tarih olamaz.');
  }
  return {
    fromId,
    toId,
    amountMinor: requireMinor(input.amount_minor, 'Tutar', { min: 1, max: MAX_ACCOUNT_AMOUNT }),
    transferDate,
    description: normalizeFreeText(input.description, { label: 'Açıklama', max: 200 }),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

const transferFingerprint = (input) =>
  fingerprintOf({ v: 1, kind: 'transfer', from: input.fromId, to: input.toId, amount: input.amountMinor, date: input.transferDate, description: input.description });

const TRANSFER_SELECT = `
  SELECT
    t.id, t.from_account_id, fa.name AS from_name, t.to_account_id, ta.name AS to_name, t.amount_minor::TEXT AS amount_minor,
    to_char(t.transfer_date, 'YYYY-MM-DD') AS transfer_date, t.description, t.created_at, t.request_fingerprint,
    (SELECT r.id FROM account_movements o INNER JOIN account_movements r ON r.reverses_movement_id = o.id WHERE o.transfer_id = t.id AND o.kind = 'transfer_out') AS voided_movement_id,
    (SELECT r.created_at FROM account_movements o INNER JOIN account_movements r ON r.reverses_movement_id = o.id WHERE o.transfer_id = t.id AND o.kind = 'transfer_out') AS voided_at
  FROM account_transfers t
  INNER JOIN finance_accounts fa ON fa.id = t.from_account_id
  INNER JOIN finance_accounts ta ON ta.id = t.to_account_id
`;

function mapTransferRow(row) {
  return {
    id: Number(row.id),
    from_account: { id: Number(row.from_account_id), name: row.from_name },
    to_account: { id: Number(row.to_account_id), name: row.to_name },
    amount_minor: minorToNumber(row.amount_minor),
    transfer_date: row.transfer_date,
    description: row.description ?? null,
    voided: row.voided_movement_id === null || row.voided_movement_id === undefined ? null : { at: new Date(row.voided_at).toISOString() },
    created_at: new Date(row.created_at).toISOString(),
  };
}

async function loadTransferRow(db, siteCode, id) {
  const result = await db.query(`${TRANSFER_SELECT} WHERE t.id = $1 AND t.site_code = $2`, [id, siteCode]);
  return result.rows?.[0] ?? null;
}

async function transferMovements(db, siteCode, transferId) {
  const result = await db.query(`${MOVEMENT_SELECT} WHERE m.site_code = $1 AND m.transfer_id = $2 ORDER BY m.id`, [siteCode, transferId]);
  return (result.rows ?? []).map(mapMovementRow);
}

/** POST transfers -> { replayed, transfer, movements: [out, in] }. Tek işlem, iki hareket; hesaplar id sırasıyla kilitlenir. */
export async function createTransfer({ siteCode, body, actor, now = new Date() }) {
  const input = parseTransfer(body, now);
  const actorInfo = actorFromAuthUser(actor);
  const fingerprint = transferFingerprint(input);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const accounts = await lockAccountRows(client, siteCode, [input.fromId, input.toId]);
    const existing = await client.query(`SELECT id, request_fingerprint FROM account_transfers WHERE site_code = $1 AND idempotency_key = $2`, [siteCode, input.idempotencyKey]);
    if (existing.rows?.[0]) {
      if (existing.rows[0].request_fingerprint !== fingerprint) {
        throw idempotencyConflict();
      }
      const id = Number(existing.rows[0].id);
      return { replayed: true, transfer: mapTransferRow(await loadTransferRow(client, siteCode, id)), movements: await transferMovements(client, siteCode, id) };
    }
    const period = await assertWritableDate(client, siteCode, input.transferDate, 'Aktarım tarihi', now);
    for (const account of accounts.values()) {
      if (account.is_active !== true) {
        throw accountInactive();
      }
      if (input.transferDate < account.opening_date) {
        throw beforeOpeningDate();
      }
    }
    const inserted = await client.query(
      `
        INSERT INTO account_transfers (site_code, from_account_id, to_account_id, amount_minor, transfer_date, description, idempotency_key, request_fingerprint, created_by)
        VALUES ($1, $2, $3, $4::BIGINT, $5::DATE, $6, $7, $8, $9)
        RETURNING id
      `,
      [siteCode, input.fromId, input.toId, String(input.amountMinor), input.transferDate, input.description, input.idempotencyKey, fingerprint, actorInfo.userCode],
    );
    const id = Number(inserted.rows[0].id);
    await client.query(
      `
        INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, transfer_id, created_by)
        VALUES ($1, $2, 'transfer_out', $3::BIGINT, $5::DATE, $6::DATE, $7, $8), ($1, $4, 'transfer_in', $9::BIGINT, $5::DATE, $6::DATE, $7, $8)
      `,
      [siteCode, input.fromId, String(-input.amountMinor), input.toId, input.transferDate, period, id, actorInfo.userCode, String(input.amountMinor)],
    );
    await recordFinanceAudit(client, actor, 'finance.transfer.created', siteCode, id, {
      from_account_id: input.fromId,
      to_account_id: input.toId,
      amount_minor: input.amountMinor,
    });
    return { replayed: false, transfer: mapTransferRow(await loadTransferRow(client, siteCode, id)), movements: await transferMovements(client, siteCode, id) };
  });
}

export function parseTransfersQuery(query = {}) {
  const base = parseMovementsQuery(query);
  return base;
}

/** GET transfers -> { items, next_before_id }. */
export async function listTransfers(siteCode, query = {}, db = pool) {
  const filters = parseTransfersQuery(query);
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
  return { items: page.map(mapTransferRow), next_before_id: rows.length > filters.limit && page.length > 0 ? Number(page[page.length - 1].id) : null };
}

export function parseVoidBody(body) {
  const input = objectOf(body);
  return {
    reason: normalizeFreeText(input.reason, { label: 'Neden', max: 200, required: true }),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

/** POST transfers/:id/void -> { replayed, transfer, movements }. İki ayna hareket (AÇIK ay, bugünün tarihi). */
export async function voidTransfer({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw transferNotFound();
  }
  const input = parseVoidBody(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const head = await loadTransferRow(client, siteCode, id);
    if (!head) {
      throw transferNotFound();
    }
    await lockAccountRows(client, siteCode, [Number(head.from_account_id), Number(head.to_account_id)]);
    const existing = await findMovementByKey(client, siteCode, input.idempotencyKey);
    if (existing) {
      const original = existing.reverses_movement_id
        ? await client.query(`SELECT transfer_id FROM account_movements WHERE id = $1`, [Number(existing.reverses_movement_id)])
        : { rows: [] };
      if (existing.kind !== 'reversal' || Number(original.rows?.[0]?.transfer_id) !== id || (existing.note ?? null) !== input.reason) {
        throw idempotencyConflict();
      }
      return { replayed: true, transfer: mapTransferRow(await loadTransferRow(client, siteCode, id)), movements: await transferMovements(client, siteCode, id) };
    }
    if (head.voided_movement_id !== null && head.voided_movement_id !== undefined) {
      throw transferAlreadyVoided();
    }
    const openPeriod = await resolveOpenPeriod(client, siteCode, now);
    const originals = await client.query(
      `SELECT id, account_id, amount_minor::TEXT AS amount_minor, kind FROM account_movements WHERE site_code = $1 AND transfer_id = $2 ORDER BY CASE kind WHEN 'transfer_out' THEN 0 ELSE 1 END`,
      [siteCode, id],
    );
    let first = true;
    for (const original of originals.rows) {
      await insertMirrorMovement(client, {
        siteCode,
        movement: original,
        openPeriod,
        todayIsoDate: today(now),
        note: input.reason,
        idempotencyKey: first ? input.idempotencyKey : null,
        actorUserCode: actorInfo.userCode,
      });
      first = false;
    }
    await recordFinanceAudit(client, actor, 'finance.transfer.voided', siteCode, id, { amount_minor: minorToNumber(head.amount_minor) });
    return { replayed: false, transfer: mapTransferRow(await loadTransferRow(client, siteCode, id)), movements: await transferMovements(client, siteCode, id) };
  });
}

// --- Toplu eşleme -------------------------------------------------------------------------------------------------------------------------

export function parseAssignBody(body, { commit }) {
  const input = objectOf(body);
  const map = objectOf(input.account_by_method);
  const accountByMethod = {};
  for (const method of PAYMENT_METHODS) {
    if (present(map[method])) {
      accountByMethod[method] = requireId(map[method], 'Hesap');
    }
  }
  for (const key of Object.keys(map)) {
    if (!PAYMENT_METHODS.includes(key)) {
      throw invalidBody('Ödeme yöntemi geçersiz.');
    }
  }
  if (Object.keys(accountByMethod).length === 0) {
    throw invalidBody('En az bir ödeme yöntemi için hesap seçin.');
  }
  const result = { accountByMethod };
  if (commit) {
    const count = input.expected_count;
    if (typeof count !== 'number' || !Number.isInteger(count) || count < 0 || count > 1000000) {
      throw invalidBody('Beklenen sayı geçersiz.');
    }
    result.expectedCount = count;
    result.expectedTotal = requireMinor(input.expected_total_minor, 'Beklenen toplam', { min: 0, max: 100000000000000 });
    if (typeof input.expected_hash !== 'string' || !/^[0-9a-f]{64}$/.test(input.expected_hash)) {
      throw invalidBody('Önizleme özeti (expected_hash) zorunludur; önizlemeyi yenileyin.');
    }
    result.expectedHash = input.expected_hash;
    result.idempotencyKey = parseIdempotencyKey(input.idempotency_key, { required: true });
  }
  return result;
}

/** Eşlenebilir tahsilatlar + atlananlar. Kilit yok; commit'te işlem içinde yeniden çağrılır. */
async function computeAssignPlan(db, siteCode, accountByMethod, accounts) {
  const policy = await loadAccountPolicy(db, siteCode);
  const plan = { rows: [], skipped: { before_opening: 0, closed_period: 0, no_account: 0 }, earliest: policy.earliestOpening };
  if (policy.earliestOpening === null) {
    return plan;
  }
  const closed = await db.query(`SELECT to_char(MAX(period), 'YYYY-MM-DD') AS latest FROM finance_period_closures WHERE site_code = $1`, [siteCode]);
  const latestClosed = closed.rows?.[0]?.latest ?? null;
  const result = await db.query(
    `
      SELECT l.id, l.method, (-l.amount_minor)::TEXT AS amount, to_char(l.entry_date, 'YYYY-MM-DD') AS entry_date, to_char(l.period, 'YYYY-MM-DD') AS period
      FROM ledger_entries l
      WHERE ${UNASSIGNED_WHERE}
      ORDER BY l.id
    `,
    [siteCode, periodOfDate(policy.earliestOpening), policy.earliestOpening],
  );
  for (const row of result.rows ?? []) {
    const accountId = accountByMethod[row.method];
    if (accountId === undefined) {
      plan.skipped.no_account += 1;
    } else if (latestClosed !== null && row.period <= latestClosed) {
      plan.skipped.closed_period += 1;
    } else if (row.entry_date < accounts.get(accountId).opening_date) {
      plan.skipped.before_opening += 1;
    } else {
      plan.rows.push({ id: Number(row.id), method: row.method, amount: toBigInt(row.amount), entryDate: row.entry_date, accountId });
    }
  }
  return plan;
}

function assignSummary(plan, accountByMethod) {
  let total = 0n;
  const byMethod = new Map();
  for (const row of plan.rows) {
    total += row.amount;
    const entry = byMethod.get(row.method) ?? { method: row.method, account_id: row.accountId, count: 0, total: 0n };
    entry.count += 1;
    entry.total += row.amount;
    byMethod.set(row.method, entry);
  }
  const hash = sha256Hex(
    `v1|${JSON.stringify(PAYMENT_METHODS.map((method) => [method, accountByMethod[method] ?? null]))}|${plan.rows.map((row) => `${row.id}:${row.amount}:${row.accountId}`).join(',')}`,
  );
  return {
    count: plan.rows.length,
    total_minor: minorToNumber(total),
    by_method: [...byMethod.values()].map((entry) => ({ method: entry.method, account_id: entry.account_id, count: entry.count, total_minor: minorToNumber(entry.total) })),
    skipped: plan.skipped,
    preview_hash: hash,
  };
}

async function loadAssignAccounts(client, siteCode, accountByMethod, { lock }) {
  const ids = [...new Set(Object.values(accountByMethod))];
  const accounts = lock
    ? await lockAccountRows(client, siteCode, ids)
    : new Map(
        (
          await client.query(
            `SELECT id, name, is_active, to_char(opening_date, 'YYYY-MM-DD') AS opening_date FROM finance_accounts WHERE site_code = $1 AND id = ANY($2::BIGINT[])`,
            [siteCode, ids],
          )
        ).rows.map((row) => [Number(row.id), row]),
      );
  for (const id of ids) {
    const account = accounts.get(id);
    if (!account) {
      throw accountNotFound();
    }
    if (account.is_active !== true) {
      throw accountInactive();
    }
  }
  return accounts;
}

/** POST accounts/assign-payments/preview (YAZMAZ). */
export async function previewAssignPayments({ siteCode, body, db = pool }) {
  const input = parseAssignBody(body, { commit: false });
  const accounts = await loadAssignAccounts(db, siteCode, input.accountByMethod, { lock: false });
  const plan = await computeAssignPlan(db, siteCode, input.accountByMethod, accounts);
  return assignSummary(plan, input.accountByMethod);
}

/** POST accounts/assign-payments/commit -> { replayed, count, total_minor }. Kilit altında yeniden hesap; uyuşmazlık 409 PREVIEW_STALE. */
export async function commitAssignPayments({ siteCode, body, actor }) {
  const input = parseAssignBody(body, { commit: true });
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const accounts = await loadAssignAccounts(client, siteCode, input.accountByMethod, { lock: true });
    const existing = await findMovementByKey(client, siteCode, input.idempotencyKey);
    if (existing) {
      if (existing.kind !== 'collection') {
        throw idempotencyConflict();
      }
      const group = await client.query(
        `SELECT COUNT(*)::INTEGER AS n, COALESCE(SUM(amount_minor), 0)::TEXT AS total FROM account_movements WHERE site_code = $1 AND kind = 'collection' AND created_by IS NOT DISTINCT FROM $2 AND created_at = (SELECT created_at FROM account_movements WHERE id = $3)`,
        [siteCode, actorInfo.userCode, Number(existing.id)],
      );
      // Gövde doğrulaması: ilk istekte kullanılan yöntem->hesap eşlemesi ve beklenen sayı / toplam AYNI olmalı (farklı hesap / sahte özetle tekrar = 409).
      const methods = await client.query(
        `
          SELECT DISTINCT l.method, m.account_id
          FROM account_movements m INNER JOIN ledger_entries l ON l.id = m.ledger_entry_id
          WHERE m.site_code = $1 AND m.kind = 'collection' AND m.created_by IS NOT DISTINCT FROM $2 AND m.created_at = (SELECT created_at FROM account_movements WHERE id = $3)
        `,
        [siteCode, actorInfo.userCode, Number(existing.id)],
      );
      const sameMapping = (methods.rows ?? []).every((row) => input.accountByMethod[row.method] === Number(row.account_id));
      if (!sameMapping || Number(group.rows[0].n) !== input.expectedCount || minorToNumber(group.rows[0].total) !== input.expectedTotal) {
        throw idempotencyConflict();
      }
      return { replayed: true, count: Number(group.rows[0].n), total_minor: minorToNumber(group.rows[0].total) };
    }
    const plan = await computeAssignPlan(client, siteCode, input.accountByMethod, accounts);
    const summary = assignSummary(plan, input.accountByMethod);
    if (plan.rows.length === 0 || summary.preview_hash !== input.expectedHash || summary.count !== input.expectedCount || summary.total_minor !== input.expectedTotal) {
      throw previewStale({ count: summary.count, total_minor: summary.total_minor, preview_hash: summary.preview_hash });
    }
    const rows = plan.rows;
    const inserted = await client.query(
      `
        INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, ledger_entry_id, idempotency_key, created_by)
        SELECT $1, t.account_id, 'collection', t.amount, t.entry_date, date_trunc('month', t.entry_date)::DATE, t.ledger_entry_id,
               CASE WHEN t.ord = 1 THEN $6 ELSE NULL END, $7
        FROM unnest($2::BIGINT[], $3::BIGINT[], $4::BIGINT[], $5::DATE[]) WITH ORDINALITY AS t(ledger_entry_id, account_id, amount, entry_date, ord)
        ORDER BY t.ord
      `,
      [
        siteCode,
        rows.map((row) => String(row.id)),
        rows.map((row) => String(row.accountId)),
        rows.map((row) => String(row.amount)),
        rows.map((row) => row.entryDate),
        input.idempotencyKey,
        actorInfo.userCode,
      ],
    );
    if (inserted.rowCount !== rows.length) {
      throw new Error('toplu eşleme satır sayısı uyuşmuyor');
    }
    await recordFinanceAudit(client, actor, 'finance.payments.assigned', siteCode, siteCode, { count: summary.count, total_minor: summary.total_minor });
    return { replayed: false, count: summary.count, total_minor: summary.total_minor };
  });
}

// --- Mutabakat ----------------------------------------------------------------------------------------------------------------------------

export function parseReconciliation(body, now = new Date()) {
  const input = objectOf(body);
  const asOf = parseIsoDate(input.as_of_date, 'Ekstre tarihi');
  if (asOf > today(now)) {
    throw invalidBody('Ekstre tarihi gelecek bir tarih olamaz.');
  }
  const result = {
    asOf,
    statementMinor: requireMinor(input.statement_balance_minor, 'Ekstre bakiyesi', { min: -MAX_ACCOUNT_AMOUNT, max: MAX_ACCOUNT_AMOUNT }),
    expectedComputed: requireMinor(input.expected_computed_minor, 'Beklenen hesaplanan bakiye', { min: -100000000000000, max: 100000000000000 }),
    note: normalizeFreeText(input.note, { label: 'Not', max: 200 }),
    adjust: null,
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
  if (present(input.adjust)) {
    const adjust = objectOf(input.adjust);
    if (!ADJUSTMENT_REASONS.includes(adjust.reason_code)) {
      throw invalidBody('Düzeltme nedeni geçersiz.');
    }
    result.adjust = { reasonCode: adjust.reason_code, note: normalizeFreeText(adjust.note, { label: 'Düzeltme notu', max: 200, required: adjust.reason_code === 'other' }) };
  }
  return result;
}

/**
 * `asOf` itibarıyla hesaplanan bakiye. Bir mutabakat düzeltmesi, hareket tarihi (bugün) değil KENDİ mutabakatının `as_of_date` günü etkili sayılır:
 *   - mutabakat düzeltmesi olmayan hareketler: `movement_date <= asOf`;
 *   - mutabakat düzeltmeleri: `r.as_of_date <= asOf` (o ekstre tarihinde bakiye zaten düzeltilmiştir).
 * Böylece aynı tarih için tekrar mutabakat VE sonraki bir tarihli mutabakat öncekinin düzeltmesini görür, aynı fark ikinci kez düzeltilmez (R10 P1-3, R15 P1-A).
 * Yapısal kalan durum: DAHA YENİ tarihli düzeltilmiş mutabakat varken daha eski tarihe düzeltme istenirse (createReconciliation) 409 RECONCILIATION_ORDER.
 */
async function computedBalanceAsOf(db, siteCode, accountId, asOf) {
  const result = await db.query(
    `
      SELECT COALESCE(SUM(m.amount_minor), 0)::TEXT AS balance
      FROM account_movements m
      WHERE m.site_code = $1 AND m.account_id = $2
        AND (
          (m.movement_date <= $3::DATE AND NOT EXISTS (SELECT 1 FROM account_reconciliations r WHERE r.adjustment_movement_id = m.id))
          OR EXISTS (SELECT 1 FROM account_reconciliations r WHERE r.adjustment_movement_id = m.id AND r.as_of_date <= $3::DATE)
        )
    `,
    [siteCode, accountId, asOf],
  );
  return toBigInt(result.rows[0].balance);
}

function mapReconciliationRow(row) {
  return {
    id: Number(row.id),
    account_id: Number(row.account_id),
    as_of_date: row.as_of_date,
    statement_balance_minor: minorToNumber(row.statement_balance_minor),
    computed_balance_minor: minorToNumber(row.computed_balance_minor),
    difference_minor: minorToNumber(row.difference_minor),
    adjusted: row.adjustment_movement_id !== null && row.adjustment_movement_id !== undefined,
    adjustment_movement_id: row.adjustment_movement_id === null || row.adjustment_movement_id === undefined ? null : Number(row.adjustment_movement_id),
    note: row.note ?? null,
    reconciled_by_name: row.reconciled_by_name ?? null,
    reconciled_at: new Date(row.reconciled_at).toISOString(),
  };
}

const RECONCILIATION_SELECT = `
  SELECT r.id, r.account_id, to_char(r.as_of_date, 'YYYY-MM-DD') AS as_of_date, r.statement_balance_minor::TEXT AS statement_balance_minor,
         r.computed_balance_minor::TEXT AS computed_balance_minor, r.difference_minor::TEXT AS difference_minor, r.adjustment_movement_id, r.note,
         u.full_name AS reconciled_by_name, r.reconciled_at, r.idempotency_key
  FROM account_reconciliations r LEFT JOIN users u ON u.user_code = r.reconciled_by
`;

/** GET accounts/:id/reconciliations -> { items }. */
export async function listReconciliations(siteCode, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw accountNotFound();
  }
  const account = await loadAccount(db, siteCode, id);
  if (!account) {
    throw accountNotFound();
  }
  const result = await db.query(`${RECONCILIATION_SELECT} WHERE r.site_code = $1 AND r.account_id = $2 ORDER BY r.as_of_date DESC, r.id DESC LIMIT 100`, [siteCode, id]);
  return { items: (result.rows ?? []).map(mapReconciliationRow) };
}

/**
 * POST accounts/:id/reconciliations. Sunucu `as_of_date` itibarıyla hesaplanan bakiyeyi KİLİT ALTINDA yeniden hesaplar; `expected_computed_minor`'dan farklıysa
 * 409 RECONCILIATION_STALE (+ güncel değer). `adjust` verilirse fark kadar düzeltme hareketi AYNI işlemde (bugünün AÇIK ayı) yazılır.
 */
export async function createReconciliation({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw accountNotFound();
  }
  const input = parseReconciliation(body, now);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const accounts = await lockAccountRows(client, siteCode, [id]);
    const account = accounts.get(id);
    const existing = await client.query(`${RECONCILIATION_SELECT} WHERE r.site_code = $1 AND r.idempotency_key = $2`, [siteCode, input.idempotencyKey]);
    if (existing.rows?.[0]) {
      const row = existing.rows[0];
      const adjustmentRow =
        row.adjustment_movement_id === null || row.adjustment_movement_id === undefined
          ? null
          : (await client.query(`SELECT reason_code, note FROM account_movements WHERE id = $1`, [Number(row.adjustment_movement_id)])).rows?.[0] ?? null;
      const expectsAdjustment = input.adjust !== null && BigInt(row.difference_minor) !== 0n;
      if (
        Number(row.account_id) !== id ||
        row.as_of_date !== input.asOf ||
        BigInt(row.statement_balance_minor) !== BigInt(input.statementMinor) ||
        BigInt(row.computed_balance_minor) !== BigInt(input.expectedComputed) ||
        (row.note ?? null) !== (input.note ?? null) ||
        (adjustmentRow === null) !== !expectsAdjustment ||
        (adjustmentRow !== null && (adjustmentRow.reason_code !== input.adjust.reasonCode || (adjustmentRow.note ?? null) !== (input.adjust.note ?? null)))
      ) {
        throw idempotencyConflict();
      }
      return { replayed: true, reconciliation: mapReconciliationRow(row) };
    }
    if (input.asOf < account.opening_date) {
      throw beforeOpeningDate();
    }
    const computed = await computedBalanceAsOf(client, siteCode, id, input.asOf);
    if (computed !== BigInt(input.expectedComputed)) {
      throw reconciliationStale({ computed_balance_minor: minorToNumber(computed) });
    }
    const difference = BigInt(input.statementMinor) - computed;
    let adjustmentId = null;
    if (input.adjust !== null && difference !== 0n) {
      // Daha YENİ tarihli, düzeltmesi yazılmış mutabakat varsa eski tarihe ikinci düzeltme yazılamaz (fark iki tarihten önce oluşmuşsa çift düzeltme olurdu).
      const newer = await client.query(
        `SELECT 1 FROM account_reconciliations WHERE site_code = $1 AND account_id = $2 AND adjustment_movement_id IS NOT NULL AND as_of_date > $3::DATE LIMIT 1`,
        [siteCode, id, input.asOf],
      );
      if (newer.rows?.[0]) {
        throw reconciliationOrder();
      }
      if (account.is_active !== true) {
        throw accountInactive();
      }
      const todayIsoDate = today(now);
      const period = await resolveOpenPeriod(client, siteCode, now);
      const movement = await client.query(
        `
          INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, reason_code, note, created_by)
          VALUES ($1, $2, 'adjustment', $3::BIGINT, $4::DATE, $5::DATE, $6, $7, $8)
          RETURNING id
        `,
        [siteCode, id, difference.toString(), todayIsoDate, period, input.adjust.reasonCode, input.adjust.note, actorInfo.userCode],
      );
      adjustmentId = Number(movement.rows[0].id);
    }
    const inserted = await client.query(
      `
        INSERT INTO account_reconciliations (
          site_code, account_id, as_of_date, statement_balance_minor, computed_balance_minor, difference_minor, adjustment_movement_id, note, idempotency_key, reconciled_by
        )
        VALUES ($1, $2, $3::DATE, $4::BIGINT, $5::BIGINT, $6::BIGINT, $7, $8, $9, $10)
        RETURNING id
      `,
      [siteCode, id, input.asOf, String(input.statementMinor), computed.toString(), difference.toString(), adjustmentId, input.note, input.idempotencyKey, actorInfo.userCode],
    );
    const recId = Number(inserted.rows[0].id);
    await recordFinanceAudit(client, actor, 'finance.reconciliation.recorded', siteCode, recId, {
      account_id: id,
      difference_minor: minorToNumber(difference),
      adjusted: adjustmentId !== null,
    });
    const row = (await client.query(`${RECONCILIATION_SELECT} WHERE r.id = $1`, [recId])).rows[0];
    return { replayed: false, reconciliation: mapReconciliationRow(row) };
  });
}

void isPeriodClosed;
