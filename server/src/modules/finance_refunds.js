// Alacak iadesi (karar K4 / P1-4): fazla ödeme VARSAYILAN olarak ALACAK kalır ve sonraki borçtan düşer; iade ISTEĞE BAĞLIDIR ve YÖNETİCİ ONAYLIDIR.
// Sözleşme: docs/PLATFORM_FINANS.md "Alacak iadesi".
//
// AKIŞ: sakin "Fazla ödememi iade et" (tutar <= alacak) ya da yönetici sakin adına talep açar (requested) -> YÖNETİCİ onaylar (ödeme hesabı seçer) ya da gerekçeyle reddeder; sakin talebini
// onaydan önce geri çekebilir (cancelled). ONAYDA TEK işlemde: (1) defter: avansı tüketen `charge` (source_kind = 'refund'; allocateFunds `refund` bayrağı kasaya tahsilat YAZMAZ),
// (2) seçilen kasa / banka hesabından ÇIKIŞ hareketi (account_movements.kind = 'refund', negatif; nakit hesapta bakiye yetmiyorsa 409), (3) iade makbuzu (IA-yıl-sıra; değişmez
// anlık görüntü + doğrulama kodu; mevcut makbuz deseni), (4) denetim kaydı, (5) sakine bildirim. Yanlış onaylanan iade GERİ ALINIR (ters kayıt + ayna hareket; makbuz iptal sayılır).
//
// KURALLAR
//  - İade tutarı onayda daire kilidi altında `max(0, -hesap bakiyesi)` ile sınanır (409 REFUND_EXCEEDS_CREDIT); talep anında bekleyen talepler de düşülür. Tutar onayda DEĞİŞTİRİLEMEZ.
//  - İade tarihi her zaman BUGÜNDÜR (sunucu, İstanbul); o ayın dönemi kapalıysa 409 PERIOD_CLOSED (tahsilatla aynı kural).
//  - Sakin yalnız KENDİ hesabı için talep açar / geri çeker / görür (başka dairenin talebi 404). Kurul okur (adsız); görevli ve ilgisiz 403 (rota katmanı).
//  - Defter eklemelidir: iade satırları silinmez / değiştirilmez; düzeltme yalnız bu dosyadaki geri alma ile (genel "kaydı iptal et" ucu iade satırını reddeder: finance_refund_guard).
//  - Hesapta onaylı iade varken o hesabın ödemesi iptal / düzeltilemez (finance_refund_guard); önce iade geri alınır.
//  - Audit `details`: yalnız tutar / kimlik / hesap / dönem (not, ret nedeni, geri alma nedeni ASLA). Kilit sırası finance_tx ile aynı: sites -> finance_post -> apartments -> users -> hesap satırları -> finans satırları.

