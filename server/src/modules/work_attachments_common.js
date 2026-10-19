// İş Takibi fotoğraf ekleri (047): sabitler, sınırlar, hata üreticileri, girdi doğrulayıcıları, içerik imzası kararı ve yanıt eşleyicileri. Saf: DB/ağ bağımsız.
//
// Sözleşme: docs/PLATFORM_IS_TAKIBI.md "Fotoğraf ekleri". Hata gövdesi { error, code } (PlatformError). Tür kararı İÇERİK İMZASIYLA verilir (belgeler modülüyle aynı
// ilke): istemcinin bildirdiği mime_type yalnız imzayla UYUŞMASI gereken bir beyandır; dosya adı yola hiçbir biçimde girmez (storage_key sunucuya aittir).
// Günlüğe ve audit `details` alanına dosya adı YAZILMAZ (yalnız kimlik, tür, boyut, durum).

import { PlatformError } from './errors.js';
import { newErrorId } from '../middlewares/error_handler.js';
import { DELETED_USER_NAME } from './account_common.js';
import { parsePositiveId, toIso } from './people_common.js';
import { sanitizeFileName } from './document_validation.js';

/** İzinli görüntü türleri (DB CHECK ile aynı küme). */
export const ATTACHMENT_MIMES = Object.freeze(['image/jpeg', 'image/png', 'image/webp']);
/** Kanonik uzantı: dosya adı istemcinin uzantısına DEĞİL, bildirilen (ve imzayla doğrulanan) türe göre tamamlanır. */
export const ATTACHMENT_EXTENSIONS = Object.freeze({ 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' });
/** Tek fotoğraf üst sınırı (5 MB; DB CHECK ile aynı). */
export const ATTACHMENT_MAX_BYTES = 5242880;
/** Talep başına en çok fotoğraf (ready + uploading, tüm yükleyenler birlikte). */
export const MAX_ATTACHMENTS_PER_ITEM = 4;
/** Kullanıcı başına saatte en çok fotoğraf kaydı (POST; siteler arası toplam). */
export const ATTACHMENTS_PER_USER_PER_HOUR = 30;
export const ATTACHMENT_FILE_NAME_MAX = 160;
/** `uploading` satırın bakım işince silinmeden önceki ömrü (dakika); süresi dolan satıra PUT 410. */
export const ATTACHMENT_UPLOAD_TTL_MINUTES = 120;
/** Depo kökü altındaki alt ağaç (belgelerin `sites/` ağacından AYRI: belge yetim süpürmesi bu dosyalara dokunmaz). */
export const ATTACHMENT_SUBTREE = 'work_attachments';
/** Süreç genelinde eşzamanlı fotoğraf yükleme / indirme sınırı. */
export const ATTACHMENT_UPLOAD_CONCURRENCY = 8;
export const ATTACHMENT_DOWNLOAD_CONCURRENCY = 32;
/** Sakin görünümünde yönetim tarafının (yönetici / görevli / süper) eklediği fotoğrafın yükleyen adı: kişi adı sakine SIZDIRILMAZ (WA-SEC-1). */
export const MANAGEMENT_UPLOADER_LABEL = 'Yönetim';
/**
 * Sakin kotasının KAYAN penceresi (gün; R2-2): yalnız son 30 günde açılmış kayıtlar sayılır. Kapanan talepteki fotoğrafını silemeyen sakin bu yüzden kalıcı
 * olarak kilitlenmez; toplam disk üst sınırı site kotasıdır.
 */
export const ATTACHMENT_USER_QUOTA_WINDOW_DAYS = 30;

const MB = 1048576;
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
    console.warn(`[work_tracking] ${name} gecersiz ya da sinir disi; varsayilan (${fallback}) kullaniliyor.`);
  }
  return fallback;
}

/**
 * Ortam değişkenleriyle ayarlanabilir fotoğraf sınırları (her çağrıda okunur; geçersiz değer varsayılana döner, uyarı yalnız ad ile).
 *  WORK_ATTACHMENTS_USER_QUOTA_MB (200): YALNIZ SAKİN; bir sakinin TEK sitede SON 30 GÜNDE (ATTACHMENT_USER_QUOTA_WINDOW_DAYS) açtığı fotoğrafların toplam
 *    boyutu (ready + süresi dolmamış uploading). Görevli / yönetici / süper bu kotaya tabi DEĞİL (R2-2).
 *  WORK_ATTACHMENTS_SITE_QUOTA_MB (10240): bir sitenin tüm fotoğraflarının toplam boyutu (herkes için; pencere yok).
 *  WORK_ATTACHMENTS_ORPHAN_MIN_AGE_DAYS (30): DB'de satırı olmayan fotoğraf dosyası bakım işince bu yaştan SONRA silinir (karantina yok; yaş güvenlik payıdır).
 */
