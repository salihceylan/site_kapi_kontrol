// Dekont bildirimi (geçici kabul; 066): sabitler, hatalar, gövde ayrıştırma, durum makinesi ve uyarı hesabı (saf işlevler). Sözleşme: docs/PLATFORM_FINANS_DEKONT.md.

import { PlatformError } from './errors.js';
import { METHODS, assertNotTooOld, invalidBody, normalizeFreeText, parseAccountParty, parseIdempotencyKey, parseIsoDate, requireMinor, today } from './finance_common.js';
import { parseFundField } from './finance_funds.js';
import { parseTrIban } from './finance_iban.js';
import { parsePositiveId } from './people_common.js';
import { foldText } from './people_common.js';

export const NOTICE_MAX_BYTES = 10 * 1024 * 1024;
export const NOTICE_MIMES = Object.freeze({ 'application/pdf': 'pdf', 'image/jpeg': 'jpg', 'image/png': 'png' });
export const NOTICE_STATUSES = Object.freeze(['uploading', 'pending', 'approved', 'rejected', 'withdrawn']);
export const NOTICE_ORIGINS = Object.freeze(['resident_app', 'resident_share', 'manager']);
export const REJECT_REASONS = Object.freeze(['not_received', 'amount_mismatch', 'wrong_apartment', 'duplicate', 'unreadable', 'other']);
export const REJECT_REASON_TEXT = Object.freeze({
  not_received: 'Ödeme hesabımıza ulaşmadı.',
  amount_mismatch: 'Tutar dekonttaki ile uyuşmuyor.',
  wrong_apartment: 'Ödeme başka bir daire için yapılmış görünüyor.',
  duplicate: 'Bu ödeme daha önce kaydedilmiş.',
  unreadable: 'Dekont okunamadı; yeniden gönderin.',
  other: 'Yönetim bildirimi kabul etmedi.',
});
export const MAX_PENDING_PER_USER = 5;
export const MAX_PER_APARTMENT_30D = 20;
export const BULK_MAX = 50;
export const STALE_UPLOAD_MINUTES = 120;
export const PAID_ON_LOOKBACK_DAYS = 365;
export const OLD_DATE_DAYS = 60;
export const DUPLICATE_WINDOW_DAYS = 3;
export const DEFAULT_SITE_QUOTA_MB = 2048;

export const siteQuotaBytes = (env = process.env) => {
  const mb = Number(env.PAYMENT_NOTICES_SITE_QUOTA_MB);
  return (Number.isFinite(mb) && mb > 0 ? mb : DEFAULT_SITE_QUOTA_MB) * 1024 * 1024;
};

export const noticeNotFound = () => new PlatformError(404, 'PAYMENT_NOTICE_NOT_FOUND', 'Dekont bildirimi bulunamadı.');
export const noticesDisabled = () => new PlatformError(403, 'PAYMENT_NOTICES_DISABLED', 'Bu sitede dekont bildirimi henüz açık değil.');
export const noticeInvalidState = (message = 'Bildirim bu işleme uygun durumda değil.') => new PlatformError(409, 'NOTICE_INVALID_STATE', message);
export const warningsUnacknowledged = (warnings) =>
  new PlatformError(409, 'NOTICE_WARNINGS_UNACKNOWLEDGED', 'Önemli uyarılar var; onaylamadan önce her birini gözden geçirdiğinizi işaretleyin.', { warnings });
export const noticePeriodClosed = () =>
  new PlatformError(409, 'NOTICE_PERIOD_CLOSED', 'Dekontun tarihi kapalı bir döneme düşüyor. Bugünün tarihiyle işlemek için "Açık döneme yaz" seçeneğini işaretleyin.');
