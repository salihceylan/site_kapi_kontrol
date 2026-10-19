// Ziyaretçi ve Kargo (F11.03) ortak sabitleri, hata üreticileri, girdi doğrulayıcıları ve yanıt eşleyicileri. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_ZIYARETCI_KARGO.md. Hata gövdesi { error, code } (PlatformError). Kullanıcı metni düz yazıdır. Günlüğe ve audit `details`
// alanına ziyaretçi adı / firma / not YAZILMAZ (yalnız kimlik, tür, durum).

import { PlatformError } from './errors.js';
import { INVISIBLE_RE } from './document_common.js';
import { DELETED_USER_NAME } from './account_common.js';
import { apartmentLabel, optionalQueryId, parsePositiveId, parseSearchTerm, toIso } from './people_common.js';

export const VISITOR_LOG_MODULE = 'visitor_log';

export const KINDS = Object.freeze(['visitor', 'cargo']);
export const STATUSES = Object.freeze(['bekliyor', 'iceride', 'teslim_edildi', 'ayrildi', 'iptal']);
export const OPEN_STATUSES = Object.freeze(['bekliyor', 'iceride']);
export const TERMINAL_STATUSES = Object.freeze(['teslim_edildi', 'ayrildi', 'iptal']);
/** Başlangıç durumu türe göre sunucuda hesaplanır: kargo -> bekliyor, ziyaretçi -> iceride. */
export const INITIAL_STATUS = Object.freeze({ visitor: 'iceride', cargo: 'bekliyor' });
/** Geçişler (sunucuda doğrulanır). teslim_edildi / ayrildi / iptal SONDUR. */
export const TRANSITIONS = Object.freeze({
  bekliyor: Object.freeze(['teslim_edildi', 'iptal']),
  iceride: Object.freeze(['ayrildi', 'iptal']),
  teslim_edildi: Object.freeze([]),
  ayrildi: Object.freeze([]),
  iptal: Object.freeze([]),
});

export const NAME_MAX = 120;
export const COMPANY_MAX = 120;
export const NOTE_MAX = 500;
export const LIST_DEFAULT_LIMIT = 50;
export const LIST_MAX_LIMIT = 200;
export const LIST_MAX_OFFSET = 100000;
/** İstek gövdesi için kaba üst sınır (bayt; Content-Length). */
export const MAX_BODY_BYTES = 8192;

// --- Hatalar -----------------------------------------------------------------------------------------------------

export const visitorEntryNotFound = () => new PlatformError(404, 'VISITOR_ENTRY_NOT_FOUND', 'Kayıt bulunamadı ya da erişiminiz yok.');
export const apartmentNotFound = () => new PlatformError(404, 'APARTMENT_NOT_FOUND', 'Daire bu sitede bulunamadı.');
export const siteNotFound = () => new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
export const moduleDisabled = () =>
  new PlatformError(403, 'MODULE_DISABLED', 'Ziyaretçi ve Kargo modülü kapalı.', { module: VISITOR_LOG_MODULE });
export const forbiddenRole = () => new PlatformError(403, 'FORBIDDEN_ROLE', 'Bu işlem için yetkiniz yok.');
export const accountDeleted = () => new PlatformError(401, 'ACCOUNT_DELETED', 'Bu hesap silinmiş.');
export const invalidField = (message) => new PlatformError(400, 'INVALID_BODY', message);
export const invalidQuery = () => new PlatformError(400, 'INVALID_QUERY', 'Geçersiz sorgu parametresi.');
export const invalidTransition = (from, to) =>
  new PlatformError(409, 'INVALID_TRANSITION', 'Kayıt bu durumdan istenen duruma geçirilemez.', { from, to });
export const bodyTooLarge = () => new PlatformError(413, 'BODY_TOO_LARGE', 'İstek gövdesi çok büyük.');

// --- Metin temizliği ---------------------------------------------------------------------------------------------

const LINE_BREAKS = String.fromCodePoint(0x2028) + String.fromCodePoint(0x2029);
const BREAKS_RE = new RegExp('[' + String.fromCharCode(13, 10, 9) + LINE_BREAKS + ']+', 'g');
const NEWLINES_RE = new RegExp(String.fromCharCode(13) + '?' + String.fromCharCode(10) + '|' + String.fromCharCode(13) + '|[' + LINE_BREAKS + ']', 'g');
const codePointLength = (text) => Array.from(text).length;

function singleLine(value) {
  return value.normalize('NFC').replace(BREAKS_RE, ' ').replace(INVISIBLE_RE, '').replace(/\s+/gu, ' ').trim();
}

