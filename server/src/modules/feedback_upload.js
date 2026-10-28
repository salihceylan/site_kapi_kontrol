// Geri bildirim ekleri (103): ham gövde akışıyla içerik yükleme (PUT .../attachments/:attId/content) ve içerik indirme (GET aynı yol).
//
// İş takibi fotoğraf yüklemesinin (work_attachments_upload.js) aynası: belgeler modülünün ilkel işlevleri AYNEN yeniden kullanılır; dosya türü kararı görüntü
// imzalarına (JPEG / PNG / WebP) göredir ve dosyalar `<kök>/feedback_attachments/<site | 1000000000>/<uuid>` alt ağacına yazılır. Akış: Content-Type
// application/octet-stream + ZORUNLU Content-Length (= bildirilen boyut) -> süreç içi (kullanıcı, ek) uçuş anahtarı -> depolama / boş alan / eşzamanlılık -> hedef
// (uploading, bu kullanıcı, süresi dolmamış) -> req -> UploadInspector (bayt sayar, sha256, ilk baytlarda ERKEN tür kararı) -> _tmp/<uuid>.part -> fsync -> diskten
// yeniden doğrulama (imza, PNG bütünlüğü, piksel boyutu) -> `link` ile son yola (hazır dosya ASLA ezilmez) -> TEK DB işlemi (ready + audit).
// Hata / kopma: _tmp silinir, kayıt `uploading` kalır (2 saat sonra bakım işi siler). Boyut sınırları K11 gereği 400'dür (sunucu istemciye güvenmez).

import { promises as fsp } from 'node:fs';
import { pool } from '../db.js';
import { actorFromAuthUser } from './audit_service.js';
import { documentLimits, invalidContentType, uploadBusy, uploadInProgress } from './document_common.js';
import { commitUploadedFile, contentLengthOf, receiveBody } from './document_upload.js';
import { sendDocument } from './document_download.js';
import { UploadInspector, checkStorage, ensureSiteDir, freeBytes, fsyncFile, pathForKey, removeStoredFile, removeTempFile, tmpFilePath } from './document_storage.js';
import { assertImageDimensions, assertImageHead, attachmentContentMismatch, readImageDimensions } from './work_attachments_common.js';
import {
  FEEDBACK_ATTACHMENT_MAX_BYTES,
  FEEDBACK_DOWNLOAD_CONCURRENCY,
  FEEDBACK_NO_SITE_BUCKET,
  FEEDBACK_SUBTREE,
  FEEDBACK_UPLOAD_CONCURRENCY,
  feedbackAccountDeleted,
  feedbackAttachmentNotFound,
  feedbackAttachmentTooLarge,
  feedbackMissingContentLength,
  feedbackSizeMismatch,
  feedbackStorageUnavailable,
  parseFeedbackAttachmentId,
  parseFeedbackId,
} from './feedback_common.js';
import { completeFeedbackUpload, findFeedbackUploadTarget, resolveFeedbackDownload } from './feedback_service.js';
import { newErrorId } from '../middlewares/error_handler.js';
import { PlatformError } from './errors.js';

let activeUploads = 0;
const inFlight = new Set();
/** Geri bildirim indirmelerinin KENDİ eşzamanlılık sayacı (belge / iş takibi indirmeleriyle yuva paylaşmaz). */
const downloadSlots = { active: 0 };

/** Test yardımcıları. */
export const feedbackUploadState = {
  active: () => activeUploads,
  inFlight: () => inFlight.size,
  downloads: () => downloadSlots.active,
};

/** Uçuş anahtarı KULLANICI başınadır: başka biri aynı ek kimliğine PUT atarak sahibinin yüklemesini 409 ile engelleyemez. */
export const feedbackFlightKeyOf = (userCode, attId) => `fb:${Number(userCode) || 0}:${attId}`;

function mapStreamError(error) {
  if (error?.code === 'DOCUMENT_SIZE_MISMATCH') return feedbackSizeMismatch();
  if (error?.code === 'ENOSPC') return feedbackStorageUnavailable();
  return error;
}