export function attachmentLimits(env = process.env) {
  return {
    userQuotaBytes: intEnv(env, 'WORK_ATTACHMENTS_USER_QUOTA_MB', 200, { min: 1, max: 1048576 }) * MB,
    siteQuotaBytes: intEnv(env, 'WORK_ATTACHMENTS_SITE_QUOTA_MB', 10240, { min: 1, max: 1048576 }) * MB,
    orphanMinAgeDays: intEnv(env, 'WORK_ATTACHMENTS_ORPHAN_MIN_AGE_DAYS', 30, { min: 1, max: 3650 }),
  };
}

const formatMb = (bytes) => {
  const mb = Number(bytes) / MB;
  return Number.isInteger(mb) ? String(mb) : mb.toFixed(1).replace('.', ',');
};

// --- Hatalar -----------------------------------------------------------------------------------------------------

export const attachmentNotFound = () => new PlatformError(404, 'WORK_ATTACHMENT_NOT_FOUND', 'Fotoğraf bulunamadı ya da erişiminiz yok.');
export const attachmentLimitReached = () =>
  new PlatformError(409, 'LIMIT_REACHED', `Bir talebe en fazla ${MAX_ATTACHMENTS_PER_ITEM} fotoğraf eklenebilir.`, { attachment_limit: MAX_ATTACHMENTS_PER_ITEM });
/** Kapalı (kapandi / iptal) talep: fotoğraf eklenemez; silme yalnız yönetici / süper içindir (moderasyon / KVKK, WA-SEC-2). */
export const attachmentInvalidState = () =>
  new PlatformError(409, 'INVALID_STATE', 'Kapatılmış ya da iptal edilmiş talebe fotoğraf eklenemez; bu talepteki fotoğrafları yalnız yönetici silebilir.');
/**
 * Fotoğraf alanı kotası doldu (WA-SEC-3, R2-2). `quota`: 'user' (sakinin bu sitede son 30 günde açtıkları; gövdede ayrıca `window_days`) | 'site' (sitenin
 * toplamı); gövdede `quota`, `quota_bytes`, `used_bytes`.
 */
export const attachmentQuotaExceeded = (quota, usedBytes, quotaBytes) =>
  quota === 'user'
    ? new PlatformError(
        409,
        'ATTACHMENT_QUOTA_EXCEEDED',
        `Son ${ATTACHMENT_USER_QUOTA_WINDOW_DAYS} günde bu sitede yükleyebileceğiniz fotoğraf sınırına ulaştınız (en çok ${formatMb(quotaBytes)} MB); daha sonra yeniden deneyin ya da yönetime başvurun.`,
        { quota, quota_bytes: Number(quotaBytes), used_bytes: Number(usedBytes), window_days: ATTACHMENT_USER_QUOTA_WINDOW_DAYS },
      )
    : new PlatformError(409, 'ATTACHMENT_QUOTA_EXCEEDED', 'Sitenin fotoğraf alanı doldu. Yönetimle iletişime geçin.', {
        quota,
        quota_bytes: Number(quotaBytes),
        used_bytes: Number(usedBytes),
      });
export const attachmentHourlyLimitReached = () =>
  new PlatformError(429, 'WORK_ATTACHMENT_RATE_LIMITED', 'Bir saat içinde çok fazla fotoğraf eklediniz. Biraz sonra tekrar deneyin.', {
    hourly_limit: ATTACHMENTS_PER_USER_PER_HOUR,
    retry_after_seconds: 3600,
  });
export const attachmentTooLarge = () =>
  new PlatformError(413, 'ATTACHMENT_TOO_LARGE', 'Fotoğraf çok büyük. En fazla 5 MB yükleyebilirsiniz.', { max_bytes: ATTACHMENT_MAX_BYTES });
export const attachmentTypeNotAllowed = () =>
  new PlatformError(415, 'ATTACHMENT_TYPE_NOT_ALLOWED', 'Bu dosya türü desteklenmiyor. JPEG, PNG veya WebP fotoğraf yükleyin.');
export const attachmentContentMismatch = () =>
  new PlatformError(415, 'ATTACHMENT_CONTENT_MISMATCH', 'Fotoğraf içeriği bildirilen türle uyuşmuyor ya da bozuk.');
