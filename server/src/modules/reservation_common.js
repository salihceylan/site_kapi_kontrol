// Rezervasyon ve Konsiyerj ortak sabitleri, sınırları, hata üreticileri, girdi doğrulayıcıları ve yanıt eşleyicileri. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_REZERVASYON.md. Hata gövdesi { error, code } (PlatformError). Kullanıcı metni düz yazıdır. Günlüğe ve audit `details` alanına
// not / açıklama / gerekçe metni YAZILMAZ (yalnız kimlik, durum, sayı). Zaman hesabı reservation_time.js'te TEK yerdedir.

import { PlatformError } from './errors.js';
import { INVISIBLE_RE, IDEMPOTENCY_KEY_PATTERN } from './document_common.js';
import { DELETED_USER_NAME } from './account_common.js';
import { apartmentLabel, optionalQueryId, parsePositiveId, toIso } from './people_common.js';
import { normalizeHoursList } from './reservation_slots.js';
import { addDays, diffDays, formatHhmm, isValidDateStr, istanbulParts, parseHhmm, todayIstanbul } from './reservation_time.js';

export const RESERVATION_MODULE = 'reservation';

export const APPROVAL_MODES = Object.freeze(['otomatik', 'yonetici_onayli']);
export const DB_STATUSES = Object.freeze(['beklemede', 'onaylandi', 'reddedildi', 'iptal']);
export const ACTIVE_DB_STATUSES = Object.freeze(['beklemede', 'onaylandi']);
export const API_STATUSES = Object.freeze(['beklemede', 'onaylandi', 'reddedildi', 'iptal', 'tamamlandi']);
export const DECISION_ACTIONS = Object.freeze(['approve', 'reject', 'cancel']);
export const SCOPES = Object.freeze(['upcoming', 'past', 'all']);

export const CONCIERGE_CATEGORIES = Object.freeze(['paket_teslim', 'misafir_hazirlik', 'temizlik', 'tasima', 'diger']);
export const CONCIERGE_STATUSES = Object.freeze(['yeni', 'hazirlaniyor', 'tamamlandi', 'iptal']);
export const CONCIERGE_OPEN = Object.freeze(['yeni', 'hazirlaniyor']);
export const CONCIERGE_CLOSED_STATUSES = Object.freeze(['tamamlandi', 'iptal']);
/** Yönetici / görevli geçişleri. tamamlandi ve iptal SONDUR. */
export const CONCIERGE_TRANSITIONS = Object.freeze({
  yeni: Object.freeze(['hazirlaniyor', 'tamamlandi', 'iptal']),
  hazirlaniyor: Object.freeze(['tamamlandi', 'iptal']),
  tamamlandi: Object.freeze([]),
  iptal: Object.freeze([]),
});

export const NAME_MAX = 80;
export const AREA_DESCRIPTION_MAX = 500;
export const RESERVATION_NOTE_MAX = 200;
export const DECISION_NOTE_MAX = 300;
export const CONCIERGE_NOTE_MAX = 500;
export const STAFF_NOTE_MAX = 300;
export const LIST_DEFAULT_LIMIT = 30;
export const LIST_MAX_LIMIT = 100;
export const MAX_AREAS_PER_SITE = 50;
export const MAX_HOURS_ENTRIES = 21;
export const MAX_WINDOWS_PER_DAY = 3;
export const AVAILABILITY_MAX_DAYS = 14;
export const CALENDAR_MAX_DAYS = 366;
export const CONCIERGE_MAX_DAYS_AHEAD = 90;
export const MAX_BODY_BYTES = 16384;

const warnedEnv = new Set();

function intEnv(env, name, fallback, { min = 1, max = Number.MAX_SAFE_INTEGER } = {}) {
  const raw = env?.[name];
  if (raw === undefined || raw === null || String(raw).trim() === '') {
    return fallback;
  }
  const parsed = Number(String(raw).trim());
  if (Number.isSafeInteger(parsed) && parsed >= min && parsed <= max) {
    return parsed;
  }
  if (!warnedEnv.has(name)) {
    warnedEnv.add(name);
    // eslint-disable-next-line no-console
    console.warn(`[reservation] ${name} gecersiz ya da sinir disi; varsayilan (${fallback}) kullaniliyor.`);
  }
  return fallback;
}