import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { notifyApartmentUsers } from './apartment_mgmt_core.js';
import { registerAttentionSource } from './attention_registry.js';
import { PlatformError } from './errors.js';
import { fingerprintOf, formatMinor, objectOf, queryEnum, queryId, queryInt, requireId } from './finance_4b_common.js';
import { resolveOpenPeriod } from './finance_4b_guard.js';
import { lockAccountRows } from './finance_accounts.js';
import {
  REASON_MAX,
  apartmentNotFound,
  idempotencyConflict,
  moduleDisabled,
  normalizeFreeText,
  parseAccountParty,
  parseIdempotencyKey,
  periodClosed,
  periodLabel,
  periodOfDate,
  requireMinor,
  today,
} from './finance_common.js';
import { ENTRY_SELECT, insertReversal } from './finance_ledger_service.js';
import { minorToNumber, toBigInt } from './finance_money.js';
import { accountPartySql } from './finance_parties.js';
import { RECEIPT_TEMPLATE_VERSION, receiptSecret, snapshotHash, verificationCodeFor } from './finance_receipts.js';
import { enabledFinanceSites, loadVisibleAccounts } from './finance_read_service.js';
import { isPeriodClosed, lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { apartmentLabel, parsePositiveId, toIso } from './people_common.js';
import { syncUserPeopleSafe } from './people_sync.js';

export const REFUND_STATUSES = Object.freeze(['requested', 'approved', 'rejected', 'cancelled', 'reversed']);
export const REFUND_DEFINITION_NAME = 'Alacak iadesi';
export const REFUND_SOURCE_KIND = 'refund';
export const REFUND_SERIES = 'IA';
export const MAX_PENDING_REFUNDS_PER_ACCOUNT = 5;

const conflict = (code, message, extra = null) => new PlatformError(409, code, message, extra);

export const refundNotFound = () => new PlatformError(404, 'REFUND_NOT_FOUND', 'İade talebi bulunamadı.');
export const refundNotPending = (status) =>
  conflict('REFUND_NOT_PENDING', status === 'approved' ? 'Bu iade talebi zaten onaylanmış.' : 'Bu iade talebi karara bağlanmış; işlem yapılamaz.', { status });
export const refundNotApproved = () => conflict('REFUND_NOT_APPROVED', 'Yalnız onaylanmış iade geri alınabilir.');
export const refundExceedsCredit = (creditMinor) =>
  conflict('REFUND_EXCEEDS_CREDIT', 'İade tutarı hesaptaki alacaktan fazla olamaz.', { credit_minor: creditMinor });
export const noCredit = () => conflict('NO_CREDIT', 'Bu hesapta iade edilecek alacak (fazla ödeme) yok.');
export const tooManyPending = () => conflict('TOO_MANY_PENDING', `Bir hesapta en çok ${MAX_PENDING_REFUNDS_PER_ACCOUNT} bekleyen iade talebi olabilir.`);
export const insufficientCash = (balanceMinor) =>
  conflict('CASH_INSUFFICIENT', 'Seçilen kasada yeterli nakit yok. Başka bir hesap seçin ya da önce kasaya para girişi yapın.', { balance_minor: balanceMinor });
export const accountInactiveForRefund = () => conflict('ACCOUNT_INACTIVE', 'Hesap pasif; iade bu hesaptan yapılamaz.');
export const beforeAccountOpening = () => conflict('BEFORE_OPENING_DATE', 'Bugün hesabın açılış tarihinden önce; iade bu hesaptan yapılamaz.');
export const receiptUnavailable = () => new PlatformError(503, 'RECEIPT_UNAVAILABLE', 'İade makbuzu şu anda düzenlenemiyor (sunucu yapılandırması eksik).');

// --- Saf yardımcılar ------------------------------------------------------------------------------------------------------------------

export const formatRefundNumber = (year, no) => `${REFUND_SERIES}-${year}-${String(no).padStart(6, '0')}`;

/** Hesap bakiyesinden (kuruş; borç +, alacak -) iade edilebilir alacak. */
export function creditOf(balanceMinor) {
  const balance = toBigInt(balanceMinor);
  return balance < 0n ? -balance : 0n;
}

/** Hesaptan çıkış yöntemi: nakit hesap -> nakit, banka hesabı -> havale. */
export const payMethodOf = (accountKind) => (accountKind === 'cash' ? 'cash' : 'transfer');

/** Talep gövdesi (sakin: apartment_id + tutar; yönetici: + account_party). */
export function parseRequestInput(body, { manager }) {
  const input = objectOf(body);
  const apartmentId = parsePositiveId(input.apartment_id);
  if (apartmentId === null) {
    throw new PlatformError(400, 'INVALID_BODY', 'Daire seçimi geçersiz.');
  }
  const accountParty = parseAccountParty(input.account_party);
  if (manager && accountParty === null) {
    throw new PlatformError(400, 'INVALID_BODY', 'Hesap (ev sahibi / kiracı) seçimi zorunludur.');
  }
  return {
    apartmentId,
    accountParty,
    amountMinor: requireMinor(input.amount_minor, 'İade tutarı', { min: 1 }),
    note: normalizeFreeText(input.note, { label: 'Not', max: 200 }),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

export function parseApproveInput(body) {
  const input = objectOf(body);
  return {
    payAccountId: requireId(input.pay_account_id, 'Ödeme hesabı'),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

export function parseRejectInput(body) {
  const input = objectOf(body);
  return {
    reason: normalizeFreeText(input.reason, { label: 'Ret nedeni', max: REASON_MAX, required: true }),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

export function parseReverseInput(body) {
  const input = objectOf(body);
  return {
    reason: normalizeFreeText(input.reason, { label: 'Geri alma nedeni', max: REASON_MAX, required: true }),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

/** İstek parmak izi: aynı anahtar + farklı gövde = 409 IDEMPOTENCY_CONFLICT. */
export const requestFingerprint = ({ apartmentId, accountParty, amountMinor, note }) =>
  fingerprintOf({ a: Number(apartmentId), p: accountParty, m: Number(amountMinor), n: note ?? null });

/** Değişmez iade makbuzu anlık görüntüsü (v1). TCKN / telefon / e-posta / adres / bakiye / serbest not YOK. */
export function buildRefundSnapshot(input) {
  return {
    v: 1,
    number: input.number,
    kind: 'refund',
    issued_on: input.issuedOn,
    paid_on: input.paidOn,
    amount_minor: input.amountMinor,
    currency: 'TRY',
    method: input.method,
    site: { name: input.siteName },
    apartment: { label: input.apartmentLabel },
    payee: { party: input.accountParty, name: input.payeeName ?? null },
    from_account: { name: input.accountName },
    issuer: { name: input.issuerName ?? null },
    template_version: RECEIPT_TEMPLATE_VERSION,
    verification_code: input.verificationCode,
  };
}

// --- Okuma ----------------------------------------------------------------------------------------------------------------------------

const REFUND_SELECT = `
  SELECT r.id, r.site_code, r.apartment_id, r.account_party, r.amount_minor::TEXT AS amount_minor, r.status, r.requested_by_kind, r.requested_by, r.requested_at,
         r.note, r.resolved_by, r.resolved_at, r.reject_reason, r.pay_account_id, to_char(r.pay_date, 'YYYY-MM-DD') AS pay_date, r.pay_method, r.ledger_entry_id,
         r.receipt_year, r.receipt_no, to_char(r.receipt_issued_on, 'YYYY-MM-DD') AS receipt_issued_on, r.receipt_snapshot, r.receipt_code,
         r.decision_key, r.reversed_at, r.reversal_reason, r.reversal_ledger_entry_id, r.reversal_key, r.idempotency_key, r.request_fingerprint,
         fa.name AS pay_account_name, fa.kind AS pay_account_kind,
         b.block_name, a.unit_label, ru.full_name AS requested_by_name, du.full_name AS resolved_by_name, vu.full_name AS reversed_by_name
  FROM finance_refunds r
  INNER JOIN apartments a ON a.id = r.apartment_id
  INNER JOIN site_blocks b ON b.id = a.block_id
  LEFT JOIN finance_accounts fa ON fa.id = r.pay_account_id
  LEFT JOIN users ru ON ru.user_code = r.requested_by
  LEFT JOIN users du ON du.user_code = r.resolved_by
  LEFT JOIN users vu ON vu.user_code = r.reversed_by
`;

/**
 * Satır -> API gövdesi. `forResident`: yönetici adları / iç notlar / işlem anahtarları çıkarılır (ret nedeni sakine görünür).
 */
export function mapRefundRow(row, { forResident = false } = {}) {
  const receipt =
    row.receipt_no === null || row.receipt_no === undefined
      ? null
      : {
          number: formatRefundNumber(row.receipt_year, row.receipt_no),
          issued_on: row.receipt_issued_on,
          verification_code: row.receipt_code,
          status: row.status === 'reversed' ? 'cancelled' : 'active',
          snapshot: row.receipt_snapshot ?? null,
        };
  const body = {
    id: Number(row.id),
    apartment_id: Number(row.apartment_id),
    apartment_label: apartmentLabel(row.block_name, row.unit_label),
    account_party: row.account_party,
    amount_minor: minorToNumber(row.amount_minor),
    status: row.status,
    requested_by_kind: row.requested_by_kind,
    requested_at: toIso(row.requested_at),
    resolved_at: row.resolved_at ? toIso(row.resolved_at) : null,
    reject_reason: row.status === 'rejected' ? (row.reject_reason ?? null) : null,
    pay_date: row.pay_date ?? null,
    receipt,
    reversed_at: row.reversed_at ? toIso(row.reversed_at) : null,
  };
  if (forResident) {
    return { ...body, note: row.note ?? null };
  }
  return {
    ...body,
    note: row.note ?? null,
    pay_account_id: row.pay_account_id === null || row.pay_account_id === undefined ? null : Number(row.pay_account_id),
    pay_account_name: row.pay_account_name ?? null,
    pay_method: row.pay_method ?? null,
    ledger_entry_id: row.ledger_entry_id === null || row.ledger_entry_id === undefined ? null : Number(row.ledger_entry_id),
    reversal_reason: row.reversal_reason ?? null,
    requested_by_name: row.requested_by_name ?? null,
    resolved_by_name: row.resolved_by_name ?? null,
    reversed_by_name: row.reversed_by_name ?? null,
  };
}

async function loadRefund(db, siteCode, id, { lock = false } = {}) {
  const result = await db.query(`${REFUND_SELECT} WHERE r.id = $1 AND r.site_code = $2 ${lock ? 'FOR UPDATE OF r' : ''}`, [id, siteCode]);
  return result.rows?.[0] ?? null;
}

async function loadRefundByKey(db, siteCode, key) {
  const result = await db.query(`${REFUND_SELECT} WHERE r.site_code = $1 AND r.idempotency_key = $2 LIMIT 1`, [siteCode, key]);
  return result.rows?.[0] ?? null;
}

/** Hesabın bakiyesi (kuruş, BigInt; borç +, alacak -). */
async function accountBalance(db, siteCode, apartmentId, accountParty) {
  const result = await db.query(
    `SELECT COALESCE(SUM(l.amount_minor), 0)::TEXT AS balance FROM ledger_entries l WHERE l.site_code = $1 AND l.apartment_id = $2 AND ${accountPartySql('l')} = $3`,
    [siteCode, apartmentId, accountParty],
  );
  return toBigInt(result.rows?.[0]?.balance ?? '0');
}

async function pendingTotal(db, siteCode, apartmentId, accountParty) {
  const result = await db.query(
    `SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS total, COUNT(*)::INT AS n FROM finance_refunds WHERE site_code = $1 AND apartment_id = $2 AND account_party = $3 AND status = 'requested'`,
    [siteCode, apartmentId, accountParty],
  );
  return { total: toBigInt(result.rows?.[0]?.total ?? '0'), count: Number(result.rows?.[0]?.n ?? 0) };
}

async function lockApartment(client, siteCode, apartmentId) {
  const result = await client.query(`SELECT id, responsible_party FROM apartments WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [apartmentId, siteCode]);
  if (!result.rows?.[0]) {
    throw apartmentNotFound();
  }
  return result.rows[0];
}

/**
 * Sakine uygulama içi bildirim (best-effort): sakin kendi açtıysa o kullanıcıya; yönetici sakin adına açtıysa hesabın güncel kişi(ler)ine (ev sahibi / kiracı). Hata kararı bozmaz.
 */
async function notifyRequester(client, row, message) {
  try {
    let userCodes = [];
    if (row.requested_by_kind === 'resident' && row.requested_by !== null && row.requested_by !== undefined) {
      userCodes = [Number(row.requested_by)];
    } else {
      const people = await client.query(
        `
          SELECT DISTINCT sp.user_code
          FROM apartment_residencies r
          INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE AND sp.user_code IS NOT NULL
          WHERE r.apartment_id = $1 AND r.is_current = TRUE AND r.relation = $2
        `,
        [Number(row.apartment_id), row.account_party === 'tenant' ? 'tenant' : 'owner'],
      );
      userCodes = (people.rows ?? []).map((person) => Number(person.user_code));
    }
    await notifyApartmentUsers(client, { siteCode: Number(row.site_code), apartmentId: Number(row.apartment_id), userCodes, kind: 'refund', message });
  } catch (_error) {
    // bildirim yazılamaması kararı bozmaz
  }
}

// --- Talep (sakin / yönetici) ---------------------------------------------------------------------------------------------------------

async function insertRequest(client, { siteCode, input, accountParty, kind, requestedBy, actor }) {
  const fingerprint = requestFingerprint({ apartmentId: input.apartmentId, accountParty, amountMinor: input.amountMinor, note: input.note });
  const existing = await loadRefundByKey(client, siteCode, input.idempotencyKey);
  if (existing) {
    const same =
      Number(existing.apartment_id) === input.apartmentId &&
      existing.account_party === accountParty &&
      existing.request_fingerprint === fingerprint &&
      existing.requested_by_kind === kind &&
      (existing.requested_by === null ? requestedBy === null : Number(existing.requested_by) === requestedBy);
    if (!same) {
      throw idempotencyConflict();
    }
    return { replayed: true, row: existing };
  }
  const balance = await accountBalance(client, siteCode, input.apartmentId, accountParty);
  const credit = creditOf(balance);
  if (credit === 0n) {
    throw noCredit();
  }
  const pending = await pendingTotal(client, siteCode, input.apartmentId, accountParty);
  if (pending.count >= MAX_PENDING_REFUNDS_PER_ACCOUNT) {
    throw tooManyPending();
  }
  const available = credit - pending.total;
  if (BigInt(input.amountMinor) > available) {
    throw refundExceedsCredit(minorToNumber(available > 0n ? available : 0n));
  }
  const inserted = await client.query(
    `
      INSERT INTO finance_refunds (site_code, apartment_id, account_party, amount_minor, requested_by_kind, requested_by, note, idempotency_key, request_fingerprint)
      VALUES ($1, $2, $3, $4::BIGINT, $5, $6, $7, $8, $9)
      RETURNING id
    `,
    [siteCode, input.apartmentId, accountParty, String(input.amountMinor), kind, requestedBy, input.note, input.idempotencyKey, fingerprint],
  );
  await recordFinanceAudit(client, actor, 'finance.refund.requested', siteCode, Number(inserted.rows[0].id), {
    apartment_id: input.apartmentId,
    account_party: accountParty,
    amount_minor: input.amountMinor,
    by: kind,
  });
  return { replayed: false, row: await loadRefund(client, siteCode, Number(inserted.rows[0].id)) };
}

const userCodeOf = (authUser) => parsePositiveId(authUser?.user_code ?? authUser?.userCode ?? authUser?.id);

/** POST /app/my-finance/refund-requests -> { replayed, refund }. Sakin YALNIZ kendi hesabı için talep açar (başka daire 404). */
export async function createMyRefundRequest(authUser, body) {
  const userCode = userCodeOf(authUser);
  if (userCode === null) throw refundNotFound();
  const input = parseRequestInput(body, { manager: false });
  await syncUserPeopleSafe(userCode);
  const visible = await loadVisibleAccounts(pool, userCode);
  const apartment = visible.find((row) => Number(row.apartment_id) === input.apartmentId);
  const own = apartment?.views?.find((view) => view.role === 'own');
  const ownParty = own?.account_party;
  if (!apartment || (ownParty !== 'owner' && ownParty !== 'tenant')) throw apartmentNotFound();
  if (input.accountParty !== null && input.accountParty !== ownParty) throw apartmentNotFound();
  const siteCode = Number(apartment.site_code);
  if (!(await enabledFinanceSites(pool, [siteCode])).has(siteCode)) throw moduleDisabled();
  const actorInfo = actorFromAuthUser(authUser);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockApartment(client, siteCode, input.apartmentId);
    await lockActorRow(client, actorInfo);
    const out = await insertRequest(client, { siteCode, input, accountParty: ownParty, kind: 'resident', requestedBy: userCode, actor: authUser });
    return { replayed: out.replayed, refund: mapRefundRow(out.row, { forResident: true }) };
  });
}

/** GET /app/my-finance/refund-requests[?apartment_id=] -> { items } (kendi talepleri; yeni -> eski, en çok 50). */
export async function listMyRefundRequests(authUser, query = {}) {
  const userCode = userCodeOf(authUser);
  if (userCode === null) return { items: [] };
  const apartmentId = query.apartment_id === undefined ? null : parsePositiveId(query.apartment_id);
  const result = await pool.query(
    `${REFUND_SELECT} WHERE r.requested_by = $1 AND r.requested_by_kind = 'resident' AND ($2::BIGINT IS NULL OR r.apartment_id = $2) ORDER BY r.id DESC LIMIT 50`,
    [userCode, apartmentId],
  );
  return { items: (result.rows ?? []).map((row) => mapRefundRow(row, { forResident: true })) };
}

/** POST /app/my-finance/refund-requests/:id/cancel -> { refund }. Yalnız KENDİ bekleyen talebi. */
export async function cancelMyRefundRequest(authUser, rawId) {
  const userCode = userCodeOf(authUser);
  const id = parsePositiveId(rawId);
  if (userCode === null || id === null) throw refundNotFound();
  const head = await pool.query(`SELECT site_code, apartment_id FROM finance_refunds WHERE id = $1 AND requested_by = $2 AND requested_by_kind = 'resident'`, [id, userCode]);
  if (!head.rows?.[0]) throw refundNotFound();
  const siteCode = Number(head.rows[0].site_code);
  const actorInfo = actorFromAuthUser(authUser);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockApartment(client, siteCode, Number(head.rows[0].apartment_id));
    await lockActorRow(client, actorInfo);
    const row = await loadRefund(client, siteCode, id, { lock: true });
    if (!row || Number(row.requested_by) !== userCode) throw refundNotFound();
    if (row.status === 'cancelled') return { replayed: true, refund: mapRefundRow(row, { forResident: true }) };
    if (row.status !== 'requested') throw refundNotPending(row.status);
    await client.query(`UPDATE finance_refunds SET status = 'cancelled', resolved_by = $2, resolved_at = NOW() WHERE id = $1 AND status = 'requested'`, [id, userCode]);
    await recordFinanceAudit(client, authUser, 'finance.refund.cancelled', siteCode, id, { apartment_id: Number(row.apartment_id), amount_minor: minorToNumber(row.amount_minor) });
    return { replayed: false, refund: mapRefundRow(await loadRefund(client, siteCode, id), { forResident: true }) };
  });
}

/** POST .../finance/refunds (yönetici sakin adına talep) -> { replayed, refund }. */
export async function createManagerRefundRequest({ siteCode, body, actor }) {
  const input = parseRequestInput(body, { manager: true });
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockApartment(client, siteCode, input.apartmentId);
    await lockActorRow(client, actorInfo);
    const out = await insertRequest(client, { siteCode, input, accountParty: input.accountParty, kind: 'manager', requestedBy: actorInfo.userCode, actor });
    return { replayed: out.replayed, refund: mapRefundRow(out.row) };
  });
}

// --- Yönetici: okuma ------------------------------------------------------------------------------------------------------------------

/** GET .../finance/refunds[?status=requested|approved|rejected|cancelled|reversed|all&apartment_id=&before_id=&limit=] -> { items, pending_count, pending_total_minor, next_before_id }. */
export async function listRefunds(siteCode, query = {}, db = pool) {
  const status = queryEnum(query.status, [...REFUND_STATUSES, 'all'], 'requested');
  const apartmentId = query.apartment_id === undefined ? null : parsePositiveId(query.apartment_id);
  const beforeId = queryId(query.before_id);
  const limit = queryInt(query.limit, { min: 1, max: 100, fallback: 50 });
  const result = await db.query(
    `${REFUND_SELECT}
     WHERE r.site_code = $1 AND ($2::TEXT = 'all' OR r.status = $2) AND ($3::BIGINT IS NULL OR r.apartment_id = $3) AND ($4::BIGINT IS NULL OR r.id < $4)
     ORDER BY r.id DESC LIMIT $5`,
    [siteCode, status, apartmentId, beforeId, limit + 1],
  );
  const rows = result.rows ?? [];
  const page = rows.slice(0, limit);
  const summary = await refundSummary(siteCode, db);
  return {
    items: page.map((row) => mapRefundRow(row)),
    pending_count: summary.count,
    pending_total_minor: summary.total_minor,
    next_before_id: rows.length > limit && page.length > 0 ? Number(page[page.length - 1].id) : null,
  };
}

export async function getRefund(siteCode, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  const row = id === null ? null : await loadRefund(db, siteCode, id);
  if (!row) throw refundNotFound();
  return { refund: mapRefundRow(row) };
}

/** Bekleyen talep sayısı ve toplamı (dikkat kaydı / liste başlığı). */
export async function refundSummary(siteCode, db = pool) {
  const result = await db.query(
    `SELECT COUNT(*)::INT AS n, COALESCE(SUM(amount_minor), 0)::TEXT AS total FROM finance_refunds WHERE site_code = $1 AND status = 'requested'`,
    [siteCode],
  );
  return { count: Number(result.rows?.[0]?.n ?? 0), total_minor: minorToNumber(result.rows?.[0]?.total ?? '0') };
}

registerAttentionSource({
  key: 'refund_requests',
  module: 'finance',
  run: async (db, siteCode) => {
    const summary = await refundSummary(siteCode, db);
    return { count: summary.count, total_minor: summary.total_minor };
  },
});

// --- Yönetici: karar ------------------------------------------------------------------------------------------------------------------

async function loadReceiptContext(client, siteCode, refund, issuerUserCode) {
  const site = await client.query(`SELECT name FROM sites WHERE site_code = $1`, [siteCode]);
  const payee = await client.query(
    `
      SELECT COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS name
      FROM apartment_residencies r
      INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE
      LEFT JOIN users u ON u.user_code = sp.user_code
      WHERE r.apartment_id = $1 AND r.is_current = TRUE AND r.relation = $2
      ORDER BY r.id
      LIMIT 1
    `,
    [Number(refund.apartment_id), refund.account_party === 'tenant' ? 'tenant' : 'owner'],
  );
  const issuer = issuerUserCode === null || issuerUserCode === undefined ? { rows: [] } : await client.query(`SELECT full_name FROM users WHERE user_code = $1`, [issuerUserCode]);
  return { siteName: site.rows?.[0]?.name ?? '', payeeName: payee.rows?.[0]?.name ?? null, issuerName: issuer.rows?.[0]?.full_name ?? null };
}

/** Sayaç (site + yıl) bir artar; işlem geri alınırsa sayaç da geri döner (boşluksuz). Yıl DB saatinden (İstanbul). */
async function allocateReceiptNumber(client, siteCode) {
  const clock = await client.query(`SELECT to_char(t AT TIME ZONE 'Europe/Istanbul', 'YYYY-MM-DD') AS issued_on FROM (SELECT clock_timestamp() AS t) x`);
  const issuedOn = clock.rows[0].issued_on;
  const year = Number(issuedOn.slice(0, 4));
  const counter = await client.query(
    `
      INSERT INTO finance_refund_counters (site_code, receipt_year, last_no) VALUES ($1, $2, 1)
      ON CONFLICT (site_code, receipt_year) DO UPDATE SET last_no = finance_refund_counters.last_no + 1
      RETURNING last_no
    `,
    [siteCode, year],
  );
  return { issuedOn, year, no: Number(counter.rows[0].last_no) };
}

/**
 * POST .../finance/refunds/:id/approve { pay_account_id, idempotency_key } -> { replayed, refund }.
 * Tek işlemde defter + hesap hareketi + makbuz + durum. Tutar talepteki tutardır (değişmez).
 */
export async function approveRefund({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) throw refundNotFound();
  const input = parseApproveInput(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const head = await client.query(`SELECT apartment_id FROM finance_refunds WHERE id = $1 AND site_code = $2`, [id, siteCode]);
    if (!head.rows?.[0]) throw refundNotFound();
    const apartmentId = Number(head.rows[0].apartment_id);
    const apartment = await lockApartment(client, siteCode, apartmentId);
    await lockActorRow(client, actorInfo);
    const refund = await loadRefund(client, siteCode, id, { lock: true });
    if (!refund) throw refundNotFound();
    if (refund.status === 'approved' && refund.decision_key === input.idempotencyKey) {
      return { replayed: true, refund: mapRefundRow(refund) };
    }
    if (refund.status !== 'requested') throw refundNotPending(refund.status);
    const todayIso = today(now);
    const period = periodOfDate(todayIso);
    if (await isPeriodClosed(client, siteCode, period)) throw periodClosed();
    const accounts = await lockAccountRows(client, siteCode, [input.payAccountId]);
    const account = accounts.get(input.payAccountId);
    if (account.is_active !== true) throw accountInactiveForRefund();
    if (todayIso < account.opening_date) throw beforeAccountOpening();
    const amount = toBigInt(refund.amount_minor);
    const balance = await accountBalance(client, siteCode, apartmentId, refund.account_party);
    const credit = creditOf(balance);
    if (amount > credit) throw refundExceedsCredit(minorToNumber(credit));
    if (account.kind === 'cash') {
      const cash = await client.query(`SELECT COALESCE(SUM(amount_minor), 0)::TEXT AS balance FROM account_movements WHERE site_code = $1 AND account_id = $2`, [siteCode, input.payAccountId]);
      const cashBalance = toBigInt(cash.rows[0].balance);
      if (cashBalance < amount) throw insufficientCash(minorToNumber(cashBalance));
    }
    // (1) defter: avansı tüketen borç satırı (allocateFunds `refund` bayrağı); kasa YOK
    const ledger = await client.query(
      `
        INSERT INTO ledger_entries (
          site_code, apartment_id, kind, amount_minor, period, entry_date, due_date, definition_name, payer_party, description, created_by, account_party, source_kind, source_id
        )
        VALUES ($1, $2, 'charge', $3::BIGINT, $4::DATE, $5::DATE, $5::DATE, $6, $7, $8, $9, $10, $11, $12)
        RETURNING id
      `,
      [
        siteCode,
        apartmentId,
        String(amount),
        period,
        todayIso,
        REFUND_DEFINITION_NAME,
        apartment.responsible_party,
        'Fazla ödeme iadesi',
        actorInfo.userCode,
        refund.account_party,
        REFUND_SOURCE_KIND,
        id,
      ],
    );
    const ledgerEntryId = Number(ledger.rows[0].id);
    // (2) hesaptan çıkış hareketi
    const movement = await client.query(
      `
        INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, refund_id, created_by)
        VALUES ($1, $2, 'refund', $3::BIGINT, $4::DATE, $5::DATE, $6, $7)
        RETURNING id
      `,
      [siteCode, input.payAccountId, String(-amount), todayIso, period, id, actorInfo.userCode],
    );
    const movementId = Number(movement.rows[0].id);
    // (3) makbuz (IA-yıl-sıra)
    const secret = receiptSecret();
    if (secret === null) throw receiptUnavailable();
    const { issuedOn, year, no } = await allocateReceiptNumber(client, siteCode);
    const context = await loadReceiptContext(client, siteCode, refund, actorInfo.userCode);
    const number = formatRefundNumber(year, no);
    const code = verificationCodeFor(secret, { siteCode: `${REFUND_SERIES}:${siteCode}`, year, no, amountMinor: minorToNumber(amount), paidOn: todayIso });
    const method = payMethodOf(account.kind);
    const snapshot = buildRefundSnapshot({
      number,
      issuedOn,
      paidOn: todayIso,
      amountMinor: minorToNumber(amount),
      method,
      siteName: context.siteName,
      apartmentLabel: apartmentLabel(refund.block_name, refund.unit_label),
      accountParty: refund.account_party,
      payeeName: context.payeeName,
      accountName: account.name,
      issuerName: context.issuerName,
      verificationCode: code,
    });
    // (4) durum
    await client.query(
      `
        UPDATE finance_refunds
        SET status = 'approved', resolved_by = $2, resolved_at = NOW(), pay_account_id = $3, pay_date = $4::DATE, pay_method = $5, ledger_entry_id = $6,
            receipt_year = $7, receipt_no = $8, receipt_issued_on = $9::DATE, receipt_snapshot = $10::JSONB, receipt_sha256 = $11, receipt_code = $12, decision_key = $13
        WHERE id = $1 AND status = 'requested'
      `,
      [id, actorInfo.userCode, input.payAccountId, todayIso, method, ledgerEntryId, year, no, issuedOn, JSON.stringify(snapshot), snapshotHash(snapshot), code, input.idempotencyKey],
    );
    await recordFinanceAudit(client, actor, 'finance.refund.approved', siteCode, id, {
      apartment_id: apartmentId,
      account_party: refund.account_party,
      amount_minor: minorToNumber(amount),
      account_id: input.payAccountId,
      ledger_entry_id: ledgerEntryId,
      movement_id: movementId,
      receipt_number: number,
      period: periodLabel(period),
    });
    await notifyRequester(client, refund, `${formatMinor(amount)} ₺ tutarındaki iade talebiniz onaylandı (makbuz ${number}).`);
    return { replayed: false, refund: mapRefundRow(await loadRefund(client, siteCode, id)) };
  });
}

/** POST .../finance/refunds/:id/reject { reason, idempotency_key } -> { replayed, refund }. */
export async function rejectRefund({ siteCode, rawId, body, actor }) {
  const id = parsePositiveId(rawId);
  if (id === null) throw refundNotFound();
  const input = parseRejectInput(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const head = await client.query(`SELECT apartment_id FROM finance_refunds WHERE id = $1 AND site_code = $2`, [id, siteCode]);
    if (!head.rows?.[0]) throw refundNotFound();
    await lockApartment(client, siteCode, Number(head.rows[0].apartment_id));
    await lockActorRow(client, actorInfo);
    const refund = await loadRefund(client, siteCode, id, { lock: true });
    if (!refund) throw refundNotFound();
    if (refund.status === 'rejected' && refund.decision_key === input.idempotencyKey) {
      return { replayed: true, refund: mapRefundRow(refund) };
    }
    if (refund.status !== 'requested') throw refundNotPending(refund.status);
    await client.query(
      `UPDATE finance_refunds SET status = 'rejected', resolved_by = $2, resolved_at = NOW(), reject_reason = $3, decision_key = $4 WHERE id = $1 AND status = 'requested'`,
      [id, actorInfo.userCode, input.reason, input.idempotencyKey],
    );
    await recordFinanceAudit(client, actor, 'finance.refund.rejected', siteCode, id, {
      apartment_id: Number(refund.apartment_id),
      account_party: refund.account_party,
      amount_minor: minorToNumber(refund.amount_minor),
    });
    await notifyRequester(client, refund, `${formatMinor(toBigInt(refund.amount_minor))} ₺ tutarındaki iade talebiniz reddedildi. Gerekçe: ${input.reason}`);
    return { replayed: false, refund: mapRefundRow(await loadRefund(client, siteCode, id)) };
  });
}

/**
 * POST .../finance/refunds/:id/reverse { reason, idempotency_key } -> { replayed, refund }. Yalnız ONAYLI iade: defter satırının tersi + hesap hareketinin AYNASI (açık ayda, bugünün
 * tarihiyle); makbuz iptal sayılır. Alacak yeniden oluşur (iade edilen tutar kadar).
 */
export async function reverseRefund({ siteCode, rawId, body, actor, now = new Date() }) {
  const id = parsePositiveId(rawId);
  if (id === null) throw refundNotFound();
  const input = parseReverseInput(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const head = await client.query(`SELECT apartment_id FROM finance_refunds WHERE id = $1 AND site_code = $2`, [id, siteCode]);
    if (!head.rows?.[0]) throw refundNotFound();
    const apartmentId = Number(head.rows[0].apartment_id);
    await lockApartment(client, siteCode, apartmentId);
    await lockActorRow(client, actorInfo);
    const refund = await loadRefund(client, siteCode, id, { lock: true });
    if (!refund) throw refundNotFound();
    if (refund.status === 'reversed' && refund.reversal_key === input.idempotencyKey) {
      return { replayed: true, refund: mapRefundRow(refund) };
    }
    if (refund.status !== 'approved') throw refundNotApproved();
    // Kilit sırası: hesap satırı, defter / hareket satırlarından ÖNCE
    await lockAccountRows(client, siteCode, [Number(refund.pay_account_id)]);
    const openPeriod = await resolveOpenPeriod(client, siteCode, now);
    const todayIso = today(now);
    const original = await client.query(`${ENTRY_SELECT} WHERE l.id = $1 AND l.site_code = $2 LIMIT 1`, [Number(refund.ledger_entry_id), siteCode]);
    if (!original.rows?.[0]) throw refundNotFound();
    const reversalId = await insertReversal(client, {
      siteCode,
      original: original.rows[0],
      openPeriod,
      todayIsoDate: todayIso,
      reason: input.reason,
      key: null,
      actorUserCode: actorInfo.userCode,
    });
    const movement = await client.query(`SELECT id, account_id, amount_minor::TEXT AS amount_minor FROM account_movements WHERE kind = 'refund' AND refund_id = $1`, [id]);
    const source = movement.rows?.[0];
    if (!source) throw refundNotFound();
    await client.query(
      `
        INSERT INTO account_movements (site_code, account_id, kind, amount_minor, movement_date, period, reverses_movement_id, note, created_by)
        VALUES ($1, $2, 'reversal', $3::BIGINT, $4::DATE, $5::DATE, $6, $7, $8)
      `,
      [siteCode, Number(source.account_id), String(-toBigInt(source.amount_minor)), todayIso, openPeriod, Number(source.id), 'Alacak iadesi geri alındı', actorInfo.userCode],
    );
    await client.query(
      `
        UPDATE finance_refunds
        SET status = 'reversed', reversed_by = $2, reversed_at = NOW(), reversal_reason = $3, reversal_ledger_entry_id = $4, reversal_key = $5
        WHERE id = $1 AND status = 'approved'
      `,
      [id, actorInfo.userCode, input.reason, reversalId, input.idempotencyKey],
    );
    await recordFinanceAudit(client, actor, 'finance.refund.reversed', siteCode, id, {
      apartment_id: apartmentId,
      account_party: refund.account_party,
      amount_minor: minorToNumber(refund.amount_minor),
      reversal_entry_id: reversalId,
      period: periodLabel(openPeriod),
    });
    await notifyRequester(client, refund, `${formatMinor(toBigInt(refund.amount_minor))} ₺ tutarındaki iade işlemi site yönetimi tarafından geri alındı; tutar alacağınıza döndü.`);
    return { replayed: false, refund: mapRefundRow(await loadRefund(client, siteCode, id)) };
  });
}