export const attachmentSizeMismatch = () =>
  new PlatformError(400, 'ATTACHMENT_SIZE_MISMATCH', 'Gönderilen fotoğraf boyutu bildirilen boyutla uyuşmuyor.');
export const attachmentStorageUnavailable = () =>
  new PlatformError(503, 'ATTACHMENT_STORAGE_UNAVAILABLE', 'Fotoğraf yükleme şu an kullanılamıyor.');
export const attachmentForbidden = () => new PlatformError(403, 'FORBIDDEN_ROLE', 'Bu fotoğrafı yalnız ekleyen kişi ya da yönetici silebilir.');
export const invalidAttachmentField = (message) => new PlatformError(400, 'INVALID_BODY', message);

/** Dosya kaybı (DB'de kayıt var, diskte yok): ERROR günlüğü (kimlikler; ad yok) + 500 ATTACHMENT_FILE_MISSING + errorId. */
export function attachmentFileMissing(context) {
  const errorId = newErrorId();
  // eslint-disable-next-line no-console
  console.error(`[work_tracking] FOTOGRAF DOSYASI KAYIP (errorId=${errorId}) ${context}`);
  return new PlatformError(500, 'ATTACHMENT_FILE_MISSING', 'Fotoğraf dosyasına ulaşılamadı. Yöneticiyle iletişime geçin.', { errorId });
}

// --- Girdi -------------------------------------------------------------------------------------------------------

const isPlainObject = (value) => Boolean(value) && typeof value === 'object' && !Array.isArray(value);

export function normalizeAttachmentMime(value) {
  const mime = typeof value === 'string' ? value.trim().toLowerCase() : '';
  if (!ATTACHMENT_MIMES.includes(mime)) {
    throw attachmentTypeNotAllowed();
  }
  return mime;
}

/**
 * Görünen dosya adı: belgelerle AYNI temizlik (yol parçaları atılır, görünmez / kontrol karakterleri atılır, 100 kod noktası); uzantı istemciden DEĞİL
 * bildirilen türden gelir (`foto.png` + image/jpeg -> `foto.jpg`; imza uyuşmazlığı PUT'ta 415). Boş ad -> `fotograf`.
 */
export function buildAttachmentFileName(rawName, mime) {
  const { base } = sanitizeFileName(rawName);
  const stem = base === 'belge' ? 'fotograf' : base;
  const name = `${stem}.${ATTACHMENT_EXTENSIONS[mime]}`;
  return Array.from(name).length > ATTACHMENT_FILE_NAME_MAX ? Array.from(name).slice(0, ATTACHMENT_FILE_NAME_MAX).join('') : name;
}

/** POST .../attachments gövdesi { file_name, mime_type, size_bytes } -> { fileName, mimeType, sizeBytes }. */
export function parseAttachmentInput(body) {
  if (!isPlainObject(body)) throw invalidAttachmentField('İstek gövdesi geçersiz.');
  if (typeof body.file_name !== 'string' || body.file_name.trim() === '') throw invalidAttachmentField('Dosya adı zorunludur.');
  if (body.file_name.length > 1000) throw invalidAttachmentField('Dosya adı çok uzun.');
  const mimeType = normalizeAttachmentMime(body.mime_type);
  const size = body.size_bytes;
  if (typeof size !== 'number' || !Number.isSafeInteger(size) || size < 0) throw invalidAttachmentField('Dosya boyutu geçersiz.');
  if (size === 0) throw invalidAttachmentField('Boş dosya yüklenemez.');
  if (size > ATTACHMENT_MAX_BYTES) throw attachmentTooLarge();
  return { fileName: buildAttachmentFileName(body.file_name, mimeType), mimeType, sizeBytes: size };
}

/** :attId yol parametresi -> pozitif tam sayı ya da 404. */
export function parseAttachmentId(raw) {
  const id = parsePositiveId(raw);
  if (id === null) throw attachmentNotFound();
  return id;
}

// --- İçerik imzası -------------------------------------------------------------------------------------------------

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/** İlk baytlardan görüntü türü: JPEG (FF D8 FF), PNG (8 baytlık imza), WebP (RIFF....WEBP) ya da null (HTML / SVG / GIF / PDF / çalıştırılabilir ... hepsi null). */
export function detectImageMime(head) {
  if (!Buffer.isBuffer(head)) return null;
  if (head.length >= 3 && head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff) return 'image/jpeg';
  if (head.length >= 8 && head.subarray(0, 8).equals(PNG_SIGNATURE)) return 'image/png';
  if (head.length >= 12 && head.latin1Slice(0, 4) === 'RIFF' && head.latin1Slice(8, 12) === 'WEBP') return 'image/webp';
  return null;
}

