// Tahsilat makbuzu (Faz 4b Ö1): numaralama, değişmez anlık görüntü + doğrulama kodu, iptal makbuzu, basım olayları, listeleme ve sakin görünümü.
//
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Ö1". KARARLAR:
//  - Numara `MK-{yıl}-{sıra:06}`: site başına yıl başına 1'den; TEK dizi (iptal makbuzu da yeni numara alır). Sayaç satırı ödemeyle/iptalle AYNI işlemde
//    artar (`receipt_counters` ON CONFLICT DO UPDATE); işlem geri alınırsa sayaç da geri döner (boşluk yok). SEQUENCE kullanılmaz. `issued_on` ve yıl DB
//    saatinden (İstanbul), `finance_post` kilidi ALTINDA alınır; geçmiş tarihli tahsilat bile BUGÜNÜN numarasını alır.
//  - Makbuz değişmez belgedir (DB tetikleyicisi): düzeltme = iptal makbuzu + yeni makbuz. Her ödemenin aynı anda tek aktif makbuzu olur.
//  - PDF istemcide üretilir; sunucu snapshot + HMAC doğrulama kodu verir. Genel (kimliksiz) doğrulama ucu YOK.
//  - Snapshot yalnız gerekli kişisel veriyi taşır (ad + daire + tutar); TCKN/telefon/e-posta/bakiye/serbest açıklama YOK.
//  - Şablon metni taslaktır (template_version 1) [AVUKAT DOĞRULASIN]: mahsup bildirimi + çekince (TBK m.101-104) + "defter yerine geçmez".

import { createHmac, timingSafeEqual } from 'node:crypto';
import { pool } from '../db.js';
import { PlatformError } from './errors.js';
import { actorFromAuthUser } from './audit_service.js';
import {
  objectOf,
  paymentReversed,
  queryEnum,
  queryInt,
  queryId,
  receiptAlreadyCancelled,
  receiptNotCancellable,
  receiptNotFound,
  sha256Hex,
} from './finance_4b_common.js';
import {
  canonicalJson,
  entryNotFound,
  idempotencyConflict,
  invalidBody,
  normalizeFreeText,
  parseIdempotencyKey,
} from './finance_common.js';
import { minorToNumber } from './finance_money.js';
import { enabledFinanceSites, loadVisibleApartments } from './finance_read_service.js';
import { lockActorRow, recordFinanceAudit, withFinanceTransaction } from './finance_tx.js';
import { apartmentLabel, escapeLike, foldSql, foldText, parsePositiveId, toIso } from './people_common.js';

export const RECEIPT_TEMPLATE_VERSION = 1;
export const RECEIPT_REASON_CODES = Object.freeze(['payment_reversed', 'payment_corrected', 'issued_in_error']);

/** Şablon sürüm 1 sabit metinleri (taslak) [AVUKAT DOĞRULASIN]. İstemci PDF'i bu metinleri sunucudan alır (tek kaynak). */
export const RECEIPT_TEMPLATE = Object.freeze({
  version: RECEIPT_TEMPLATE_VERSION,
  draft: true,
  mahsup_text: 'Tahsil edilen tutar, kayıtlardaki vadesi en eski borçtan başlayarak mahsup edilir.',
  cekince_text:
    'Bu makbuz yalnızca yukarıda belirtilen tutarın tahsil edildiğini gösterir; önceki dönemlere ait borçlara, gecikme tazminatına ve diğer hak ve alacaklara ilişkin haklar saklıdır.',
  disclaimer_text: 'Bu belge noter onaylı karar defteri/yasal defterlerin yerine geçmez.',
});

// --- Saf yardımcılar -----------------------------------------------------------------------------------------------------------------

export const formatReceiptNumber = (year, no) => `MK-${year}-${String(no).padStart(6, '0')}`;

/** 'MK-2026-000123' -> { year, no } | null. */
export function parseReceiptNumber(text) {
  const match = typeof text === 'string' ? /^MK-(\d{4})-(\d{6})$/.exec(text.trim().toUpperCase()) : null;
  if (!match) {
    return null;
  }
  const [year, no] = [Number(match[1]), Number(match[2])];
  return year >= 2000 && year <= 2100 && no >= 1 ? { year, no } : null;
}

/**
 * Doğrulama kodu anahtarı: FINANCE_RECEIPT_SECRET (>= 16 karakter); yoksa JWT_SECRET'tan TÜRETİLİR (HMAC). Kod satırda saklandığı için sır dönüşü eski
 * makbuzları etkilemez. Hiçbiri yoksa null (makbuz düzenlenemez: kapalı-başarısız).
 */
