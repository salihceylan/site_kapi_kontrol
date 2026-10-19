// Firma ve Sözleşme Takibi ortak sabitleri, hata üreticileri, girdi doğrulayıcıları, durum (state) hesabı ve yanıt eşleyicileri. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_SOZLESMELER.md. Hata gövdesi { error, code, ...ek } (PlatformError). Alan hatası 400 INVALID_FIELD { field }.
// Takvim hesabı (days_left, state, notice_deadline) Europe/Istanbul takvim gününe göredir ("bugün" tek yerde: istanbulToday). Günlüğe ve audit `details`
// alanına firma adı / telefon / e-posta / vergi no / tutar / not YAZILMAZ (yalnız kimlik ve alan adları).

import { PlatformError } from './errors.js';
import { INVISIBLE_RE } from './document_common.js';
import { DELETED_USER_NAME } from './account_common.js';
import { parsePositiveId, parseSearchTerm, toIso } from './people_common.js';
import { addDays, diffDays, todayIstanbul } from './reservation_time.js';

export const CONTRACTS_MODULE = 'contracts';

export const CATEGORIES = Object.freeze(['asansor', 'guvenlik', 'temizlik', 'bahce', 'havuz', 'teknik_bakim', 'yazilim', 'sigorta', 'diger']);
export const PERIODS = Object.freeze(['aylik', 'yillik', 'tek_sefer', 'diger']);
export const STATUSES = Object.freeze(['aktif', 'feshedildi']);
/** Hesaplanan durum (state): feshedildi > sona_erdi > yaklasiyor > aktif. */
export const STATES = Object.freeze(['aktif', 'yaklasiyor', 'sona_erdi', 'feshedildi']);
export const CURRENCY = 'TRY';

export const VENDOR_LIMIT_PER_SITE = 500;
export const CONTRACT_LIMIT_PER_SITE = 2000;

export const VENDOR_NAME_MAX = 120;
export const CONTACT_NAME_MAX = 120;
export const PHONE_MAX = 32;
export const EMAIL_MAX = 254;
export const TAX_NO_MAX = 20;
export const VENDOR_NOTE_MAX = 1000;
export const TITLE_MAX = 160;
export const CONTRACT_NOTE_MAX = 2000;
export const NOTICE_DAYS_MAX = 365;
export const REMIND_BEFORE_DAYS_MAX = 180;
export const DEFAULT_NOTICE_DAYS = 30;
export const DEFAULT_REMIND_BEFORE_DAYS = 30;
/** NUMERIC(14,2): en çok 12 tam basamak. */
export const AMOUNT_MAX = '999999999999.99';
/** Fesih bildirimi hatırlatması son tarihten kaç gün önce başlar. */
export const NOTICE_REMINDER_LEAD_DAYS = 7;

export const LIST_DEFAULT_LIMIT = 50;
export const LIST_MAX_LIMIT = 200;
/** İstek gövdesi için kaba üst sınır (bayt; Content-Length). Not alanları 2000 karaktere kadar (Türkçe karakter 2 bayt). */
export const MAX_BODY_BYTES = 16384;

/** Tarih aralığı (takvim günü): sözleşme başlangıcı eski olabilir. */
const MIN_YEAR = 1990;
const MAX_YEAR = 2100;

// --- Hatalar -----------------------------------------------------------------------------------------------------

export const invalidField = (field, message) => new PlatformError(400, 'INVALID_FIELD', message, { field });
export const contractNotFound = () => new PlatformError(404, 'CONTRACT_NOT_FOUND', 'Sözleşme bulunamadı ya da erişiminiz yok.');
export const vendorNotFound = () => new PlatformError(404, 'VENDOR_NOT_FOUND', 'Firma bulunamadı ya da erişiminiz yok.');
export const siteNotFound = () => new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
export const vendorNameTaken = () => new PlatformError(409, 'VENDOR_NAME_TAKEN', 'Bu sitede aynı adla kayıtlı bir firma zaten var.');
export const vendorInactive = () => new PlatformError(409, 'VENDOR_INACTIVE', 'Firma pasif; pasif firmaya yeni sözleşme eklenemez.');
export const limitReached = (limit, message) => new PlatformError(409, 'LIMIT_REACHED', message, { limit });
export const vendorLimitReached = () => limitReached(VENDOR_LIMIT_PER_SITE, `Bir sitede en fazla ${VENDOR_LIMIT_PER_SITE} firma kaydedilebilir.`);
export const contractLimitReached = () => limitReached(CONTRACT_LIMIT_PER_SITE, `Bir sitede en fazla ${CONTRACT_LIMIT_PER_SITE} sözleşme kaydedilebilir.`);
export const moduleDisabled = () =>
  new PlatformError(403, 'MODULE_DISABLED', 'Firma ve Sözleşme Takibi modülü kapalı.', { module: CONTRACTS_MODULE });
