// Gider belgesi eki için Belgeler (dosya deposu) dikişi (seam) adaptörü.
//
// Sözleşme: docs/PLATFORM_FINANS_4B.md "Dış bağımlılık arayüzleri" + docs/PLATFORM_BELGELER.md A2-A4, A8. Gider belgesi AYNI depolama boru hattını kullanır;
// bu modül depolama katmanını (`document_storage.js`: storeUpload / openDownload / removeFile) İNCE bir adaptör arkasında sarar. Katman yoksa (henüz yazılmamış ya
// da yüklenemiyorsa) ek uçları 409 DOCUMENTS_NOT_AVAILABLE döner ve gider kaydı ekten bağımsız çalışır.
//
// Beklenen dikiş (S-3b / BELGELER A-S1):
//   storeUpload({ siteCode, req, declaredSize, allowedMimeTypes, maxBytes }) -> { storageKey, mimeType, sizeBytes, sha256 }   (akışı diske yazar; hata PlatformError)
//   openDownload(siteCode, storageKey, sizeBytes) -> Readable | { stream: Readable }
//   removeFile(siteCode, storageKey) -> void   (yalnız yükleme başarısızlığında geri alma için; gider belgeleri KALICI silinmez: KMK m.36)
// İsteğe bağlı: maxFileBytes (sayı).
//
// AÇILIŞ KOŞULU (R10 P1-6): dikiş açılmadan ÖNCE BELGELER bakım işi / yetim dosya süpürmesi `expense_documents.storage_key`'i (ve kota hesabı `expense_documents.size_bytes`'i)
// BİLİNEN dosya saymalıdır (document_versions UNION expense_documents). Süpürme "gider belgelerini topla" DEĞİLDİR: bilmezse ready gider belgelerini yetim sanıp siler.
// KOTA da aynı koşula bağlıdır: BELGELER site kotası (document_service.js: kullanılan alan = document_versions toplamı) `expense_documents.size_bytes`'i SAYMIYOR; kota ve süpürme
// `expense_documents`'i bilmeden dikiş AÇILMAZ (aksi halde gider belgeleri kotayı aşırtır / kota yanlış hesaplanır). Finans tarafı kendi kotasını `siteUsageBytes` ile ayrıca sınar.
// Bu değişiklik BELGELER sahibindedir (document_*.js finans tarafından DEĞİŞTİRİLMEZ); finans tarafı belge satırlarını KALICI tutar (KMK m.36), dosyayı kendisi silmez.

import { randomUUID } from 'node:crypto';
import { documentsNotAvailable } from './finance_4b_common.js';
import { invalidBody } from './finance_common.js';
import { PlatformError } from './errors.js';

export const EXPENSE_DOCUMENT_MIME_TYPES = Object.freeze(['application/pdf', 'image/jpeg', 'image/png']);
export const DEFAULT_MAX_FILE_BYTES = 10485760;
export const HARD_MAX_FILE_BYTES = 26214400;
export const DEFAULT_SITE_QUOTA_BYTES = 209715200;
export const UPLOAD_WINDOW_MS = 2 * 60 * 60 * 1000;

let seamOverride; // testler: undefined = gerçek modül; null = katman yok; nesne = sahte dikiş
let cachedSeam;

export function setDocumentSeamForTests(seam) {
  seamOverride = seam;
  cachedSeam = undefined;
}

/** Depolama dikişi ya da null (katman yok). */
export async function loadDocumentSeam() {
  if (seamOverride !== undefined) {
    return seamOverride;
  }
  if (cachedSeam !== undefined) {
    return cachedSeam;
  }
  let seam = null;
  try {
    const mod = await import('./document_storage.js');
    if (typeof mod.storeUpload === 'function' && typeof mod.openDownload === 'function' && typeof mod.removeFile === 'function') {
      seam = mod;
    }
  } catch (error) {
    if (error?.code !== 'ERR_MODULE_NOT_FOUND') {
      // eslint-disable-next-line no-console
      console.error('[finance] belge depolama katmani yuklenemedi:', error?.code || error?.message);
    }
  }
  cachedSeam = seam;
  return seam;
}

export async function requireDocumentSeam() {
  const seam = await loadDocumentSeam();
  if (!seam) {
    throw documentsNotAvailable();
  }
  return seam;
}

export function maxFileBytes(seam, env = process.env) {
  if (seam && Number.isSafeInteger(seam.maxFileBytes) && seam.maxFileBytes > 0) {
    return Math.min(seam.maxFileBytes, HARD_MAX_FILE_BYTES);
  }
  const configured = Number(env.DOCUMENTS_MAX_FILE_BYTES);
  return Number.isSafeInteger(configured) && configured > 0 && configured <= HARD_MAX_FILE_BYTES ? configured : DEFAULT_MAX_FILE_BYTES;
}

export function siteQuotaBytes(env = process.env) {
  const configured = Number(env.DOCUMENTS_SITE_QUOTA_BYTES);
  return Number.isSafeInteger(configured) && configured > 0 ? configured : DEFAULT_SITE_QUOTA_BYTES;
}