let shortSecretWarned = false;
export function receiptSecret(env = process.env) {
  const direct = String(env.FINANCE_RECEIPT_SECRET ?? '').trim();
  if (direct.length >= 16) {
    return direct;
  }
  if (direct.length > 0 && !shortSecretWarned) {
    shortSecretWarned = true;
    // eslint-disable-next-line no-console
    console.warn('[finance] FINANCE_RECEIPT_SECRET 16 karakterden kisa: yok sayildi, JWT_SECRET turevi kullaniliyor (deger yazdirilmaz).');
  }
  const jwt = String(env.JWT_SECRET ?? '').trim();
  return jwt.length > 0 ? createHmac('sha256', jwt).update('finance-receipt-secret-v1').digest('hex') : null;
}

/** HMAC-SHA256(secret, "site|yıl|no|tutar|paid_on") ilk 12 karakter, büyük harf/rakam. */
export function verificationCodeFor(secret, { siteCode, year, no, amountMinor, paidOn }) {
  return createHmac('sha256', secret).update(`${siteCode}|${year}|${no}|${amountMinor}|${paidOn}`).digest('hex').slice(0, 12).toUpperCase();
}

export function codesMatch(expected, supplied) {
  const a = Buffer.from(String(expected ?? ''), 'utf8');
  const b = Buffer.from(String(supplied ?? '').trim().toUpperCase(), 'utf8');
  return a.length === b.length && a.length > 0 && timingSafeEqual(a, b);
}

/** Ödeyen: ödeme anındaki payer_party'ye karşılık gelen ilişki (both -> malik). */
export const relationForPayer = (party) => (party === 'tenant' ? 'tenant' : 'owner');

/** Değişmez snapshot (v1). TCKN / telefon / e-posta / adres / bakiye / serbest açıklama YOK. */
export function buildSnapshot(input) {
  return {
    v: 1,
    number: input.number,
    kind: input.kind,
    issued_on: input.issuedOn,
    paid_on: input.paidOn,
    amount_minor: input.amountMinor,
    currency: 'TRY',
    method: input.method,
    site: { name: input.siteName },
    apartment: { label: input.apartmentLabel },
    payer: { party: input.payerParty, name: input.payerName ?? null },
    issuer: { name: input.issuerName ?? null },
    cancels_number: input.cancelsNumber ?? null,
    mahsup: 'oldest_due_first',
    cekince: true,
    template_version: RECEIPT_TEMPLATE_VERSION,
    verification_code: input.verificationCode,
  };
}

export const snapshotHash = (snapshot) => sha256Hex(canonicalJson(snapshot));

// --- Okuma ---------------------------------------------------------------------------------------------------------------------------

const RECEIPT_SELECT = `
  SELECT
    r.id, r.receipt_year, r.receipt_no, r.kind, r.ledger_entry_id, r.cancels_receipt_id, r.apartment_id, r.amount_minor::TEXT AS amount_minor,
    to_char(r.paid_on, 'YYYY-MM-DD') AS paid_on, to_char(r.issued_on, 'YYYY-MM-DD') AS issued_on, r.issued_at, r.snapshot,
    r.verification_code, r.template_version, r.cancel_reason_code, r.cancel_note, u.full_name AS issued_by_name,
    c.id AS cancelled_by_id, c.receipt_year AS cancelled_by_year, c.receipt_no AS cancelled_by_no,
    t.receipt_year AS target_year, t.receipt_no AS target_no,
    (SELECT COUNT(*) FROM receipt_print_events p WHERE p.receipt_id = r.id)::INTEGER AS copy_count
  FROM receipts r
  LEFT JOIN receipts c ON c.cancels_receipt_id = r.id
  LEFT JOIN receipts t ON t.id = r.cancels_receipt_id
  LEFT JOIN users u ON u.user_code = r.issued_by
`;

function statusOf(row) {
  if (row.kind !== 'collection') {
    return null;
  }
  return row.cancelled_by_id === null || row.cancelled_by_id === undefined ? 'active' : 'cancelled';
}

/** Liste öğesi. */
export function mapReceiptSummary(row) {
  const snapshot = row.snapshot ?? {};
  return {
    id: Number(row.id),
    number: formatReceiptNumber(row.receipt_year, row.receipt_no),
    kind: row.kind,
    status: statusOf(row),
    paid_on: row.paid_on,
    issued_on: row.issued_on,
    amount_minor: minorToNumber(row.amount_minor),
    apartment: { id: Number(row.apartment_id), label: snapshot.apartment?.label ?? null },
    payer_name: snapshot.payer?.name ?? null,
  };
}

