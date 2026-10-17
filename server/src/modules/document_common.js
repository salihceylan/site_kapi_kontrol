// Belgeler (Faz 3b-A, dosya deposu) ortak sabitleri, sınırları, hata üreticileri, girdi doğrulayıcıları ve yanıt eşleyicileri. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_BELGELER.md Bölüm A. Hata gövdesi { error, code } (PlatformError); INVALID_BODY mesajları alan adıyla DEĞİL Türkçe
// etiketle yazılır. Kullanıcı metni düz yazıdır. Günlüğe ve audit `details` alanına başlık / açıklama / dosya adı / not YAZILMAZ.

import { PlatformError } from './errors.js';
import { parseTargetInput } from './announcement_common.js';
import { parsePositiveId, toIso } from './people_common.js';

export const DOCUMENTS_MODULE = 'documents';

export const CATEGORIES = Object.freeze(['regulation', 'minutes', 'contract', 'notice', 'other']);
export const AUDIENCES = Object.freeze(['residents', 'board', 'managers']);
export const DOCUMENT_STATUSES = Object.freeze(['pending', 'active', 'deleted']);
export const LIST_STATUS_FILTERS = Object.freeze(['active', 'deleted', 'all']);

export const TITLE_MAX = 120;
export const DESCRIPTION_MAX = 1000;
export const NOTE_MAX = 200;
export const DISPLAY_NAME_MAX = 120;
export const LIST_DEFAULT_LIMIT = 30;
export const LIST_MAX_LIMIT = 100;
/** Bir yüklemenin (uploading sürümü / pending belge) bakım işi tarafından silinmeden önceki ömrü. */
export const UPLOAD_TTL_MINUTES = 120;
/** Belge başına en çok sürüm (ready + uploading). */
export const MAX_VERSIONS_PER_DOCUMENT = 20;
/** Kullanıcı başına en çok bekleyen (uploading) sürüm. */
export const MAX_PENDING_PER_USER = 5;
/** Eşzamanlı indirme sınırı (süreç genelinde). */
export const DOWNLOAD_CONCURRENCY = 32;
/** Yüklemede istemcinin bildirebileceği en büyük dosya sınırı (env bunu AŞAMAZ). */
export const MAX_FILE_BYTES_CEILING = 26214400;

export const IDEMPOTENCY_KEY_PATTERN = /^[A-Za-z0-9_.:-]{8,64}$/;

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
    console.warn(`[documents] ${name} gecersiz ya da sinir disi; varsayilan (${fallback}) kullaniliyor.`);
  }
  return fallback;
}

/**
 * Ortam değişkenleriyle ayarlanabilir sınırlar (geçersiz değer varsayılana döner; uyarı yalnız ad ile, değer yazılmaz).
 *  DOCUMENTS_MAX_FILE_BYTES (10 MiB; 25 MiB üstü YOK SAYILIR), DOCUMENTS_SITE_QUOTA_BYTES (200 MiB), DOCUMENTS_MIN_FREE_BYTES (2 GiB),
 *  DOCUMENTS_MAX_PER_SITE (2000), DOCUMENTS_ALLOW_OFFICE (1), DOCUMENTS_RETENTION_DAYS (30), DOCUMENTS_UPLOAD_CONCURRENCY (8),
 *  DOCUMENTS_ORPHAN_QUARANTINE_DAYS (14; yetim dosyalar silinmeden önce bu kadar gün karantinada bekler).
 */
export function documentLimits(env = process.env) {
  const officeRaw = String(env?.DOCUMENTS_ALLOW_OFFICE ?? '').trim().toLowerCase();
  return {
    maxFileBytes: intEnv(env, 'DOCUMENTS_MAX_FILE_BYTES', 10485760, { min: 1024, max: MAX_FILE_BYTES_CEILING }),
    siteQuotaBytes: intEnv(env, 'DOCUMENTS_SITE_QUOTA_BYTES', 209715200, { min: 1048576 }),
    minFreeBytes: intEnv(env, 'DOCUMENTS_MIN_FREE_BYTES', 2147483648, { min: 0 }),
    maxPerSite: intEnv(env, 'DOCUMENTS_MAX_PER_SITE', 2000, { min: 1 }),
    allowOffice: !['0', 'false', 'no', 'off'].includes(officeRaw),
    retentionDays: intEnv(env, 'DOCUMENTS_RETENTION_DAYS', 30, { min: 1, max: 365 }),
    uploadConcurrency: intEnv(env, 'DOCUMENTS_UPLOAD_CONCURRENCY', 8, { min: 1, max: 64 }),
    orphanQuarantineDays: intEnv(env, 'DOCUMENTS_ORPHAN_QUARANTINE_DAYS', 14, { min: 1, max: 365 }),
    downloadConcurrency: DOWNLOAD_CONCURRENCY,
    maxVersions: MAX_VERSIONS_PER_DOCUMENT,
    pendingPerUser: MAX_PENDING_PER_USER,
    uploadTtlMinutes: UPLOAD_TTL_MINUTES,
  };
}

