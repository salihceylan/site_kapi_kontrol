// Kişi ve Daire Kayıtları (CRM) ortak sabitleri ve doğrulayıcıları. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_KISILER.md.

import { PlatformError } from './errors.js';
import { normalizeRequestNote } from './module_request_service.js';

export const RELATIONS = Object.freeze(['owner', 'tenant', 'family_member', 'resident']);
export const RELATION_ORDER = Object.freeze({ owner: 0, tenant: 1, family_member: 2, resident: 3 });
export const RESPONSIBLE_PARTIES = Object.freeze(['owner', 'tenant', 'both']);
export const PERSON_STATUSES = Object.freeze(['active', 'inactive', 'all']);

export const PERSON_NAME_MIN = 2;
export const PERSON_NAME_MAX = 100;
export const PERSON_NOTE_MAX = 500;
export const CATEGORY_MAX = 40;
export const DEFAULT_PAGE_LIMIT = 50;
export const MAX_PAGE_LIMIT = 200;

const TURKISH_FROM = 'ÇĞİÖŞÜçğıöşü';
const TURKISH_TO = 'CGIOSUcgiosu';

const FOLD_MAP = new Map([...TURKISH_FROM].map((ch, index) => [ch, TURKISH_TO[index]]));

/** Türkçe karakter ve büyük/küçük harf duyarsız karşılaştırma metni (SQL tarafı foldSql ile aynı kuralı uygular). */
export function foldText(value) {
  let out = '';
  for (const ch of String(value ?? '')) {
    out += FOLD_MAP.get(ch) ?? ch;
  }
  return out.toLowerCase();
}

/** SQL ifadesi: sütunu foldText ile aynı kurala göre katlar (translate önce, ASCII lower sonra: yerel ayardan bağımsız). */
export function foldSql(expression) {
  return `lower(translate(COALESCE(${expression}, ''), '${TURKISH_FROM}', '${TURKISH_TO}'))`;
}

/** LIKE joker karakterlerini kaçırır (kaçış karakteri ters bölü). */
export function escapeLike(value) {
  return String(value).replace(/[\\%_]/g, (ch) => `\\${ch}`);
}

export function invalidBody(field, message) {
  return new PlatformError(400, 'INVALID_BODY', message ?? `${field} alanı geçersiz.`);
}

function invalidQuery() {
  return new PlatformError(400, 'INVALID_QUERY', 'Geçersiz sorgu parametresi.');
}

/** Pozitif tamsayı kimlik (varsayılan üst sınır: JS güvenli tamsayı); aksi null. */
export function parsePositiveId(value, max = Number.MAX_SAFE_INTEGER) {
  if (typeof value === 'number') {
    return Number.isSafeInteger(value) && value > 0 && value <= max ? value : null;
  }
  if (typeof value === 'string' && /^\d{1,16}$/.test(value.trim())) {
    const parsed = Number(value.trim());
    return Number.isSafeInteger(parsed) && parsed > 0 && parsed <= max ? parsed : null;
  }
  return null;
}

/** İsteğe bağlı sorgu kimliği: yok/boş -> null; geçersizse 400 INVALID_QUERY. */
export function optionalQueryId(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return null;
  }
  const parsed = parsePositiveId(typeof value === 'string' ? value : String(value));
  if (parsed === null) {
    throw invalidQuery();
  }
  return parsed;
}

/** limit (1-200, varsayılan 50) ve offset (>=0) sorgu değerleri. */
export function parsePage(query = {}) {
  let limit = DEFAULT_PAGE_LIMIT;
  const rawLimit = query.limit;
  if (rawLimit !== undefined && rawLimit !== null && String(rawLimit).trim() !== '') {
    const parsed = Number(rawLimit);
    if (Number.isFinite(parsed)) {
      limit = Math.min(MAX_PAGE_LIMIT, Math.max(1, Math.floor(parsed)));
    }
  }
  let offset = 0;
  const rawOffset = query.offset;
  if (rawOffset !== undefined && rawOffset !== null && String(rawOffset).trim() !== '') {
    const parsed = Number(rawOffset);
    if (!Number.isFinite(parsed) || parsed < 0) {
      throw invalidQuery();
    }
    offset = Math.min(1_000_000, Math.floor(parsed));
  }
  return { limit, offset };
}