/** Tam makbuz (yönetici / kurul). */
export function mapReceipt(row) {
  return {
    ...mapReceiptSummary(row),
    snapshot: row.snapshot,
    verification_code: row.verification_code,
    template_version: Number(row.template_version),
    template: RECEIPT_TEMPLATE,
    copy_count: Number(row.copy_count ?? 0),
    ledger_entry_id: Number(row.ledger_entry_id),
    cancels_number: row.target_no === null || row.target_no === undefined ? null : formatReceiptNumber(row.target_year, row.target_no),
    cancelled_by_number: row.cancelled_by_id === null || row.cancelled_by_id === undefined ? null : formatReceiptNumber(row.cancelled_by_year, row.cancelled_by_no),
    cancel_reason_code: row.cancel_reason_code ?? null,
    cancel_note: row.cancel_note ?? null,
    issued_at: toIso(row.issued_at),
    issued_by_name: row.issued_by_name ?? null,
  };
}

/** Sakin görünümü: ledger_entry_id, copy_count, cancel_note, issued_by_name çıkarılır (neden KODU kalır). */
export function mapReceiptForResident(row) {
  const full = mapReceipt(row);
  const { ledger_entry_id: _l, copy_count: _c, cancel_note: _n, issued_by_name: _i, ...rest } = full;
  return rest;
}

async function loadReceiptRow(db, siteCode, id) {
  const result = await db.query(`${RECEIPT_SELECT} WHERE r.id = $1 AND r.site_code = $2 LIMIT 1`, [id, siteCode]);
  return result.rows?.[0] ?? null;
}

async function loadReceiptByKey(db, siteCode, key) {
  const result = await db.query(`${RECEIPT_SELECT} WHERE r.site_code = $1 AND r.idempotency_key = $2 LIMIT 1`, [siteCode, key]);
  return result.rows?.[0] ?? null;
}

/** Ödemenin AKTİF makbuzu (iptal edilmemiş `collection`). */
async function loadActiveReceiptForEntry(db, siteCode, entryId) {
  const result = await db.query(
    `${RECEIPT_SELECT} WHERE r.site_code = $1 AND r.ledger_entry_id = $2 AND r.kind = 'collection' AND c.id IS NULL ORDER BY r.id DESC LIMIT 1`,
    [siteCode, entryId],
  );
  return result.rows?.[0] ?? null;
}

/** Defter satırı -> { id, number, status } küçük özeti (ekstre / ödeme yanıtı). */
export function receiptRef(row) {
  return row ? { id: Number(row.id), number: formatReceiptNumber(row.receipt_year, row.receipt_no) } : null;
}

// --- Düzenleme (işlem İÇİNDE; çağıran finance_post kilidini almış olmalı) ----------------------------------------------------------------

class ReceiptSecretMissing extends PlatformError {
  constructor() {
    super(503, 'RECEIPT_UNAVAILABLE', 'Makbuz şu anda düzenlenemiyor (sunucu yapılandırması eksik).');
  }
}

async function loadIssueContext(client, siteCode, apartmentId, payerParty, issuerUserCode) {
  const site = await client.query(`SELECT name FROM sites WHERE site_code = $1`, [siteCode]);
  const apartment = await client.query(
    `SELECT a.unit_label, b.block_name FROM apartments a INNER JOIN site_blocks b ON b.id = a.block_id WHERE a.id = $1 AND a.site_code = $2`,
    [apartmentId, siteCode],
  );
  const payer = await client.query(
    `
      SELECT COALESCE(NULLIF(u.full_name, ''), sp.full_name) AS name
      FROM apartment_residencies r
      INNER JOIN site_people sp ON sp.id = r.person_id AND sp.is_active = TRUE
      LEFT JOIN users u ON u.user_code = sp.user_code
      WHERE r.apartment_id = $1 AND r.is_current = TRUE AND r.relation = $2
      ORDER BY r.id
      LIMIT 1
    `,
    [apartmentId, relationForPayer(payerParty)],
  );
  const issuer =
    issuerUserCode === null ? { rows: [] } : await client.query(`SELECT full_name FROM users WHERE user_code = $1`, [issuerUserCode]);
  return {
    siteName: site.rows?.[0]?.name ?? '',
    apartmentLabel: apartmentLabel(apartment.rows?.[0]?.block_name, apartment.rows?.[0]?.unit_label),
    payerName: payer.rows?.[0]?.name ?? null,
    issuerName: issuer.rows?.[0]?.full_name ?? null,
  };
}

