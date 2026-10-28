// Geri bildirim (103): sabitler, sınırlar, hata üreticileri, girdi doğrulayıcıları ve yanıt eşleyicileri. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_GERI_BILDIRIM.md. Karar K11: ek en çok 4 dosya, dosya başı 5 MB, toplam 20 MB; sınır aşımı 400 (sunucu istemciye GÜVENMEZ, aynı sınırlar
// burada da doğrulanır). Ekran bağlamı (ekran adı + rota) istemciden gelir ama kullanıcı alanı olarak değil, otomatik üstveri olarak saklanır. Rol ve site ilişkisi
// SUNUCUDA türetilir (istemcinin bildirdiği rol dinlenmez). Günlüğe ve audit `details` alanına metin / dosya adı YAZILMAZ (yalnız kimlik, tür, boyut).

import { PlatformError } from './errors.js';
import { INVISIBLE_RE } from './document_common.js';
import { DELETED_USER_NAME } from './account_common.js';
import { parsePositiveId, toIso } from './people_common.js';
import { ATTACHMENT_EXTENSIONS, ATTACHMENT_MIMES, buildAttachmentFileName } from './work_attachments_common.js';

/** Bir geri bildirime en çok dosya. */
export const FEEDBACK_MAX_ATTACHMENTS = 4;
/** Dosya başı üst sınır (5 MB; DB CHECK ile aynı). */
export const FEEDBACK_ATTACHMENT_MAX_BYTES = 5242880;
/** Toplam üst sınır (20 MB). */
export const FEEDBACK_TOTAL_MAX_BYTES = 20971520;
export const FEEDBACK_MESSAGE_MAX = 2000;
export const FEEDBACK_SCREEN_NAME_MAX = 120;
export const FEEDBACK_SCREEN_ROUTE_MAX = 120;
export const FEEDBACK_APP_VERSION_MAX = 40;
export const FEEDBACK_PLATFORM_MAX = 20;
/** Kullanıcı başına saatte en çok geri bildirim ve 24 saatte en çok yüklenecek dosya baytı (disk doldurma koruması; DB düzeyinde, süreçler arası). */
export const FEEDBACK_PER_USER_PER_HOUR = 5;
export const FEEDBACK_USER_DAILY_BYTES = 104857600;
/** `uploading` satırın bakım işince silinmeden önceki ömrü (dakika); süresi dolan satıra PUT 410. */
export const FEEDBACK_UPLOAD_TTL_MINUTES = 120;
/** Depo kökü altındaki alt ağaç (belgelerin ve iş takibi fotoğraflarının ağaçlarından AYRI). */
export const FEEDBACK_SUBTREE = 'feedback_attachments';
/** Siteye bağlı olmayan geri bildirimin dosya dizini (depolama anahtarı 10 haneli dizin ister; gerçek site kodu aralığının en küçük değeri). */
export const FEEDBACK_NO_SITE_BUCKET = 1000000000;
export const FEEDBACK_UPLOAD_CONCURRENCY = 4;
export const FEEDBACK_DOWNLOAD_CONCURRENCY = 16;
export const FEEDBACK_LIST_DEFAULT_LIMIT = 30;
export const FEEDBACK_LIST_MAX_LIMIT = 100;
/** İstek gövdesi (JSON) için kaba üst sınır (bayt). */
export const FEEDBACK_MAX_BODY_BYTES = 16384;

export const FEEDBACK_PLATFORMS = Object.freeze(['android', 'ios', 'web', 'windows', 'macos', 'linux']);

const MB = 1048576;
export const formatMb = (bytes) => {
  const mb = Number(bytes) / MB;
  return Number.isInteger(mb) ? String(mb) : mb.toFixed(1).replace('.', ',');
};

// --- Hatalar -----------------------------------------------------------------------------------------------------

export const invalidFeedbackField = (message) => new PlatformError(400, 'INVALID_BODY', message);
export const feedbackTooManyAttachments = () =>
  new PlatformError(400, 'FEEDBACK_TOO_MANY_ATTACHMENTS', `En fazla ${FEEDBACK_MAX_ATTACHMENTS} dosya eklenebilir.`, {
    max_attachments: FEEDBACK_MAX_ATTACHMENTS,
  });