const formatMb = (bytes) => {
  const mb = Number(bytes) / 1048576;
  return Number.isInteger(mb) ? String(mb) : mb.toFixed(1).replace('.', ',');
};

// --- Hatalar -----------------------------------------------------------------------------------------------------

export const documentNotFound = () => new PlatformError(404, 'DOCUMENT_NOT_FOUND', 'Belge bulunamadı ya da erişiminiz yok.');
export const versionNotFound = () => new PlatformError(404, 'DOCUMENT_VERSION_NOT_FOUND', 'Belge sürümü bulunamadı.');
export const siteNotFound = () => new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
export const moduleDisabled = () =>
  new PlatformError(403, 'MODULE_DISABLED', 'Belgeler modülü kapalı.', { module: DOCUMENTS_MODULE });
export const invalidField = (message) => new PlatformError(400, 'INVALID_BODY', message);
export const invalidQuery = () => new PlatformError(400, 'INVALID_QUERY', 'Geçersiz sorgu parametresi.');
export const invalidState = (message) =>
  new PlatformError(409, 'INVALID_STATE', message ?? 'Bu işlem belgenin mevcut durumunda yapılamaz.');
export const confirmRequired = () => new PlatformError(400, 'CONFIRM_REQUIRED', 'Bu işlem için onay gerekli.');
export const accountDeleted = () => new PlatformError(401, 'ACCOUNT_DELETED', 'Bu hesap silinmiş.');
export const emptyFile = () => new PlatformError(400, 'DOCUMENT_EMPTY', 'Boş dosya yüklenemez.');
export const sizeMismatch = () =>
  new PlatformError(400, 'DOCUMENT_SIZE_MISMATCH', 'Gönderilen dosya boyutu bildirilen boyutla uyuşmuyor.');
export const lengthRequired = () => new PlatformError(411, 'LENGTH_REQUIRED', 'İçerik uzunluğu (Content-Length) zorunludur.');
export const tooLarge = (maxBytes) =>
  new PlatformError(413, 'DOCUMENT_TOO_LARGE', `Dosya çok büyük. En fazla ${formatMb(maxBytes)} MB yükleyebilirsiniz.`, { max_bytes: Number(maxBytes) });
export const typeNotAllowed = () =>
  new PlatformError(415, 'DOCUMENT_TYPE_NOT_ALLOWED', 'Bu dosya türü desteklenmiyor. PDF, JPG, PNG, DOCX veya XLSX yükleyin.');
export const contentMismatch = () =>
  new PlatformError(415, 'DOCUMENT_CONTENT_MISMATCH', 'Dosya içeriği uzantısıyla uyuşmuyor ya da bozuk.');
/** Etkin içerik nedenine göre DOĞRU ileti (R16 P2-1: gömülü nesne "betik, makro" diye anılmasın). Makine kodu hep DOCUMENT_ACTIVE_CONTENT. */
const ACTIVE_CONTENT_MESSAGES = Object.freeze({
  script: 'Etkin içerik (betik) taşıyan dosya yüklenemez.',
  macro: 'Makro içeren belge yüklenemez. Makrosuz kaydedip yeniden yükleyin.',
  embedded: 'Gömülü nesne (OLE / ActiveX / iliştirilmiş dosya) içeren belge yüklenemez. Nesneyi kaldırıp yeniden kaydedin.',
  external: 'Uzak şablon ya da dış kaynağa bağlı nesne içeren belge yüklenemez. Bağlantıyı kaldırıp yeniden kaydedin.',
  executable: 'Çalıştırılabilir dosya içeren belge yüklenemez.',
});
export const activeContent = (reason = 'script') =>
  new PlatformError(415, 'DOCUMENT_ACTIVE_CONTENT', ACTIVE_CONTENT_MESSAGES[reason] ?? ACTIVE_CONTENT_MESSAGES.script, { reason });