/**
 * Ortam değişkenleriyle ayarlanabilir sınırlar (geçersiz değer varsayılana döner; uyarı yalnız ad ile; her çağrıda okunur).
 *  RESERVATIONS_MAX_PER_USER_PER_HOUR (20): kullanıcının saatte yapabileceği rezervasyon (siteler arası toplam).
 *  RESERVATIONS_MAX_ACTIVE_PER_USER (30): kişinin tek sitede gelecekteki beklemede/onaylandi rezervasyonu.
 *  RESERVATIONS_MAX_ACTIVE_PER_SITE (5000): sitedeki gelecekteki beklemede/onaylandi rezervasyon üst sınırı.
 *  CONCIERGE_MAX_PER_USER_PER_HOUR (10), CONCIERGE_MAX_OPEN_PER_USER (10), CONCIERGE_MAX_OPEN_PER_SITE (1000).
 */
export function reservationLimits(env = process.env) {
  return {
    maxPerUserPerHour: intEnv(env, 'RESERVATIONS_MAX_PER_USER_PER_HOUR', 20, { min: 1, max: 1000 }),
    maxActivePerUser: intEnv(env, 'RESERVATIONS_MAX_ACTIVE_PER_USER', 30, { min: 1 }),
    maxActivePerSite: intEnv(env, 'RESERVATIONS_MAX_ACTIVE_PER_SITE', 5000, { min: 1 }),
  };
}

export function conciergeLimits(env = process.env) {
  return {
    maxPerUserPerHour: intEnv(env, 'CONCIERGE_MAX_PER_USER_PER_HOUR', 10, { min: 1, max: 1000 }),
    maxOpenPerUser: intEnv(env, 'CONCIERGE_MAX_OPEN_PER_USER', 10, { min: 1 }),
    maxOpenPerSite: intEnv(env, 'CONCIERGE_MAX_OPEN_PER_SITE', 1000, { min: 1 }),
  };
}

// --- Hatalar -----------------------------------------------------------------------------------------------------

const e = (status, code, message, extra = null) => new PlatformError(status, code, message, extra);