/** Dosya kaybı (DB'de kayıt var, diskte yok): ERROR günlüğü (kimlikler; ad yok) + 500 FEEDBACK_FILE_MISSING + errorId. */
function feedbackFileMissing(context) {
  const errorId = newErrorId();
  // eslint-disable-next-line no-console
  console.error(`[feedback] DOSYA KAYIP (errorId=${errorId}) ${context}`);
  return new PlatformError(500, 'FEEDBACK_FILE_MISSING', 'Ek dosyaya ulaşılamadı.', { errorId });
}

/**
 * Diske yazılmış geçici dosyanın ilk baytları yeniden okunur (akış kararı doğrulanır); PNG için IHDR + IEND bütünlüğü; son olarak piksel boyutu (açılma bombası
 * koruması: kenar > 12.000 ya da > 40 milyon piksel -> 415 ATTACHMENT_DIMENSIONS_TOO_LARGE). Reddedilince geçici dosya çağıranın `finally`sinde silinir.
 */
async function validateStoredImage(tmp, size, mime) {
  const handle = await fsp.open(tmp, 'r');
  const readAt = async (position, length) => {
    const buffer = Buffer.alloc(length);
    const { bytesRead } = await handle.read(buffer, 0, length, position);
    return buffer.subarray(0, bytesRead);
  };
  try {
    const head = Buffer.alloc(Math.min(size, 16));
    const { bytesRead } = await handle.read(head, 0, head.length, 0);
    assertImageHead(head.subarray(0, bytesRead), mime);
    if (mime === 'image/png') {
      if (size < 33 || head.latin1Slice(12, 16) !== 'IHDR') throw attachmentContentMismatch();
      const tail = Buffer.alloc(12);
      const read = await handle.read(tail, 0, 12, size - 12);
      if (read.bytesRead !== 12 || tail.latin1Slice(4, 8) !== 'IEND') throw attachmentContentMismatch();
    }
    assertImageDimensions(await readImageDimensions(mime, readAt, size));
  } finally {
    await handle.close();
  }
}

const loadAttachmentState = async (attId) => {
  const state = await pool.query(`SELECT status, storage_key FROM feedback_attachments WHERE id = $1`, [attId]);
  return state.rows?.[0] ?? null;
};

async function dropFinalIfNotReady(attId, root, key) {
  try {
    const row = await loadAttachmentState(attId);
    if (row && row.status === 'ready' && row.storage_key === key) {
      return;
    }
    await removeStoredFile(root, key, FEEDBACK_SUBTREE);
  } catch (_error) {
    // DB'ye ulaşılamıyor: dosya korunur (kayıt uploading kalır; 2 saat sonra bakım işi satırı ve dosyayı siler)
  }
}

/**
 * Yüklemeyi alır ve tamamlar. Başarıda { attachment } döner; hata PlatformError (ya da CLIENT_ABORTED) olarak fırlar.
 * @param {{ rawId: string, rawAttId: string, actor: object }} context
 */