export const invalidContentType = () =>
  new PlatformError(415, 'INVALID_CONTENT_TYPE', 'İçerik türü application/octet-stream olmalıdır.');
export const quotaExceeded = (used, quota) =>
  new PlatformError(
    409,
    'DOCUMENT_QUOTA_EXCEEDED',
    `Site belge alanı doldu (${formatMb(used)} MB / ${formatMb(quota)} MB). Eski belgeleri kalıcı olarak silin.`,
    { used_bytes: Number(used), quota_bytes: Number(quota) },
  );
export const documentLimitReached = (limit) =>
  new PlatformError(409, 'DOCUMENT_LIMIT', `Bir sitede en fazla ${limit} belge tutulabilir. Eski belgeleri kalıcı olarak silin.`, {
    document_limit: Number(limit),
  });
export const versionLimitReached = (limit) =>
  new PlatformError(409, 'DOCUMENT_VERSION_LIMIT', `Bir belgenin en fazla ${limit} sürümü olabilir. Eski sürümleri silin.`);
export const pendingLimitReached = () =>
  new PlatformError(409, 'UPLOAD_PENDING_LIMIT', 'Tamamlanmamış çok sayıda yüklemeniz var. Biraz sonra tekrar deneyin.');
export const documentInUse = (attachments) =>
  new PlatformError(409, 'DOCUMENT_IN_USE', 'Bu belge yayındaki bir duyuruya ekli.', { attachments_count: Number(attachments) });
export const uploadAlreadyCompleted = (extra) =>
  new PlatformError(409, 'UPLOAD_ALREADY_COMPLETED', 'Bu dosyanın yüklemesi zaten tamamlandı.', extra);
export const uploadExpired = () =>
  new PlatformError(410, 'UPLOAD_EXPIRED', 'Yükleme süresi doldu. Yeni bir yükleme başlatın.');
export const uploadInProgress = () =>
  new PlatformError(409, 'UPLOAD_IN_PROGRESS', 'Bu dosya için bir yükleme sürüyor. Birkaç saniye sonra tekrar deneyin.');
export const uploadBusy = () =>
  new PlatformError(503, 'UPLOAD_BUSY', 'Sunucu meşgul. Biraz sonra tekrar deneyin.');
export const downloadBusy = () =>
  new PlatformError(503, 'DOWNLOAD_BUSY', 'Sunucu meşgul. Biraz sonra tekrar deneyin.');
export const storageNotConfigured = () =>
  new PlatformError(503, 'DOCUMENT_STORAGE_NOT_CONFIGURED', 'Belge yükleme şu an kullanılamıyor.');
export const storageFull = () => new PlatformError(503, 'DOCUMENT_STORAGE_FULL', 'Belge yükleme şu an kullanılamıyor.');
export const attachmentNotAllowed = (message) =>
  new PlatformError(
    409,
    'ATTACHMENT_NOT_ALLOWED',
    message ?? 'Yalnızca sakinlere açık ve yayındaki belgeler duyuruya eklenebilir.',
  );

// --- Metin temizliği ---------------------------------------------------------------------------------------------

// Atılan görünmezler: kontrol karakterleri (C0/C1), yön denetimleri (RTLO/LRO/LRI... U+202A-202E, U+2066-2069, U+200E/F, U+061C), sıfır genişlikli
// karakterler (U+200B, U+2060-2064, BOM U+FEFF), yumuşak tire (U+00AD), U+180E. Emoji birleştiricisi (U+200D) ve U+200C korunur (3a ile aynı küme).
const INVISIBLE_CODEPOINTS = [
  0x00ad, 0x061c, 0x180e, 0x200b, 0x200e, 0x200f, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2060, 0x2061, 0x2062, 0x2063, 0x2064, 0x2066, 0x2067,
  0x2068, 0x2069, 0xfeff,
];
export const INVISIBLE_RE = new RegExp(`${/\p{Cc}/u.source}|[${INVISIBLE_CODEPOINTS.map((cp) => String.fromCodePoint(cp)).join('')}]`, 'gu');
const LINE_BREAKS = String.fromCodePoint(0x2028) + String.fromCodePoint(0x2029);
const BREAKS_RE = new RegExp('[' + String.fromCharCode(13, 10, 9) + LINE_BREAKS + ']+', 'g');
const NEWLINES_RE = new RegExp(String.fromCharCode(13) + '?' + String.fromCharCode(10) + '|' + String.fromCharCode(13) + '|[' + LINE_BREAKS + ']', 'g');
const codePointLength = (text) => Array.from(text).length;