export const forbiddenRole = () => new PlatformError(403, 'FORBIDDEN_ROLE', 'Bu işlem için yetkiniz yok.');
export const accountDeleted = () => new PlatformError(401, 'ACCOUNT_DELETED', 'Bu hesap silinmiş.');
export const bodyTooLarge = () => new PlatformError(413, 'BODY_TOO_LARGE', 'İstek gövdesi çok büyük.');

// --- Takvim (Europe/Istanbul) ------------------------------------------------------------------------------------

/** İstanbul takvimine göre bugün ("YYYY-MM-DD"). Tüm state / days_left hesabı bu günü kullanır; SQL'e de parametre olarak gider. */
export const istanbulToday = (now = new Date()) => todayIstanbul(now);

/** "YYYY-MM-DD" gerçek bir takvim günü mü (1990-2100)? */
export function isValidDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const [y, m, d] = value.split('-').map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  return date.getUTCFullYear() === y && date.getUTCMonth() === m - 1 && date.getUTCDate() === d && y >= MIN_YEAR && y <= MAX_YEAR;
}

/** 'YYYY-MM-DD' -> 'GG.AA.YYYY' (e-posta metni). */
export const trDate = (iso) => `${iso.slice(8, 10)}.${iso.slice(5, 7)}.${iso.slice(0, 4)}`;

/** Bitiş tarihine kalan gün (end_date − bugün); bitişsiz sözleşmede null. */
export function daysLeft(endDate, today) {
  return endDate ? diffDays(today, endDate) : null;
}

/**
 * Hesaplanan durum: feshedildi (status) > sona_erdi (end_date < bugün) > yaklasiyor (end_date − bugün <= remind_before_days) > aktif.
 * Bitişsiz (end_date null) aktif sözleşme her zaman `aktif`.
 */
export function contractState({ status, endDate, remindBeforeDays }, today) {
  if (status === 'feshedildi') return 'feshedildi';
  if (!endDate) return 'aktif';
  const left = diffDays(today, endDate);
  if (left < 0) return 'sona_erdi';
  if (left <= Number(remindBeforeDays)) return 'yaklasiyor';
  return 'aktif';
}

/** Fesih bildirimi son günü: yalnız otomatik yenilenen ve bitişi olan sözleşmede (end_date − notice_days); aksi null. */
export function noticeDeadline({ autoRenew, endDate, noticeDays }) {
  return autoRenew === true && endDate ? addDays(endDate, -Number(noticeDays)) : null;
}

/**
 * state süzgecinin SQL karşılığı (contractState ile AYNI kural). `today` = "$n::DATE" parametresi ya da onu üreten işlev (yalnız gereken dalda çağrılır:
 * `feshedildi` bugünü kullanmaz, kullanılmayan parametre PG'de tür hatası verir). 'all' / null -> null (süzgeç yok). Sütun öneki `c.` (site_contracts).
 */
export function stateSql(state, today) {
  const day = () => (typeof today === 'function' ? today() : today);
  switch (state) {
    case 'feshedildi':
      return `c.status = 'feshedildi'`;
    case 'sona_erdi': {
      const t = day();
      return `(c.status = 'aktif' AND c.end_date IS NOT NULL AND c.end_date < ${t})`;
    }
    case 'yaklasiyor': {
      const t = day();
      return `(c.status = 'aktif' AND c.end_date IS NOT NULL AND c.end_date >= ${t} AND c.end_date - ${t} <= c.remind_before_days)`;
    }
    case 'aktif': {
      const t = day();
      return `(c.status = 'aktif' AND (c.end_date IS NULL OR c.end_date - ${t} > c.remind_before_days))`;
    }
    default:
      return null;
  }
}

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

/** Zorunlu tek satır metin (1..max). */
function requiredText(value, field, label, max) {
  if (typeof value !== 'string') throw invalidField(field, `${label} zorunludur.`);
  const text = singleLine(value);
  const length = codePointLength(text);
  if (length < 1) throw invalidField(field, `${label} boş olamaz.`);
  if (length > max) throw invalidField(field, `${label} en fazla ${max} karakter olabilir.`);
  return text;
}

