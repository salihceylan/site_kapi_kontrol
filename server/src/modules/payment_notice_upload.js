// Dekont dosyası: ham gövde akışıyla yükleme (PUT .../payment-notices/:id/content) ve indirme (GET .../:id/file). 066.
//
// İş takibi fotoğraf yüklemesiyle (work_attachments_upload.js) aynı akış; belgelerin ilkelleri AYNEN kullanılır (document_storage / document_upload / document_download).
// Dosya belgeler ağacına yazılır: <kök>/sites/<site>/<uuid>. document_storage.js'e storeUpload EKLENMEZ (gider belgesi dikişi kapalı kalır). Bilinen anahtar kümesine
// payment_notices dahildir (document_integrity.js). Türler: PDF / JPEG / PNG, en çok 10 MB, ZORUNLU Content-Length (= bildirilen boyut).
// Akış: Content-Type application/octet-stream -> uçuş anahtarı (kullanıcı, bildirim) -> depolama / boş alan / eşzamanlılık -> hedef (uploading, bu kullanıcı) ->
// UploadInspector (bayt sayar, sha256, ilk baytlarda ERKEN tür kararı) -> _tmp -> fsync -> PDF etkin içerik denetimi -> son yola `link` -> tek DB adımı (pending).
// Hata / kopma: _tmp silinir, kayıt `uploading` kalır (2 saat sonra bakım işi siler).

import { promises as fsp } from 'node:fs';
import { pool } from '../db.js';
import { invalidContentType, uploadBusy, uploadInProgress } from './document_common.js';
import { commitUploadedFile, contentLengthOf, receiveBody } from './document_upload.js';
import { sendDocument } from './document_download.js';
import { UploadInspector, checkStorage, ensureSiteDir, freeBytes, fsyncFile, pathForKey, removeStoredFile, removeTempFile, tmpFilePath } from './document_storage.js';
import { pdfHasActiveContent } from './document_validation.js';
import { PlatformError } from './errors.js';
import {
  NOTICE_MAX_BYTES,
  STALE_UPLOAD_MINUTES,
  noticeContentMismatch,
  noticeFileMissing,
  noticeNotFound,
  noticeSizeMismatch,
  noticeStorageUnavailable,
  noticeTooLarge,
  noticeTypeNotAllowed,
} from './payment_notice_common.js';
import { auditFileView, completeUpload, findFileTarget, findUploadTarget, parseNoticeId } from './payment_notice_service.js';

const UPLOAD_CONCURRENCY = 8;
const DOWNLOAD_CONCURRENCY = 32;
let activeUploads = 0;
const inFlight = new Set();
const downloadSlots = { active: 0 };

export const noticeUploadState = { active: () => activeUploads, inFlight: () => inFlight.size, downloads: () => downloadSlots.active };

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/** İlk baytlar bildirilen türle uyuşmalı (PDF `%PDF-`, JPEG FF D8 FF, PNG imzası). */
export function assertNoticeHead(head, mime) {
  if (!Buffer.isBuffer(head) || head.length === 0) throw noticeContentMismatch();
  const isPdf = head.length >= 5 && head.latin1Slice(0, 5) === '%PDF-';
  const isJpeg = head.length >= 3 && head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff;
  const isPng = head.length >= 8 && head.subarray(0, 8).equals(PNG_SIGNATURE);
  if (!isPdf && !isJpeg && !isPng) throw noticeTypeNotAllowed();
  const actual = isPdf ? 'application/pdf' : isJpeg ? 'image/jpeg' : 'image/png';
  if (actual !== mime) throw noticeContentMismatch();
}

const flightKeyOf = (userCode, id) => `pn:${Number(userCode) || 0}:${id}`;

function mapStreamError(error) {
  if (error?.code === 'DOCUMENT_SIZE_MISMATCH') return noticeSizeMismatch();
  if (error?.code === 'ENOSPC') return noticeStorageUnavailable();
  return error;
}

const pdfActiveContent = () =>
  new PlatformError(415, 'NOTICE_PDF_ACTIVE_CONTENT', 'Bu PDF etkin içerik barındırıyor ve kabul edilemedi. Dekontun ekran görüntüsünü yüklemeyi deneyin.');

async function validateStored(tmp, size, mime) {
  const handle = await fsp.open(tmp, 'r');
  try {
    const head = Buffer.alloc(Math.min(size, 16));
    const { bytesRead } = await handle.read(head, 0, head.length, 0);
    assertNoticeHead(head.subarray(0, bytesRead), mime);
    if (mime === 'image/png') {
      const tail = Buffer.alloc(12);
      const read = await handle.read(tail, 0, 12, Math.max(0, size - 12));
      if (size < 33 || read.bytesRead !== 12 || tail.latin1Slice(4, 8) !== 'IEND') throw noticeContentMismatch();
    }
    if (mime === 'application/pdf' && (await pdfHasActiveContent(handle, size))) throw pdfActiveContent();
  } finally {
    await handle.close();
  }
}

/** commitUploadedFile için: uploading dışındaki her durum 'ready' sayılır (hazır dosya ASLA ezilmez). */
const loadCommitState = async (id) => {
  const row = await loadState(id);
  return row ? { status: row.status === 'uploading' ? 'uploading' : 'ready', storage_key: row.storage_key } : null;
};

const loadState = async (id) => {
  const state = await pool.query(`SELECT status, storage_key FROM payment_notices WHERE id = $1`, [id]);
  return state.rows?.[0] ?? null;
};

