// Kiracı borcunun malike devri (karar K1 / P1-1): önizleme, devir ve geri alma. Sözleşme: docs/PLATFORM_FINANS.md "Kiracı borcunun malike devri".
//
// İLKELER
//  - Devir ASLA kendiliğinden olmaz: yönetici önizlemeyi görüp onaylar (tutar + önizleme özeti gövdede; arada değişirse 409 LIABILITY_TRANSFER_CHANGED).
//  - Hesap modeli korunur; defter eklemelidir. Kalem bazlı ters kayıt + malik hesabına yeni borç (planlama: finance_liability_plan.js, SAF). Gecikme tazminatı devredilmez.
//  - Geri alınabilir: malik hesabı borçları ters çevrilir, kiracıya her kalemin TAM tutarı yeniden yazılır. Devirden sonra malik hesabına ödeme girildiyse geri alınamaz (409).
//  - İzli: finance_liability_transfers (kim / ne zaman / kaç kalem / ne kadar / neden) + denetim kaydı (tutar / sayı / kimlik; neden metni ASLA) + defterde source_kind = 'liability_transfer'.
//  - Yetki: yazma = yönetici / süper; okuma = + kurul (adsız); sakin / görevli 403 (rota katmanı). Kilit sırası finance_tx ile aynı: sites -> finance_post -> apartments -> users -> finans satırları.
//  - Tüm yazmalar TEK işlemde; yarım kalmaz. Aynı işlem anahtarı = aynı kayıt (200 replayed); farklı gövde = 409 IDEMPOTENCY_CONFLICT.

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { notifyApartmentUsers } from './apartment_mgmt_core.js';
import { registerAttentionSource } from './attention_registry.js';
import { PlatformError } from './errors.js';
import { formatMinor, objectOf } from './finance_4b_common.js';
import { resolveOpenPeriod } from './finance_4b_guard.js';
import {
  REASON_MAX,
  apartmentNotFound,
  idempotencyConflict,
  invalidBody,
  normalizeFreeText,
  parseIdempotencyKey,
  periodLabel,
  requireMinor,
  today,
} from './finance_common.js';
import { effectiveFund } from './finance_funds.js';
import {
  LIABILITY_SOURCE_KIND,
  MAX_TRANSFER_ITEMS,
  planLiabilityTransfer,
  planTransferReversal,
  reverseRequestFingerprint,
  transferPreviewHash,
  transferRequestFingerprint,
  transferWrites,
} from './finance_liability_plan.js';
import { minorToNumber, toBigInt } from './finance_money.js';
import { accountBalances, accountPartySql, currentTenantSql } from './finance_parties.js';
import { lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { parsePositiveId, toIso } from './people_common.js';

const conflict = (code, message, extra = null) => new PlatformError(409, code, message, extra);

export const noOwner = () => conflict('NO_OWNER', 'Dairenin kayıtlı bir malik kaydı yok; borç devredilemez. Önce malik kaydını ekleyin.');
export const nothingToTransfer = () => conflict('NOTHING_TO_TRANSFER', 'Devredilecek vadesi geçmiş, ödenmemiş kiracı borcu yok.');
export const tooManyItems = () => conflict('TOO_MANY_ITEMS', `Tek devirde en çok ${MAX_TRANSFER_ITEMS} borç kalemi devredilebilir.`);
export const transferChanged = (extra) =>
  conflict('LIABILITY_TRANSFER_CHANGED', 'Kiracı borçları önizlemeden sonra değişti. Önizlemeyi yenileyip tekrar inceleyin.', extra);
export const transferNotFound = () => new PlatformError(404, 'LIABILITY_TRANSFER_NOT_FOUND', 'Devir kaydı bulunamadı.');
export const transferAlreadyReversed = () => conflict('LIABILITY_TRANSFER_ALREADY_REVERSED', 'Bu devir zaten geri alınmış.');
export const transferNotReversible = () => conflict('LIABILITY_TRANSFER_NOT_REVERSIBLE', 'Geri alma kaydı tekrar geri alınamaz; gerekirse yeni bir devir yapın.');
export const ownerPaidAfterTransfer = () =>
  conflict(
    'LIABILITY_TRANSFER_OWNER_PAID',
    'Devirden sonra ev sahibi hesabına ödeme girilmiş; devir geri alınamaz. Önce o ödemeyi düzeltin ya da fazlasını ayrıca iade edin.',
  );

const HASH_PATTERN = /^[0-9a-f]{64}$/;

// --- Gövdeler -------------------------------------------------------------------------------------------------------------------------

/** POST apartments/:id/liability-transfer gövdesi. */
export function parseTransferInput(body) {
  const input = objectOf(body);
  if (typeof input.expected_hash !== 'string' || !HASH_PATTERN.test(input.expected_hash)) {
    throw invalidBody('Önizleme özeti (expected_hash) zorunludur; önizlemeyi yenileyin.');
  }
  return {
    expectedTotalMinor: requireMinor(input.expected_total_minor, 'Beklenen toplam', { min: 1 }),
    expectedHash: input.expected_hash,
    reason: normalizeFreeText(input.reason, { label: 'Devir nedeni', max: REASON_MAX, required: true }),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

/** POST liability-transfers/:id/reverse gövdesi. */
export function parseTransferReverseInput(body) {
  const input = objectOf(body);
  return {
    reason: normalizeFreeText(input.reason, { label: 'Geri alma nedeni', max: REASON_MAX, required: true }),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

// --- Okuma ----------------------------------------------------------------------------------------------------------------------------

const ACCOUNT_L = accountPartySql('l');

/** Kiracı hesabının TÜM defter satırları -> planlama girdisi (pg metin BIGINT -> BigInt; kasa etkin kasa). */
export async function loadTenantLedger(db, siteCode, apartmentId) {
  const result = await db.query(
    `
      SELECT l.id, l.kind, l.amount_minor::TEXT AS amount_minor, to_char(l.entry_date, 'YYYY-MM-DD') AS entry_date, to_char(l.due_date, 'YYYY-MM-DD') AS due_date,
             l.reverses_entry_id, l.late_fee_run_id, l.source_kind, l.definition_name, l.definition_id, l.fund, fd.charge_party AS def_charge_party, fd.kind AS def_kind
      FROM ledger_entries l
      LEFT JOIN fee_definitions fd ON fd.id = l.definition_id
      WHERE l.site_code = $1 AND l.apartment_id = $2 AND ${ACCOUNT_L} = 'tenant'
      ORDER BY l.id
    `,
    [siteCode, apartmentId],
  );
  return (result.rows ?? []).map((row) => ({
    id: Number(row.id),
    kind: row.kind,
    amount: toBigInt(row.amount_minor),
    entryDate: row.entry_date,
    dueDate: row.due_date ?? null,
    reversesId: row.reverses_entry_id === null || row.reverses_entry_id === undefined ? null : Number(row.reverses_entry_id),
    lateFeeRunId: row.late_fee_run_id === null || row.late_fee_run_id === undefined ? null : Number(row.late_fee_run_id),
    sourceKind: row.source_kind ?? null,
    definitionName: row.definition_name ?? null,
    fund: row.kind === 'charge' ? effectiveFund(row) : null,
  }));
}

/** Dairede güncel, etkin bir MALİK kaydı var mı. */
export async function hasCurrentOwner(db, siteCode, apartmentId) {
  const result = await db.query(
    `
      SELECT 1
      FROM apartment_residencies r
      INNER JOIN site_people sp ON sp.id = r.person_id AND sp.site_code = $1 AND sp.is_active = TRUE
      WHERE r.apartment_id = $2 AND r.relation = 'owner' AND r.is_current = TRUE
      LIMIT 1
    `,
    [siteCode, apartmentId],
  );
  return Boolean(result.rows?.[0]);
}

async function apartmentExists(db, siteCode, apartmentId) {
  const result = await db.query(`SELECT 1 FROM apartments WHERE id = $1 AND site_code = $2`, [apartmentId, siteCode]);
  return Boolean(result.rows?.[0]);
}

const itemBody = (item) => ({
  entry_id: item.entryId,
  name: item.name,
  due_date: item.dueDate,
  original_minor: minorToNumber(item.originalMinor),
  remaining_minor: minorToNumber(item.remainingMinor),
  paid_minor: minorToNumber(item.paidMinor),
  fund: item.fund,
});

/**
 * GET apartments/:id/liability-transfer/preview -> kalemler, tazminat istisnası, toplam ve önizleme özeti. Salt okunur (yazmaz).
 * `can_transfer`: malik kaydı var ve devredilecek kalem var.
 */
export async function previewLiabilityTransfer(siteCode, rawApartmentId, now = new Date(), db = pool) {
  const apartmentId = parsePositiveId(rawApartmentId);
  if (apartmentId === null || !(await apartmentExists(db, siteCode, apartmentId))) {
    throw apartmentNotFound();
  }
  const plan = planLiabilityTransfer(await loadTenantLedger(db, siteCode, apartmentId), { today: today(now) });
  const hasOwner = await hasCurrentOwner(db, siteCode, apartmentId);
  const balances = await accountBalances(db, { siteCode, apartmentId, onDate: today(now) });
  return {
    apartment_id: apartmentId,
    currency: 'TRY',
    has_owner: hasOwner,
    can_transfer: hasOwner && plan.items.length > 0 && plan.items.length <= MAX_TRANSFER_ITEMS,
    items: plan.items.map(itemBody),
    excluded_late_fee: plan.excludedLateFee.map((item) => ({
      entry_id: item.entryId,
      name: item.name,
      due_date: item.dueDate,
      remaining_minor: minorToNumber(item.remainingMinor),
    })),
    item_count: plan.items.length,
    total_minor: minorToNumber(plan.totalMinor),
    preview_hash: transferPreviewHash({ apartmentId, items: plan.items }),
    tenant_balance_minor: balances.tenant.balance_minor,
    owner_balance_minor: balances.owner.balance_minor,
  };
}

const TRANSFER_SELECT = `
  SELECT t.request_fingerprint, t.id, t.apartment_id, t.from_party, t.to_party, t.total_minor::TEXT AS total_minor, t.item_count, t.reason, t.reverses_transfer_id,
         rv.id AS reversed_by_transfer_id, t.created_at, u.full_name AS created_by_name
  FROM finance_liability_transfers t
  LEFT JOIN finance_liability_transfers rv ON rv.reverses_transfer_id = t.id
  LEFT JOIN users u ON u.user_code = t.created_by
`;

export function mapTransferRow(row) {
  return {
    id: Number(row.id),
    apartment_id: Number(row.apartment_id),
    kind: row.reverses_transfer_id === null || row.reverses_transfer_id === undefined ? 'transfer' : 'reversal',
    from_party: row.from_party,
    to_party: row.to_party,
    total_minor: minorToNumber(row.total_minor),
    item_count: Number(row.item_count),
    reason: row.reason,
    reverses_transfer_id: row.reverses_transfer_id === null || row.reverses_transfer_id === undefined ? null : Number(row.reverses_transfer_id),
    reversed_by_transfer_id: row.reversed_by_transfer_id === null || row.reversed_by_transfer_id === undefined ? null : Number(row.reversed_by_transfer_id),
    created_by_name: row.created_by_name ?? null,
    created_at: toIso(row.created_at),
  };
}

async function ownerPaidAfter(db, siteCode, apartmentId, afterEntryId) {
  const result = await db.query(
    `
      SELECT 1 FROM ledger_entries p
      WHERE p.site_code = $1 AND p.apartment_id = $2 AND ${accountPartySql('p')} = 'owner' AND p.kind = 'payment' AND p.id > $3
        AND NOT EXISTS (SELECT 1 FROM ledger_entries r WHERE r.reverses_entry_id = p.id)
      LIMIT 1
    `,
    [siteCode, apartmentId, afterEntryId],
  );
  return Boolean(result.rows?.[0]);
}

/** GET apartments/:id/liability-transfers -> { items } (yeni -> eski, en çok 50). Etkin devirde `reversible` (geri alınabilir mi) hesaplanır. */
export async function listLiabilityTransfers(siteCode, rawApartmentId, db = pool) {
  const apartmentId = parsePositiveId(rawApartmentId);
  if (apartmentId === null || !(await apartmentExists(db, siteCode, apartmentId))) {
    throw apartmentNotFound();
  }
  const result = await db.query(`${TRANSFER_SELECT} WHERE t.site_code = $1 AND t.apartment_id = $2 ORDER BY t.id DESC LIMIT 50`, [siteCode, apartmentId]);
  const items = [];
  for (const row of result.rows ?? []) {
    const item = mapTransferRow(row);
    let reversible = false;
    if (item.kind === 'transfer' && item.reversed_by_transfer_id === null) {
      const first = await db.query(
        `SELECT MIN(id) AS first_id FROM ledger_entries WHERE site_code = $1 AND source_kind = $2 AND source_id = $3`,
        [siteCode, LIABILITY_SOURCE_KIND, item.id],
      );
      const firstId = first.rows?.[0]?.first_id;
      reversible = firstId === null || firstId === undefined ? false : !(await ownerPaidAfter(db, siteCode, apartmentId, Number(firstId)));
    }
    items.push({ ...item, reversible });
  }
  return { items };
}

// --- Yazma ----------------------------------------------------------------------------------------------------------------------------

async function lockApartment(client, siteCode, apartmentId) {
  const result = await client.query(`SELECT id FROM apartments WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [apartmentId, siteCode]);
  if (!result.rows?.[0]) {
    throw apartmentNotFound();
  }
}

async function loadTransferByKey(client, siteCode, key) {
  const result = await client.query(
    `${TRANSFER_SELECT} WHERE t.site_code = $1 AND t.idempotency_key = $2 LIMIT 1`,
    [siteCode, key],
  );
  return result.rows?.[0] ?? null;
}

const isUniqueViolation = (error, constraint) => error?.code === '23505' && String(error?.constraint ?? '') === constraint;

/** Devir sonrası iki hesabın bakiyeleri (yanıt için). */
async function balancesOf(client, siteCode, apartmentId, now) {
  const balances = await accountBalances(client, { siteCode, apartmentId, onDate: today(now) });
  return { tenant_balance_minor: balances.tenant.balance_minor, owner_balance_minor: balances.owner.balance_minor };
}

/**
 * POST apartments/:id/liability-transfer -> { replayed, transfer, tenant_balance_minor, owner_balance_minor }.
 * Önizlemedeki kalemler / toplam / özet değiştiyse 409 LIABILITY_TRANSFER_CHANGED. Malik kaydı yoksa 409 NO_OWNER. Devredilecek kalem yoksa 409 NOTHING_TO_TRANSFER.
 */
export async function createLiabilityTransfer({ siteCode, rawApartmentId, body, actor, now = new Date() }) {
  const apartmentId = parsePositiveId(rawApartmentId);
  if (apartmentId === null) {
    throw apartmentNotFound();
  }
  const input = parseTransferInput(body);
  const actorInfo = actorFromAuthUser(actor);
  const fingerprint = transferRequestFingerprint({ apartmentId, expectedTotalMinor: input.expectedTotalMinor, expectedHash: input.expectedHash, reason: input.reason });
  return withFinanceTransaction(siteCode, async (client) => {
    await lockApartment(client, siteCode, apartmentId);
    await lockActorRow(client, actorInfo);
    const existing = await loadTransferByKey(client, siteCode, input.idempotencyKey);
    if (existing) {
      if (existing.request_fingerprint !== fingerprint || Number(existing.apartment_id) !== apartmentId || existing.reverses_transfer_id !== null) {
        throw idempotencyConflict();
      }
      return { replayed: true, transfer: mapTransferRow(existing), ...(await balancesOf(client, siteCode, apartmentId, now)) };
    }
    if (!(await hasCurrentOwner(client, siteCode, apartmentId))) {
      throw noOwner();
    }
    const plan = planLiabilityTransfer(await loadTenantLedger(client, siteCode, apartmentId), { today: today(now) });
    if (plan.items.length === 0) {
      throw nothingToTransfer();
    }
    if (plan.items.length > MAX_TRANSFER_ITEMS) {
      throw tooManyItems();
    }
    const hash = transferPreviewHash({ apartmentId, items: plan.items });
    if (plan.totalMinor !== BigInt(input.expectedTotalMinor) || hash !== input.expectedHash) {
      throw transferChanged({ total_minor: minorToNumber(plan.totalMinor), item_count: plan.items.length, preview_hash: hash });
    }
    const openPeriod = await resolveOpenPeriod(client, siteCode, now);
    const todayIso = today(now);
    const inserted = await client.query(
      `
        INSERT INTO finance_liability_transfers (site_code, apartment_id, from_party, to_party, total_minor, item_count, reason, preview_hash, idempotency_key, request_fingerprint, created_by)
        VALUES ($1, $2, 'tenant', 'owner', $3::BIGINT, $4, $5, $6, $7, $8, $9)
        RETURNING id
      `,
      [siteCode, apartmentId, String(plan.totalMinor), plan.items.length, input.reason, hash, input.idempotencyKey, fingerprint, actorInfo.userCode],
    );
    const transferId = Number(inserted.rows[0].id);
    const writes = transferWrites(plan.items);
    const base = { siteCode, apartmentId, transferId, openPeriod, todayIso, actorUserCode: actorInfo.userCode };
    try {
      await insertTenantReversals(client, { ...base, entryIds: writes.reversals, reason: input.reason });
    } catch (error) {
      if (isUniqueViolation(error, 'uq_ledger_entries_reverses')) {
        throw transferChanged({ total_minor: minorToNumber(plan.totalMinor), item_count: plan.items.length, preview_hash: hash });
      }
      throw error;
    }
    const itemById = new Map(plan.items.map((item) => [item.entryId, item]));
    await insertChargesLike(client, {
      ...base,
      accountParty: 'tenant',
      description: 'Devir sonrası kalan borç (ödenmiş kısım)',
      rows: writes.tenantCharges.map((row) => ({ originalId: row.entryId, amountMinor: row.amountMinor, fund: itemById.get(row.entryId).fund })),
    });
    await insertChargesLike(client, {
      ...base,
      accountParty: 'owner',
      description: 'Kiracı hesabından devreden borç',
      rows: writes.ownerCharges.map((row) => ({ originalId: row.entryId, amountMinor: row.amountMinor, fund: itemById.get(row.entryId).fund })),
    });
    await recordFinanceAudit(client, actor, 'finance.liability_transfer.created', siteCode, transferId, {
      apartment_id: apartmentId,
      total_minor: minorToNumber(plan.totalMinor),
      item_count: plan.items.length,
      from: 'tenant',
      to: 'owner',
      period: periodLabel(openPeriod),
    });
    await notifyOwners(client, siteCode, apartmentId, `Kiracı hesabındaki ${formatMinor(plan.totalMinor)} ₺ tutarında ödenmemiş borç (${plan.items.length} kalem), site yönetimi tarafından ev sahibi hesabınıza devredildi.`);
    const row = await client.query(`${TRANSFER_SELECT} WHERE t.id = $1`, [transferId]);
    return { replayed: false, transfer: mapTransferRow(row.rows[0]), ...(await balancesOf(client, siteCode, apartmentId, now)) };
  });
}

/** Kiracı hesabındaki asıl borçların tersi (kalem başına; DB tetikleyicisi aynalamayı, hesabı ve kasayı zorlar). */
async function insertTenantReversals(client, { siteCode, apartmentId, transferId, openPeriod, todayIso, actorUserCode, entryIds, reason }) {
  if (entryIds.length === 0) return 0;
  const result = await client.query(
    `
      INSERT INTO ledger_entries (
        site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, definition_id, definition_name, run_id, payer_party,
        reverses_entry_id, reversal_reason, created_by, late_fee_run_id, account_party, source_kind, source_id, fund
      )
      SELECT l.site_code, l.apartment_id, 'reversal', -l.amount_minor, $3::DATE, $4::DATE, l.due_date, l.definition_id, l.definition_name, l.run_id, l.payer_party,
             l.id, $5::TEXT, $6::INTEGER, l.late_fee_run_id, 'tenant', 'liability_transfer', $7::BIGINT, l.fund
      FROM ledger_entries l
      WHERE l.site_code = $1 AND l.apartment_id = $2 AND l.id = ANY($8::BIGINT[]) AND l.kind = 'charge'
      ORDER BY l.id
      RETURNING id
    `,
    [siteCode, apartmentId, openPeriod, todayIso, reason, actorUserCode, transferId, entryIds],
  );
  if ((result.rows ?? []).length !== entryIds.length) {
    throw transferChanged({ item_count: (result.rows ?? []).length });
  }
  return result.rows.length;
}

/**
 * Borç satırları (kiracı ya da malik hesabı): her satır asıl kalemin vadesini / adını / ödeyen anlık görüntüsünü taşır; run_id ve tanım bağı YOKTUR (borçlandırma çalıştırması
 * satır sayısı bozulmasın), kasa AÇIK yazılır (etkin kasa).
 */
async function insertChargesLike(client, { siteCode, apartmentId, transferId, openPeriod, todayIso, actorUserCode, accountParty, description, rows }) {
  if (rows.length === 0) return 0;
  const result = await client.query(
    `
      INSERT INTO ledger_entries (
        site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, definition_name, payer_party, account_party, description, created_by,
        source_kind, source_id, fund
      )
      SELECT l.site_code, l.apartment_id, 'charge', v.amount, $3::DATE, $4::DATE, l.due_date, l.definition_name, l.payer_party, $5::TEXT, $6::TEXT, $7::INTEGER,
             'liability_transfer', $8::BIGINT, v.fund
      FROM unnest($9::BIGINT[], $10::BIGINT[], $11::TEXT[]) AS v(original_id, amount, fund)
      INNER JOIN ledger_entries l ON l.id = v.original_id AND l.site_code = $1 AND l.apartment_id = $2
      ORDER BY v.original_id
      RETURNING id
    `,
    [
      siteCode,
      apartmentId,
      openPeriod,
      todayIso,
      accountParty,
      description,
      actorUserCode,
      transferId,
      rows.map((row) => row.originalId),
      rows.map((row) => String(row.amountMinor)),
      rows.map((row) => row.fund ?? null),
    ],
  );
  if ((result.rows ?? []).length !== rows.length) {
    throw new Error('liability transfer: beklenen defter satırı sayısı yazılamadı');
  }
  return result.rows.length;
}

/** Malik(ler)e uygulama içi bildirim (best-effort: hata devri bozmaz; notifyApartmentUsers kendi SAVEPOINT'ini kullanır). */
async function notifyOwners(client, siteCode, apartmentId, message) {
  try {
    const owners = await client.query(
      `
        SELECT DISTINCT sp.user_code
        FROM apartment_residencies r
        INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE AND sp.user_code IS NOT NULL
        WHERE r.apartment_id = $1 AND r.relation = 'owner' AND r.is_current = TRUE
      `,
      [apartmentId],
    );
    await notifyApartmentUsers(client, { siteCode, apartmentId, userCodes: (owners.rows ?? []).map((row) => Number(row.user_code)), kind: 'liability_transfer', message });
  } catch (_error) {
    // bildirim yazılamaması devri / geri almayı bozmaz
  }
}

/**
 * POST liability-transfers/:id/reverse -> { replayed, transfer, tenant_balance_minor, owner_balance_minor }.
 * Yalnız etkin (geri alınmamış) devir geri alınır; geri alma kaydı tekrar geri alınamaz. Devirden sonra ev sahibi hesabına ödeme girildiyse 409.
 */
export async function reverseLiabilityTransfer({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw transferNotFound();
  }
  const input = parseTransferReverseInput(body);
  const actorInfo = actorFromAuthUser(actor);
  const fingerprint = reverseRequestFingerprint({ transferId: id, reason: input.reason });
  return withFinanceTransaction(siteCode, async (client) => {
    // Kilit sırası: daire (kilitsiz okuma -> daire kilidi) -> kullanıcı -> devir / defter satırları.
    const head = await client.query(`SELECT apartment_id FROM finance_liability_transfers WHERE id = $1 AND site_code = $2`, [id, siteCode]);
    if (!head.rows?.[0]) {
      throw transferNotFound();
    }
    const apartmentId = Number(head.rows[0].apartment_id);
    await lockApartment(client, siteCode, apartmentId);
    await lockActorRow(client, actorInfo);
    const existing = await loadTransferByKey(client, siteCode, input.idempotencyKey);
    if (existing) {
      if (existing.request_fingerprint !== fingerprint || Number(existing.reverses_transfer_id) !== id) {
        throw idempotencyConflict();
      }
      return { replayed: true, transfer: mapTransferRow(existing), ...(await balancesOf(client, siteCode, apartmentId, now)) };
    }
    const original = await client.query(`${TRANSFER_SELECT} WHERE t.id = $1 AND t.site_code = $2`, [id, siteCode]);
    const target = original.rows[0];
    if (!target) {
      throw transferNotFound();
    }
    if (target.reverses_transfer_id !== null && target.reverses_transfer_id !== undefined) {
      throw transferNotReversible();
    }
    if (target.reversed_by_transfer_id !== null && target.reversed_by_transfer_id !== undefined) {
      throw transferAlreadyReversed();
    }
    const rows = await loadTransferLedger(client, siteCode, id);
    if (rows.length === 0) {
      throw transferNotFound();
    }
    if (await ownerPaidAfter(client, siteCode, apartmentId, Math.min(...rows.map((row) => row.id)))) {
      throw ownerPaidAfterTransfer();
    }
    const plan = planTransferReversal(rows);
    const openPeriod = await resolveOpenPeriod(client, siteCode, now);
    const todayIso = today(now);
    const inserted = await client.query(
      `
        INSERT INTO finance_liability_transfers (
          site_code, apartment_id, from_party, to_party, total_minor, item_count, reason, preview_hash, reverses_transfer_id, idempotency_key, request_fingerprint, created_by
        )
        VALUES ($1, $2, 'owner', 'tenant', $3::BIGINT, $4, $5, NULL, $6, $7, $8, $9)
        RETURNING id
      `,
      [siteCode, apartmentId, String(toBigInt(target.total_minor)), Number(target.item_count), input.reason, id, input.idempotencyKey, fingerprint, actorInfo.userCode],
    );
    const reverseId = Number(inserted.rows[0].id);
    const base = { siteCode, apartmentId, transferId: reverseId, openPeriod, todayIso, actorUserCode: actorInfo.userCode };
    if (plan.reverseIds.length > 0) {
      const reversed = await client.query(
        `
          INSERT INTO ledger_entries (
            site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, definition_id, definition_name, run_id, payer_party,
            reverses_entry_id, reversal_reason, created_by, late_fee_run_id, account_party, source_kind, source_id, fund
          )
          SELECT l.site_code, l.apartment_id, 'reversal', -l.amount_minor, $3::DATE, $4::DATE, l.due_date, l.definition_id, l.definition_name, l.run_id, l.payer_party,
                 l.id, $5::TEXT, $6::INTEGER, l.late_fee_run_id, ${ACCOUNT_L}, 'liability_transfer', $7::BIGINT, l.fund
          FROM ledger_entries l
          WHERE l.site_code = $1 AND l.apartment_id = $2 AND l.id = ANY($8::BIGINT[]) AND l.kind = 'charge'
          ORDER BY l.id
          RETURNING id
        `,
        [siteCode, apartmentId, openPeriod, todayIso, input.reason, actorInfo.userCode, reverseId, plan.reverseIds],
      );
      if ((reversed.rows ?? []).length !== plan.reverseIds.length) {
        throw new Error('liability transfer reversal: beklenen ters kayıt sayısı yazılamadı');
      }
    }
    await insertChargesLike(client, {
      ...base,
      accountParty: 'tenant',
      description: 'Devir geri alındı: borç kiracı hesabına döndü',
      rows: plan.reinstate.map((row) => ({ originalId: row.originalEntryId, amountMinor: row.amountMinor, fund: row.fund })),
    });
    await recordFinanceAudit(client, actor, 'finance.liability_transfer.reversed', siteCode, reverseId, {
      apartment_id: apartmentId,
      reverses_transfer_id: id,
      total_minor: minorToNumber(toBigInt(target.total_minor)),
      item_count: Number(target.item_count),
      period: periodLabel(openPeriod),
    });
    const row = await client.query(`${TRANSFER_SELECT} WHERE t.id = $1`, [reverseId]);
    return { replayed: false, transfer: mapTransferRow(row.rows[0]), ...(await balancesOf(client, siteCode, apartmentId, now)) };
  });
}

/** Bir devrin yazdığı defter satırları (+ ters çevrilen asılları): geri alma planı girdisi. */
async function loadTransferLedger(client, siteCode, transferId) {
  const result = await client.query(
    `
      SELECT l.id, l.kind, ${ACCOUNT_L} AS account_party, l.amount_minor::TEXT AS amount_minor,
             EXISTS (SELECT 1 FROM ledger_entries r WHERE r.reverses_entry_id = l.id) AS reversed,
             o.id AS o_id, o.amount_minor::TEXT AS o_amount, to_char(o.due_date, 'YYYY-MM-DD') AS o_due, o.definition_name AS o_name, o.kind AS o_kind,
             o.fund AS o_fund, o.source_kind AS o_source_kind, o.late_fee_run_id AS o_late_fee_run_id, o.definition_id AS o_definition_id,
             fd.charge_party AS o_def_charge_party, fd.kind AS o_def_kind
      FROM ledger_entries l
      LEFT JOIN ledger_entries o ON o.id = l.reverses_entry_id AND l.kind = 'reversal'
      LEFT JOIN fee_definitions fd ON fd.id = o.definition_id
      WHERE l.site_code = $1 AND l.source_kind = $2 AND l.source_id = $3
      ORDER BY l.id
    `,
    [siteCode, LIABILITY_SOURCE_KIND, transferId],
  );
  return (result.rows ?? []).map((row) => ({
    id: Number(row.id),
    kind: row.kind,
    accountParty: row.account_party,
    amount: toBigInt(row.amount_minor),
    reversedBy: row.reversed === true ? 1 : null,
    original:
      row.kind === 'reversal' && row.o_id !== null && row.o_id !== undefined
        ? {
            id: Number(row.o_id),
            amount: toBigInt(row.o_amount),
            dueDate: row.o_due ?? null,
            definitionName: row.o_name ?? null,
            fund: effectiveFund({
              fund: row.o_fund,
              kind: row.o_kind,
              amount_minor: row.o_amount,
              source_kind: row.o_source_kind,
              late_fee_run_id: row.o_late_fee_run_id,
              definition_id: row.o_definition_id,
              def_charge_party: row.o_def_charge_party,
              def_kind: row.o_def_kind,
            }),
          }
        : null,
  }));
}

// --- Dikkat kaydı: kiracısı AYRILMIŞ ama kiracı hesabında ödenmemiş borcu duran daireler (yönetici devir kararı verebilir) -----------------------------------------------------------

/** Güncel kiracısı olmayan ve kiracı hesabı borçlu olan daire sayısı + toplam borç (kuruş). */
export async function tenantDebtPendingAttention(db, siteCode) {
  const result = await db.query(
    `
      SELECT COUNT(*)::INT AS n, COALESCE(SUM(t.balance), 0)::TEXT AS total
      FROM (
        SELECT l.apartment_id, SUM(l.amount_minor) AS balance
        FROM ledger_entries l
        WHERE l.site_code = $1 AND ${ACCOUNT_L} = 'tenant'
        GROUP BY l.apartment_id
        HAVING SUM(l.amount_minor) > 0
      ) t
      INNER JOIN apartments a ON a.id = t.apartment_id AND a.site_code = $1
      WHERE NOT ${currentTenantSql('a')}
    `,
    [siteCode],
  );
  return { count: Number(result.rows?.[0]?.n ?? 0), total_minor: minorToNumber(result.rows?.[0]?.total ?? '0') };
}

registerAttentionSource({ key: 'tenant_debt_pending_transfer', module: 'finance', run: (db, siteCode) => tenantDebtPendingAttention(db, siteCode) });