export const siteNotFound = () => e(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
export const areaNotFound = () => e(404, 'AREA_NOT_FOUND', 'Alan bulunamadı ya da erişiminiz yok.');
export const reservationNotFound = () => e(404, 'RESERVATION_NOT_FOUND', 'Rezervasyon bulunamadı ya da erişiminiz yok.');
export const conciergeNotFound = () => e(404, 'CONCIERGE_NOT_FOUND', 'Talep bulunamadı ya da erişiminiz yok.');
export const moduleDisabled = () => e(403, 'MODULE_DISABLED', 'Rezervasyon ve Konsiyerj modülü kapalı.', { module: RESERVATION_MODULE });
export const forbiddenRole = () => e(403, 'FORBIDDEN_ROLE', 'Bu işlem için yetkiniz yok.');
export const notResident = () => e(403, 'NOT_A_RESIDENT', 'Bu işlem için sitede aktif daire sakini olmalısınız.');
export const accountDeleted = () => e(401, 'ACCOUNT_DELETED', 'Bu hesap silinmiş.');
export const invalidField = (message) => e(400, 'INVALID_BODY', message);
export const invalidQuery = () => e(400, 'INVALID_QUERY', 'Geçersiz sorgu parametresi.');
export const invalidLocation = (message) => e(400, 'INVALID_LOCATION', message ?? 'Daire bu kişiye ait değil.');
export const idempotencyConflict = () => e(409, 'IDEMPOTENCY_CONFLICT', 'Bu işlem anahtarı farklı bir içerik için daha önce kullanılmış.');
export const areaNameTaken = () => e(409, 'AREA_NAME_TAKEN', 'Bu sitede aynı adlı bir alan var.');
export const areaLimitReached = () => e(409, 'AREA_LIMIT', `Sitede en fazla ${MAX_AREAS_PER_SITE} alan tanımlanabilir.`, { area_limit: MAX_AREAS_PER_SITE });
export const areaInactive = () => e(409, 'AREA_INACTIVE', 'Bu alan şu anda rezervasyona kapalı.');
export const outsideBookingWindow = (maxDays) =>
  e(409, 'OUTSIDE_BOOKING_WINDOW', `Rezervasyon şimdiden sonra ve en fazla ${maxDays} gün sonrası için yapılabilir.`, { max_days_ahead: Number(maxDays) });
export const outsideOpenHours = () => e(409, 'OUTSIDE_OPEN_HOURS', 'Seçilen saat alanın açık saatlerine ya da dilim düzenine uymuyor.');
export const invalidSlotCount = (min, max) =>
  e(409, 'INVALID_SLOT_COUNT', `Rezervasyon en az ${min}, en çok ${max} dilim olabilir.`, { min_slots: Number(min), max_slots: Number(max) });
export const slotFull = () => e(409, 'SLOT_FULL', 'Seçilen saatte alan dolu.');
export const alreadyBooked = () => e(409, 'ALREADY_BOOKED', 'Bu alanda aynı saatlerde zaten rezervasyonunuz var.');
export const dailyLimitReached = (limit) =>
  e(409, 'RESERVATION_DAILY_LIMIT', `Bu alanda aynı gün için en fazla ${limit} rezervasyon yapabilirsiniz.`, { daily_limit: Number(limit) });
export const weeklyLimitReached = (limit) =>
  e(409, 'RESERVATION_WEEKLY_LIMIT', `Bu alanda aynı hafta için en fazla ${limit} rezervasyon yapabilirsiniz.`, { weekly_limit: Number(limit) });
export const userActiveLimitReached = (limit) =>
  e(409, 'RESERVATION_USER_LIMIT', `Bu sitede aynı anda en fazla ${limit} geçerli rezervasyonunuz olabilir.`, { active_limit: Number(limit) });
export const siteActiveLimitReached = (limit) =>
  e(409, 'RESERVATION_SITE_LIMIT', 'Sitede geçerli rezervasyon üst sınırına ulaşıldı. Yönetimle iletişime geçin.', { active_limit: Number(limit) });
export const cancelWindowClosed = (hours) =>
  e(409, 'CANCEL_WINDOW_CLOSED', `Rezervasyon başlangıcına ${hours} saatten az kaldığı için iptal edilemez. Yönetimle iletişime geçin.`, { cancel_cutoff_hours: Number(hours) });
export const reservationPast = () => e(409, 'RESERVATION_PAST', 'Başlangıç zamanı geçmiş rezervasyon onaylanamaz.');
export const invalidTransition = (from, to) => e(409, 'INVALID_TRANSITION', 'Kayıt bu durumdan istenen duruma geçirilemez.', { from, to });
export const conciergeClosed = () => e(409, 'CONCIERGE_CLOSED', 'Tamamlanmış ya da iptal edilmiş talepte değişiklik yapılamaz.');
export const conciergeUserLimit = (limit) =>
  e(409, 'CONCIERGE_USER_LIMIT', `Bu sitede aynı anda en fazla ${limit} açık talebiniz olabilir. Önce mevcut taleplerinizin sonuçlanmasını bekleyin.`, { user_open_limit: Number(limit) });
export const conciergeSiteLimit = (limit) =>
  e(409, 'CONCIERGE_SITE_LIMIT', 'Sitede açık talep üst sınırına ulaşıldı. Yönetimle iletişime geçin.', { open_limit: Number(limit) });
export const reservationRateLimited = (limit) =>
  e(429, 'RESERVATION_RATE_LIMITED', 'Bir saat içinde çok fazla rezervasyon yaptınız. Biraz sonra tekrar deneyin.', { hourly_limit: Number(limit), retry_after_seconds: 3600 });
export const conciergeRateLimited = (limit) =>
  e(429, 'CONCIERGE_RATE_LIMITED', 'Bir saat içinde çok fazla talep açtınız. Biraz sonra tekrar deneyin.', { hourly_limit: Number(limit), retry_after_seconds: 3600 });
export const bodyTooLarge = () => e(413, 'BODY_TOO_LARGE', 'İstek gövdesi çok büyük.');

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

function requiredText(value, label, max, { single = false } = {}) {
  if (typeof value !== 'string') throw invalidField(`${label} zorunludur.`);
  const text = single ? singleLine(value) : multiLine(value);
  const length = codePointLength(text);
  if (length < 1) throw invalidField(`${label} boş olamaz.`);
  if (length > max) throw invalidField(`${label} en fazla ${max} karakter olabilir.`);
  return text;
}

/** İsteğe bağlı metin: undefined / null / boş -> null; aksi halde doğrulanmış metin. */
function optionalText(value, label, max) {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') throw invalidField(`${label} metin olmalıdır.`);
  if (value.trim() === '') return null;
  return requiredText(value, label, max);
}

export function normalizeIdempotencyKey(value) {
  if (typeof value !== 'string' || !IDEMPOTENCY_KEY_PATTERN.test(value.trim())) {
    throw invalidField('İşlem anahtarı geçersiz.');
  }
  return value.trim();
}

const isPlainObject = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);

function optionalId(value, label) {
  if (value === undefined || value === null) return null;
  const id = parsePositiveId(value);
  if (id === null) throw invalidField(`${label} geçersiz.`);
  return id;
}

function intInRange(value, label, min, max) {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < min || value > max) {
    throw invalidField(`${label} ${min}-${max} arasında tam sayı olmalıdır.`);
  }
  return value;
}