/** Tek satırlık metin: satır sonu/sekme boşluğa, görünmezler atılır, boşluklar tekleştirilir. */
function singleLine(value) {
  return value
    .normalize('NFC')
    .replace(BREAKS_RE, ' ')
    .replace(INVISIBLE_RE, '')
    .replace(/\s+/gu, ' ')
    .trim();
}

export function normalizeTitle(value) {
  if (typeof value !== 'string') {
    throw invalidField('Başlık zorunludur.');
  }
  const text = singleLine(value);
  const length = codePointLength(text);
  if (length < 1) {
    throw invalidField('Başlık boş olamaz.');
  }
  if (length > TITLE_MAX) {
    throw invalidField(`Başlık en fazla ${TITLE_MAX} karakter olabilir.`);
  }
  return text;
}

/** Açıklama: isteğe bağlı düz yazı (satır sonları korunur, kontrol karakterleri atılır), en çok 1000 karakter; boş = null. */
export function normalizeDescription(value) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw invalidField('Açıklama geçersiz.');
  }
  const text = value
    .normalize('NFC')
    .replace(NEWLINES_RE, '\n')
    .replace(/\t/g, ' ')
    .replace(INVISIBLE_RE, (match) => (match === '\n' ? '\n' : ''))
    .replace(/[^\S\n]+\n/g, '\n')
    .replace(/\n{4,}/g, '\n\n\n')
    .trim();
  if (text === '') {
    return null;
  }
  if (codePointLength(text) > DESCRIPTION_MAX) {
    throw invalidField(`Açıklama en fazla ${DESCRIPTION_MAX} karakter olabilir.`);
  }
  return text;
}

export function normalizeNote(value) {
  if (value === undefined || value === null) {
    return null;
  }
  if (typeof value !== 'string') {
    throw invalidField('Sürüm notu geçersiz.');
  }
  const text = singleLine(value);
  if (text === '') {
    return null;
  }
  if (codePointLength(text) > NOTE_MAX) {
    throw invalidField(`Sürüm notu en fazla ${NOTE_MAX} karakter olabilir.`);
  }
  return text;
}

export function normalizeCategory(value) {
  if (typeof value !== 'string' || !CATEGORIES.includes(value)) {
    throw invalidField('Kategori geçersiz (yönetmelik, toplantı tutanağı/karar, sözleşme, bilgilendirme veya diğer olmalıdır).');
  }
  return value;
}

export function normalizeAudience(value) {
  if (typeof value !== 'string' || !AUDIENCES.includes(value)) {
    throw invalidField('Belgenin kime açılacağı seçilmelidir (sakinler, yönetim kurulu veya yalnız yöneticiler).');
  }
  return value;
}

export function normalizeIdempotencyKey(value) {
  if (typeof value !== 'string' || !IDEMPOTENCY_KEY_PATTERN.test(value.trim())) {
    throw invalidField('İşlem anahtarı geçersiz.');
  }
  return value.trim();
}

/**
 * Kitle + hedef tutarlılığı. Hedef (blok/daire) yalnız `audience: 'residents'` iken anlamlıdır; verilmezse tüm site. Diğer kitlelerde hedef
 * verilirse (site dışında) 400 INVALID_TARGET.
 * @returns {{ type: string, blockIds: number[], apartmentIds: number[] }}
 */
export function resolveTarget(audience, rawTarget) {
  if (rawTarget === undefined || rawTarget === null) {
    return { type: 'site', blockIds: [], apartmentIds: [] };
  }
  return assertTargetMatchesAudience(audience, parseTargetInput(rawTarget));
}