/** Çok satırlı düz yazı: satır sonları korunur, kontrol / görünmez karakterler atılır. */
function multiLine(value) {
  return value
    .normalize('NFC')
    .replace(NEWLINES_RE, '\n')
    .replace(/\t/g, ' ')
    .replace(INVISIBLE_RE, (match) => (match === '\n' ? '\n' : ''))
    .replace(/[^\S\n]+\n/g, '\n')
    .replace(/\n{4,}/g, '\n\n\n')
    .trim();
}

/** Ziyaretçi adı (kargoda: kargo firması / gönderen). Tek satır, 1-120 karakter. */
export function normalizeVisitorName(value) {
  if (typeof value !== 'string') throw invalidField('Ziyaretçi ya da kargo adı zorunludur.');
  const text = singleLine(value);
  const length = codePointLength(text);
  if (length < 1) throw invalidField('Ziyaretçi ya da kargo adı boş olamaz.');
  if (length > NAME_MAX) throw invalidField(`Ad en fazla ${NAME_MAX} karakter olabilir.`);
  return text;
}

/** Firma (isteğe bağlı): boş / null -> null. */
export function normalizeCompany(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw invalidField('Firma geçersiz.');
  const text = singleLine(value);
  if (text === '') return null;
  if (codePointLength(text) > COMPANY_MAX) throw invalidField(`Firma en fazla ${COMPANY_MAX} karakter olabilir.`);
  return text;
}

/** Not (isteğe bağlı, çok satırlı): boş / null -> null (PATCH'te notu siler). */
export function normalizeNote(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw invalidField('Not geçersiz.');
  const text = multiLine(value);
  if (text === '') return null;
  if (codePointLength(text) > NOTE_MAX) throw invalidField(`Not en fazla ${NOTE_MAX} karakter olabilir.`);
  return text;
}

const isPlainObject = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);

function optionalId(value, label) {
  if (value === undefined || value === null) return null;
  const id = parsePositiveId(value);
  if (id === null) throw invalidField(`${label} geçersiz.`);
  return id;
}

// --- Geçiş kuralı -------------------------------------------------------------------------------------------------

/**
 * Durum geçişini doğrular. Aynı durum -> false (değişiklik yok, idempotent). İzinsiz geçiş (sonlanmış kayıt dahil) -> 409 INVALID_TRANSITION { from, to }.
 * @returns {boolean} true: geçiş uygulanmalı
 */
export function assertTransition(from, to) {
  if (from === to) return false;
  if (!(TRANSITIONS[from] ?? []).includes(to)) throw invalidTransition(from, to);
  return true;
}

export const nextStatuses = (status) => [...(TRANSITIONS[status] ?? [])];

// --- Girdi ayrıştırıcıları --------------------------------------------------------------------------------------

/** POST .../visitor-entries gövdesi: { kind, apartment_id?, visitor_name, company?, note? }. Durum türe göre hesaplanır. */
export function parseCreateInput(body) {
  if (!isPlainObject(body)) throw invalidField('İstek gövdesi geçersiz.');
  if (typeof body.kind !== 'string' || !KINDS.includes(body.kind)) {
    throw invalidField('Kayıt türü geçersiz (ziyaretçi ya da kargo olmalıdır).');
  }
  return {
    kind: body.kind,
    apartmentId: optionalId(body.apartment_id, 'Daire'),
    visitorName: normalizeVisitorName(body.visitor_name),
    company: normalizeCompany(body.company),
    note: normalizeNote(body.note),
    status: INITIAL_STATUS[body.kind],
  };
}

/** PATCH gövdesi: en az bir alan ({ status?, note? }); note null / boş -> notu siler. */
export function parsePatchInput(body) {
  if (!isPlainObject(body)) throw invalidField('İstek gövdesi geçersiz.');
  const out = {};
  if ('status' in body) {
    if (typeof body.status !== 'string' || !STATUSES.includes(body.status)) throw invalidField('Durum geçersiz.');
    out.status = body.status;
  }
  if ('note' in body) {
    out.note = normalizeNote(body.note);
  }
  if (Object.keys(out).length === 0) throw invalidField('Değiştirilecek bir alan gönderilmedi.');
  return out;
}

function parseLimit(value) {
  if (value === undefined || value === null || String(value).trim() === '') return LIST_DEFAULT_LIMIT;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) throw invalidQuery();
  return Math.min(LIST_MAX_LIMIT, parsed);
}

function parseOffset(value) {
  if (value === undefined || value === null || String(value).trim() === '') return 0;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > LIST_MAX_OFFSET) throw invalidQuery();
  return parsed;
}

function parseEnum(value, allowed) {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  if (typeof value !== 'string' || !allowed.includes(value)) throw invalidQuery();
  return value;
}

const DATE_ONLY_RE = /^\d{4}-\d{2}-\d{2}$/;