// --- Alan (area) girdisi -----------------------------------------------------------------------------------------

/** Haftalık açık saatler: [{ weekday 1-7, start "HH:MM", end "HH:MM"|"24:00" }]; günde ≤3 aralık, çakışmaz, her aralık ≥ 1 dilim. Normalize edilmiş sıralı liste döner. */
export function parseWeeklyHours(raw, slotMinutes) {
  if (!Array.isArray(raw)) throw invalidField('Haftalık açık saatler liste olmalıdır.');
  if (raw.length > MAX_HOURS_ENTRIES) throw invalidField(`Haftalık açık saat aralığı en fazla ${MAX_HOURS_ENTRIES} olabilir.`);
  const entries = raw.map((entry) => {
    if (!isPlainObject(entry)) throw invalidField('Açık saat aralığı geçersiz.');
    const weekday = intInRange(entry.weekday, 'Gün', 1, 7);
    const startMin = parseHhmm(entry.start);
    const endMin = parseHhmm(entry.end, { allow24: true });
    if (startMin === null || endMin === null) throw invalidField('Açık saatler SS:DD biçiminde olmalıdır.');
    if (endMin <= startMin) throw invalidField('Açık saat aralığının bitişi başlangıçtan sonra olmalıdır.');
    if (endMin - startMin < slotMinutes) throw invalidField('Her açık saat aralığı en az bir dilim sığmalıdır.');
    return { weekday, startMin, endMin };
  });
  const sorted = [...entries].sort((a, b) => a.weekday - b.weekday || a.startMin - b.startMin);
  for (let i = 0; i < sorted.length; i += 1) {
    const same = sorted.filter((entry) => entry.weekday === sorted[i].weekday);
    if (same.length > MAX_WINDOWS_PER_DAY) throw invalidField(`Bir günde en fazla ${MAX_WINDOWS_PER_DAY} açık saat aralığı olabilir.`);
    if (i > 0 && sorted[i].weekday === sorted[i - 1].weekday && sorted[i].startMin < sorted[i - 1].endMin) {
      throw invalidField('Aynı günün açık saat aralıkları çakışamaz.');
    }
  }
  return normalizeHoursList(sorted);
}

const NUMERIC_AREA_FIELDS = Object.freeze([
  ['capacity', 'Kapasite', 1, 100],
  ['slot_minutes', 'Dilim süresi (dakika)', 15, 480],
  ['min_slots', 'En az dilim', 1, 48],
  ['max_slots', 'En çok dilim', 1, 48],
  ['max_days_ahead', 'Kaç gün önceden', 1, 180],
  ['cancel_cutoff_hours', 'İptal süresi (saat)', 0, 168],
  ['per_user_daily_limit', 'Günlük kişi limiti', 1, 20],
  ['per_user_weekly_limit', 'Haftalık kişi limiti', 1, 100],
]);
const AREA_KEYS = Object.freeze(['name', 'description', 'approval_mode', 'weekly_hours', 'is_active', ...NUMERIC_AREA_FIELDS.map(([key]) => key)]);

/**
 * Alan gövdesinin ALAN DÜZEYİNDE doğrulaması (DB'siz): yalnız gönderilen alanları döndürür. Oluşturmada (requireAll) ad, kapasite, dilim süresi ve haftalık saatler zorunludur;
 * güncellemede en az bir alan gerekir. weekly_hours burada yalnız liste olup olmadığına bakılır (dilim süresi bilinmeden aralık doğrulanamaz: buildAreaValues).
 */
export function parseAreaChanges(body, { requireAll = false } = {}) {
  if (!isPlainObject(body)) throw invalidField('İstek gövdesi geçersiz.');
  const changes = {};
  if ('name' in body) changes.name = requiredText(body.name, 'Alan adı', NAME_MAX, { single: true });
  if ('description' in body) changes.description = optionalText(body.description, 'Açıklama', AREA_DESCRIPTION_MAX);
  if ('approval_mode' in body) {
    if (typeof body.approval_mode !== 'string' || !APPROVAL_MODES.includes(body.approval_mode)) throw invalidField('Onay modu geçersiz (otomatik ya da yönetici onaylı olmalıdır).');
    changes.approval_mode = body.approval_mode;
  }
  if ('is_active' in body) {
    if (typeof body.is_active !== 'boolean') throw invalidField('Etkinlik durumu geçersiz.');
    changes.is_active = body.is_active;
  }
  for (const [key, label, min, max] of NUMERIC_AREA_FIELDS) {
    if (key in body) changes[key] = intInRange(body[key], label, min, max);
  }
  if ('weekly_hours' in body) {
    if (!Array.isArray(body.weekly_hours)) throw invalidField('Haftalık açık saatler liste olmalıdır.');
    changes.weekly_hours = body.weekly_hours;
  }
  if (requireAll) {
    const labels = { name: 'Alan adı', capacity: 'Kapasite', slot_minutes: 'Dilim süresi', weekly_hours: 'Haftalık açık saatler' };
    for (const key of Object.keys(labels)) {
      if (!(key in changes)) throw invalidField(`${labels[key]} zorunludur.`);
    }
  } else if (!AREA_KEYS.some((key) => key in changes)) {
    throw invalidField('Değiştirilecek bir alan gönderilmedi.');
  }
  return changes;
}