export const feedbackAttachmentTooLarge = () =>
  new PlatformError(400, 'FEEDBACK_ATTACHMENT_TOO_LARGE', `Her dosya en fazla ${formatMb(FEEDBACK_ATTACHMENT_MAX_BYTES)} MB olabilir.`, {
    max_bytes: FEEDBACK_ATTACHMENT_MAX_BYTES,
  });
export const feedbackTotalTooLarge = () =>
  new PlatformError(400, 'FEEDBACK_ATTACHMENTS_TOO_LARGE', `Dosyaların toplam boyutu en fazla ${formatMb(FEEDBACK_TOTAL_MAX_BYTES)} MB olabilir.`, {
    max_total_bytes: FEEDBACK_TOTAL_MAX_BYTES,
  });
export const feedbackTypeNotAllowed = () =>
  new PlatformError(400, 'FEEDBACK_ATTACHMENT_TYPE_NOT_ALLOWED', 'Bu dosya türü desteklenmiyor. JPEG, PNG veya WebP fotoğraf ekleyin.');
export const feedbackNotFound = () => new PlatformError(404, 'FEEDBACK_NOT_FOUND', 'Geri bildirim bulunamadı ya da erişiminiz yok.');
export const feedbackAttachmentNotFound = () => new PlatformError(404, 'FEEDBACK_ATTACHMENT_NOT_FOUND', 'Ek dosya bulunamadı ya da erişiminiz yok.');
export const feedbackSiteNotFound = () => new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
export const feedbackForbiddenSite = () => new PlatformError(403, 'FORBIDDEN_SITE', 'Bu site için geri bildirim gönderemezsiniz.');
export const feedbackAccountDeleted = () => new PlatformError(401, 'ACCOUNT_DELETED', 'Bu hesap silinmiş.');
export const feedbackRateLimited = () =>
  new PlatformError(429, 'FEEDBACK_RATE_LIMITED', 'Bir saat içinde çok fazla geri bildirim gönderdiniz. Biraz sonra tekrar deneyin.', {
    hourly_limit: FEEDBACK_PER_USER_PER_HOUR,
    retry_after_seconds: 3600,
  });
export const feedbackQuotaExceeded = () =>
  new PlatformError(429, 'FEEDBACK_QUOTA_EXCEEDED', 'Bugün çok fazla dosya gönderdiniz. Yarın tekrar deneyin ya da dosyasız gönderin.', {
    daily_bytes: FEEDBACK_USER_DAILY_BYTES,
    retry_after_seconds: 3600,
  });
export const feedbackStorageUnavailable = () => new PlatformError(503, 'FEEDBACK_STORAGE_UNAVAILABLE', 'Dosya yükleme şu an kullanılamıyor.');
export const feedbackSizeMismatch = () =>
  new PlatformError(400, 'FEEDBACK_ATTACHMENT_SIZE_MISMATCH', 'Gönderilen dosya boyutu bildirilen boyutla uyuşmuyor.');
export const feedbackMissingContentLength = () =>
  new PlatformError(400, 'FEEDBACK_ATTACHMENT_SIZE_MISMATCH', 'Dosya boş ya da boyutu bildirilmemiş.');

// --- Metin ------------------------------------------------------------------------------------------------------

const LINE_BREAKS = String.fromCodePoint(0x2028) + String.fromCodePoint(0x2029);
const NEWLINES_RE = new RegExp(String.fromCharCode(13) + '?' + String.fromCharCode(10) + '|' + String.fromCharCode(13) + '|[' + LINE_BREAKS + ']', 'g');
const BREAKS_RE = new RegExp('[' + String.fromCharCode(13, 10, 9) + LINE_BREAKS + ']+', 'g');
const codePointLength = (text) => Array.from(text).length;

/** Çok satırlı düz yazı: satır sonları korunur, kontrol / görünmez karakterler atılır, ardışık boş satırlar kısaltılır. */
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

function singleLine(value) {
  return value.normalize('NFC').replace(BREAKS_RE, ' ').replace(INVISIBLE_RE, '').replace(/\s+/gu, ' ').trim();
}