/** Akış sırasında ERKEN karar: tanınmayan -> 415 ATTACHMENT_TYPE_NOT_ALLOWED; bildirilenle uyuşmayan -> 415 ATTACHMENT_CONTENT_MISMATCH. */
export function assertImageHead(head, expectedMime) {
  const detected = detectImageMime(head);
  if (detected === null) throw attachmentTypeNotAllowed();
  if (detected !== expectedMime) throw attachmentContentMismatch();
  return detected;
}

// --- Piksel boyutu (açılma bombası koruması) -------------------------------------------------------------------------
// Sunucu görüntüyü ÇÖZMEZ; yalnız başlıktaki genişlik / yükseklik okunur. Küçük dosyada dev çözünürlük (ör. 60000x60000 tek renk PNG) istemcide (uygulama /
// tarayıcı) çözülürken belleği tüketir: kenar 12.000 pikseli ya da toplam 40 milyon pikseli aşan fotoğraf 415 ATTACHMENT_DIMENSIONS_TOO_LARGE ile reddedilir.

export const MAX_IMAGE_SIDE = 12000;
export const MAX_IMAGE_PIXELS = 40000000;

export const attachmentDimensionsTooLarge = (width, height) =>
  new PlatformError(
    415,
    'ATTACHMENT_DIMENSIONS_TOO_LARGE',
    'Fotoğrafın çözünürlüğü çok yüksek (bir kenar en çok 12.000 piksel, toplam en çok 40 milyon piksel olabilir). Fotoğrafı küçültüp yeniden deneyin.',
    { width: Number(width), height: Number(height), max_side: MAX_IMAGE_SIDE, max_pixels: MAX_IMAGE_PIXELS },
  );

/** Boyut sınırı: kenar > 12.000 ya da genişlik x yükseklik > 40.000.000 -> 415 ATTACHMENT_DIMENSIONS_TOO_LARGE. */
export function assertImageDimensions({ width, height }) {
  if (width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE || width * height > MAX_IMAGE_PIXELS) {
    throw attachmentDimensionsTooLarge(width, height);
  }
  return { width, height };
}

/** JPEG kare başlangıcı (SOFn) işaretleri: C0..CF, DHT (C4), JPG (C8), DAC (CC) HARİÇ. */
const JPEG_SOF_MARKERS = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);
/** Uzunluk alanı olmayan bağımsız işaretler: TEM (01), RST0..7 (D0..D7). */
const JPEG_STANDALONE = new Set([0x01, 0xd0, 0xd1, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7]);
const JPEG_MAX_SEGMENTS = 1024;

function dimensionsOrMismatch(width, height) {
  if (!Number.isFinite(width) || !Number.isFinite(height) || width < 1 || height < 1) {
    throw attachmentContentMismatch();
  }
  return { width, height };
}

/**
 * Görüntünün piksel boyutları, YALNIZ başlıklardan (çözümleme yok). `readAt(position, length)` -> Buffer (dosya sonunda kısa olabilir); `size` dosya boyutu.
 *  - PNG: IHDR (16: genişlik, 20: yükseklik; büyük uçlu 32 bit)
 *  - WebP: 'VP8 ' (26 / 28: 14 bit küçük uçlu), 'VP8L' (21: 14 + 14 bit, değer + 1), 'VP8X' (24 / 27: 24 bit küçük uçlu, değer + 1)
 *  - JPEG: işaret dizisi taranır (en çok 1024 bölüt), ilk SOFn bölütünde yükseklik / genişlik; SOS / EOI SOFn'den önce gelirse bozuk sayılır
 * Biçim bozuksa ya da boyut okunamıyorsa (0 dahil) 415 ATTACHMENT_CONTENT_MISMATCH.
 * @returns {Promise<{ width: number, height: number }>}
 */
