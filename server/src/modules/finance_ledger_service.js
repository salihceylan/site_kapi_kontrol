// Aidat ve Finans (Faz 4a): elle tahsilat, ters kayıt (düzeltme), tahsilat düzeltme ve dönem kapatma.
//
// Sözleşme: docs/PLATFORM_FINANS.md. Defter eklemelidir (append-only): kayıt SİLİNMEZ, DEĞİŞTİRİLMEZ; yanlış kayıt ters kayıtla düzeltilir.
//  - Tüm yazmalar finance_tx.js ile: sites FOR KEY SHARE -> finance_post:<site> advisory kilidi -> apartments (FOR KEY SHARE) -> finans tabloları.
//    Defter satırlarına satır kilidi KONMAZ (değişmezler; tekillik kısmi tekil indekslerle ve advisory kilitle sağlanır): kullanıcı silme
//    (apartments -> users -> ledger SET NULL) ile ters sıra oluşmaz.
//  - İdempotans: `idempotency_key` tekrarı AYNI kaydı döndürür (200); aynı anahtar FARKLI bir işlem için gelirse 409 IDEMPOTENCY_CONFLICT.
//  - Kapalı döneme kayıt eklenemez (409 PERIOD_CLOSED): bir ay, ay <= MAX(kapalı dönem) ise KAPALIDIR (ilk kapatılan aydan önceki aylar dahil). Ters kayıt AÇIK
//    dönemdedir (bugünün açık ayı; bugünün ayı kapalıysa sonraki açık ay).
//  - Kilit sırası: ... apartments -> users(işlemi yapan; lockActorRow) -> finans satırları (kullanıcı silmeyle 40P01 olmasın).
//  - Audit `details` yalnız tutar / sayı / dönem / tür içerir: açıklama, neden metni ve kişi adı ASLA yazılmaz.

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import {
  addMonths,
  apartmentNotFound,
  closableMonths,
  computeOpenPeriod,
  currentPeriod,
  entryAccountParty,
  entryAlreadyReversed,
  entryNotCorrectable,
  entryNotFound,
  entryNotReversible,
  idempotencyConflict,
  latestClosedPeriod,
  mapEntryRow,
  minEntryDate,
  parseCorrectInput,
  parsePaymentInput,
  parsePeriod,
  parseReverseInput,
  periodClosed,
  periodLabel,
  periodNotClosable,
  periodNotReopenable,
  periodOfDate,
  today,
} from './finance_common.js';
import { periodHasLateFeeRun } from './finance_4b_common.js';
import {
  assertNoUnassignedPayments,
  findCollectionMovement,
  lockAccountRows,
  mirrorCollectionForEntry,
  resolvePaymentAccount,
} from './finance_accounts.js';
import { loadPaymentFundSplit } from './finance_funds.js';
import { MANAGED_SOURCE_KINDS, entryManagedByFlow, hasApprovedRefund, refundBlocksPaymentChange } from './finance_refund_guard.js';
import { minorToNumber } from './finance_money.js';
import { loadAccountBalance, postPayment } from './finance_parties.js';
import { activeReceiptRef, cancelActiveReceiptForEntry } from './finance_receipts.js';
import { isPeriodClosed, lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { parsePositiveId } from './people_common.js';

// ---------------------------------------------------------------------------
// Ortak okumalar
// ---------------------------------------------------------------------------

/** Ekstre satırı (Entry) SELECT'i; çağıran WHERE ekler. */
export const ENTRY_SELECT = `
  SELECT
    l.id, l.apartment_id, l.kind, l.amount_minor::text AS amount_minor, to_char(l.period, 'YYYY-MM-DD') AS period,
    to_char(l.entry_date, 'YYYY-MM-DD') AS entry_date, to_char(l.due_date, 'YYYY-MM-DD') AS due_date,
    l.description, l.method, l.payer_party, l.definition_name, l.reverses_entry_id, rv.id AS reversed_by_entry_id,
    l.reversal_reason, u.full_name AS created_by_name, l.created_at, l.definition_id, l.run_id, l.idempotency_key, l.late_fee_run_id,
    rc.id AS receipt_id, rc.receipt_year, rc.receipt_no, rc.cancel_year AS receipt_cancel_year, rc.cancel_no AS receipt_cancel_no,
    l.account_party, l.source_kind, l.source_id, l.fund, fd.charge_party AS def_charge_party, fd.kind AS def_kind
  FROM ledger_entries l
  LEFT JOIN ledger_entries rv ON rv.reverses_entry_id = l.id
  LEFT JOIN fee_definitions fd ON fd.id = l.definition_id
  LEFT JOIN users u ON u.user_code = l.created_by
  LEFT JOIN LATERAL (
    SELECT r.id, r.receipt_year, r.receipt_no, c.receipt_year AS cancel_year, c.receipt_no AS cancel_no
    FROM receipts r LEFT JOIN receipts c ON c.cancels_receipt_id = r.id
    WHERE r.ledger_entry_id = l.id AND r.kind = 'collection'
    ORDER BY r.id DESC LIMIT 1
  ) rc ON l.kind = 'payment'
`;

async function loadEntryRow(db, siteCode, id) {
  const result = await db.query(`${ENTRY_SELECT} WHERE l.id = $1 AND l.site_code = $2 LIMIT 1`, [id, siteCode]);
  return result.rows?.[0] ?? null;
}

async function loadEntryByKey(db, siteCode, key) {
  const result = await db.query(`${ENTRY_SELECT} WHERE l.site_code = $1 AND l.idempotency_key = $2 LIMIT 1`, [siteCode, key]);
  return result.rows?.[0] ?? null;
}

/** Bir dairenin bakiyesi (kuruş, işaretli toplam; pozitif = borç). */
export async function loadApartmentBalance(db, siteCode, apartmentId) {
  const result = await db.query(
    `SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS balance FROM ledger_entries WHERE site_code = $1 AND apartment_id = $2`,
    [siteCode, apartmentId],
  );
  return minorToNumber(result.rows?.[0]?.balance ?? '0');
}

/** Bir tahsilatin su anki kasa dagitimi (hesabin tum satirlariyla; finance_funds.allocateFunds). */
export function paymentSplit(db, siteCode, apartmentId, accountParty, paymentId) {
  return loadPaymentFundSplit(db, { siteCode, apartmentId, accountParty, paymentId, toNumber: minorToNumber });
}

async function lockApartment(client, siteCode, apartmentId) {
  const result = await client.query(
    `SELECT id, responsible_party FROM apartments WHERE id = $1 AND site_code = $2 FOR KEY SHARE`,
    [apartmentId, siteCode],
  );
  const row = result.rows?.[0];
  if (!row) {
    throw apartmentNotFound();
  }
  return row;
}

/** Site kapanışları (artan sırada, 'YYYY-MM-DD'). */
async function loadClosures(db, siteCode) {
  const result = await db.query(
    `
      SELECT to_char(c.period, 'YYYY-MM-DD') AS period, c.closed_at, u.full_name AS closed_by_name
      FROM finance_period_closures c
      LEFT JOIN users u ON u.user_code = c.closed_by
      WHERE c.site_code = $1
      ORDER BY c.period
    `,
    [siteCode],
  );
  return result.rows ?? [];
}

const toIsoOrNull = (value) => (value === null || value === undefined ? null : new Date(value).toISOString());

/**
 * GET periods gövdesi: { closed_through (en son kapalı ay), items (kapatma satırları, yeni -> eski), open_period, closable }.
 * `closable` (yeni -> eski, en çok 12): kapalı ay yoksa bu ay ve önceki 11 ay; varsa closed_through + 1 aydan bu aya kadar bütün aylar, aksi halde boş.
 */
export function periodsBody(closures, now = new Date()) {
  const periods = closures.map((row) => row.period);
  const last = latestClosedPeriod(periods);
  return {
    closed_through: last === null ? null : periodLabel(last),
    closable: closableMonths(currentPeriod(now), periods).map(periodLabel),
    items: [...closures].reverse().map((row) => ({
      period: periodLabel(row.period),
      closed_at: toIsoOrNull(row.closed_at),
      closed_by_name: row.closed_by_name ?? null,
    })),
    open_period: periodLabel(computeOpenPeriod(currentPeriod(now), new Set(periods))),
  };
}

export async function listPeriods(siteCode, now = new Date(), db = pool) {
  return periodsBody(await loadClosures(db, siteCode), now);
}

// ---------------------------------------------------------------------------
// Tahsilat
// ---------------------------------------------------------------------------

/**
 * POST payments -> { replayed, entry, balance_minor, account_balance_minor, receipt, movement_id }. Tahsilat tutarı pozitif girilir, defterde negatif yazılır.
 * Fazla ödeme alacak olur. İki hesap (İP-1A): yazma TEK giriş noktası finance_parties.postPayment'tır; `account_party` verilmezse (eski istemci) vadesi en
 * eski açık borcu olan hesap seçilir. Dönem = tahsilat tarihinin ayı; kapalıysa 409 PERIOD_CLOSED. Aynı işlem anahtarı = aynı kayıt. Faz 4b: `account_id`
 * (kasa / banka; hesap varsa zorunlu) AYNI işlemde `collection` hareketini yazar; site ayarı açıksa makbuz AYNI işlemde düzenlenir.
 * `balance_minor` dairenin iki hesabının toplamıdır (eski istemci uyumu); `account_balance_minor` tahsilatın yazıldığı hesabın bakiyesi.
 */
export async function recordPayment({ siteCode, body, actor, now = new Date() }) {
  const input = parsePaymentInput(body, now);
  return withFinanceTransaction(siteCode, async (client) => {
    const posted = await postPayment(client, {
      siteCode,
      apartmentId: input.apartmentId,
      accountParty: input.accountParty,
      amountMinor: input.amountMinor,
      paidOn: input.entryDate,
      method: input.method,
      description: input.description,
      sourceKind: 'manual',
      sourceId: null,
      idempotencyKey: input.idempotencyKey,
      actor,
      cashAccountId: input.accountId,
      fund: input.fund,
      now,
    });
    return {
      replayed: posted.replayed,
      entry: mapEntryRow(await loadEntryRow(client, siteCode, posted.entryId)),
      balance_minor: await loadApartmentBalance(client, siteCode, input.apartmentId),
      account_balance_minor: await loadAccountBalance(client, { siteCode, apartmentId: input.apartmentId, accountParty: posted.accountParty }),
      receipt: posted.receipt,
      movement_id: posted.movementId,
      // Kasa dagitimi (docs/PLATFORM_FINANS_KASALAR.md 3): bu tahsilatin SU ANKI dagitimi { operating_minor, capital_minor, advance_minor }
      fund_split: await paymentSplit(client, siteCode, input.apartmentId, posted.accountParty, posted.entryId),
    };
  });
}

// ---------------------------------------------------------------------------
// Ters kayıt ve düzeltme
// ---------------------------------------------------------------------------

/** Bir kaydın apartment_id'sini KİLİTSİZ okur (daire kilidi önce alınsın; kilit sırası apartments -> ledger). */
async function apartmentOfEntry(client, siteCode, entryId) {
  const head = await client.query(`SELECT apartment_id FROM ledger_entries WHERE id = $1 AND site_code = $2`, [entryId, siteCode]);
  if (!head.rows?.[0]) {
    throw entryNotFound();
  }
  return Number(head.rows[0].apartment_id);
}

async function isReversed(client, entryId) {
  const result = await client.query(`SELECT 1 FROM ledger_entries WHERE reverses_entry_id = $1 LIMIT 1`, [entryId]);
  return Boolean(result.rows?.[0]);
}

const isReverseUniqueViolation = (error) => error?.code === '23505' && String(error?.constraint ?? '') === 'uq_ledger_entries_reverses';

/**
 * Karşı işaretli ters kayıt satırını yazar (asılın hesabıyla; İP-1A); yeni kaydın kimliğini döndürür.
 * Asılın kaynak izi (`source_kind` / `source_id`) ters kayda da KOPYALANIR: devir (opening) kaydı tek tek iptal edilince ters kaydı kaynaksız kalırsa
 * raporlarda (finance_reports / finance_home "borçlandırılan": source_kind <> 'opening' süzgeci) asıl dışarıda, ters kayıt içeride kalır ve tahakkuku
 * düşürürdü. Toplu devir geri alması (finance_opening.js) zaten aynı izi yazar. chk_ledger_entries_source: kaynak türü listede, source_id yalnız tür varken.
 */
export async function insertReversal(client, { siteCode, original, openPeriod, todayIsoDate, reason, key, actorUserCode }) {
  try {
    const inserted = await client.query(
      `
        INSERT INTO ledger_entries (
          site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, definition_id, definition_name, run_id, payer_party,
          reverses_entry_id, reversal_reason, idempotency_key, created_by, late_fee_run_id, account_party, source_kind, source_id, fund
        )
        VALUES ($1, $2, 'reversal', $3::BIGINT, $4::DATE, $5::DATE, $6::DATE, $7, $8::TEXT, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18::BIGINT, $19)
        RETURNING id
      `,
      [
        siteCode,
        Number(original.apartment_id),
        String(-BigInt(original.amount_minor)),
        openPeriod,
        todayIsoDate,
        original.due_date,
        original.definition_id === null ? null : Number(original.definition_id),
        original.definition_name ?? null,
        original.run_id === null ? null : Number(original.run_id),
        original.payer_party,
        Number(original.id),
        reason,
        key,
        actorUserCode,
        original.late_fee_run_id === null || original.late_fee_run_id === undefined ? null : Number(original.late_fee_run_id),
        entryAccountParty(original),
        original.source_kind ?? null,
        // source_id yalnız source_kind varken yazılır (CHECK); pg BIGINT'i metin döndürür
        original.source_kind && original.source_id !== null && original.source_id !== undefined ? String(original.source_id) : null,
        // Kasa: ters kayit asilin kasasini (ham deger; 080 oncesi asilda NULL) tasir; DB tetikleyicisi (trg_ledger_entries_fund) de zorlar
        original.fund ?? null,
      ],
    );
    return Number(inserted.rows[0].id);
  } catch (error) {
    if (isReverseUniqueViolation(error)) {
      throw entryAlreadyReversed();
    }
    throw error;
  }
}

/** Bugünün açık dönemi (kapalıysa sonraki açık ay). */
async function resolveOpenPeriod(client, siteCode, now) {
  const closures = await loadClosures(client, siteCode);
  return computeOpenPeriod(currentPeriod(now), new Set(closures.map((row) => row.period)));
}

/**
 * POST entries/:id/reverse -> { replayed, entry, balance_minor }. Karşı işaretli `reversal` kaydı; bir kaydın tek ters kaydı olur, ters kaydın tersi yoktur.
 */
export async function reverseEntry({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw entryNotFound();
  }
  const input = parseReverseInput(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const apartmentId = await apartmentOfEntry(client, siteCode, id);
    await lockApartment(client, siteCode, apartmentId);
    await lockActorRow(client, actorInfo);
    const original = await loadEntryRow(client, siteCode, id);
    if (!original) {
      throw entryNotFound();
    }
    if (input.idempotencyKey !== null) {
      const existing = await loadEntryByKey(client, siteCode, input.idempotencyKey);
      if (existing) {
        if (existing.kind !== 'reversal' || Number(existing.reverses_entry_id) !== id) {
          throw idempotencyConflict();
        }
        return { replayed: true, entry: mapEntryRow(existing), balance_minor: await loadApartmentBalance(client, siteCode, apartmentId) };
      }
    }
    if (original.kind === 'reversal') {
      throw entryNotReversible();
    }
    if (MANAGED_SOURCE_KINDS.includes(original.source_kind)) {
      // alacak iadesi / borç devri satırı: yalnız kendi akışından geri alınır (hesap hareketi, makbuz, devir kaydı birlikte)
      throw entryManagedByFlow();
    }
    if (await isReversed(client, id)) {
      throw entryAlreadyReversed();
    }
    if (original.kind === 'payment' && (await hasApprovedRefund(client, { siteCode, apartmentId, accountParty: entryAccountParty(original) }))) {
      throw refundBlocksPaymentChange();
    }
    const openPeriod = await resolveOpenPeriod(client, siteCode, now);
    let receiptCancelled = false;
    let movementMirrored = false;
    if (original.kind === 'payment') {
      // Faz 4b: aktif makbuz AYNI işlemde iptal makbuzuyla iptal edilir; eşlenmiş hesap hareketinin AYNASI yazılır.
      // KİLİT SIRASI (sözleşme 7): hesap satırı, makbuz / sayaç / ayna satırlarından ÖNCE kilitlenir (R10 P2-15).
      const collection = await findCollectionMovement(client, id);
      if (collection) {
        await lockAccountRows(client, siteCode, [Number(collection.account_id)]);
      }
      receiptCancelled = (await cancelActiveReceiptForEntry(client, { siteCode, entryId: id, reasonCode: 'payment_reversed', actor, actorInfo })) !== null;
      movementMirrored =
        (await mirrorCollectionForEntry(client, { siteCode, entryId: id, openPeriod, todayIsoDate: today(now), actorUserCode: actorInfo.userCode })) !== null;
    }
    const newId = await insertReversal(client, {
      siteCode,
      original,
      openPeriod,
      todayIsoDate: today(now),
      reason: input.reason,
      key: input.idempotencyKey,
      actorUserCode: actorInfo.userCode,
    });
    await recordFinanceAudit(client, actor, 'finance.entry.reversed', siteCode, newId, {
      reversed_entry_id: id,
      reversed_kind: original.kind,
      amount_minor: minorToNumber(-BigInt(original.amount_minor)),
      period: periodLabel(openPeriod),
      receipt_cancelled: receiptCancelled,
      movement_mirrored: movementMirrored,
    });
    return {
      replayed: false,
      entry: mapEntryRow(await loadEntryRow(client, siteCode, newId)),
      balance_minor: await loadApartmentBalance(client, siteCode, apartmentId),
    };
  });
}

