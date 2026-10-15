// Duyuru ve Bildirim (Faz 3a) ortak sabitleri, doğrulayıcıları ve yanıt eşleyicileri. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_DUYURU.md. Hata gövdesi { error, code } (PlatformError); INVALID_BODY mesajları alan adıyla DEĞİL Türkçe
// etiketle yazılır. Kullanıcı metni düz yazıdır: HTML ayrıştırılmaz, e-postada kaçışlanır.

import { PlatformError } from './errors.js';
import { parsePositiveId, redactForReadOnlyRole, toIso } from './people_common.js';

export const IMPORTANCES = Object.freeze(['normal', 'urgent']);
export const STATUSES = Object.freeze(['draft', 'scheduled', 'published', 'withdrawn']);
export const TARGET_TYPES = Object.freeze(['site', 'blocks', 'apartments']);
export const PUBLISH_MODES = Object.freeze(['draft', 'now', 'schedule']);
export const LIST_STATUS_FILTERS = Object.freeze([...STATUSES, 'all']);
export const READ_FILTERS = Object.freeze(['all', 'true', 'false']);
export const EMAIL_STATUSES = Object.freeze([
  'none',
  'pending',
  'sent',
  'failed',
  'no_address',
  'skipped_pref',
  'capped',
  'duplicate',
]);

export const TITLE_MAX = 120;
export const BODY_MAX = 5000;
export const PREVIEW_MAX = 160;
export const TARGET_IDS_MAX = 500;
/** Tek yayında e-posta gönderilecek en çok adres (yönetici yayınında aşılırsa 400 ANNOUNCEMENT_EMAIL_LIMIT). */
export const EMAIL_PER_PUBLISH_LIMIT = 1000;
/** ANNOUNCEMENT_EMAIL_MAX_PER_DAY_PER_SITE yoksa/geçersizse site başına günlük e-posta sınırı. */
export const DEFAULT_EMAIL_DAILY_LIMIT = 500;
export const MAX_EMAIL_ATTEMPTS = 3;

export const SCHEDULE_MIN_MS = 60 * 1000;

export const LIST_DEFAULT_LIMIT = 30;
export const LIST_MAX_LIMIT = 100;
export const RECIPIENTS_DEFAULT_LIMIT = 50;
export const RECIPIENTS_MAX_LIMIT = 200;

// --- Hatalar ---------------------------------------------------------------------------------------------

export const announcementNotFound = () => new PlatformError(404, 'ANNOUNCEMENT_NOT_FOUND', 'Duyuru bulunamadı.');
export const siteNotFound = () => new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
export const invalidState = (message) =>
  new PlatformError(409, 'INVALID_STATE', message ?? 'Bu işlem duyurunun mevcut durumunda yapılamaz.');
export const noRecipients = () =>
  new PlatformError(409, 'NO_RECIPIENTS', 'Seçilen hedefte duyuruyu alacak kimse bulunamadı.');
export const invalidTarget = (message) =>
  new PlatformError(400, 'INVALID_TARGET', message ?? 'Seçilen blok veya daireler bu siteye ait değil.');
export const invalidField = (message) => new PlatformError(400, 'INVALID_BODY', message);
export const invalidSchedule = (message) =>
  new PlatformError(400, 'INVALID_SCHEDULE', message ?? 'Yayın zamanı geçersiz.');
export const invalidQuery = () => new PlatformError(400, 'INVALID_QUERY', 'Geçersiz sorgu parametresi.');
export const emailLimitExceeded = () =>
  new PlatformError(
    400,
    'ANNOUNCEMENT_EMAIL_LIMIT',
    `E-posta gönderilecek kişi sayısı tek yayında ${EMAIL_PER_PUBLISH_LIMIT} adresi aşıyor. Duyuruyu bloklara veya dairelere bölerek yayınlayın.`,
  );

// --- Metin temizliği ---------------------------------------------------------------------------------------