/** A2 depolama anahtarı biçimi: <10 haneli site>/<uuid>. */
export const STORAGE_KEY_PATTERN = /^\d{10}\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Yükleme rezervasyonu için sunucuya ait anahtar (tamamlanınca dikişin döndürdüğü anahtar yazılır). */
export const reserveStorageKey = (siteCode) => `${String(siteCode).padStart(10, '0')}/${randomUUID()}`;

// --- Dosya adı güvenliği (A4) ----------------------------------------------------------------------------------------------------------------

const INVISIBLE = new Set([0x061c, 0x200b, 0x200c, 0x200d, 0x200e, 0x200f, 0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2060, 0x2066, 0x2067, 0x2068, 0x2069, 0xfeff]);
const EXTENSIONS = Object.freeze({ pdf: 'application/pdf', jpg: 'image/jpeg', jpeg: 'image/jpeg', jpe: 'image/jpeg', png: 'image/png' });
const CANONICAL_EXT = Object.freeze({ 'application/pdf': 'pdf', 'image/jpeg': 'jpg', 'image/png': 'png' });
const RESERVED = new Set(['CON', 'PRN', 'AUX', 'NUL', ...Array.from({ length: 9 }, (_, i) => `COM${i + 1}`), ...Array.from({ length: 9 }, (_, i) => `LPT${i + 1}`)]);

/**
 * Görünen dosya adı: NFC, kontrol / yön karakterleri atılır, yalnız SON yol parçası, yasak karakterler `_`, çift uzantı kapanır, ayrılmış adlar korunur.
 * Uzantı izin listesinde değilse (pdf/jpg/jpeg/png) 415 DOCUMENT_TYPE_NOT_ALLOWED. Uzantısız ad kabul edilir (tür içerikten tanınır).
 * @returns {{ displayName: string, declaredMime: string|null }}
 */
export function sanitizeDocumentName(rawName) {
  if (typeof rawName !== 'string') {
    throw invalidBody('Dosya adı geçersiz.');
  }
  let text = '';
  for (const ch of rawName.normalize('NFC')) {
    const code = ch.codePointAt(0);
    if (code < 0x20 || (code >= 0x7f && code <= 0x9f) || code === 0x2028 || code === 0x2029 || INVISIBLE.has(code)) {
      continue;
    }
    text += ch;
  }
  const parts = text.split(/[\\/]/);
  let name = parts[parts.length - 1].replace(/[<>:"|?*]/g, '_').replace(/\s+/g, ' ').trim().replace(/\.+$/, '').trim();
  let declaredMime = null;
  const dot = name.lastIndexOf('.');
  let base = name;
  if (dot > 0) {
    const ext = name.slice(dot + 1).toLowerCase();
    if (!Object.prototype.hasOwnProperty.call(EXTENSIONS, ext)) {
      throw new PlatformError(415, 'DOCUMENT_TYPE_NOT_ALLOWED', 'Bu dosya türü desteklenmiyor. PDF, JPG veya PNG yükleyin.');
    }
    declaredMime = EXTENSIONS[ext];
    base = name.slice(0, dot);
  }
  base = base.replace(/\./g, '_').trim();
  if (RESERVED.has(base.toUpperCase())) {
    base = `_${base}`;
  }
  const baseChars = Array.from(base).slice(0, 100).join('');
  const finalBase = baseChars === '' ? 'belge' : baseChars;
  const extension = declaredMime ? CANONICAL_EXT[declaredMime] : null;
  name = extension ? `${finalBase}.${extension}` : finalBase;
  return { displayName: Array.from(name).slice(0, 120).join(''), declaredMime };
}

// --- İndirme başlıkları (A8) ---------------------------------------------------------------------------------------------------------------

const ASCII_FOLD = new Map([['ç', 'c'], ['ğ', 'g'], ['ı', 'i'], ['ö', 'o'], ['ş', 's'], ['ü', 'u'], ['Ç', 'C'], ['Ğ', 'G'], ['İ', 'I'], ['Ö', 'O'], ['Ş', 'S'], ['Ü', 'U']]);

function asciiFallback(name) {
  let out = '';
  for (const ch of name) {
    const mapped = ASCII_FOLD.get(ch) ?? ch;
    const code = mapped.codePointAt(0);
    if (mapped === '"' || mapped === '\\' || mapped === ';') {
      continue;
    }
    out += code >= 0x20 && code < 0x7f ? mapped : '_';
  }
  return out === '' ? 'belge' : out;
}

/** A8 indirme başlıkları (inline ASLA). */
export function downloadHeaders({ mimeType, sizeBytes, displayName }) {
  return {
    'Content-Type': mimeType,
    'Content-Length': String(sizeBytes),
    'Content-Disposition': `attachment; filename="${asciiFallback(displayName)}"; filename*=UTF-8''${encodeURIComponent(displayName)}`,
    'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': "default-src 'none'; sandbox",
    'Cache-Control': 'private, no-store',
    Pragma: 'no-cache',
    'Referrer-Policy': 'no-referrer',
    'Cross-Origin-Resource-Policy': 'same-site',
  };
}

/** `openDownload` çıktısı -> Readable. */
export function streamOf(opened) {
  if (opened && typeof opened.pipe === 'function') {
    return opened;
  }
  if (opened?.stream && typeof opened.stream.pipe === 'function') {
    return opened.stream;
  }
  throw new Error('belge deposu okunabilir akis dondurmedi');
}