/** DB saatinden (İstanbul) şimdi + sıradaki sayaç. Sayaç ödemeyle AYNI işlemde artar. */
async function allocateNumber(client, siteCode) {
  const clock = await client.query(
    `SELECT to_char(t AT TIME ZONE 'Europe/Istanbul', 'YYYY-MM-DD') AS issued_on FROM (SELECT clock_timestamp() AS t) x`,
  );
  const issuedOn = clock.rows[0].issued_on;
  const year = Number(issuedOn.slice(0, 4));
  const counter = await client.query(
    `
      INSERT INTO receipt_counters (site_code, receipt_year, last_no) VALUES ($1, $2, 1)
      ON CONFLICT (site_code, receipt_year) DO UPDATE SET last_no = receipt_counters.last_no + 1
      RETURNING last_no
    `,
    [siteCode, year],
  );
  return { issuedOn, year, no: Number(counter.rows[0].last_no) };
}

async function insertReceipt(client, input) {
  const secret = receiptSecret();
  if (secret === null) {
    throw new ReceiptSecretMissing();
  }
  const { issuedOn, year, no } = await allocateNumber(client, input.siteCode);
  const number = formatReceiptNumber(year, no);
  const code = verificationCodeFor(secret, { siteCode: input.siteCode, year, no, amountMinor: input.amountMinor, paidOn: input.paidOn });
  const snapshot = buildSnapshot({
    number,
    kind: input.kind,
    issuedOn,
    paidOn: input.paidOn,
    amountMinor: input.amountMinor,
    method: input.method,
    siteName: input.context.siteName,
    apartmentLabel: input.context.apartmentLabel,
    payerParty: input.payerParty,
    payerName: input.context.payerName,
    issuerName: input.context.issuerName,
    cancelsNumber: input.cancelsNumber ?? null,
    verificationCode: code,
  });
  const inserted = await client.query(
    `
      INSERT INTO receipts (
        site_code, receipt_year, receipt_no, kind, ledger_entry_id, cancels_receipt_id, apartment_id, amount_minor, paid_on, issued_on,
        snapshot, snapshot_sha256, verification_code, template_version, cancel_reason_code, cancel_note, idempotency_key, issued_by
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8::BIGINT, $9::DATE, $10::DATE, $11::JSONB, $12, $13, $14, $15, $16, $17, $18)
      RETURNING id
    `,
    [
      input.siteCode,
      year,
      no,
      input.kind,
      input.ledgerEntryId,
      input.cancelsReceiptId ?? null,
      input.apartmentId,
      String(input.amountMinor),
      input.paidOn,
      issuedOn,
      JSON.stringify(snapshot),
      snapshotHash(snapshot),
      code,
      RECEIPT_TEMPLATE_VERSION,
      input.reasonCode ?? null,
      input.note ?? null,
      input.idempotencyKey ?? null,
      input.actorUserCode,
    ],
  );
  return Number(inserted.rows[0].id);
}

async function loadPaymentForReceipt(client, siteCode, entryId) {
  const result = await client.query(
    `
      SELECT l.id, l.apartment_id, l.kind, (-l.amount_minor)::TEXT AS amount, to_char(l.entry_date, 'YYYY-MM-DD') AS entry_date, l.method, l.payer_party,
             EXISTS (SELECT 1 FROM ledger_entries rv WHERE rv.reverses_entry_id = l.id) AS reversed
      FROM ledger_entries l WHERE l.id = $1 AND l.site_code = $2
    `,
    [entryId, siteCode],
  );
  return result.rows?.[0] ?? null;
}

/** Ödemenin aktif makbuzu { id, number } ya da null (tekrar yanıtı). */
export async function activeReceiptRef(db, siteCode, entryId) {
  return receiptRef(await loadActiveReceiptForEntry(db, siteCode, entryId));
}

/**
 * Ödeme için AKTİF makbuz yoksa düzenler (varsa onu döndürür). `payment` satırı AYNI işlemde yazılmış olabilir. Ters kayıtlı ödemeye 409 PAYMENT_REVERSED.
 * @returns {Promise<{ created: boolean, row: object }>} row = RECEIPT_SELECT satırı
 */