/**
 * POST entries/:id/correct (yalnız payment) -> { replayed, reversal, entry, balance_minor }. TEK işlemde ters kayıt + yeni tahsilat; yarım kalmaz.
 */
export async function correctPayment({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw entryNotFound();
  }
  const input = parseCorrectInput(body, now);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const apartmentId = await apartmentOfEntry(client, siteCode, id);
    await lockApartment(client, siteCode, apartmentId);
    await lockActorRow(client, actorInfo);
    const original = await loadEntryRow(client, siteCode, id);
    if (!original) {
      throw entryNotFound();
    }
    const existing = await loadEntryByKey(client, siteCode, input.idempotencyKey);
    if (existing) {
      const reversal = await client.query(`${ENTRY_SELECT} WHERE l.reverses_entry_id = $1 AND l.site_code = $2 LIMIT 1`, [id, siteCode]);
      const replayMovement = await findCollectionMovement(client, Number(existing.id));
      const same =
        existing.kind === 'payment' &&
        Number(existing.apartment_id) === apartmentId &&
        BigInt(existing.amount_minor) === -BigInt(input.amountMinor) &&
        existing.entry_date === input.entryDate &&
        existing.method === input.method &&
        // gövdede hesap verildiyse yeni tahsilat O hesaba yazılmış olmalı (R10 P2-2)
        (input.accountId === null || (replayMovement !== null && replayMovement !== undefined && Number(replayMovement.account_id) === input.accountId)) &&
        // İP-1A: gövdede daire hesabı verildiyse yeni tahsilat O hesapta olmalı
        (input.accountParty === null || entryAccountParty(existing) === input.accountParty) &&
        // kasa kisiti verildiyse yeni tahsilat O kisitla yazilmis olmali
        (input.fund === null || (existing.fund ?? null) === input.fund) &&
        Boolean(reversal.rows?.[0]);
      if (!same) {
        throw idempotencyConflict();
      }
      return {
        replayed: true,
        reversal: mapEntryRow(reversal.rows[0]),
        entry: mapEntryRow(existing),
        balance_minor: await loadApartmentBalance(client, siteCode, apartmentId),
        // İP-1A (inceleme): tekrar yanıtı da yeni tahsilatın yazıldığı hesabın bakiyesini taşır (ilk yanıtla aynı alanlar)
        account_balance_minor: await loadAccountBalance(client, { siteCode, apartmentId, accountParty: entryAccountParty(existing) }),
        receipt: await activeReceiptRef(client, siteCode, Number(existing.id)),
        movement_id: replayMovement ? Number(replayMovement.id) : null,
        fund_split: await paymentSplit(client, siteCode, apartmentId, entryAccountParty(existing), Number(existing.id)),
      };
    }
    if (original.kind === 'reversal') {
      throw entryNotReversible();
    }
    if (original.kind !== 'payment') {
      throw entryNotCorrectable();
    }
    if (await isReversed(client, id)) {
      throw entryAlreadyReversed();
    }
    if (await hasApprovedRefund(client, { siteCode, apartmentId, accountParty: entryAccountParty(original) })) {
      throw refundBlocksPaymentChange();
    }
    const newPeriod = periodOfDate(input.entryDate);
    if (await isPeriodClosed(client, siteCode, newPeriod)) {
      throw periodClosed();
    }
    // Faz 4b: yeni ödemenin hesabı gövdede verilmezse eskisinin hesabı kullanılır; her iki hesap satırı id sırasıyla ÖNCE kilitlenir.
    const oldMovement = await findCollectionMovement(client, id);
    const fallbackAccountId = input.accountId ?? (oldMovement ? Number(oldMovement.account_id) : null);
    await lockAccountRows(client, siteCode, [oldMovement ? Number(oldMovement.account_id) : null, fallbackAccountId].filter((value) => value !== null));
    const account = await resolvePaymentAccount(client, siteCode, { accountId: fallbackAccountId, entryDate: input.entryDate });
    const openPeriod = await resolveOpenPeriod(client, siteCode, now);
    const receiptCancelled = (await cancelActiveReceiptForEntry(client, { siteCode, entryId: id, reasonCode: 'payment_corrected', actor, actorInfo })) !== null;
    await mirrorCollectionForEntry(client, { siteCode, entryId: id, openPeriod, todayIsoDate: today(now), actorUserCode: actorInfo.userCode });
    const reversalId = await insertReversal(client, {
      siteCode,
      original,
      openPeriod,
      todayIsoDate: today(now),
      reason: 'Tahsilat düzeltmesi',
      key: null,
      actorUserCode: actorInfo.userCode,
    });
    // Yeni tahsilat TEK giriş noktasından (postPayment): daire hesabı gövdede verilmezse ASILIN hesabı korunur (İP-1A); denetimi bu akış yazar.
    const posted = await postPayment(client, {
      siteCode,
      apartmentId,
      accountParty: input.accountParty ?? entryAccountParty(original),
      amountMinor: input.amountMinor,
      paidOn: input.entryDate,
      method: input.method,
      description: input.description,
      sourceKind: 'manual',
      sourceId: null,
      idempotencyKey: input.idempotencyKey,
      actor,
      cashAccountId: account ? account.id : null,
      // duzeltmede kasa kisiti gövdede verilmezse ASILIN kisiti korunur
      fund: input.fund ?? original.fund ?? null,
      now,
      audit: false,
    });
    const newId = posted.entryId;
    await recordFinanceAudit(client, actor, 'finance.entry.corrected', siteCode, newId, {
      reversed_entry_id: id,
      reversal_entry_id: reversalId,
      old_amount_minor: minorToNumber(-BigInt(original.amount_minor)),
      new_amount_minor: input.amountMinor,
      period: periodLabel(newPeriod),
      receipt_cancelled: receiptCancelled,
      account_id: account ? account.id : null,
      account_party: posted.accountParty,
    });
    return {
      replayed: false,
      reversal: mapEntryRow(await loadEntryRow(client, siteCode, reversalId)),
      entry: mapEntryRow(await loadEntryRow(client, siteCode, newId)),
      balance_minor: await loadApartmentBalance(client, siteCode, apartmentId),
      account_balance_minor: await loadAccountBalance(client, { siteCode, apartmentId, accountParty: posted.accountParty }),
      receipt: posted.receipt,
      movement_id: posted.movementId,
      fund_split: await paymentSplit(client, siteCode, apartmentId, posted.accountParty, newId),
    };
  });
}