/** İsteğe bağlı tek satır metin: yok / null / boş -> null. */
function optionalText(value, field, label, max) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw invalidField(field, `${label} geçersiz.`);
  const text = singleLine(value);
  if (text === '') return null;
  if (codePointLength(text) > max) throw invalidField(field, `${label} en fazla ${max} karakter olabilir.`);
  return text;
}

/** İsteğe bağlı çok satırlı not: yok / null / boş -> null (PATCH'te notu siler). */
function optionalNote(value, field, max) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw invalidField(field, 'Not geçersiz.');
  const text = multiLine(value);
  if (text === '') return null;
  if (codePointLength(text) > max) throw invalidField(field, `Not en fazla ${max} karakter olabilir.`);
  return text;
}

// --- Alan doğrulayıcıları ----------------------------------------------------------------------------------------

export const normalizeVendorName = (value) => requiredText(value, 'name', 'Firma adı', VENDOR_NAME_MAX);
export const normalizeTitle = (value) => requiredText(value, 'title', 'Sözleşme başlığı', TITLE_MAX);
export const normalizeContactName = (value) => optionalText(value, 'contact_name', 'Yetkili kişi', CONTACT_NAME_MAX);
export const normalizeVendorNote = (value) => optionalNote(value, 'note', VENDOR_NOTE_MAX);
export const normalizeContractNote = (value) => optionalNote(value, 'note', CONTRACT_NOTE_MAX);

export function normalizeCategory(value, field = 'category') {
  if (typeof value !== 'string' || !CATEGORIES.includes(value)) throw invalidField(field, 'Kategori geçersiz.');
  return value;
}

/** Telefon (isteğe bağlı): firma / santral / 444 numarası olabilir; yalnız rakam, boşluk ve + ( ) - . / ; 3-20 rakam, en çok 32 karakter. */
export function normalizeVendorPhone(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw invalidField('phone', 'Telefon geçersiz.');
  const text = value.normalize('NFC').replace(INVISIBLE_RE, '').replace(/\s+/gu, ' ').trim();
  if (text === '') return null;
  const digits = text.replace(/\D/g, '').length;
  if (!/^[+\d\s()\-./]+$/.test(text) || digits < 3 || digits > 20 || text.length > PHONE_MAX) {
    throw invalidField('phone', 'Telefon geçersiz (yalnız rakam, boşluk ve + ( ) - . / kullanılabilir).');
  }
  return text;
}

const EMAIL_PATTERN = /^[^\s@,;<>"()]+@[^\s@,;<>"()]+\.[^\s@,;<>"()]+$/;

/** E-posta (isteğe bağlı): küçük harfe çevrilir. */
export function normalizeVendorEmail(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw invalidField('email', 'E-posta geçersiz.');
  const text = value.trim().toLowerCase();
  if (text === '') return null;
  if (text.length > EMAIL_MAX || !EMAIL_PATTERN.test(text) || text.includes('..')) throw invalidField('email', 'E-posta geçersiz.');
  return text;
}

/** Vergi / kimlik no (isteğe bağlı): harf, rakam, boşluk ve tire; en çok 20 karakter. */
export function normalizeTaxNo(value) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw invalidField('tax_no', 'Vergi numarası geçersiz.');
  const text = value.trim().replace(/\s+/g, ' ');
  if (text === '') return null;
  if (text.length > TAX_NO_MAX || !/^[0-9A-Za-z -]+$/.test(text)) throw invalidField('tax_no', 'Vergi numarası geçersiz (harf, rakam, boşluk ve tire; en çok 20 karakter).');
  return text;
}

function requiredBoolean(value, field, label) {
  if (typeof value !== 'boolean') throw invalidField(field, `${label} geçersiz (true / false).`);
  return value;
}

function boundedInt(value, field, label, max) {
  const parsed = typeof value === 'string' && /^\d{1,4}$/.test(value.trim()) ? Number(value.trim()) : value;
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > max) throw invalidField(field, `${label} 0 ile ${max} arasında bir tam sayı olmalıdır.`);
  return parsed;
}

function requiredDate(value, field, label) {
  if (typeof value !== 'string' || !isValidDate(value.trim())) throw invalidField(field, `${label} geçersiz (YYYY-AA-GG).`);
  return value.trim();
}

function optionalDate(value, field, label) {
  if (value === undefined || value === null || value === '') return null;
  return requiredDate(value, field, label);
}