export async function ensureReceiptForPayment(client, { siteCode, entryId, actor, actorInfo }) {
  const payment = await loadPaymentForReceipt(client, siteCode, entryId);
  if (!payment || payment.kind !== 'payment') {
    throw entryNotFound();
  }
  const existing = await loadActiveReceiptForEntry(client, siteCode, entryId);
  if (existing) {
    return { created: false, row: existing };
  }
  if (payment.reversed === true) {
    throw paymentReversed();
  }
  const context = await loadIssueContext(client, siteCode, Number(payment.apartment_id), payment.payer_party, actorInfo.userCode);
  const id = await insertReceipt(client, {
    siteCode,
    kind: 'collection',
    ledgerEntryId: entryId,
    apartmentId: Number(payment.apartment_id),
    amountMinor: minorToNumber(payment.amount),
    paidOn: payment.entry_date,
    method: payment.method,
    payerParty: payment.payer_party,
    context,
    actorUserCode: actorInfo.userCode,
  });
  const row = await loadReceiptRow(client, siteCode, id);
  await recordFinanceAudit(client, actor, 'finance.receipt.issued', siteCode, id, {
    kind: 'collection',
    apartment_id: Number(payment.apartment_id),
    amount_minor: minorToNumber(payment.amount),
    ledger_entry_id: entryId,
  });
  return { created: true, row };
}

/** Bir makbuzu iptal makbuzuyla iptal eder (hedef `collection`, iptal edilmemiş olmalı). */
async function cancelReceiptRow(client, { siteCode, target, reasonCode, note, idempotencyKey, actor, actorInfo }) {
  const snapshot = target.snapshot ?? {};
  const secretContext = {
    siteName: snapshot.site?.name ?? '',
    apartmentLabel: snapshot.apartment?.label ?? '',
    payerName: snapshot.payer?.name ?? null,
    issuerName: null,
  };
  if (actorInfo.userCode !== null) {
    const issuer = await client.query(`SELECT full_name FROM users WHERE user_code = $1`, [actorInfo.userCode]);
    secretContext.issuerName = issuer.rows?.[0]?.full_name ?? null;
  }
  const id = await insertReceipt(client, {
    siteCode,
    kind: 'cancellation',
    ledgerEntryId: Number(target.ledger_entry_id),
    cancelsReceiptId: Number(target.id),
    cancelsNumber: formatReceiptNumber(target.receipt_year, target.receipt_no),
    apartmentId: Number(target.apartment_id),
    amountMinor: minorToNumber(target.amount_minor),
    paidOn: target.paid_on,
    method: snapshot.method ?? null,
    payerParty: snapshot.payer?.party ?? 'owner',
    context: secretContext,
    reasonCode,
    note,
    idempotencyKey,
    actorUserCode: actorInfo.userCode,
  });
  await recordFinanceAudit(client, actor, 'finance.receipt.cancelled', siteCode, id, {
    cancelled_receipt_id: Number(target.id),
    reason_code: reasonCode,
    amount_minor: minorToNumber(target.amount_minor),
  });
  return id;
}

/** Ödeme ters çevrilirken / düzeltilirken aktif makbuz varsa AYNI işlemde iptal eder (iptal makbuzu); yoksa null. */
export async function cancelActiveReceiptForEntry(client, { siteCode, entryId, reasonCode, actor, actorInfo }) {
  const active = await loadActiveReceiptForEntry(client, siteCode, entryId);
  if (!active) {
    return null;
  }
  const id = await cancelReceiptRow(client, { siteCode, target: active, reasonCode, note: null, idempotencyKey: null, actor, actorInfo });
  return id;
}

/** Ödeme satırı kimlikleri için makbuz özetleri (ekstre): entryId -> { id, number, status, cancelled_by_number }. */
export async function loadReceiptRefsForEntries(db, siteCode, entryIds) {
  if (entryIds.length === 0) {
    return new Map();
  }
  const result = await db.query(
    `
      SELECT DISTINCT ON (r.ledger_entry_id) r.ledger_entry_id, r.id, r.receipt_year, r.receipt_no, c.receipt_year AS c_year, c.receipt_no AS c_no
      FROM receipts r
      LEFT JOIN receipts c ON c.cancels_receipt_id = r.id
      WHERE r.site_code = $1 AND r.ledger_entry_id = ANY($2::BIGINT[]) AND r.kind = 'collection'
      ORDER BY r.ledger_entry_id, r.id DESC
    `,
    [siteCode, entryIds],
  );
  return new Map(
    (result.rows ?? []).map((row) => [
      Number(row.ledger_entry_id),
      {
        id: Number(row.id),
        number: formatReceiptNumber(row.receipt_year, row.receipt_no),
        status: row.c_no === null ? 'active' : 'cancelled',
        cancelled_by_number: row.c_no === null ? null : formatReceiptNumber(row.c_year, row.c_no),
      },
    ]),
  );
}

// --- Uçlar (yönetici) ----------------------------------------------------------------------------------------------------------------