/** Arama metni: kırpılır, 100 karaktere indirilir; boşsa null. */
export function parseSearchTerm(value) {
  if (value === undefined || value === null) {
    return null;
  }
  const text = typeof value === 'string' ? value.trim() : '';
  if (text === '') {
    return null;
  }
  return Array.from(text).slice(0, 100).join('');
}

export function parseRelationFilter(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return null;
  }
  if (typeof value !== 'string' || !RELATIONS.includes(value.trim())) {
    throw invalidQuery();
  }
  return value.trim();
}

export function parseStatusFilter(value, fallback = 'active') {
  if (value === undefined || value === null || String(value).trim() === '') {
    return fallback;
  }
  if (typeof value !== 'string' || !PERSON_STATUSES.includes(value.trim())) {
    throw invalidQuery();
  }
  return value.trim();
}

/** İlişki türü (gövde): geçerli değer döner; yoksa fallback; geçersizse 400 INVALID_BODY. */
export function parseRelationInput(value, fallback = 'resident') {
  if (value === undefined || value === null || value === '') {
    return fallback;
  }
  if (typeof value !== 'string' || !RELATIONS.includes(value.trim())) {
    throw invalidBody('relation', 'relation alanı geçersiz (owner, tenant, family_member, resident).');
  }
  return value.trim();
}

/** Ad Soyad: 2-100 karakter, kontrol karakterleri temizlenir, boşluklar tekleştirilir. */
export function normalizePersonName(value, field = 'full_name') {
  if (typeof value !== 'string') {
    throw invalidBody(field, `${field} zorunludur (${PERSON_NAME_MIN}-${PERSON_NAME_MAX} karakter).`);
  }
  // eslint-disable-next-line no-control-regex
  const text = value.replace(/[\x00-\x1f\x7f]/g, ' ').replace(/\s+/g, ' ').trim();
  const length = Array.from(text).length;
  if (length < PERSON_NAME_MIN || length > PERSON_NAME_MAX) {
    throw invalidBody(field, `${field} ${PERSON_NAME_MIN}-${PERSON_NAME_MAX} karakter olmalıdır.`);
  }
  return text;
}

/**
 * Telefon: +90 ve 10 hane (+905551234567). 0555..., 90555..., +90 555 123 45 67, (0555) 123-45-67 biçimleri kabul edilir.
 * Boş/yok -> null. Geçersiz -> 400 INVALID_BODY.
 */
export function normalizePersonPhone(value, field = 'phone') {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw invalidBody(field, `${field} alanı geçersiz.`);
  }
  const text = value.trim();
  if (text === '') {
    return null;
  }
  if (!/^[+\d\s()\-.]+$/.test(text)) {
    throw invalidBody(field, `${field} alanı geçersiz (yalnız rakam, boşluk ve + ( ) - kullanılabilir).`);
  }
  let digits = text.replace(/\D/g, '');
  if (digits.startsWith('90') && digits.length === 12) {
    digits = digits.slice(2);
  } else if (digits.startsWith('0') && digits.length === 11) {
    digits = digits.slice(1);
  }
  if (!/^[1-9]\d{9}$/.test(digits)) {
    throw invalidBody(field, `${field} alanı geçersiz (+90 ve 10 hane).`);
  }
  return `+90${digits}`;
}

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** E-posta: küçük harfe çevrilir; boş/yok -> null; geçersiz -> 400 INVALID_BODY. */
export function normalizePersonEmail(value, field = 'email') {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw invalidBody(field, `${field} alanı geçersiz.`);
  }
  const text = value.trim().toLowerCase();
  if (text === '') {
    return null;
  }
  if (text.length > 254 || !EMAIL_PATTERN.test(text) || text.includes('..')) {
    throw invalidBody(field, `${field} alanı geçersiz.`);
  }
  return text;
}

/** İsteğe bağlı not (<=500 karakter); ortak not normalleştirici. */
export function normalizePersonNote(value, field = 'note') {
  const note = normalizeRequestNote(value, field);
  return note;
}

/** Istanbul'a göre bugünün tarihi (YYYY-MM-DD). */
export function todayIso(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Istanbul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const get = (type) => parts.find((part) => part.type === type)?.value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}

/**
 * Tarih: YYYY-MM-DD veya GG.AA.YYYY -> 'YYYY-MM-DD'. Yok/boş -> null. Geçersiz/gerçek olmayan tarih (1900-2100 dışı dahil)
 * -> 400 INVALID_BODY.
 */