/** Tutar (isteğe bağlı): sayı ya da "1250.50" / "1250,50"; >= 0, en çok 2 ondalık, NUMERIC(14,2) sınırı. -> "1250.50" | null. */
export function normalizeAmount(value) {
  if (value === undefined || value === null || value === '') return null;
  let text;
  if (typeof value === 'number') {
    if (!Number.isFinite(value) || value < 0) throw invalidField('amount', 'Tutar geçersiz.');
    // String(1250.5) = "1250.5"; üç ondalık ya da üstel gösterim ("1e+21") aşağıdaki biçim denetiminde reddedilir.
    text = String(value);
  } else if (typeof value === 'string') {
    text = value.trim().replace(',', '.');
  } else {
    throw invalidField('amount', 'Tutar geçersiz.');
  }
  const match = /^(\d{1,12})(?:\.(\d{1,2}))?$/.exec(text);
  if (!match) throw invalidField('amount', 'Tutar geçersiz (0 ya da pozitif, en çok 12 tam ve 2 ondalık basamak).');
  const whole = match[1].replace(/^0+(?=\d)/, '');
  const fraction = (match[2] ?? '').padEnd(2, '0');
  return `${whole}.${fraction}`;
}

function optionalEnum(value, field, label, allowed) {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string' || !allowed.includes(value)) throw invalidField(field, `${label} geçersiz.`);
  return value;
}

const isPlainObject = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);

function requireBody(body) {
  if (!isPlainObject(body)) throw invalidField('body', 'İstek gövdesi geçersiz.');
}

function requireId(value, field, label) {
  const id = parsePositiveId(value);
  if (id === null) throw invalidField(field, `${label} geçersiz.`);
  return id;
}

// --- Gövde ayrıştırıcıları ----------------------------------------------------------------------------------------

/** POST .../contract-vendors: { name, category, contact_name?, phone?, email?, tax_no?, note? }. */
export function parseVendorCreate(body) {
  requireBody(body);
  return {
    name: normalizeVendorName(body.name),
    category: normalizeCategory(body.category),
    contactName: normalizeContactName(body.contact_name),
    phone: normalizeVendorPhone(body.phone),
    email: normalizeVendorEmail(body.email),
    taxNo: normalizeTaxNo(body.tax_no),
    note: normalizeVendorNote(body.note),
  };
}

const VENDOR_PATCH_FIELDS = Object.freeze({
  name: ['name', normalizeVendorName],
  category: ['category', (value) => normalizeCategory(value)],
  contact_name: ['contact_name', normalizeContactName],
  phone: ['phone', normalizeVendorPhone],
  email: ['email', normalizeVendorEmail],
  tax_no: ['tax_no', normalizeTaxNo],
  note: ['note', normalizeVendorNote],
  is_active: ['is_active', (value) => requiredBoolean(value, 'is_active', 'Etkinlik')],
});

/** PATCH .../contract-vendors/:id: en az bir alan. Boş / null isteğe bağlı alan o alanı siler. -> { <sütun>: değer } */
export function parseVendorPatch(body) {
  requireBody(body);
  const out = {};
  for (const [key, [column, normalize]] of Object.entries(VENDOR_PATCH_FIELDS)) {
    if (key in body) out[column] = normalize(body[key]);
  }
  if (Object.keys(out).length === 0) throw invalidField('body', 'Değiştirilecek bir alan gönderilmedi.');
  return out;
}

/**
 * POST .../contracts: { vendor_id, title, category?, start_date, end_date?, notice_days?, remind_before_days?, amount?, period?, auto_renew?, note? }.
 * category verilmezse firmanın kategorisi kullanılır (serviste). end_date >= start_date.
 */
export function parseContractCreate(body) {
  requireBody(body);
  const input = {
    vendorId: requireId(body.vendor_id, 'vendor_id', 'Firma'),
    title: normalizeTitle(body.title),
    category: body.category === undefined || body.category === null ? null : normalizeCategory(body.category),
    startDate: requiredDate(body.start_date, 'start_date', 'Başlangıç tarihi'),
    endDate: optionalDate(body.end_date, 'end_date', 'Bitiş tarihi'),
    noticeDays: body.notice_days === undefined || body.notice_days === null ? DEFAULT_NOTICE_DAYS : boundedInt(body.notice_days, 'notice_days', 'Fesih bildirim süresi (gün)', NOTICE_DAYS_MAX),
    remindBeforeDays:
      body.remind_before_days === undefined || body.remind_before_days === null
        ? DEFAULT_REMIND_BEFORE_DAYS
        : boundedInt(body.remind_before_days, 'remind_before_days', 'Hatırlatma süresi (gün)', REMIND_BEFORE_DAYS_MAX),
    amount: normalizeAmount(body.amount),
    period: optionalEnum(body.period, 'period', 'Ödeme dönemi', PERIODS),
    autoRenew: body.auto_renew === undefined || body.auto_renew === null ? false : requiredBoolean(body.auto_renew, 'auto_renew', 'Otomatik yenileme'),
    note: normalizeContractNote(body.note),
  };
  assertDateOrder(input.startDate, input.endDate);
  return input;
}