/** POST entries/:id/receipt -> { created, receipt } (idempotent: aktif makbuz varsa onu döndürür). */
export async function issueReceiptManually({ siteCode, rawEntryId, actor }) {
  const entryId = parsePositiveId(rawEntryId);
  if (entryId === null) {
    throw entryNotFound();
  }
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const head = await client.query(`SELECT apartment_id FROM ledger_entries WHERE id = $1 AND site_code = $2`, [entryId, siteCode]);
    if (!head.rows?.[0]) {
      throw entryNotFound();
    }
    // KİLİT SIRASI: apartments -> users -> finans satırları
    await client.query(`SELECT id FROM apartments WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [Number(head.rows[0].apartment_id), siteCode]);
    await lockActorRow(client, actorInfo);
    const result = await ensureReceiptForPayment(client, { siteCode, entryId, actor, actorInfo });
    return { created: result.created, receipt: mapReceipt(result.row) };
  });
}

export function parseCancelBody(body) {
  const input = objectOf(body);
  if (input.reason_code !== 'issued_in_error') {
    throw invalidBody('İptal nedeni geçersiz.');
  }
  return {
    reasonCode: 'issued_in_error',
    note: normalizeFreeText(input.note, { label: 'Not', max: 200 }),
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

/** POST receipts/:id/cancel -> { replayed, cancellation, receipt }. */
export async function cancelReceipt({ siteCode, rawId, body, actor }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw receiptNotFound();
  }
  const input = parseCancelBody(body);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    const head = await client.query(`SELECT apartment_id FROM receipts WHERE id = $1 AND site_code = $2`, [id, siteCode]);
    if (!head.rows?.[0]) {
      throw receiptNotFound();
    }
    await client.query(`SELECT id FROM apartments WHERE id = $1 AND site_code = $2 FOR KEY SHARE`, [Number(head.rows[0].apartment_id), siteCode]);
    await lockActorRow(client, actorInfo);
    const target = await loadReceiptRow(client, siteCode, id);
    if (!target) {
      throw receiptNotFound();
    }
    const replay = await loadReceiptByKey(client, siteCode, input.idempotencyKey);
    if (replay) {
      if (
        replay.kind !== 'cancellation' ||
        Number(replay.cancels_receipt_id) !== id ||
        replay.cancel_reason_code !== input.reasonCode ||
        (replay.cancel_note ?? null) !== (input.note ?? null)
      ) {
        throw idempotencyConflict();
      }
      return { replayed: true, cancellation: mapReceipt(replay), receipt: mapReceipt(target) };
    }
    if (target.kind !== 'collection') {
      throw receiptNotCancellable();
    }
    if (target.cancelled_by_id !== null && target.cancelled_by_id !== undefined) {
      throw receiptAlreadyCancelled();
    }
    const cancellationId = await cancelReceiptRow(client, {
      siteCode,
      target,
      reasonCode: input.reasonCode,
      note: input.note,
      idempotencyKey: input.idempotencyKey,
      actor,
      actorInfo,
    });
    return {
      replayed: false,
      cancellation: mapReceipt(await loadReceiptRow(client, siteCode, cancellationId)),
      receipt: mapReceipt(await loadReceiptRow(client, siteCode, id)),
    };
  });
}

const PRINT_DEBOUNCE_SECONDS = 5;

/** POST receipts/:id/print { idempotency_key? } -> { copy_number, is_original, receipt: { number, status } }. */
export async function printReceipt({ siteCode, rawId, body, actor }) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw receiptNotFound();
  }
  const key = parseIdempotencyKey(objectOf(body).idempotency_key);
  const actorInfo = actorFromAuthUser(actor);
  return withFinanceTransaction(siteCode, async (client) => {
    await lockActorRow(client, actorInfo);
    const receipt = await loadReceiptRow(client, siteCode, id);
    if (!receipt) {
      throw receiptNotFound();
    }
    const respond = (copyNumber, replayed) => ({
      replayed,
      copy_number: copyNumber,
      is_original: copyNumber === 1,
      receipt: { id, number: formatReceiptNumber(receipt.receipt_year, receipt.receipt_no), status: statusOf(receipt) },
    });
    if (key !== null) {
      const byKey = await client.query(`SELECT copy_number FROM receipt_print_events WHERE receipt_id = $1 AND idempotency_key = $2`, [id, key]);
      if (byKey.rows?.[0]) {
        return respond(Number(byKey.rows[0].copy_number), true);
      }
    }
    if (actorInfo.userCode !== null) {
      const recent = await client.query(
        `
          SELECT copy_number FROM receipt_print_events
          WHERE receipt_id = $1 AND printed_by = $2 AND printed_at > clock_timestamp() - make_interval(secs => $3)
          ORDER BY copy_number DESC LIMIT 1
        `,
        [id, actorInfo.userCode, PRINT_DEBOUNCE_SECONDS],
      );
      if (recent.rows?.[0]) {
        return respond(Number(recent.rows[0].copy_number), true);
      }
    }
    const next = await client.query(`SELECT COALESCE(MAX(copy_number), 0) + 1 AS n FROM receipt_print_events WHERE receipt_id = $1`, [id]);
    const copyNumber = Number(next.rows[0].n);
    await client.query(
      `INSERT INTO receipt_print_events (site_code, receipt_id, copy_number, idempotency_key, printed_by) VALUES ($1, $2, $3, $4, $5)`,
      [siteCode, id, copyNumber, key, actorInfo.userCode],
    );
    await recordFinanceAudit(client, actor, 'finance.receipt.printed', siteCode, id, { copy_number: copyNumber });
    return respond(copyNumber, false);
  });
}

export function parseVerifyBody(body) {
  const input = objectOf(body);
  const number = parseReceiptNumber(input.number);
  if (number === null) {
    throw invalidBody('Makbuz numarası geçersiz (MK-YYYY-NNNNNN).');
  }
  if (typeof input.code !== 'string' || !/^[0-9A-Za-z]{12}$/.test(input.code.trim())) {
    throw invalidBody('Doğrulama kodu 12 karakter olmalıdır.');
  }
  return { ...number, code: input.code.trim() };
}

/**
 * POST receipts/verify -> { valid, status } (+ geçerliyse number, amount_minor, paid_on, issued_on, apartment_label: elindeki belgeyle karşılaştırılsın; gerçek numara + kodla
 * tutarı / tarihi değiştirilmiş sahte belge "valid" görünmesin). Hiçbir şey yazmaz. Kayıt yoksa / kod uyuşmazsa valid false (ayrıntı sızmaz).
 */
export async function verifyReceipt({ siteCode, body, db = pool }) {
  const input = parseVerifyBody(body);
  const result = await db.query(`${RECEIPT_SELECT} WHERE r.site_code = $1 AND r.receipt_year = $2 AND r.receipt_no = $3 LIMIT 1`, [
    siteCode,
    input.year,
    input.no,
  ]);
  const row = result.rows?.[0];
  if (!row || !codesMatch(row.verification_code, input.code)) {
    return { valid: false, status: null };
  }
  return {
    valid: true,
    status: row.kind === 'cancellation' ? 'cancellation' : statusOf(row),
    number: formatReceiptNumber(row.receipt_year, row.receipt_no),
    amount_minor: minorToNumber(row.amount_minor),
    paid_on: row.paid_on,
    issued_on: row.issued_on,
    apartment_label: row.snapshot?.apartment?.label ?? null,
  };
}

// --- Listeleme ---------------------------------------------------------------------------------------------------------------------------

export function parseReceiptsQuery(query = {}) {
  const year = queryInt(query.year, { min: 2000, max: 2100, fallback: null });
  return {
    apartmentId: queryId(query.apartment_id),
    year,
    kind: queryEnum(query.kind, ['collection', 'cancellation'], null),
    q: typeof query.q === 'string' && query.q.trim() !== '' ? Array.from(query.q.trim()).slice(0, 60).join('') : null,
    limit: queryInt(query.limit, { min: 1, max: 200, fallback: 50 }),
    beforeId: queryId(query.before_id),
  };
}

function receiptFilters(filters, startParams) {
  const params = [...startParams];
  const clauses = [];
  if (filters.apartmentId !== null) {
    params.push(filters.apartmentId);
    clauses.push(`r.apartment_id = $${params.length}`);
  }
  if (filters.year !== null) {
    params.push(filters.year);
    clauses.push(`r.receipt_year = $${params.length}`);
  }
  if (filters.kind !== null) {
    params.push(filters.kind);
    clauses.push(`r.kind = $${params.length}`);
  }
  if (filters.q !== null) {
    params.push(`%${escapeLike(foldText(filters.q))}%`);
    const like = `$${params.length}`;
    clauses.push(`(
      lower('MK-' || r.receipt_year::TEXT || '-' || lpad(r.receipt_no::TEXT, 6, '0')) LIKE ${like} ESCAPE '\\'
      OR ${foldSql(`r.snapshot #>> '{apartment,label}'`)} LIKE ${like} ESCAPE '\\'
      OR ${foldSql(`r.snapshot #>> '{payer,name}'`)} LIKE ${like} ESCAPE '\\'
    )`);
  }
  if (filters.beforeId !== null) {
    params.push(filters.beforeId);
    clauses.push(`r.id < $${params.length}`);
  }
  return { params, clauses };
}

/** GET receipts -> { items, next_before_id }. */
export async function listReceipts(siteCode, query = {}, db = pool) {
  const filters = parseReceiptsQuery(query);
  const { params, clauses } = receiptFilters(filters, [siteCode]);
  params.push(filters.limit + 1);
  const result = await db.query(
    `${RECEIPT_SELECT} WHERE r.site_code = $1${clauses.map((c) => ` AND ${c}`).join('')} ORDER BY r.id DESC LIMIT $${params.length}`,
    params,
  );
  const rows = result.rows ?? [];
  const page = rows.slice(0, filters.limit);
  return { items: page.map(mapReceiptSummary), next_before_id: rows.length > filters.limit && page.length > 0 ? Number(page[page.length - 1].id) : null };
}

/** Dışa aktarma: liste süzgeçleriyle AYNI mantık, sayfalamasız (en çok limit+1 satır; çağıran üst sınırı denetler). */
export async function exportReceiptRows(siteCode, query = {}, db = pool, limit = 20001) {
  const filters = parseReceiptsQuery({ ...query, limit: undefined, before_id: undefined });
  const { params, clauses } = receiptFilters({ ...filters, beforeId: null }, [siteCode]);
  params.push(limit);
  const result = await db.query(
    `${RECEIPT_SELECT} WHERE r.site_code = $1${clauses.map((c) => ` AND ${c}`).join('')} ORDER BY r.id DESC LIMIT $${params.length}`,
    params,
  );
  return (result.rows ?? []).map(mapReceiptSummary);
}

/** GET receipts/:id. */
export async function getReceipt(siteCode, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw receiptNotFound();
  }
  const row = await loadReceiptRow(db, siteCode, id);
  if (!row) {
    throw receiptNotFound();
  }
  return mapReceipt(row);
}

// --- Sakin -------------------------------------------------------------------------------------------------------------------------------

const INT32_MAX = 2147483647;

async function visibleApartmentIds(db, authUser) {
  const userCode = parsePositiveId(authUser?.user_code ?? authUser?.userCode ?? authUser?.id, INT32_MAX);
  if (userCode === null) {
    return { siteCodes: [], apartmentIds: [] };
  }
  const visible = await loadVisibleApartments(db, userCode);
  const enabled = await enabledFinanceSites(db, [...new Set(visible.map((row) => Number(row.site_code)))]);
  const rows = visible.filter((row) => enabled.has(Number(row.site_code)));
  return {
    siteCodes: [...new Set(rows.map((row) => Number(row.site_code)))],
    apartmentIds: rows.map((row) => Number(row.apartment_id)),
  };
}

/** GET /app/my-finance/receipts -> { items, next_before_id } (yalnız çağıranın F2.05 kuralıyla borcu görebildiği daireler). */
export async function listMyReceipts(authUser, query = {}, db = pool) {
  const filters = parseReceiptsQuery(query);
  const scope = await visibleApartmentIds(db, authUser);
  if (scope.apartmentIds.length === 0 || (filters.apartmentId !== null && !scope.apartmentIds.includes(filters.apartmentId))) {
    return { items: [], next_before_id: null };
  }
  const { params, clauses } = receiptFilters({ ...filters, q: null }, [scope.siteCodes, scope.apartmentIds]);
  params.push(filters.limit + 1);
  const result = await db.query(
    `${RECEIPT_SELECT} WHERE r.site_code = ANY($1::BIGINT[]) AND r.apartment_id = ANY($2::BIGINT[])${clauses.map((c) => ` AND ${c}`).join('')} ORDER BY r.id DESC LIMIT $${params.length}`,
    params,
  );
  const rows = result.rows ?? [];
  const page = rows.slice(0, filters.limit);
  return {
    items: page.map(mapReceiptSummary),
    next_before_id: rows.length > filters.limit && page.length > 0 ? Number(page[page.length - 1].id) : null,
  };
}

/** GET /app/my-finance/receipts/:id. */
export async function getMyReceipt(authUser, rawId, db = pool) {
  const id = parsePositiveId(rawId);
  if (id === null) {
    throw receiptNotFound();
  }
  const scope = await visibleApartmentIds(db, authUser);
  if (scope.apartmentIds.length === 0) {
    throw receiptNotFound();
  }
  const result = await db.query(
    `${RECEIPT_SELECT} WHERE r.id = $1 AND r.site_code = ANY($2::BIGINT[]) AND r.apartment_id = ANY($3::BIGINT[]) LIMIT 1`,
    [id, scope.siteCodes, scope.apartmentIds],
  );
  if (!result.rows?.[0]) {
    throw receiptNotFound();
  }
  return mapReceiptForResident(result.rows[0]);
}