export function normalizeFeedbackMessage(value) {
  if (typeof value !== 'string') throw invalidFeedbackField('Geri bildirim metni zorunludur.');
  const text = multiLine(value);
  const length = codePointLength(text);
  if (length < 1) throw invalidFeedbackField('Geri bildirim metni boş olamaz.');
  if (length > FEEDBACK_MESSAGE_MAX) throw invalidFeedbackField(`Geri bildirim en fazla ${FEEDBACK_MESSAGE_MAX} karakter olabilir.`);
  return text;
}

function normalizeScreenName(value) {
  if (typeof value !== 'string') throw invalidFeedbackField('Ekran adı zorunludur.');
  const text = singleLine(value);
  const length = codePointLength(text);
  if (length < 1) throw invalidFeedbackField('Ekran adı boş olamaz.');
  if (length > FEEDBACK_SCREEN_NAME_MAX) throw invalidFeedbackField(`Ekran adı en fazla ${FEEDBACK_SCREEN_NAME_MAX} karakter olabilir.`);
  return text;
}

/** Rota: makine okunur tanıtıcı (harf, rakam ve `_ . : / -`); boşluk / denetim karakteri yok. */
const ROUTE_RE = /^[A-Za-z0-9_.:/-]+$/;
function normalizeScreenRoute(value) {
  if (typeof value !== 'string') throw invalidFeedbackField('Ekran rotası zorunludur.');
  const text = value.trim();
  if (text === '' || text.length > FEEDBACK_SCREEN_ROUTE_MAX || !ROUTE_RE.test(text)) {
    throw invalidFeedbackField('Ekran rotası geçersiz.');
  }
  return text;
}

function optionalShortText(value, max, label) {
  if (value === undefined || value === null || value === '') return null;
  if (typeof value !== 'string') throw invalidFeedbackField(`${label} geçersiz.`);
  const text = singleLine(value);
  if (text === '') return null;
  if (codePointLength(text) > max) throw invalidFeedbackField(`${label} çok uzun.`);
  return text;
}

// --- Ekler ------------------------------------------------------------------------------------------------------

const isPlainObject = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);

function parseDeclaredAttachment(raw) {
  if (!isPlainObject(raw)) throw invalidFeedbackField('Ek dosya bilgisi geçersiz.');
  if (typeof raw.file_name !== 'string' || raw.file_name.trim() === '') throw invalidFeedbackField('Dosya adı zorunludur.');
  if (raw.file_name.length > 1000) throw invalidFeedbackField('Dosya adı çok uzun.');
  const mime = typeof raw.mime_type === 'string' ? raw.mime_type.trim().toLowerCase() : '';
  if (!ATTACHMENT_MIMES.includes(mime)) throw feedbackTypeNotAllowed();
  const size = raw.size_bytes;
  if (typeof size !== 'number' || !Number.isSafeInteger(size) || size < 0) throw invalidFeedbackField('Dosya boyutu geçersiz.');
  if (size === 0) throw invalidFeedbackField('Boş dosya eklenemez.');
  if (size > FEEDBACK_ATTACHMENT_MAX_BYTES) throw feedbackAttachmentTooLarge();
  return { fileName: buildAttachmentFileName(raw.file_name, mime), mimeType: mime, sizeBytes: size, extension: ATTACHMENT_EXTENSIONS[mime] };
}

/**
 * Sınırlar (K11): adet <= 4, dosya <= 5 MB, toplam <= 20 MB. Hepsi 400. Sıra: adet -> dosya başı -> toplam (en özgün hata önce).
 * @returns {Array<{ fileName: string, mimeType: string, sizeBytes: number }>}
 */
export function parseDeclaredAttachments(value) {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw invalidFeedbackField('Ek dosya listesi geçersiz.');
  if (value.length > FEEDBACK_MAX_ATTACHMENTS) throw feedbackTooManyAttachments();
  const parsed = value.map(parseDeclaredAttachment);
  const total = parsed.reduce((sum, item) => sum + item.sizeBytes, 0);
  if (total > FEEDBACK_TOTAL_MAX_BYTES) throw feedbackTotalTooLarge();
  return parsed;
}