/** Ayrıştırılmış hedef (type/blockIds/apartmentIds) kitleyle uyumlu mu: sakin dışı kitlede yalnız tüm site. */
export function assertTargetMatchesAudience(audience, target) {
  if (audience !== 'residents' && target.type !== 'site') {
    throw new PlatformError(400, 'INVALID_TARGET', 'Blok veya daire hedefi yalnızca sakinlere açık belgelerde kullanılabilir.');
  }
  return target;
}

const hasOwn = (object, key) => Object.prototype.hasOwnProperty.call(object, key);
const plain = (value) => (value && typeof value === 'object' && !Array.isArray(value) ? value : {});

/** Dosya bildirimi: { name, size, content_type? } -> { name, size, contentType }. */
export function parseFileInput(raw, limits) {
  const file = plain(raw);
  if (typeof file.name !== 'string' || file.name.trim() === '') {
    throw invalidField('Dosya adı zorunludur.');
  }
  if (file.name.length > 1000) {
    throw invalidField('Dosya adı çok uzun.');
  }
  const size = file.size;
  if (typeof size !== 'number' || !Number.isSafeInteger(size) || size < 0) {
    throw invalidField('Dosya boyutu geçersiz.');
  }
  if (size === 0) {
    throw emptyFile();
  }
  if (size > limits.maxFileBytes) {
    throw tooLarge(limits.maxFileBytes);
  }
  const contentType = typeof file.content_type === 'string' ? file.content_type.trim().toLowerCase().slice(0, 200) : null;
  return { name: file.name, size, contentType };
}

/** POST /documents gövdesi. */
export function parseCreateInput(body, limits) {
  const input = plain(body);
  const audience = normalizeAudience(input.audience);
  return {
    title: normalizeTitle(input.title),
    description: normalizeDescription(input.description),
    category: normalizeCategory(input.category),
    audience,
    target: resolveTarget(audience, input.target),
    file: parseFileInput(input.file, limits),
    note: normalizeNote(input.note),
    idempotencyKey: normalizeIdempotencyKey(input.idempotency_key),
  };
}

/** POST /documents/:id/versions gövdesi. */
export function parseVersionInput(body, limits) {
  const input = plain(body);
  return { file: parseFileInput(input.file, limits), note: normalizeNote(input.note) };
}

export const PATCH_KEYS = Object.freeze(['title', 'description', 'category', 'audience', 'target']);

/** PATCH gövdesi -> yalnız gönderilen alanlar (`target` çözümü audience ile birlikte serviste yapılır). */
export function parsePatchInput(body) {
  const input = plain(body);
  const keys = PATCH_KEYS.filter((key) => hasOwn(input, key) && input[key] !== undefined);
  if (keys.length === 0) {
    throw invalidField('Güncellenecek bir alan gönderilmedi.');
  }
  const patch = { keys };
  if (keys.includes('title')) patch.title = normalizeTitle(input.title);
  if (keys.includes('description')) patch.description = normalizeDescription(input.description);
  if (keys.includes('category')) patch.category = normalizeCategory(input.category);
  if (keys.includes('audience')) patch.audience = normalizeAudience(input.audience);
  if (keys.includes('target')) {
    if (input.target === null) {
      throw invalidField('Hedef bilgisi geçersiz.');
    }
    patch.target = parseTargetInput(input.target);
  }
  patch.confirm = input.confirm === true;
  return patch;
}

function parseSearch(value) {
  if (value === undefined || value === null) {
    return null;
  }
  const text = typeof value === 'string' ? value.trim() : '';
  return text === '' ? null : Array.from(text).slice(0, 100).join('');
}

function parsePage(query, { defaultLimit, maxLimit }) {
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

function enumQuery(value, allowed) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return null;
  }
  if (typeof value !== 'string' || !allowed.includes(value.trim())) {
    throw invalidQuery();
  }
  return value.trim();
}

/** Yönetici listesi sorgusu: category, status (varsayılan active), audience, q, limit (1-100, 30), offset. */
export function parseListQuery(query = {}) {
  return {
    category: enumQuery(query.category, CATEGORIES),
    status: enumQuery(query.status, LIST_STATUS_FILTERS) ?? 'active',
    audience: enumQuery(query.audience, AUDIENCES),
    q: parseSearch(query.q),
    ...parsePage(query, { defaultLimit: LIST_DEFAULT_LIMIT, maxLimit: LIST_MAX_LIMIT }),
  };
}