// ---------------------------------------------------------------------------
// Dönem kapatma / yeniden açma
// ---------------------------------------------------------------------------

/**
 * POST periods/:period/close. İlk kapatmada herhangi bir ay serbest (<= bu ay, en çok 5 yıl öncesi); sonra closed_through'tan sonraki herhangi bir ay seçilebilir;
 * seçilen aya kadar bütün açık aylar birlikte kapanır (her ay için ayrı satır). Gelecek ay kapatılamaz. Hata: 409 PERIOD_NOT_CLOSABLE. Dönüş: GET periods gövdesi.
 */
export async function closePeriod({ siteCode, rawPeriod, actor, now = new Date() }) {
  const period = parsePeriod(rawPeriod);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    if (period > currentPeriod(now)) {
      throw periodNotClosable('Gelecek dönem kapatılamaz.');
    }
    const closures = await loadClosures(client, siteCode);
    const latest = latestClosedPeriod(closures.map((row) => row.period));
    if (latest === null) {
      if (period < periodOfDate(minEntryDate(now))) {
        throw periodNotClosable('Bu dönem çok eski; en fazla 5 yıl öncesi kapatılabilir.');
      }
    } else if (period <= latest) {
      throw periodNotClosable('Bu dönem zaten kapalı.');
    }
    await lockActorRow(client, actorInfo);
    // Faz 4b: kapanan aya sonradan hareket yazılamayacağından, hesaba eşlenmemiş tahsilat varken ay kapatılamaz (hesap tanımlıysa).
    await assertNoUnassignedPayments(client, siteCode, period);
    const from = latest === null ? period : addMonths(latest, 1);
    await client.query(
      `INSERT INTO finance_period_closures (site_code, period, closed_by)
       SELECT $1, d::DATE, $4 FROM generate_series($2::DATE, $3::DATE, INTERVAL '1 month') AS d`,
      [siteCode, from, period, actorInfo.userCode],
    );
    const months = (Number(period.slice(0, 4)) - Number(from.slice(0, 4))) * 12 + Number(period.slice(5, 7)) - Number(from.slice(5, 7)) + 1;
    await recordFinanceAudit(client, actor, 'finance.period.closed', siteCode, periodLabel(period), { period: periodLabel(period), from: periodLabel(from), months });
    return periodsBody(await loadClosures(client, siteCode), now);
  });
}