/** from / to: "YYYY-MM-DD" (gün; `to` o günün sonuna kadar) ya da ISO tarih-saat. -> { value, dateOnly } | null */
export function parseDateBound(value) {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  if (typeof value !== 'string' || value.length > 40) throw invalidQuery();
  const text = value.trim();
  if (DATE_ONLY_RE.test(text)) {
    const [y, m, d] = text.split('-').map(Number);
    const date = new Date(Date.UTC(y, m - 1, d));
    if (date.getUTCFullYear() !== y || date.getUTCMonth() !== m - 1 || date.getUTCDate() !== d) throw invalidQuery();
    return { value: text, dateOnly: true };
  }
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(text) || Number.isNaN(Date.parse(text))) throw invalidQuery();
  return { value: new Date(text).toISOString(), dateOnly: false };
}

/** Yönetim listesi sorgusu: kind, status (tek durum | open | closed), apartment_id, q, from, to, limit (50, en çok 200), offset. */
export function parseListQuery(query = {}) {
  let statuses = null;
  const rawStatus = query.status;
  if (rawStatus !== undefined && rawStatus !== null && String(rawStatus).trim() !== '') {
    if (rawStatus === 'open') statuses = [...OPEN_STATUSES];
    else if (rawStatus === 'closed') statuses = [...TERMINAL_STATUSES];
    else if (typeof rawStatus === 'string' && STATUSES.includes(rawStatus)) statuses = [rawStatus];
    else throw invalidQuery();
  }
  return {
    kind: parseEnum(query.kind, KINDS),
    statuses,
    apartmentId: optionalQueryId(query.apartment_id),
    q: parseSearchTerm(typeof query.q === 'string' ? query.q : null),
    from: parseDateBound(query.from),
    to: parseDateBound(query.to),
    limit: parseLimit(query.limit),
    offset: parseOffset(query.offset),
  };
}

/** Sakin listesi sorgusu: site_code (isteğe bağlı), before_id imleci, limit. */
export function parseResidentListQuery(query = {}) {
  return { siteCode: optionalQueryId(query.site_code), beforeId: optionalQueryId(query.before_id), limit: parseLimit(query.limit) };
}

// --- Yanıt eşleyicileri -----------------------------------------------------------------------------------------

const num = (value) => (value === null || value === undefined ? null : Number(value));

/**
 * Entry. Yönetim görünümü: recorded_by_name / completed_by_name (silinmiş ya da FK ile NULL'lanmış kullanıcı "Silinmiş Kullanıcı").
 * Sakin görünümü (resident: true): kaydeden / sonlandıran adı YOK; site_code, site_name ve unread eklenir; next_statuses boş (sakin geçiş yapamaz).
 */
export function mapEntry(row, { resident = false } = {}) {
  const terminal = TERMINAL_STATUSES.includes(row.status);
  const hasApartment = row.apartment_id !== null && row.apartment_id !== undefined;
  const entry = {
    id: num(row.id),
    kind: row.kind,
    apartment_id: hasApartment ? num(row.apartment_id) : null,
    apartment_label: hasApartment ? apartmentLabel(row.block_name, row.unit_label) : null,
    block_name: hasApartment ? row.block_name ?? null : null,
    visitor_name: row.visitor_name,
    company: row.company ?? null,
    note: row.note ?? null,
    status: row.status,
    next_statuses: resident ? [] : nextStatuses(row.status),
    arrived_at: toIso(row.arrived_at),
    completed_at: toIso(row.completed_at),
    resident_seen_at: toIso(row.resident_seen_at),
  };
  if (resident) {
    entry.site_code = num(row.site_code);
    entry.site_name = row.site_name ?? null;
    entry.unread = row.resident_seen_at === null || row.resident_seen_at === undefined;
  } else {
    entry.recorded_by_name = row.recorded_by_name ?? DELETED_USER_NAME;
    entry.completed_by_name = terminal ? row.completed_by_name ?? DELETED_USER_NAME : null;
  }
  return entry;
}

/**
 * Hesap silme önizlemesi: kapıcı / görevli / yönetici olarak girdiğiniz ya da sonlandırdığınız kayıtlar SİLİNMEZ (siteye aittir); recorded_by / completed_by
 * FK ile NULL olur ya da tombstone kalır; ad "Silinmiş Kullanıcı" görünür. Sakin bu modülde kayıt üretmez; dışa aktarmaya eklenecek bir şey yoktur.
 */
export function visitorEntriesKeepNote(count) {
  const n = Number(count);
  return `Görevli ya da yönetici olarak girdiğiniz veya sonlandırdığınız ziyaretçi ve kargo kayıtları (${n}) site yönetiminde kalır (kayıtlar siteye aittir); kaydeden ve sonlandıran kişi adı "Silinmiş Kullanıcı" olarak görünür.`;
}