/** end_date >= start_date (DB kısıtıyla aynı); aksi 400 INVALID_FIELD { field: 'end_date' }. */
export function assertDateOrder(startDate, endDate) {
  if (endDate && startDate && endDate < startDate) {
    throw invalidField('end_date', 'Bitiş tarihi başlangıç tarihinden önce olamaz.');
  }
}

const CONTRACT_PATCH_FIELDS = Object.freeze({
  vendor_id: ['vendor_id', (value) => requireId(value, 'vendor_id', 'Firma')],
  title: ['title', normalizeTitle],
  category: ['category', (value) => normalizeCategory(value)],
  start_date: ['start_date', (value) => requiredDate(value, 'start_date', 'Başlangıç tarihi')],
  end_date: ['end_date', (value) => optionalDate(value, 'end_date', 'Bitiş tarihi')],
  notice_days: ['notice_days', (value) => boundedInt(value, 'notice_days', 'Fesih bildirim süresi (gün)', NOTICE_DAYS_MAX)],
  remind_before_days: ['remind_before_days', (value) => boundedInt(value, 'remind_before_days', 'Hatırlatma süresi (gün)', REMIND_BEFORE_DAYS_MAX)],
  amount: ['amount', normalizeAmount],
  period: ['period', (value) => optionalEnum(value, 'period', 'Ödeme dönemi', PERIODS)],
  auto_renew: ['auto_renew', (value) => requiredBoolean(value, 'auto_renew', 'Otomatik yenileme')],
  note: ['note', normalizeContractNote],
  status: ['status', (value) => {
    if (typeof value !== 'string' || !STATUSES.includes(value)) throw invalidField('status', 'Durum geçersiz (aktif ya da feshedildi).');
    return value;
  }],
});

/**
 * PATCH .../contracts/:id: en az bir alan. end_date / amount / period / note null -> siler. status: "feshedildi" (terminated_at = NOW()) | "aktif"
 * (yeniden etkin, terminated_at temizlenir). Tarih sırası birleşik değerle serviste denetlenir. -> { <sütun>: değer }
 */
export function parseContractPatch(body) {
  requireBody(body);
  const out = {};
  for (const [key, [column, normalize]] of Object.entries(CONTRACT_PATCH_FIELDS)) {
    if (key in body) out[column] = normalize(body[key]);
  }
  if (Object.keys(out).length === 0) throw invalidField('body', 'Değiştirilecek bir alan gönderilmedi.');
  return out;
}

// --- Sorgu ayrıştırıcıları ----------------------------------------------------------------------------------------

function parseLimit(value) {
  if (value === undefined || value === null || String(value).trim() === '') return LIST_DEFAULT_LIMIT;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) throw invalidField('limit', 'Sayfa boyutu geçersiz.');
  return Math.min(LIST_MAX_LIMIT, parsed);
}

function queryEnum(value, field, allowed) {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  if (typeof value !== 'string' || !allowed.includes(value)) throw invalidField(field, 'Geçersiz sorgu parametresi.');
  return value;
}

function queryId(value, field) {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  const id = typeof value === 'string' ? parsePositiveId(value) : null;
  if (id === null) throw invalidField(field, 'Geçersiz sorgu parametresi.');
  return id;
}

/** GET .../contract-vendors: active (all | 1 | 0; varsayılan all), q (ad / yetkili kişi). */
export function parseVendorListQuery(query = {}) {
  const active = queryEnum(query.active, 'active', ['all', '1', '0']) ?? 'all';
  return { active: active === 'all' ? null : active === '1', q: parseSearchTerm(typeof query.q === 'string' ? query.q : null) };
}