export async function readImageDimensions(mime, readAt, size) {
  if (mime === 'image/png') {
    const head = await readAt(0, 24);
    if (head.length < 24 || head.latin1Slice(12, 16) !== 'IHDR') throw attachmentContentMismatch();
    return dimensionsOrMismatch(head.readUInt32BE(16), head.readUInt32BE(20));
  }
  if (mime === 'image/webp') {
    const head = await readAt(0, 30);
    if (head.length < 30 || head.latin1Slice(0, 4) !== 'RIFF' || head.latin1Slice(8, 12) !== 'WEBP') throw attachmentContentMismatch();
    const chunk = head.latin1Slice(12, 16);
    if (chunk === 'VP8 ') {
      if (head[23] !== 0x9d || head[24] !== 0x01 || head[25] !== 0x2a) throw attachmentContentMismatch();
      return dimensionsOrMismatch(head.readUInt16LE(26) & 0x3fff, head.readUInt16LE(28) & 0x3fff);
    }
    if (chunk === 'VP8L') {
      if (head[20] !== 0x2f) throw attachmentContentMismatch();
      const bits = head.readUInt32LE(21);
      return dimensionsOrMismatch((bits & 0x3fff) + 1, ((bits >>> 14) & 0x3fff) + 1);
    }
    if (chunk === 'VP8X') {
      return dimensionsOrMismatch(head.readUIntLE(24, 3) + 1, head.readUIntLE(27, 3) + 1);
    }
    throw attachmentContentMismatch();
  }
  if (mime === 'image/jpeg') {
    let position = 2; // SOI (FF D8) sonrası
    for (let segment = 0; segment < JPEG_MAX_SEGMENTS && position + 2 <= size; segment += 1) {
      const header = await readAt(position, 4);
      if (header.length < 2 || header[0] !== 0xff) throw attachmentContentMismatch();
      const marker = header[1];
      if (marker === 0xff) {
        position += 1; // dolgu baytı
        continue;
      }
      if (JPEG_STANDALONE.has(marker)) {
        position += 2;
        continue;
      }
      if (marker === 0xd9 || marker === 0xda || marker === 0xd8) throw attachmentContentMismatch(); // SOFn'den önce EOI / SOS / ikinci SOI
      if (header.length < 4) throw attachmentContentMismatch();
      const length = header.readUInt16BE(2);
      if (length < 2) throw attachmentContentMismatch();
      if (JPEG_SOF_MARKERS.has(marker)) {
        const sof = await readAt(position + 4, 5); // kesinlik (1), yükseklik (2), genişlik (2)
        if (sof.length < 5 || length < 7) throw attachmentContentMismatch();
        return dimensionsOrMismatch(sof.readUInt16BE(3), sof.readUInt16BE(1));
      }
      position += 2 + length;
    }
    throw attachmentContentMismatch();
  }
  throw attachmentTypeNotAllowed();
}

// --- Yanıt eşleyicileri -----------------------------------------------------------------------------------------

const num = (value) => (value === null || value === undefined ? null : Number(value));

/**
 * Ek satırı -> yanıt şekli. `userCode`: çağıran (uploaded_by_me). `uploaded_by_kind`: yükleyen talebi AÇAN kişiyse 'resident', değilse 'management'
 * (satırdaki `uploaded_by_resident`, work_attachments_read.ATTACHMENT_COLUMNS). Yönetim görünümü (yönetici / görevli / kurul / süper): gerçek ad; silinmiş /
 * kaldırılmış yükleyen "Silinmiş Kullanıcı". SAKİN görünümü (`residentView`, WA-SEC-1): yalnız kendi eklediği fotoğrafta gerçek ad; diğer her fotoğrafta
 * yükleyen adı 'Yönetim' (yönetici / görevli adı sakine sızmaz; null'a düşüp "Silinmiş Kullanıcı" da yazılmaz).
 */
export function mapAttachment(row, { userCode = null, residentView = false } = {}) {
  const uploader = row.uploaded_by === null || row.uploaded_by === undefined ? null : Number(row.uploaded_by);
  const mine = uploader !== null && userCode !== null && uploader === Number(userCode);
  const name = residentView && !mine ? MANAGEMENT_UPLOADER_LABEL : row.uploaded_by_name ?? DELETED_USER_NAME;
  return {
    id: num(row.id),
    work_item_id: num(row.work_item_id),
    file_name: row.file_name,
    mime_type: row.mime_type,
    size_bytes: num(row.size_bytes),
    status: row.status,
    uploaded_by_kind: row.uploaded_by_resident === true ? 'resident' : 'management',
    uploaded_by_name: name,
    uploaded_by_me: mine,
    created_at: toIso(row.created_at),
    ready_at: toIso(row.ready_at),
  };
}

/**
 * Hesap silme önizlemesi: yüklenen fotoğraflar SİLİNMEZ (taleple birlikte siteye aittir); yükleyen adı "Silinmiş Kullanıcı" görünür.
 * @param {number} count yüklediği fotoğraf sayısı (0 ise satır çıkmaz)
 */
export function attachmentsKeepNote(count) {
  return `İş takibi taleplerine eklediğiniz fotoğraflar (${Number(count)}) taleple birlikte site yönetiminde kalır; yükleyen adı "Silinmiş Kullanıcı" görünür.`;
}