const AREA_CREATE_DEFAULTS = Object.freeze({
  description: null, approval_mode: 'otomatik', is_active: true, min_slots: 1, max_slots: 4, max_days_ahead: 14, cancel_cutoff_hours: 2, per_user_daily_limit: 2, per_user_weekly_limit: 5,
});

/**
 * Çapraz kurallar (dilim süresi 5'in katı, min <= max, günlük <= haftalık, her aralık >= 1 dilim) BİRLEŞİK değerlere uygulanır.
 * current = null: oluşturma (varsayılanlar; açıkça gönderilmeyen max / haftalık değer min / günlük değere uyarlanır). Dönen { values, changes }: tam değerler ve normalize değişiklikler.
 */
export function buildAreaValues(current, rawChanges) {
  const changes = { ...rawChanges };
  const values = { ...(current ?? AREA_CREATE_DEFAULTS), ...changes };
  if (current === null) {
    if (!('max_slots' in changes)) values.max_slots = Math.max(AREA_CREATE_DEFAULTS.max_slots, values.min_slots);
    if (!('per_user_weekly_limit' in changes)) values.per_user_weekly_limit = Math.max(AREA_CREATE_DEFAULTS.per_user_weekly_limit, values.per_user_daily_limit);
  }
  if (values.slot_minutes % 5 !== 0) throw invalidField('Dilim süresi 5 dakikanın katı olmalıdır.');
  if (values.min_slots > values.max_slots) throw invalidField('En az dilim, en çok dilimden büyük olamaz.');
  if (values.per_user_daily_limit > values.per_user_weekly_limit) throw invalidField('Günlük limit haftalık limitten büyük olamaz.');
  if ('weekly_hours' in changes || 'slot_minutes' in changes) {
    values.weekly_hours = parseWeeklyHours('weekly_hours' in changes ? changes.weekly_hours : current.weekly_hours, values.slot_minutes);
    changes.weekly_hours = values.weekly_hours;
  }
  return { values, changes };
}

// --- Rezervasyon girdileri ---------------------------------------------------------------------------------------

/** POST /app/reservations gövdesi. */
export function parseReservationCreate(body) {
  if (!isPlainObject(body)) throw invalidField('İstek gövdesi geçersiz.');
  const siteCode = parsePositiveId(body.site_code);
  if (siteCode === null) throw invalidField('Site seçilmelidir.');
  const areaId = parsePositiveId(body.area_id);
  if (areaId === null) throw invalidField('Alan seçilmelidir.');
  if (!isValidDateStr(body.date)) throw invalidField('Tarih YYYY-AA-GG biçiminde geçerli bir gün olmalıdır.');
  const startMin = parseHhmm(body.start);
  if (startMin === null) throw invalidField('Başlangıç saati SS:DD biçiminde olmalıdır.');
  const slots = intInRange(body.slots, 'Dilim sayısı', 1, 48);
  return {
    siteCode,
    areaId,
    date: body.date,
    startMin,
    slots,
    note: optionalText(body.note, 'Not', RESERVATION_NOTE_MAX),
    apartmentId: optionalId(body.apartment_id, 'Daire'),
    idempotencyKey: normalizeIdempotencyKey(body.idempotency_key),
  };
}

/** POST .../reservations/:id/decision gövdesi. reject / cancel için gerekçe ZORUNLU. */
export function parseDecisionInput(body) {
  if (!isPlainObject(body)) throw invalidField('İstek gövdesi geçersiz.');
  if (typeof body.action !== 'string' || !DECISION_ACTIONS.includes(body.action)) throw invalidField('İşlem geçersiz (approve, reject veya cancel olmalıdır).');
  const note = body.action === 'approve' ? optionalText(body.note, 'Not', DECISION_NOTE_MAX) : requiredText(body.note, 'Gerekçe', DECISION_NOTE_MAX);
  return { action: body.action, note };
}