/** POST periods/:period/reopen (yalnız süper kullanıcı; rota denetler). Yalnız EN SON kapatılan ay açılır. */
export async function reopenPeriod({ siteCode, rawPeriod, actor, now = new Date() }) {
  const period = parsePeriod(rawPeriod);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const closures = await loadClosures(client, siteCode);
    if (closures.length === 0) {
      throw periodNotReopenable('Kapalı dönem yok.');
    }
    const latest = closures[closures.length - 1].period;
    if (period !== latest) {
      throw periodNotReopenable('Yalnızca en son kapatılan dönem yeniden açılabilir.');
    }
    // Faz 4b: yeniden açıldıktan sonra kapalı kalacak son ayın (closed_through') ötesinde AKTİF gecikme tazminatı çalıştırması varsa engellenir.
    const remainingThrough = closures.length >= 2 ? closures[closures.length - 2].period : null;
    const lateFee = await client.query(
      `SELECT 1 FROM late_fee_runs WHERE site_code = $1 AND status = 'active' AND ($2::DATE IS NULL OR period > $2::DATE) LIMIT 1`,
      [siteCode, remainingThrough],
    );
    if (lateFee.rows?.[0]) {
      throw periodHasLateFeeRun();
    }
    await client.query(`DELETE FROM finance_period_closures WHERE site_code = $1 AND period = $2::DATE`, [siteCode, period]);
    await recordFinanceAudit(client, actor, 'finance.period.reopened', siteCode, periodLabel(period), { period: periodLabel(period) });
    return periodsBody(await loadClosures(client, siteCode), now);
  });
}