// Görünmez ve yön denetim karakterleri kullanıcı metninden atılır (kod noktası olarak; kaynakta kaçış dizisi yazılmaz).
// Emoji birleştiricisi (U+200D) ve U+200C korunur.
const STRIPPED_CODE_POINTS = new Set([
  0x061c, 0x200b, 0x200e, 0x200f, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2060, 0x2066, 0x2067, 0x2068, 0x2069, 0xfeff,
]);
const LINE_SEPARATORS = new RegExp(`\\r\\n?|${String.fromCodePoint(0x2028)}|${String.fromCodePoint(0x2029)}`, 'g');
// eslint-disable-next-line no-control-regex
const CONTROL_EXCEPT_LAYOUT = /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]/g;
// eslint-disable-next-line no-control-regex
const CONTROL_ALL = /[\x00-\x1f\x7f-\x9f]/g;

function stripInvisible(text) {
  let out = '';
  for (const ch of text) {
    if (!STRIPPED_CODE_POINTS.has(ch.codePointAt(0))) {
      out += ch;
    }
  }
  return out;
}

const codePointLength = (text) => Array.from(text).length;

/** Başlık: tek satır (satır sonu/sekme boşluğa), boşluklar tekleştirilir, 1-120 karakter. */
export function normalizeTitle(value) {
  if (typeof value !== 'string') {
    throw invalidField('Başlık zorunludur.');
  }
  const text = stripInvisible(value.normalize('NFC').replace(LINE_SEPARATORS, ' '))
    .replace(CONTROL_ALL, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  const length = codePointLength(text);
  if (length < 1) {
    throw invalidField('Başlık boş olamaz.');
  }
  if (length > TITLE_MAX) {
    throw invalidField(`Başlık en fazla ${TITLE_MAX} karakter olabilir.`);
  }
  return text;
}

/** Metin: düz yazı; satır sonları LF'ye çevrilir, kontrol karakterleri atılır, kırpılır, 1-5000 karakter. */
export function normalizeBody(value) {
  if (typeof value !== 'string') {
    throw invalidField('Duyuru metni zorunludur.');
  }
  const text = stripInvisible(value.normalize('NFC').replace(LINE_SEPARATORS, '\n'))
    .replace(CONTROL_EXCEPT_LAYOUT, '')
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{4,}/g, '\n\n\n')
    .trim();
  const length = codePointLength(text);
  if (length < 1) {
    throw invalidField('Duyuru metni boş olamaz.');
  }
  if (length > BODY_MAX) {
    throw invalidField(`Duyuru metni en fazla ${BODY_MAX} karakter olabilir.`);
  }
  return text;
}

export function normalizeImportance(value) {
  if (typeof value !== 'string' || !IMPORTANCES.includes(value)) {
    throw invalidField('Önem derecesi geçersiz (Normal veya Acil olmalıdır).');
  }
  return value;
}

export function normalizeSendEmail(value) {
  if (typeof value !== 'boolean') {
    throw invalidField('E-posta seçeneği geçersiz (evet veya hayır olmalıdır).');
  }
  return value;
}

export function parsePublishMode(value) {
  if (value === undefined || value === null) {
    return 'draft';
  }
  if (typeof value !== 'string' || !PUBLISH_MODES.includes(value)) {
    throw invalidField('Yayın türü geçersiz (taslak, hemen veya zamanlı olmalıdır).');
  }
  return value;
}

// --- Hedef ---------------------------------------------------------------------------------------------------

function parseIdList(value, emptyMessage, label) {
  if (!Array.isArray(value)) {
    throw invalidTarget(emptyMessage);
  }
  const ids = [];
  const seen = new Set();
  for (const entry of value) {
    const id = parsePositiveId(typeof entry === 'string' ? entry : entry);
    if (id === null) {
      throw invalidTarget(`Seçilen ${label} geçersiz.`);
    }
    if (!seen.has(id)) {
      seen.add(id);
      ids.push(id);
    }
  }
  if (ids.length === 0) {
    throw invalidTarget(emptyMessage);
  }
  if (ids.length > TARGET_IDS_MAX) {
    throw invalidTarget(`En fazla ${TARGET_IDS_MAX} ${label} seçilebilir.`);
  }
  return ids;
}

/**
 * Hedef gövdesi { type, block_ids?, apartment_ids? } -> { type, blockIds, apartmentIds } (yalnız biçim doğrulaması; "kimlikler bu
 * siteye ait mi" denetimi serviste, sorguyla yapılır). `site` hedefinde kimlik listeleri yoksayılır.
 */
