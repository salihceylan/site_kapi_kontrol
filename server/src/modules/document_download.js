// Belgeler (Faz 3b-A): indirme yanıtı (başlıklar + akış).
//
// Sözleşme: docs/PLATFORM_BELGELER.md A8. Başlıklar (HEPSİ): Content-Type (DB'deki kanonik MIME, asla istemcinin bildirdiği), Content-Length,
// Content-Disposition (attachment; RFC 6266/5987; `inline` ASLA), X-Content-Type-Options: nosniff, Content-Security-Policy: default-src 'none'; sandbox,
// Cache-Control: private, no-store, Pragma: no-cache, Referrer-Policy: no-referrer, Cross-Origin-Resource-Policy: same-site. `Range` YOK SAYILIR (tam 200).
// Dosya sunucuda ayrıştırılmaz. HEAD gövdesizdir. İstemci koparsa akış yok edilir.

import { pipeline } from 'node:stream/promises';
import { PlatformError } from './errors.js';
import { newErrorId } from '../middlewares/error_handler.js';
import { downloadBusy } from './document_common.js';
import { openStoredFile } from './document_storage.js';

const ASCII_FALLBACK = new Map(
  [...'çğıöşüÇĞİÖŞÜ'].map((ch, index) => [ch, 'cgiosuCGIOSU'[index]]),
);

/** RFC 6266 ASCII yedek ad: ç->c ğ->g ı->i ö->o ş->s ü->u (büyükleri de), diğer ASCII dışı `_`; `"` `\` `;` ve kontrol karakterleri atılır. */
export function asciiFileName(name) {
  let out = '';
  for (const ch of String(name ?? '')) {
    const mapped = ASCII_FALLBACK.get(ch);
    if (mapped !== undefined) {
      out += mapped;
    } else if (ch === '"' || ch === '\\' || ch === ';') {
      // atılır
    } else if (ch.codePointAt(0) < 0x20 || ch.codePointAt(0) === 0x7f) {
      // atılır
    } else if (ch.codePointAt(0) > 0x7e) {
      out += '_';
    } else {
      out += ch;
    }
  }
  return out.trim() === '' ? 'belge' : out;
}

/** RFC 5987 ext-value: UTF-8 yüzde kodlama (attr-char dışındaki her şey; `'()*` dahil). */
export function encodeRfc5987(name) {
  return encodeURIComponent(String(name ?? '')).replace(/['()*]/g, (ch) => `%${ch.charCodeAt(0).toString(16).toUpperCase()}`);
}

export function contentDisposition(name) {
  return `attachment; filename="${asciiFileName(name)}"; filename*=UTF-8''${encodeRfc5987(name)}`;
}

let activeDownloads = 0;

/** Test yardımcısı. */
export function activeDownloadCount() {
  return activeDownloads;
}

/**
 * Dosyayı yanıta akıtır. Dosya yok / boyut uyuşmaz -> `onMissing()` (çağıran önce DB'den "silindi mi" bakar: silme × indirme yarışında 404, gerçek
 * kayıpta 500 DOCUMENT_FILE_MISSING). Eşzamanlı indirme sınırı aşılırsa 503 DOWNLOAD_BUSY + Retry-After.
 * @param {{ root: string, version: { storageKey: string, sizeBytes: number, displayName: string, mimeType: string }, limit: number,
 *           onMissing: () => Promise<Error> }} options
 */
export async function sendDocument(req, res, { root, version, limit, onMissing }) {
  if (activeDownloads >= limit) {
    res.setHeader('Retry-After', '5');
    const error = downloadBusy();
    return res.status(error.statusCode).json({ error: error.message, code: error.code });
  }
  activeDownloads += 1;
  let handle = null;
  try {
    const opened = await openStoredFile(root, version.storageKey, version.sizeBytes);
    if (opened.error) {
      throw await onMissing(opened.error);
    }
    handle = opened.handle;
    res.status(200);
    res.setHeader('Content-Type', version.mimeType);
    res.setHeader('Content-Length', String(opened.size));
    res.setHeader('Content-Disposition', contentDisposition(version.displayName));
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Content-Security-Policy', "default-src 'none'; sandbox");
    res.setHeader('Cache-Control', 'private, no-store');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Cross-Origin-Resource-Policy', 'same-site');
    res.removeHeader('ETag');
    res.removeHeader('Last-Modified');
    if (req.method === 'HEAD') {
      await handle.close();
      handle = null;
      return res.end();
    }
    const stream = handle.createReadStream({ autoClose: true });
    handle = null; // akış kapanışta tanıtıcıyı kapatır
    try {
      await pipeline(stream, res);
    } catch (_error) {
      // istemci koptu ya da okuma hatası: akışlar pipeline tarafından yok edildi; başlık gönderildiği için yanıt değiştirilemez
      res.destroy();
    }
    return undefined;
  } finally {
    activeDownloads -= 1;
    if (handle) {
      await handle.close().catch(() => {});
    }
  }
}

/** Dosya kaybı (DB'de kayıt var, diskte yok): ERROR günlüğü (kimlik/numara, ad yok) + 500 DOCUMENT_FILE_MISSING + errorId. */
export function fileMissingError(context) {
  const errorId = newErrorId();
  // eslint-disable-next-line no-console
  console.error(`[documents] DOSYA KAYIP (errorId=${errorId}) ${context}`);
  const error = new PlatformError(500, 'DOCUMENT_FILE_MISSING', 'Belge dosyasına ulaşılamadı. Yöneticiyle iletişime geçin.', { errorId });
  return error;
}