function parseLimit(value) {
  if (value === undefined || value === null || String(value).trim() === '') return LIST_DEFAULT_LIMIT;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1) throw invalidQuery();
  return Math.min(LIST_MAX_LIMIT, parsed);
}

function parseEnum(value, allowed) {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  if (typeof value !== 'string' || !allowed.includes(value)) throw invalidQuery();
  return value;
}

function parseDateQuery(value) {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  if (typeof value !== 'string' || !isValidDateStr(value)) throw invalidQuery();
  return value;
}

export const encodeCursor = (startsAt, id) => Buffer.from(`${new Date(startsAt).getTime()}.${Number(id)}`).toString('base64url');

function decodeCursor(value) {
  if (value === undefined || value === null || String(value).trim() === '') return null;
  if (typeof value !== 'string' || value.length > 64) throw invalidQuery();
  const match = /^(\d{1,15})\.(\d{1,16})$/.exec(Buffer.from(value, 'base64url').toString('utf8'));
  if (!match) throw invalidQuery();
  return { ms: Number(match[1]), id: Number(match[2]) };
}

/** Yönetim takvimi sorgusu. from / to İstanbul günleri (uygulanan varsayılan: from = bugün); durumlar virgüllü. */
export function parseManagerReservationQuery(query = {}) {
  let statuses = null;
  if (query.status !== undefined && query.status !== null && String(query.status).trim() !== '') {
    if (typeof query.status !== 'string') throw invalidQuery();
    const parts = query.status.split(',').map((part) => part.trim());
    if (parts.length > 5 || parts.some((part) => !API_STATUSES.includes(part))) throw invalidQuery();
    statuses = [...new Set(parts)];
  }
  const from = parseDateQuery(query.from);
  const to = parseDateQuery(query.to);
  if (from && to && (to < from || diffDays(from, to) > CALENDAR_MAX_DAYS)) throw invalidQuery();
  return { areaId: optionalQueryId(query.area_id), statuses, from, to, cursor: decodeCursor(query.cursor), limit: parseLimit(query.limit) };
}

export function parseResidentReservationQuery(query = {}) {
  return {
    siteCode: optionalQueryId(query.site_code),
    scope: parseEnum(query.scope, SCOPES) ?? 'all',
    beforeId: optionalQueryId(query.before_id),
    limit: parseLimit(query.limit),
  };
}

export function parseAreaListQuery(query = {}) {
  return { siteCode: optionalQueryId(query.site_code) };
}

/** Boş dilim sorgusu: from / to (varsayılan bugün .. +6), en çok 14 gün; rezerve edilebilir aralığa [bugün, bugün + max_days_ahead] kırpılır. */
export function parseAvailabilityQuery(query = {}, area, now = new Date()) {
  const today = todayIstanbul(now);
  const from = parseDateQuery(query.from) ?? today;
  const to = parseDateQuery(query.to) ?? addDays(from, 6);
  if (to < from || diffDays(from, to) >= AVAILABILITY_MAX_DAYS) throw invalidQuery();
  const bookableUntil = addDays(today, Number(area.max_days_ahead));
  const first = from < today ? today : from;
  const last = to > bookableUntil ? bookableUntil : to;
  return { first, last, bookableUntil };
}

// --- Konsiyerj girdileri -----------------------------------------------------------------------------------------

/** requested_for aralığı: şimdiden en fazla 5 dk geri, +90 gün. YALNIZ yeni kayıtta denetlenir (aynı anahtarla tekrar oynatma bu denetimden önce döner). */
export function assertRequestedForRange(requestedFor, now = new Date()) {
  const ms = requestedFor.getTime();
  if (ms < now.getTime() - 5 * 60_000 || ms > now.getTime() + CONCIERGE_MAX_DAYS_AHEAD * 86_400_000) {
    throw invalidField(`İstenen zaman geçerli bir zaman olmalı ve en fazla ${CONCIERGE_MAX_DAYS_AHEAD} gün sonrası olabilir.`);
  }
}