export function parseTargetInput(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw invalidField('Hedef bilgisi geçersiz.');
  }
  const type = raw.type;
  if (typeof type !== 'string' || !TARGET_TYPES.includes(type)) {
    throw invalidField('Hedef türü geçersiz (tüm site, bloklar veya daireler olmalıdır).');
  }
  if (type === 'site') {
    return { type, blockIds: [], apartmentIds: [] };
  }
  if (type === 'blocks') {
    return { type, blockIds: parseIdList(raw.block_ids, 'En az bir blok seçin.', 'blok'), apartmentIds: [] };
  }
  return { type, blockIds: [], apartmentIds: parseIdList(raw.apartment_ids, 'En az bir daire seçin.', 'daire') };
}

// --- Zamanlama -----------------------------------------------------------------------------------------------

const SCHEDULE_PATTERN =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:[.,]\d{1,9})?)?(Z|[+-]\d{2}(?::?\d{2})?)?$/;

/** Offset yazımı -> '+03:00' / 'Z'. Offset yoksa Türkiye saati (UTC+03:00, yaz saati uygulaması yok) varsayılır. */
function normalizeOffset(offset) {
  if (offset === undefined || offset === '') {
    return '+03:00';
  }
  if (offset === 'Z') {
    return 'Z';
  }
  const digits = offset.slice(1).replace(':', '');
  const hours = digits.slice(0, 2);
  const minutes = digits.length >= 4 ? digits.slice(2, 4) : '00';
  return `${offset[0]}${hours}:${minutes}`;
}

/**
 * ISO 8601 yayın zamanı -> Date. Bugünden >= 1 dakika, <= 1 yıl sonra olmalıdır (aksi 400 INVALID_SCHEDULE).
 * Zaman dilimi yoksa Türkiye saati (+03:00) sayılır.
 */
export function parseScheduleInput(value, now = new Date()) {
  if (typeof value !== 'string') {
    throw invalidSchedule('Yayın zamanı geçersiz.');
  }
  const match = SCHEDULE_PATTERN.exec(value.trim());
  if (!match) {
    throw invalidSchedule('Yayın zamanı geçersiz (ISO 8601 biçiminde olmalıdır).');
  }
  const [, year, month, day, hour, minute, second = '00', offset] = match;
  const y = Number(year);
  const mo = Number(month);
  const d = Number(day);
  const probe = new Date(Date.UTC(y, mo - 1, d));
  const realDate = probe.getUTCFullYear() === y && probe.getUTCMonth() === mo - 1 && probe.getUTCDate() === d;
  if (!realDate || Number(hour) > 23 || Number(minute) > 59 || Number(second) > 59) {
    throw invalidSchedule('Yayın zamanı geçersiz.');
  }
  const fraction = /[.,](\d{1,9})/.exec(value)?.[1];
  const millis = fraction ? fraction.padEnd(3, '0').slice(0, 3) : '000';
  const parsed = new Date(`${year}-${month}-${day}T${hour}:${minute}:${second}.${millis}${normalizeOffset(offset)}`);
  if (Number.isNaN(parsed.getTime())) {
    throw invalidSchedule('Yayın zamanı geçersiz.');
  }
  if (parsed.getTime() - now.getTime() < SCHEDULE_MIN_MS) {
    throw invalidSchedule('Yayın zamanı en az 1 dakika sonrası olmalıdır.');
  }
  const limit = new Date(now.getTime());
  limit.setFullYear(limit.getFullYear() + 1);
  if (parsed.getTime() > limit.getTime()) {
    throw invalidSchedule('Yayın zamanı en fazla 1 yıl sonrası olabilir.');
  }
  return parsed;
}

// --- Gövdeler ------------------------------------------------------------------------------------------------

const hasOwn = (object, key) => Object.prototype.hasOwnProperty.call(object, key);

/**
 * POST gövdesi -> doğrulanmış girdi. `publish` yoksa 'draft' (yanlışlıkla yayınlamamak için en güvenli varsayılan).
 * `publish_at` yalnız `publish: 'schedule'` ile anlamlıdır (diğerlerinde yoksayılır).
 */