export const noticeLimit = (message) => new PlatformError(429, 'NOTICE_LIMIT_REACHED', message);
export const noticeQuota = () => new PlatformError(409, 'NOTICE_QUOTA_EXCEEDED', 'Sitenin dekont depolama alanı doldu. Yönetimle görüşün.');
export const noticeTooLarge = () => new PlatformError(413, 'NOTICE_FILE_TOO_LARGE', 'Dosya en fazla 10 MB olabilir.');
export const noticeSizeMismatch = () => new PlatformError(400, 'NOTICE_SIZE_MISMATCH', 'Gönderilen dosya boyutu bildirilenle uyuşmuyor.');
export const noticeTypeNotAllowed = () => new PlatformError(415, 'NOTICE_TYPE_NOT_ALLOWED', 'Yalnız PDF, JPEG ve PNG dekont yüklenebilir.');
export const noticeContentMismatch = () => new PlatformError(415, 'NOTICE_CONTENT_MISMATCH', 'Dosya içeriği bildirilen türle uyuşmuyor. Dekontun ekran görüntüsünü yüklemeyi deneyin.');
export const noticeStorageUnavailable = () => new PlatformError(503, 'NOTICE_STORAGE_UNAVAILABLE', 'Dosya depolama şu an kullanılamıyor. Biraz sonra tekrar deneyin.');
export const noticeFileMissing = () => new PlatformError(404, 'NOTICE_FILE_NOT_FOUND', 'Bu bildirimde dosya yok.');
export const noticeConflict = () => new PlatformError(409, 'IDEMPOTENCY_CONFLICT', 'Aynı işlem anahtarı farklı bir bildirimle kullanılmış.');

// --- Durum makinesi (tetikleyiciyle aynı kurallar) ----------------------------------------------------------

const TRANSITIONS = Object.freeze({
  uploading: ['pending', 'withdrawn'],
  pending: ['approved', 'rejected', 'withdrawn'],
  approved: [],
  rejected: [],
  withdrawn: [],
});
export const canTransition = (from, to) => (TRANSITIONS[from] ?? []).includes(to);

// --- Ayrıştırma -------------------------------------------------------------------------------------------

const objectOf = (body) => (body && typeof body === 'object' && !Array.isArray(body) ? body : {});