function optionalId(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return null;
  }
  const parsed = parsePositiveId(typeof value === 'string' ? value : String(value));
  if (parsed === null) {
    throw invalidQuery();
  }
  return parsed;
}

/** Sakin listesi sorgusu: site_code, category, q, limit (1-100, 30), before_id. */
export function parseResidentQuery(query = {}) {
  let limit = LIST_DEFAULT_LIMIT;
  if (query.limit !== undefined && query.limit !== null && String(query.limit).trim() !== '') {
    const parsed = Number(query.limit);
    if (Number.isFinite(parsed)) {
      limit = Math.min(LIST_MAX_LIMIT, Math.max(1, Math.floor(parsed)));
    }
  }
  return {
    siteCode: optionalId(query.site_code),
    category: enumQuery(query.category, CATEGORIES),
    q: parseSearch(query.q),
    beforeId: optionalId(query.before_id),
    limit,
  };
}

/** `?version=` indirme sürüm numarası (yok = güncel). */
export function parseVersionQuery(value) {
  if (value === undefined || value === null || String(value).trim() === '') {
    return null;
  }
  const parsed = parsePositiveId(typeof value === 'string' ? value : String(value), 2147483647);
  if (parsed === null) {
    throw versionNotFound();
  }
  return parsed;
}

// --- Yanıt eşleyicileri ------------------------------------------------------------------------------------------

export function idArray(value) {
  return Array.isArray(value) ? value.map((entry) => Number(entry)) : [];
}

const numOrNull = (value) => (value === null || value === undefined ? null : Number(value));

/** DocumentSummary. `canSeeUploader`: kurul yanıtında yükleyen adı YOKTUR (anahtar da yoktur). */
export function mapSummaryRow(row, { canSeeUploader = true } = {}) {
  const summary = {
    id: Number(row.id),
    title: row.title,
    category: row.category,
    audience: row.audience,
    target_type: row.target_type,
    // EKLEMELİ: hedefin okunur gösterimi (blok adları / daire etiketleri; tüm sitede boş) - liste kartı "A, B Blok" yazabilsin
    target_labels: Array.isArray(row.target_labels) ? row.target_labels.map(String) : [],
    status: row.status,
    version_count: Number(row.version_count ?? 0),
    download_count: Number(row.download_count ?? 0),
    current_version:
      row.cv_version_no === null || row.cv_version_no === undefined
        ? null
        : {
            version_no: Number(row.cv_version_no),
            file_name: row.cv_display_name,
            mime_type: row.cv_mime_type,
            size_bytes: Number(row.cv_size_bytes ?? 0),
            completed_at: toIso(row.cv_completed_at),
          },
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
    deleted_at: toIso(row.deleted_at),
    days_until_purge: numOrNull(row.days_until_purge),
  };
  if (canSeeUploader) {
    summary.uploaded_by_name = row.uploaded_by_name ?? null;
  }
  return summary;
}

/** Sakin listesi / ayrıntı satırı. */
export function mapResidentRow(row, { withDescription = false } = {}) {
  const item = {
    id: Number(row.id),
    site_code: Number(row.site_code),
    site_name: row.site_name ?? null,
    title: row.title,
    category: row.category,
  };
  if (withDescription || row.description !== undefined) {
    item.description = row.description ?? null;
  }
  item.file_name = row.cv_display_name;
  item.mime_type = row.cv_mime_type;
  item.size_bytes = Number(row.cv_size_bytes ?? 0);
  item.version_no = Number(row.cv_version_no);
  item.is_updated = Number(row.cv_version_no) > 1;
  item.updated_at = toIso(row.cv_completed_at ?? row.updated_at);
  return item;
}

export function usageBody(row, limits) {
  return {
    used_bytes: Number(row?.used_bytes ?? 0),
    quota_bytes: limits.siteQuotaBytes,
    document_count: Number(row?.document_count ?? 0),
    document_limit: limits.maxPerSite,
  };
}

export { parsePositiveId, toIso };