export function parseCreateInput(body, now = new Date()) {
  const input = body && typeof body === 'object' && !Array.isArray(body) ? body : {};
  const publish = parsePublishMode(input.publish);
  const result = {
    title: normalizeTitle(input.title),
    body: normalizeBody(input.body),
    importance: input.importance === undefined || input.importance === null ? 'normal' : normalizeImportance(input.importance),
    target: parseTargetInput(input.target),
    sendEmail: input.send_email === undefined || input.send_email === null ? false : normalizeSendEmail(input.send_email),
    publish,
    publishAt: null,
  };
  if (publish === 'schedule') {
    if (input.publish_at === undefined || input.publish_at === null || input.publish_at === '') {
      throw invalidSchedule('Zamanlı yayın için yayın zamanı gerekli.');
    }
    result.publishAt = parseScheduleInput(input.publish_at, now);
  }
  return result;
}

export const PATCH_KEYS = Object.freeze(['title', 'body', 'importance', 'target', 'send_email', 'publish_at', 'publish']);

/**
 * PATCH gövdesi -> yalnız gönderilen alanlar. `publish_at: null` zamanlamayı kaldırır (taslağa döner); dolu değer zamanlar.
 * `publish` verilirse create ile aynı anlamdadır ('draft' | 'now' | 'schedule').
 * @returns {{ title?: string, body?: string, importance?: string, target?: object, sendEmail?: boolean, publish?: string,
 *             publishAtProvided: boolean, publishAt?: Date|null, keys: string[] }}
 */
export function parsePatchInput(body, now = new Date()) {
  const input = body && typeof body === 'object' && !Array.isArray(body) ? body : {};
  const keys = PATCH_KEYS.filter((key) => hasOwn(input, key) && input[key] !== undefined);
  const patch = { keys, publishAtProvided: false };
  if (keys.length === 0) {
    throw invalidField('Güncellenecek bir alan gönderilmedi.');
  }
  if (keys.includes('title')) {
    patch.title = normalizeTitle(input.title);
  }
  if (keys.includes('body')) {
    patch.body = normalizeBody(input.body);
  }
  if (keys.includes('importance')) {
    patch.importance = normalizeImportance(input.importance);
  }
  if (keys.includes('target')) {
    patch.target = parseTargetInput(input.target);
  }
  if (keys.includes('send_email')) {
    patch.sendEmail = normalizeSendEmail(input.send_email);
  }
  if (keys.includes('publish')) {
    patch.publish = parsePublishMode(input.publish);
  }
  if (keys.includes('publish_at')) {
    patch.publishAtProvided = true;
    patch.publishAt = input.publish_at === null ? null : parseScheduleInput(input.publish_at, now);
  }
  return patch;
}

// --- Sorgu parametreleri -------------------------------------------------------------------------------------

function parsePageValues(query, { defaultLimit, maxLimit }) {
  let limit = defaultLimit;
  if (query.limit !== undefined && query.limit !== null && String(query.limit).trim() !== '') {
    const parsed = Number(query.limit);
    if (Number.isFinite(parsed)) {
      limit = Math.min(maxLimit, Math.max(1, Math.floor(parsed)));
    }
  }
  let offset = 0;
  if (query.offset !== undefined && query.offset !== null && String(query.offset).trim() !== '') {
    const parsed = Number(query.offset);
    if (!Number.isFinite(parsed) || parsed < 0) {
      throw invalidQuery();
    }
    offset = Math.min(1_000_000, Math.floor(parsed));
  }
  return { limit, offset };
}

export function parseSearch(value) {
  if (value === undefined || value === null) {
    return null;
  }
  const text = typeof value === 'string' ? value.trim() : '';
  return text === '' ? null : Array.from(text).slice(0, 100).join('');
}

export function parseListQuery(query = {}) {
  let status = 'all';
  if (query.status !== undefined && query.status !== null && String(query.status).trim() !== '') {
    if (typeof query.status !== 'string' || !LIST_STATUS_FILTERS.includes(query.status.trim())) {
      throw invalidQuery();
    }
    status = query.status.trim();
  }
  return {
    status,
    q: parseSearch(query.q),
    ...parsePageValues(query, { defaultLimit: LIST_DEFAULT_LIMIT, maxLimit: LIST_MAX_LIMIT }),
  };
}