export function normalizeDateInput(value, field) {
  if (value === undefined || value === null || value === '') {
    return null;
  }
  if (typeof value !== 'string') {
    throw invalidBody(field, `${field} alanı geçersiz tarih (YYYY-AA-GG).`);
  }
  const text = value.trim();
  let year;
  let month;
  let day;
  let match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (match) {
    [, year, month, day] = match;
  } else {
    match = /^(\d{2})\.(\d{2})\.(\d{4})$/.exec(text);
    if (!match) {
      throw invalidBody(field, `${field} alanı geçersiz tarih (YYYY-AA-GG).`);
    }
    [, day, month, year] = match;
  }
  const y = Number(year);
  const m = Number(month);
  const d = Number(day);
  const probe = new Date(Date.UTC(y, m - 1, d));
  const real = probe.getUTCFullYear() === y && probe.getUTCMonth() === m - 1 && probe.getUTCDate() === d;
  if (!real || y < 1900 || y > 2100) {
    throw invalidBody(field, `${field} alanı geçersiz tarih (YYYY-AA-GG).`);
  }
  return `${year}-${month}-${day}`;
}

/** DATE değeri (Date veya metin) -> 'YYYY-MM-DD' | null. */
export function dateToIso(value) {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value === 'string') {
    return value.slice(0, 10);
  }
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    return null;
  }
  // pg DATE -> yerel gece yarısı Date; yerel (Europe/Istanbul) takvim günü alınır
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/** Plaka: büyük harf, boşluk/tire/nokta atılır; yalnız A-Z0-9, 5-10 karakter. Aksi 400 PLATE_INVALID. */
export function normalizePlate(value) {
  if (typeof value !== 'string') {
    throw new PlatformError(400, 'PLATE_INVALID', 'Plaka biçimi geçersiz.');
  }
  const display = value.replace(/\s+/g, ' ').trim().toUpperCase();
  const plate = display.replace(/[\s\-.]/g, '');
  if (!/^[A-Z0-9]{5,10}$/.test(plate) || display.length > 20) {
    throw new PlatformError(400, 'PLATE_INVALID', 'Plaka biçimi geçersiz.');
  }
  return { plate, display };
}

/** Daire etiketi: "<blok adı> - <daire>" (kapı günlüğündeki apartment_label ile aynı biçim). */
export function apartmentLabel(blockName, unitLabel) {
  const block = String(blockName ?? '').trim();
  const unit = String(unitLabel ?? '').trim();
  return block && unit ? `${block} - ${unit}` : block || unit;
}

export function toIso(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

export function asNumberOrNull(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

/**
 * Salt okuma rolü (BOARD_MEMBER) için yönetici iç notları: kişi `note` ve araç `note` alanları yanıtta NULL olur (anahtar kalır;
 * istemci modelleri bozulmaz). Yönetici/süper yanıtı aynen kalır. Girdi değişmez; yeni nesne döner.
 */
export function redactManagerNotes(value) {
  if (Array.isArray(value)) {
    return value.map((entry) => redactManagerNotes(entry));
  }
  if (value && typeof value === 'object' && !(value instanceof Date)) {
    const out = {};
    for (const [key, entry] of Object.entries(value)) {
      out[key] = key === 'note' ? null : redactManagerNotes(entry);
    }
    return out;
  }
  return value;
}

/** Kurul üyesine (salt okuma) hiç verilmeyen kullanıcı kodu alanları: yönetici/hesap kimlikleri (history actor_user_code vb.). */
const USER_CODE_KEYS = new Set(['actor_user_code', 'user_code', 'created_by']);

/**
 * Salt okuma rolü (BOARD_MEMBER) yanıt temizliği: yönetici iç notları NULL (redactManagerNotes) + kullanıcı kodu alanları
 * (actor_user_code, user_code, created_by) yanıttan ÇIKARILIR (history'de yöneticilerin user_code'ları sızmasın). Girdi değişmez.
 */
export function redactForReadOnlyRole(value) {
  if (Array.isArray(value)) {
    return value.map((entry) => redactForReadOnlyRole(entry));
  }
  if (value && typeof value === 'object' && !(value instanceof Date)) {
    const out = {};
    for (const [key, entry] of Object.entries(value)) {
      if (USER_CODE_KEYS.has(key)) {
        continue;
      }
      out[key] = key === 'note' ? null : redactForReadOnlyRole(entry);
    }
    return out;
  }
  return value;
}