export async function receiveFeedbackContent(req, { rawId, rawAttId, actor }) {
  const userCode = actorFromAuthUser(actor).userCode;
  if (userCode === null) {
    throw feedbackAccountDeleted();
  }
  const type = String(req.headers['content-type'] ?? '').split(';')[0].trim().toLowerCase();
  if (type !== 'application/octet-stream') {
    throw invalidContentType();
  }
  const contentLength = contentLengthOf(req);
  if (contentLength === 0) {
    throw feedbackMissingContentLength();
  }
  if (contentLength > FEEDBACK_ATTACHMENT_MAX_BYTES) {
    throw feedbackAttachmentTooLarge();
  }
  parseFeedbackId(rawId);
  // (kullanıcı, ek) anahtarı HERHANGİ bir await'ten ÖNCE süreç içinde ayrılır: aynı kişinin aynı kayda yarışan ikinci PUT'u 409.
  const flightKey = feedbackFlightKeyOf(userCode, parseFeedbackAttachmentId(rawAttId));
  if (inFlight.has(flightKey)) {
    throw uploadInProgress();
  }
  inFlight.add(flightKey);
  let counted = false;
  let tmp = null;
  try {
    const storage = await checkStorage();
    if (!storage.ok) {
      throw feedbackStorageUnavailable();
    }
    const free = await freeBytes(storage.root);
    if (free !== null && free < documentLimits().minFreeBytes + contentLength) {
      throw feedbackStorageUnavailable();
    }
    if (activeUploads >= FEEDBACK_UPLOAD_CONCURRENCY) {
      const error = uploadBusy();
      error.extra = { retry_after_seconds: 5 };
      throw error;
    }
    activeUploads += 1;
    counted = true;

    const target = await findFeedbackUploadTarget({ rawId, rawAttId, userCode });
    if (contentLength !== target.sizeBytes) {
      throw feedbackSizeMismatch();
    }

    await ensureSiteDir(storage.root, target.siteCode ?? FEEDBACK_NO_SITE_BUCKET, FEEDBACK_SUBTREE);
    tmp = tmpFilePath(storage.root);
    const inspector = new UploadInspector({ declaredSize: target.sizeBytes, onHead: (head) => assertImageHead(head, target.mimeType) });
    try {
      await receiveBody(req, inspector, tmp);
    } catch (error) {
      await removeTempFile(tmp);
      tmp = null;
      throw mapStreamError(error);
    }
    const bytes = inspector.bytes;
    const sha256 = inspector.digest();
    await fsyncFile(tmp);
    await validateStoredImage(tmp, bytes, target.mimeType);

    const final = pathForKey(storage.root, target.storageKey, FEEDBACK_SUBTREE);
    try {
      await commitUploadedFile({ tmp, final, versionId: target.attId, key: target.storageKey, loadState: loadAttachmentState });
    } catch (error) {
      if (error?.code === 'DOCUMENT_VERSION_NOT_FOUND') throw feedbackAttachmentNotFound();
      throw error;
    }
    tmp = null;

    try {
      return await completeFeedbackUpload({ target, actor, sha256 });
    } catch (error) {
      // DB adımı başarısız: son dosya yalnız kayıt `ready` DEĞİLSE silinir (belirsiz sonuçta dosya korunur; bakım işi süpürür).
      await dropFinalIfNotReady(target.attId, storage.root, target.storageKey);
      throw error;
    }
  } finally {
    if (tmp) await removeTempFile(tmp);
    inFlight.delete(flightKey);
    if (counted) activeUploads -= 1;
  }
}

/**
 * GET .../attachments/:attId/content: HAZIR ek -> bayt akışı (Content-Type = DB mime, inline, Cache-Control private no-store, nosniff, CSP sandbox). Yok / hazır
 * değil / yabancı site -> 404. Dosya kayıpsa 500 FEEDBACK_FILE_MISSING (+ errorId). Hata yanıtını kendisi yazmaz: çağıran respondError ile yazar.
 * @param {{ siteCode?: number|null, rawId: string, rawAttId: string }} context siteCode verilirse yalnız o sitenin geri bildirimi (yönetici ucu)
 */
export async function sendFeedbackContent(req, res, { siteCode = null, rawId, rawAttId }) {
  const target = await resolveFeedbackDownload({ siteCode, rawId, rawAttId });
  const storage = await checkStorage();
  if (!storage.ok) {
    throw feedbackStorageUnavailable();
  }
  // [feedback] attachment feedback=<id> att=<id>: kimlikler; dosya adı YOK
  // eslint-disable-next-line no-console
  console.log(`[feedback] attachment feedback=${target.feedbackId} att=${target.id}`);
  await sendDocument(req, res, {
    root: storage.root,
    version: { storageKey: target.storageKey, sizeBytes: target.sizeBytes, displayName: target.fileName, mimeType: target.mimeType },
    limit: FEEDBACK_DOWNLOAD_CONCURRENCY,
    slots: downloadSlots,
    disposition: 'inline',
    subtree: FEEDBACK_SUBTREE,
    onMissing: async (reason) => {
      const still = await pool.query(`SELECT 1 FROM feedback_attachments WHERE id = $1 AND status = 'ready' LIMIT 1`, [target.id]);
      return still.rows?.[0] ? feedbackFileMissing(`feedback=${target.feedbackId} att=${target.id} neden=${reason}`) : feedbackAttachmentNotFound();
    },
  });
}