export function parseRecipientsQuery(query = {}) {
  let read = 'all';
  if (query.read !== undefined && query.read !== null && String(query.read).trim() !== '') {
    if (typeof query.read !== 'string' || !READ_FILTERS.includes(query.read.trim())) {
      throw invalidQuery();
    }
    read = query.read.trim();
  }
  return {
    read,
    q: parseSearch(query.q),
    ...parsePageValues(query, { defaultLimit: RECIPIENTS_DEFAULT_LIMIT, maxLimit: RECIPIENTS_MAX_LIMIT }),
  };
}

/** Sakin listesi: limit (1-100, varsayılan 30), before_id (sayfa imleci), site_code (isteğe bağlı süzgeç). */
export function parseInboxQuery(query = {}) {
  const optionalId = (value) => {
    if (value === undefined || value === null || String(value).trim() === '') {
      return null;
    }
    const parsed = parsePositiveId(typeof value === 'string' ? value : String(value));
    if (parsed === null) {
      throw invalidQuery();
    }
    return parsed;
  };
  let limit = LIST_DEFAULT_LIMIT;
  if (query.limit !== undefined && query.limit !== null && String(query.limit).trim() !== '') {
    const parsed = Number(query.limit);
    if (Number.isFinite(parsed)) {
      limit = Math.min(LIST_MAX_LIMIT, Math.max(1, Math.floor(parsed)));
    }
  }
  return { limit, beforeId: optionalId(query.before_id), siteCode: optionalId(query.site_code) };
}

// --- Yanıt eşleyicileri --------------------------------------------------------------------------------------

/** Listelerde gövdenin yalnız bu kadar karakteri okunur (önizleme için yeter). */
export const BODY_HEAD_CHARS = 1200;

/** Önizleme: boşluklar tekleştirilir, 160 karakteri aşarsa 159 + "…". `truncated`: okunan gövde kafası gövdenin tamamı değil. */
export function previewOf(text, { truncated = false } = {}) {
  const chars = Array.from(String(text ?? '').replace(/\s+/g, ' ').trim());
  if (chars.length > PREVIEW_MAX || (truncated && chars.length >= PREVIEW_MAX)) {
    return `${chars.slice(0, PREVIEW_MAX - 1).join('')}…`;
  }
  return truncated && chars.length > 0 ? `${chars.join('')}…` : chars.join('');
}

const bodyPreview = (row) => previewOf(row.body_head ?? row.body, { truncated: Number(row.body_length ?? 0) > BODY_HEAD_CHARS });

/** BIGINT[] (pg metin dizisi) -> sayı dizisi. */
export function idArray(value) {
  return Array.isArray(value) ? value.map((entry) => Number(entry)) : [];
}

/** AnnouncementSummary (yönetici/kurul). `created_by_name` kurula route katmanında temizlenir (redactForBoard). */
export function mapSummaryRow(row) {
  return {
    id: Number(row.id),
    title: row.title,
    body_preview: bodyPreview(row),
    importance: row.importance,
    status: row.status,
    target_type: row.target_type,
    publish_at: toIso(row.publish_at),
    published_at: toIso(row.published_at),
    edited_at: toIso(row.edited_at),
    send_email: row.send_email === true,
    recipient_count: Number(row.recipient_count ?? 0),
    read_count: Number(row.read_count ?? 0),
    created_at: toIso(row.created_at),
    created_by_name: row.created_by_name ?? null,
  };
}

/** Kurul üyesine verilmeyen alanlar: kullanıcı kodları (redactForReadOnlyRole) + oluşturan yöneticinin adı. */
export function redactForBoard(value) {
  const base = redactForReadOnlyRole(value);
  const clear = (entry) => {
    if (Array.isArray(entry)) {
      return entry.map(clear);
    }
    if (entry && typeof entry === 'object' && !(entry instanceof Date)) {
      const out = {};
      for (const [key, inner] of Object.entries(entry)) {
        out[key] = key === 'created_by_name' ? null : clear(inner);
      }
      return out;
    }
    return entry;
  };
  return clear(base);
}

/** Sakin gelen kutusu satırı. */
export function mapInboxRow(row) {
  return {
    id: Number(row.id),
    site_code: Number(row.site_code),
    site_name: row.site_name ?? null,
    title: row.title,
    body_preview: bodyPreview(row),
    importance: row.importance,
    published_at: toIso(row.published_at),
    edited_at: toIso(row.edited_at),
    is_read: row.read_at !== null && row.read_at !== undefined,
  };
}