/** POST /app/concierge-requests gövdesi. requested_for: geçerli ISO zaman (aralık denetimi assertRequestedForRange, yeni kayıtta). */
export function parseConciergeCreate(body) {
  if (!isPlainObject(body)) throw invalidField('İstek gövdesi geçersiz.');
  const siteCode = parsePositiveId(body.site_code);
  if (siteCode === null) throw invalidField('Site seçilmelidir.');
  if (typeof body.category !== 'string' || !CONCIERGE_CATEGORIES.includes(body.category)) {
    throw invalidField('Kategori geçersiz (paket teslim, misafir hazırlığı, temizlik, taşıma veya diğer olmalıdır).');
  }
  const note = optionalText(body.note, 'Not', CONCIERGE_NOTE_MAX);
  if (body.category === 'diger' && note === null) throw invalidField('Diğer talepler için açıklama (not) zorunludur.');
  let requestedFor = null;
  if (body.requested_for !== undefined && body.requested_for !== null) {
    const ms = typeof body.requested_for === 'string' ? Date.parse(body.requested_for) : Number.NaN;
    if (!Number.isFinite(ms)) {
      throw invalidField('İstenen zaman geçerli bir zaman olmalıdır.');
    }
    requestedFor = new Date(ms);
  }
  return { siteCode, category: body.category, note, requestedFor, apartmentId: optionalId(body.apartment_id, 'Daire'), idempotencyKey: normalizeIdempotencyKey(body.idempotency_key) };
}

/** PATCH .../concierge-requests/:id gövdesi: status ve/veya note (sakine görünür kısa not; null siler). */
export function parseConciergePatch(body) {
  if (!isPlainObject(body)) throw invalidField('İstek gövdesi geçersiz.');
  const out = {};
  if ('status' in body) {
    if (typeof body.status !== 'string' || !CONCIERGE_STATUSES.includes(body.status)) throw invalidField('Durum geçersiz.');
    out.status = body.status;
  }
  if ('note' in body) {
    out.note = body.note === null ? null : requiredText(body.note, 'Not', STAFF_NOTE_MAX);
  }
  if (Object.keys(out).length === 0) throw invalidField('Değiştirilecek bir alan gönderilmedi.');
  return out;
}

export function parseConciergeManagerQuery(query = {}) {
  let statuses = null;
  if (query.status !== undefined && query.status !== null && String(query.status).trim() !== '') {
    if (typeof query.status !== 'string') throw invalidQuery();
    const parts = query.status.split(',').map((part) => part.trim());
    if (parts.length > 4) throw invalidQuery();
    const set = new Set();
    for (const part of parts) {
      if (part === 'open') CONCIERGE_OPEN.forEach((status) => set.add(status));
      else if (part === 'closed') CONCIERGE_CLOSED_STATUSES.forEach((status) => set.add(status));
      else if (part === 'all') CONCIERGE_STATUSES.forEach((status) => set.add(status));
      else if (CONCIERGE_STATUSES.includes(part)) set.add(part);
      else throw invalidQuery();
    }
    statuses = [...set];
  }
  return { statuses, category: parseEnum(query.category, CONCIERGE_CATEGORIES), beforeId: optionalQueryId(query.before_id), limit: parseLimit(query.limit) };
}

export function parseConciergeResidentQuery(query = {}) {
  return {
    siteCode: optionalQueryId(query.site_code),
    status: parseEnum(query.status, ['open', 'closed', 'all']) ?? 'all',
    beforeId: optionalQueryId(query.before_id),
    limit: parseLimit(query.limit),
  };
}

// --- Yanıt eşleyicileri -----------------------------------------------------------------------------------------

const num = (value) => (value === null || value === undefined ? null : Number(value));
const HOUR_MS = 3_600_000;

export function mapArea(row, { withSite = false } = {}) {
  const out = {
    id: num(row.id),
    site_code: num(row.site_code),
    name: row.name,
    description: row.description ?? null,
    capacity: Number(row.capacity),
    slot_minutes: Number(row.slot_minutes),
    min_slots: Number(row.min_slots),
    max_slots: Number(row.max_slots),
    max_days_ahead: Number(row.max_days_ahead),
    approval_mode: row.approval_mode,
    cancel_cutoff_hours: Number(row.cancel_cutoff_hours),
    per_user_daily_limit: Number(row.per_user_daily_limit),
    per_user_weekly_limit: Number(row.per_user_weekly_limit),
    weekly_hours: Array.isArray(row.weekly_hours) ? row.weekly_hours.map((entry) => ({ weekday: entry.weekday, start: entry.start, end: entry.end })) : [],
    is_active: row.is_active === true,
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
  };
  if (withSite) out.site_name = row.site_name ?? null;
  return out;
}

/** Çıktı durumu: onaylandi + bitişi geçmiş = tamamlandi (tabloda yok, yanıtta türetilir). */
export function derivedStatus(row, now = new Date()) {
  return row.status === 'onaylandi' && new Date(row.ends_at).getTime() <= now.getTime() ? 'tamamlandi' : row.status;
}

function localTimes(startsAt, endsAt) {
  const start = istanbulParts(startsAt);
  const end = istanbulParts(endsAt);
  return { date: start.date, start: formatHhmm(start.minuteOfDay), end: end.date !== start.date && end.minuteOfDay === 0 ? '24:00' : formatHhmm(end.minuteOfDay) };
}