/**
 * POST /app/feedback gövdesi -> doğrulanmış girdi. `site_code` isteğe bağlı: verilirse pozitif tam sayı olmalı (yetki servis katmanında denetlenir).
 */
export function parseFeedbackInput(body) {
  if (!isPlainObject(body)) throw invalidFeedbackField('İstek gövdesi geçersiz.');
  const message = normalizeFeedbackMessage(body.message);
  const screenName = normalizeScreenName(body.screen_name);
  const screenRoute = normalizeScreenRoute(body.screen_route);
  let siteCode = null;
  if (body.site_code !== undefined && body.site_code !== null && body.site_code !== '') {
    siteCode = parsePositiveId(body.site_code);
    if (siteCode === null) throw invalidFeedbackField('Site kodu geçersiz.');
  }
  const appVersion = optionalShortText(body.app_version, FEEDBACK_APP_VERSION_MAX, 'Uygulama sürümü');
  let platform = optionalShortText(body.platform, FEEDBACK_PLATFORM_MAX, 'Platform');
  if (platform !== null) {
    platform = platform.toLowerCase();
    if (!FEEDBACK_PLATFORMS.includes(platform)) platform = null;
  }
  const attachments = parseDeclaredAttachments(body.attachments);
  return { message, screenName, screenRoute, siteCode, appVersion, platform, attachments };
}

/** :id / :attId yol parametresi -> pozitif tam sayı ya da 404. */
export function parseFeedbackId(raw) {
  const id = parsePositiveId(raw);
  if (id === null) throw feedbackNotFound();
  return id;
}
export function parseFeedbackAttachmentId(raw) {
  const id = parsePositiveId(raw);
  if (id === null) throw feedbackAttachmentNotFound();
  return id;
}

/** Liste sorgusu: limit (1..100, varsayılan 30) ve cursor (önceki sayfanın son kimliği). */
export function parseListQuery(query) {
  const rawLimit = query?.limit;
  let limit = FEEDBACK_LIST_DEFAULT_LIMIT;
  if (rawLimit !== undefined && rawLimit !== '') {
    const parsed = parsePositiveId(String(rawLimit));
    if (parsed === null || parsed > FEEDBACK_LIST_MAX_LIMIT) throw invalidFeedbackField(`limit 1 ile ${FEEDBACK_LIST_MAX_LIMIT} arasında olmalıdır.`);
    limit = parsed;
  }
  let cursor = null;
  if (query?.cursor !== undefined && query.cursor !== '') {
    cursor = parsePositiveId(String(query.cursor));
    if (cursor === null) throw invalidFeedbackField('cursor geçersiz.');
  }
  let siteCode = null;
  if (query?.site_code !== undefined && query.site_code !== '') {
    siteCode = parsePositiveId(String(query.site_code));
    if (siteCode === null) throw invalidFeedbackField('site_code geçersiz.');
  }
  return { limit, cursor, siteCode };
}

// --- Yanıt eşleyicileri ------------------------------------------------------------------------------------------

const num = (value) => (value === null || value === undefined ? null : Number(value));

export function mapFeedbackAttachment(row) {
  return {
    id: num(row.id),
    feedback_id: num(row.feedback_id),
    file_name: row.file_name,
    mime_type: row.mime_type,
    size_bytes: num(row.size_bytes),
    status: row.status,
  };
}

/**
 * Geri bildirim satırı -> yanıt şekli. Gönderen adı: silinmiş / kaldırılmış hesap "Silinmiş Kullanıcı". `attachments`: eşlenmiş ekler.
 * `includeSite`: platform sahibi listesinde site adı da döner.
 */
export function mapFeedback(row, attachments = [], { includeSite = false } = {}) {
  const mapped = {
    id: num(row.id),
    site_code: num(row.site_code),
    user_code: num(row.user_code),
    user_name: row.user_name ?? DELETED_USER_NAME,
    role: row.role,
    screen_name: row.screen_name,
    screen_route: row.screen_route,
    message: row.message,
    app_version: row.app_version ?? null,
    platform: row.platform ?? null,
    created_at: toIso(row.created_at),
    attachments,
  };
  if (includeSite) mapped.site_name = row.site_name ?? null;
  return mapped;
}