/** Dosya bilgisi: ad, boyut (1..10 MB), tür (PDF/JPEG/PNG). */
export function parseFileMeta(raw) {
  const file = objectOf(raw);
  const name = normalizeFreeText(file.name, { label: 'Dosya adı', max: 120, required: true }).replace(/[\\/:*?"<>|]+/g, '_');
  const size = file.size;
  if (!Number.isSafeInteger(size) || size < 1) throw invalidBody('Dosya boyutu geçersiz.');
  if (size > NOTICE_MAX_BYTES) throw noticeTooLarge();
  const type = typeof file.content_type === 'string' ? file.content_type.trim().toLowerCase() : '';
  if (!Object.hasOwn(NOTICE_MIMES, type)) throw noticeTypeNotAllowed();
  return { name, size, type };
}

/** Bildirim gövdesi (sakin ya da yönetici girişi). `manager`: dosya isteğe bağlı, yöntem seçilebilir, hesap seçilebilir. */
export function parseNoticeInput(body, { manager = false, now = new Date() } = {}) {
  const input = objectOf(body);
  const apartmentId = parsePositiveId(input.apartment_id);
  if (apartmentId === null) throw invalidBody('Daire seçimi geçersiz.');
  const paidOn = parseIsoDate(input.paid_on, 'Ödeme tarihi');
  if (paidOn > today(now)) throw invalidBody('Gelecek tarihli ödeme bildirilemez.');
  if (manager) assertNotTooOld(paidOn, 'Ödeme tarihi', now);
  else if (paidOn < addDaysIso(today(now), -PAID_ON_LOOKBACK_DAYS)) throw invalidBody('Ödeme tarihi en fazla 1 yıl öncesi olabilir.');
  let method = 'transfer';
  if (manager && input.method !== undefined && input.method !== null) {
    if (!METHODS.includes(input.method)) throw invalidBody('Ödeme yöntemi (nakit, havale veya çek) geçersiz.');
    method = input.method;
  }
  let senderIban = null;
  if (input.sender_iban !== undefined && input.sender_iban !== null && String(input.sender_iban).trim() !== '') {
    senderIban = parseTrIban(input.sender_iban);
    if (senderIban === null) throw invalidBody('Gönderen IBAN geçersiz.');
  }
  const origin = manager ? 'manager' : input.origin === 'resident_share' ? 'resident_share' : 'resident_app';
  const hasFile = input.file !== undefined && input.file !== null;
  if (!manager && !hasFile) throw invalidBody('Dekont dosyası zorunludur.');
  return {
    apartmentId,
    amountMinor: requireMinor(input.amount_minor, 'Tutar'),
    paidOn,
    method,
    senderName: normalizeFreeText(input.sender_name, { label: 'Gönderen adı', max: 80 }),
    senderIban,
    description: normalizeFreeText(input.description, { label: 'Açıklama', max: 200 }),
    note: normalizeFreeText(input.note, { label: 'Not', max: 300 }),
    origin,
    accountParty: manager ? parseAccountParty(input.account_party) : null,
    file: hasFile ? parseFileMeta(input.file) : null,
    idempotencyKey: parseIdempotencyKey(input.idempotency_key, { required: true }),
  };
}

export function parseRejectInput(body) {
  const input = objectOf(body);
  if (typeof input.reason_code !== 'string' || !REJECT_REASONS.includes(input.reason_code)) throw invalidBody('İptal nedeni seçin.');
  return { reasonCode: input.reason_code, note: normalizeFreeText(input.note, { label: 'Not', max: 300 }) };
}

export function parseApproveInput(body) {
  const input = objectOf(body);
  const accountId = input.account_id === undefined || input.account_id === null ? null : parsePositiveId(input.account_id);
  if (input.account_id !== undefined && input.account_id !== null && accountId === null) throw invalidBody('Hesap seçimi geçersiz.');
  const acknowledged = Array.isArray(input.acknowledged) ? input.acknowledged.filter((c) => typeof c === 'string').slice(0, 20) : [];
  return {
    accountId,
    accountParty: parseAccountParty(input.account_party),
    // K3: tahsilatın gireceği İşletme / Fon hesabı. Daire hesabında iki türün de açık borcu varsa ZORUNLUDUR (yoksa 400 FUND_CHOICE_REQUIRED);
    // tek tür borçta istemci önerilen hesabı seçili gönderir; verilmezse kısıtsız kayıt (eski istemci).
    fund: parseFundField(input.fund),
    bookInOpenPeriod: input.book_in_open_period === true,
    acknowledged,
  };
}

export function parseIdList(body) {
  const ids = objectOf(body).ids;
  if (!Array.isArray(ids) || ids.length === 0 || ids.length > BULK_MAX) throw invalidBody(`En az 1, en çok ${BULK_MAX} bildirim seçilebilir.`);
  const out = [];
  for (const raw of ids) {
    const id = parsePositiveId(raw);
    if (id === null) throw invalidBody('Bildirim seçimi geçersiz.');
    if (!out.includes(id)) out.push(id);
  }
  return out;
}

export function addDaysIso(iso, days) {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
const dayDiff = (a, b) => Math.abs((Date.parse(`${a}T00:00:00Z`) - Date.parse(`${b}T00:00:00Z`)) / 86400000);

/** İstek parmak izi: aynı anahtarla farklı içerik 409. */
export function fingerprintOf(input) {
  return JSON.stringify([input.apartmentId, input.amountMinor, input.paidOn, input.method, input.file?.size ?? null, input.file?.type ?? null]);
}

// --- Uyarılar (saf) ---------------------------------------------------------------------------------------

export const STRONG_WARNINGS = Object.freeze(['REFERENCE_OTHER_APARTMENT', 'SAME_FILE_OTHER_NOTICE', 'POSSIBLE_DUPLICATE']);

/**
 * facts: { notice, otherApartmentRef (bool), sameFileCount, duplicateCount, peopleNames[], accountBalanceMinor, now }.
 * Dönüş: [{ code, level: 'strong' | 'info' }]
 */
export function computeWarnings(facts) {
  const { notice } = facts;
  const out = [];
  if (facts.otherApartmentRef) out.push({ code: 'REFERENCE_OTHER_APARTMENT', level: 'strong' });
  if (facts.sameFileCount > 0) out.push({ code: 'SAME_FILE_OTHER_NOTICE', level: 'strong' });
  if (facts.duplicateCount > 0) out.push({ code: 'POSSIBLE_DUPLICATE', level: 'strong' });
  if (notice.sender_name && facts.peopleNames.length > 0 && !nameMatches(notice.sender_name, facts.peopleNames)) out.push({ code: 'NAME_MISMATCH', level: 'info' });
  if (Number.isFinite(facts.accountBalanceMinor) && Number(notice.amount_minor) > Math.max(0, facts.accountBalanceMinor)) out.push({ code: 'OVERPAYMENT', level: 'info' });
  if (dayDiff(today(facts.now ?? new Date()), notice.paid_on) > OLD_DATE_DAYS) out.push({ code: 'OLD_DATE', level: 'info' });
  return out;
}

export const WARNING_TEXT = Object.freeze({
  REFERENCE_OTHER_APARTMENT: 'Açıklamadaki referans kodu başka bir daireye ait.',
  SAME_FILE_OTHER_NOTICE: 'Aynı dosya başka bir bildirimde de var.',
  POSSIBLE_DUPLICATE: 'Bu daire için yakın tarihte aynı tutarda bir tahsilat, onaylı ya da bekleyen bildirim var.',
  NAME_MISMATCH: 'Gönderen adı dairedeki kişilerle eşleşmiyor.',
  OVERPAYMENT: 'Tutar hesabın borcundan fazla; fazlası alacak olur.',
  OLD_DATE: 'Ödeme tarihi 60 günden eski.',
});

/** Gönderen adının herhangi bir sözcüğü (3+ harf), dairedeki bir kişinin adında geçiyor mu (Türkçe karakter ve büyük/küçük harf duyarsız). */
export function nameMatches(sender, names) {
  const words = foldText(sender).split(/[^a-z0-9]+/).filter((w) => w.length >= 3);
  if (words.length === 0) return true;
  const haystack = names.map((n) => foldText(n));
  return words.some((w) => haystack.some((h) => h.includes(w)));
}

export const dayDistance = dayDiff;

// --- Çıktı ------------------------------------------------------------------------------------------------

const iso = (v) => (v ? new Date(v).toISOString() : null);

/** Satır -> API gövdesi. `resident`: IBAN/notlar sakine kendi gönderdiği kadar; yönetici aynısını görür. */
export function mapNotice(row) {
  return {
    id: Number(row.id),
    site_code: Number(row.site_code),
    apartment_id: Number(row.apartment_id),
    apartment_label: row.apartment_label ?? null,
    account_party: row.account_party,
    origin: row.origin,
    status: row.status,
    amount_minor: Number(row.amount_minor),
    paid_on: typeof row.paid_on === 'string' ? row.paid_on : row.paid_on?.toISOString?.().slice(0, 10),
    method: row.method,
    sender_name: row.sender_name ?? null,
    sender_iban: row.sender_iban ?? null,
    description: row.description ?? null,
    note: row.note ?? null,
    has_file: Boolean(row.storage_key && row.file_completed_at),
    file_required: row.file_required === true,
    display_name: row.display_name ?? null,
    mime_type: row.mime_type ?? null,
    size_bytes: row.size_bytes === null || row.size_bytes === undefined ? null : Number(row.size_bytes),
    submitted_at: iso(row.submitted_at),
    decided_at: iso(row.decided_at),
    reject_reason_code: row.reject_reason_code ?? null,
    reject_reason_text: row.reject_reason_code ? REJECT_REASON_TEXT[row.reject_reason_code] : null,
    reject_note: row.reject_note ?? null,
    ledger_entry_id: row.ledger_entry_id === null || row.ledger_entry_id === undefined ? null : Number(row.ledger_entry_id),
    linked_existing: row.linked_existing === true,
    unseen_decision: ['approved', 'rejected'].includes(row.status) && !row.resident_seen_at && row.origin !== 'manager',
  };
}

export const NOTICE_COLUMNS = `
  n.id, n.site_code, n.apartment_id, n.account_party, n.origin, n.submitted_by, n.amount_minor::TEXT AS amount_minor,
  to_char(n.paid_on, 'YYYY-MM-DD') AS paid_on, n.method, n.sender_name, n.sender_iban, n.description, n.note, n.status, n.file_required,
  n.storage_key, n.display_name, n.mime_type, n.size_bytes::TEXT AS size_bytes, n.sha256, n.file_completed_at, n.submitted_at, n.decided_by, n.decided_at,
  n.reject_reason_code, n.reject_note, n.ledger_entry_id, n.linked_existing, n.resident_seen_at, n.idempotency_key, n.request_fingerprint
`;