async function dropFinalIfNotReady(id, root, key) {
  try {
    const row = await loadState(id);
    if (row && row.status !== 'uploading' && row.storage_key === key) return;
    await removeStoredFile(root, key);
  } catch (_error) {
    // DB'ye ulaşılamıyor: dosya korunur (kayıt uploading kalır; bakım işi süpürür)
  }
}

/**
 * Yüklemeyi alır ve tamamlar -> { notice }. `manager`: yönetici girişi (siteCode ile sınırlı). Hata PlatformError ya da CLIENT_ABORTED olarak fırlar.
 */
export async function receiveNoticeContent(req, { rawId, userCode, siteCode = null, manager = false }) {
  const type = String(req.headers['content-type'] ?? '').split(';')[0].trim().toLowerCase();
  if (type !== 'application/octet-stream') throw invalidContentType();
  const contentLength = contentLengthOf(req);
  if (contentLength === 0) throw noticeSizeMismatch();
  if (contentLength > NOTICE_MAX_BYTES) throw noticeTooLarge();
  const id = parseNoticeId(rawId);
  const flightKey = flightKeyOf(userCode, id);
  if (inFlight.has(flightKey)) throw uploadInProgress();
  inFlight.add(flightKey);
  let counted = false;
  let tmp = null;
  try {
    const storage = await checkStorage();
    if (!storage.ok) throw noticeStorageUnavailable();
    const free = await freeBytes(storage.root);
    if (free !== null && free < 64 * 1024 * 1024 + contentLength) throw noticeStorageUnavailable();
    if (activeUploads >= UPLOAD_CONCURRENCY) {
      const error = uploadBusy();
      error.extra = { retry_after_seconds: 5 };
      throw error;
    }
    activeUploads += 1;
    counted = true;

    const target = await findUploadTarget({ id, userCode, siteCode, manager });
    if (contentLength !== target.sizeBytes) throw noticeSizeMismatch();

    await ensureSiteDir(storage.root, target.siteCode);
    tmp = tmpFilePath(storage.root);
    const inspector = new UploadInspector({ declaredSize: target.sizeBytes, onHead: (head) => assertNoticeHead(head, target.mimeType) });
    try {
      await receiveBody(req, inspector, tmp);
    } catch (error) {
      await removeTempFile(tmp);
      tmp = null;
      throw mapStreamError(error);
    }
    const sha256 = inspector.digest();
    await fsyncFile(tmp);
    await validateStored(tmp, inspector.bytes, target.mimeType);

    const final = pathForKey(storage.root, target.storageKey);
    try {
      await commitUploadedFile({ tmp, final, versionId: target.id, key: target.storageKey, loadState: loadCommitState });
    } catch (error) {
      if (error?.code === 'DOCUMENT_VERSION_NOT_FOUND') throw noticeNotFound();
      throw error;
    }
    tmp = null;
    try {
      return await completeUpload({ id: target.id, sha256 });
    } catch (error) {
      await dropFinalIfNotReady(target.id, storage.root, target.storageKey);
      throw error;
    }
  } finally {
    if (tmp) await removeTempFile(tmp);
    inFlight.delete(flightKey);
    if (counted) activeUploads -= 1;
  }
}

/** GET .../file: tamamlanmış dosyayı akıtır (HEP inline + nosniff + sandbox CSP; sendDocument başlıkları). Yönetici indirmesi denetim kaydı yazar. */
export async function sendNoticeFile(req, res, { rawId, userCode = null, siteCode = null, actor = null }) {
  const target = await findFileTarget({ id: parseNoticeId(rawId), userCode, siteCode });
  const storage = await checkStorage();
  if (!storage.ok) throw noticeStorageUnavailable();
  if (actor && req.method !== 'HEAD') await auditFileView(actor, target);
  await sendDocument(req, res, {
    root: storage.root,
    version: { storageKey: target.storageKey, sizeBytes: target.sizeBytes, displayName: target.displayName, mimeType: target.mimeType },
    limit: DOWNLOAD_CONCURRENCY,
    slots: downloadSlots,
    disposition: 'inline',
    onMissing: async () => noticeFileMissing(),
  });
}

/**
 * Bakım: 2 saati aşan `uploading` bildirimleri siler (ÖNCE SATIR, süre koşulu DELETE'te tekrar sınanır; sonra dosya). Dönüş silinen satır sayısı.
 * Geç gelen PUT bildirimi `pending` yaptıysa satır silinmez, dosyaya dokunulmaz.
 */
export async function sweepStaleNoticeUploads(db = pool, { limit = 100 } = {}) {
  const stale = await db.query(
    `SELECT id FROM payment_notices WHERE status = 'uploading' AND submitted_at < NOW() - make_interval(mins => $1::INTEGER) ORDER BY id LIMIT $2`,
    [STALE_UPLOAD_MINUTES, limit],
  );
  let removed = 0;
  const storage = await checkStorage();
  for (const { id } of stale.rows) {
    const deleted = await db.query(
      `DELETE FROM payment_notices WHERE id = $1 AND status = 'uploading' AND submitted_at < NOW() - make_interval(mins => $2::INTEGER) RETURNING storage_key`,
      [id, STALE_UPLOAD_MINUTES],
    );
    const key = deleted.rows[0]?.storage_key;
    if (!deleted.rows[0]) continue;
    removed += 1;
    if (key && storage.ok) await removeStoredFile(storage.root, key).catch(() => {});
  }
  return removed;
}