/**
 * Sayfalama imleci: sıra `end_date ASC NULLS LAST, id ASC` olduğundan `before_id` yetmez; imleç son satırın [end_date | null, id] çiftidir
 * (base64url JSON). İstemci için OPAK metindir: yalnız `next_cursor` değeri geri gönderilir.
 */
export function encodeCursor(endDate, id) {
  return Buffer.from(JSON.stringify([endDate ?? null, Number(id)]), 'utf8').toString('base64url');
}

export function decodeCursor(value) {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  const bad = () => invalidField('cursor', 'Sayfa imleci geçersiz.');
  if (typeof value !== 'string' || value.length > 100 || !/^[A-Za-z0-9_-]+$/.test(value)) throw bad();
  let parsed;
  try {
    parsed = JSON.parse(Buffer.from(value, 'base64url').toString('utf8'));
  } catch (_error) {
    throw bad();
  }
  if (!Array.isArray(parsed) || parsed.length !== 2) throw bad();
  const [endDate, id] = parsed;
  if (!(endDate === null || isValidDate(endDate)) || !Number.isSafeInteger(id) || id < 1) throw bad();
  return { endDate, id };
}

/** GET .../contracts: state (all | aktif | yaklasiyor | sona_erdi | feshedildi), vendor_id, category, q (başlık / firma adı), cursor, limit (50, en çok 200). */
export function parseContractListQuery(query = {}) {
  // Sessizce yok sayılsaydı istemci hep ilk sayfayı alıp döngüye girebilirdi: before_id açıkça reddedilir (sayfalama yalnız `cursor`).
  if (query.before_id !== undefined && query.before_id !== null && String(query.before_id).trim() !== '') {
    throw invalidField('before_id', 'Bu liste before_id ile değil, yanıttaki next_cursor değeriyle (cursor) sayfalanır.');
  }
  const state = queryEnum(query.state, 'state', ['all', ...STATES]) ?? 'all';
  return {
    state: state === 'all' ? null : state,
    vendorId: queryId(query.vendor_id, 'vendor_id'),
    category: queryEnum(query.category, 'category', CATEGORIES),
    q: parseSearchTerm(typeof query.q === 'string' ? query.q : null),
    cursor: decodeCursor(query.cursor),
    limit: parseLimit(query.limit),
  };
}

// --- Yanıt eşleyicileri -----------------------------------------------------------------------------------------

const num = (value) => (value === null || value === undefined ? null : Number(value));

/** Vendor: { id, name, category, contact_name, phone, email, tax_no, note, is_active, contract_count, created_at, updated_at }. */
export function mapVendor(row) {
  return {
    id: num(row.id),
    name: row.name,
    category: row.category,
    contact_name: row.contact_name ?? null,
    phone: row.phone ?? null,
    email: row.email ?? null,
    tax_no: row.tax_no ?? null,
    note: row.note ?? null,
    is_active: row.is_active === true,
    contract_count: Number(row.contract_count ?? 0),
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
  };
}

/** DATE değeri ("YYYY-MM-DD" metni; SQL'de to_char ile gelir) | null. */
const dateText = (value) => (value === null || value === undefined ? null : String(value).slice(0, 10));

/**
 * Contract (yönetim görünümü). `today` (İstanbul takvim günü) state / days_left için. created_by_name: silinmiş ya da FK ile NULL'lanmış kullanıcı
 * "Silinmiş Kullanıcı".
 */
export function mapContract(row, today) {
  const endDate = dateText(row.end_date);
  const autoRenew = row.auto_renew === true;
  const noticeDays = Number(row.notice_days);
  const remindBeforeDays = Number(row.remind_before_days);
  return {
    id: num(row.id),
    vendor_id: num(row.vendor_id),
    vendor_name: row.vendor_name ?? null,
    title: row.title,
    category: row.category,
    start_date: dateText(row.start_date),
    end_date: endDate,
    notice_days: noticeDays,
    remind_before_days: remindBeforeDays,
    amount: row.amount === null || row.amount === undefined ? null : String(row.amount),
    currency: row.currency ?? CURRENCY,
    period: row.period ?? null,
    auto_renew: autoRenew,
    status: row.status,
    state: contractState({ status: row.status, endDate, remindBeforeDays }, today),
    days_left: daysLeft(endDate, today),
    notice_deadline: noticeDeadline({ autoRenew, endDate, noticeDays }),
    terminated_at: toIso(row.terminated_at),
    note: row.note ?? null,
    created_by_name: row.created_by_name ?? DELETED_USER_NAME,
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
  };
}