function locationOf(row) {
  return row.apartment_id ? { id: num(row.apartment_id), label: apartmentLabel(row.block_name, row.unit_label) } : null;
}

/**
 * Rezervasyon görünümü. view: 'resident' (kendi kaydı) | 'manager' (yönetici / süper / görevli) | 'board' (salt okur; telefon + kullanıcı kodu yok).
 * can_cancel: sakin için "iptal süresi içinde mi", yönetim için "iptal edilebilir durumda mı"; can_decide: yalnız yönetim, beklemede ve başlangıç geçmemiş.
 */
export function mapReservation(row, { view, now = new Date() }) {
  const startsAt = new Date(row.starts_at);
  const endsAt = new Date(row.ends_at);
  const dbActive = ACTIVE_DB_STATUSES.includes(row.status);
  const deadline = new Date(startsAt.getTime() - Number(row.cancel_cutoff_hours ?? 0) * HOUR_MS);
  const out = {
    id: num(row.id),
    site_code: num(row.site_code),
    area: { id: num(row.area_id), name: row.area_name ?? null },
    starts_at: startsAt.toISOString(),
    ends_at: endsAt.toISOString(),
    ...localTimes(startsAt, endsAt),
    slot_count: Number(row.slot_count),
    status: derivedStatus(row, now),
    note: row.note ?? null,
    decision_note: row.decision_note ?? null,
    cancelled_by: row.cancelled_by_kind ?? null,
    apartment: locationOf(row),
    created_at: toIso(row.created_at),
  };
  if (view === 'resident') {
    out.site_name = row.site_name ?? null;
    out.can_cancel = dbActive && now.getTime() <= deadline.getTime();
    out.cancel_deadline = dbActive && endsAt.getTime() > now.getTime() ? deadline.toISOString() : null;
    return out;
  }
  const contact = view !== 'board';
  out.requester = { name: row.requester_name ?? DELETED_USER_NAME };
  out.decided_by = row.decided_by ? { name: row.decider_name ?? DELETED_USER_NAME } : null;
  if (contact) {
    out.requester.user_code = num(row.user_code);
    out.requester.phone = row.requester_phone ?? null;
    if (out.decided_by) out.decided_by.user_code = num(row.decided_by);
  }
  out.can_decide = view === 'manager' && row.status === 'beklemede' && startsAt.getTime() > now.getTime();
  out.can_cancel = view === 'manager' && dbActive && endsAt.getTime() > now.getTime();
  return out;
}

/** Konsiyerj görünümü. view: 'resident' | 'manager' | 'board'. */
export function mapConcierge(row, { view }) {
  const out = {
    id: num(row.id),
    site_code: num(row.site_code),
    category: row.category,
    note: row.note ?? null,
    requested_for: toIso(row.requested_for),
    status: row.status,
    staff_note: row.staff_note ?? null,
    apartment: locationOf(row),
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
    closed_at: toIso(row.closed_at),
  };
  if (view === 'resident') {
    out.site_name = row.site_name ?? null;
    out.can_cancel = row.status === 'yeni';
    return out;
  }
  out.requester = { name: row.requester_name ?? DELETED_USER_NAME };
  if (view !== 'board') {
    out.requester.user_code = num(row.user_code);
    out.requester.phone = row.requester_phone ?? null;
  }
  return out;
}

/** Hesap silme önizlemesi: gelecekteki rezervasyonlar / açık talepler iptal edilir (will_remove); geçmiş kayıtlar kalır (will_keep). */
export function reservationRemoveNote({ upcoming = 0, openRequests = 0 } = {}) {
  const parts = [];
  if (upcoming > 0) parts.push(`gelecekteki rezervasyonlarınız (${upcoming})`);
  if (openRequests > 0) parts.push(`açık konsiyerj talepleriniz (${openRequests})`);
  return `${parts.join(' ve ')[0].toUpperCase()}${parts.join(' ve ').slice(1)} iptal edilir.`;
}

export function reservationKeepNote({ reservations = 0, requests = 0 } = {}) {
  const parts = [];
  if (reservations > 0) parts.push(`rezervasyon kayıtlarınız (${reservations})`);
  if (requests > 0) parts.push(`konsiyerj talepleriniz (${requests})`);
  return `Geçmiş ${parts.join(' ve ')}, yazdığınız notlar ve daire bilginizle birlikte site yönetiminde kalır (rezervasyon ve konsiyerj siteye aittir); kişi adınız "Silinmiş Kullanıcı" olarak görünür.`;
}
