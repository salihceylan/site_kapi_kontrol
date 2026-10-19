// İş Takibi fotoğraf ekleri (047): ham gövde akışıyla içerik yükleme (PUT .../attachments/:attId/content) ve içerik indirme (GET aynı yol).
//
// Belgeler modülünün (document_upload.js / document_download.js / document_storage.js) ilkel işlevleri AYNEN yeniden kullanılır; yalnız dosya türü kararı
// görüntü imzalarına (JPEG / PNG / WebP) göredir ve dosyalar `<kök>/work_attachments/<site>/<uuid>` alt ağacına yazılır (belgelerin `sites/` ağacından AYRI).
// Akış: Content-Type application/octet-stream + ZORUNLU Content-Length (= size_bytes) -> süreç içi (kullanıcı, attId) uçuş anahtarı (eşzamanlı ikinci PUT 409 UPLOAD_IN_PROGRESS)
// -> depolama / boş alan / eşzamanlılık -> hedef (uploading, bu kullanıcı, süresi dolmamış, talep açık) -> req -> UploadInspector (bayt sayar, sha256, ilk 16 baytta
// ERKEN tür kararı) -> _tmp/<uuid>.part -> fsync -> diskten yeniden doğrulama -> `link` ile son yola (hazır dosya ASLA ezilmez) -> TEK DB işlemi (ready + olay + audit).
// Hata / kopma: _tmp silinir, kayıt `uploading` kalır (2 saat sonra bakım işi siler). DB adımı başarısızsa son dosya yalnız kayıt `ready` DEĞİLSE silinir.

import { promises as fsp } from 'node:fs';
import { pool } from '../db.js';
import { documentLimits, invalidContentType, uploadBusy, uploadInProgress } from './document_common.js';
import { commitUploadedFile, contentLengthOf, receiveBody } from './document_upload.js';
import { sendDocument } from './document_download.js';
import { UploadInspector, checkStorage, ensureSiteDir, freeBytes, fsyncFile, pathForKey, removeStoredFile, removeTempFile, tmpFilePath } from './document_storage.js';
import {
  ATTACHMENT_DOWNLOAD_CONCURRENCY,
  ATTACHMENT_MAX_BYTES,
  ATTACHMENT_SUBTREE,
  ATTACHMENT_UPLOAD_CONCURRENCY,
  assertImageDimensions,
  assertImageHead,
  attachmentContentMismatch,
  attachmentFileMissing,
  attachmentNotFound,
  attachmentSizeMismatch,
  attachmentStorageUnavailable,
  attachmentTooLarge,
  parseAttachmentId,
  readImageDimensions,
} from './work_attachments_common.js';
import { completeAttachmentUpload, findAttachmentUploadTarget } from './work_attachments_service.js';
import { resolveAttachmentDownload } from './work_attachments_read.js';
import { workItemNotFound } from './work_tracking_common.js';
import { parsePositiveId } from './people_common.js';

let activeUploads = 0;
const inFlight = new Set();
/** Fotoğraf indirmelerinin KENDİ eşzamanlılık sayacı (belge indirmeleriyle yuva paylaşmaz, WA-SEC-4). */
const downloadSlots = { active: 0 };

/** Test yardımcıları. */
export const attachmentUploadState = {
  active: () => activeUploads,
  inFlight: () => inFlight.size,
  downloads: () => downloadSlots.active,
};

/** Uçuş anahtarı KULLANICI başınadır (WA-SEC-5): başka biri aynı ek kimliğine PUT atarak sahibinin yüklemesini 409 ile engelleyemez. */
export const flightKeyOf = (userCode, attId) => `wa:${Number(userCode) || 0}:${attId}`;

/** Belgelerle aynı hata kodu farklı mesajla gelmesin: belge modülünün boyut hatası fotoğraf hatasına çevrilir. */
function mapStreamError(error) {
  if (error?.code === 'DOCUMENT_SIZE_MISMATCH') return attachmentSizeMismatch();
  if (error?.code === 'ENOSPC') return attachmentStorageUnavailable();
  return error;
}

/**
 * Diske yazılmış geçici dosyanın ilk 16 baytı yeniden okunur (akış kararı doğrulanır); PNG için IHDR + IEND bütünlüğü; son olarak piksel boyutu (açılma
 * bombası koruması: kenar > 12.000 ya da > 40 milyon piksel -> 415 ATTACHMENT_DIMENSIONS_TOO_LARGE). Reddedilince geçici dosya çağıranın `finally`sinde
 * silinir, kayıt `uploading` kalır (diğer içerik retleriyle aynı).
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
  const state = await pool.query(`SELECT status, storage_key FROM work_item_attachments WHERE id = $1`, [attId]);
  return state.rows?.[0] ?? null;
};

async function dropFinalIfNotReady(attId, root, key) {
  try {
    const row = await loadAttachmentState(attId);
    if (row && row.status === 'ready' && row.storage_key === key) {
      return;
    }
    await removeStoredFile(root, key, ATTACHMENT_SUBTREE);
  } catch (_error) {
    // DB'ye ulaşılamıyor: dosya korunur (kayıt uploading kalır; 2 saat sonra bakım işi satırı ve dosyayı siler)
  }
}

/**
 * Yüklemeyi alır ve tamamlar. Başarıda { attachment } döner; hata PlatformError (ya da CLIENT_ABORTED) olarak fırlar.
 * @param {{ scope: object, rawId: string, rawAttId: string, actor: object }} context
 */
export async function receiveAttachmentContent(req, { scope, rawId, rawAttId, actor }) {
  const type = String(req.headers['content-type'] ?? '').split(';')[0].trim().toLowerCase();
  if (type !== 'application/octet-stream') {
    throw invalidContentType();
  }
  const contentLength = contentLengthOf(req);
  if (contentLength === 0) {
    throw attachmentSizeMismatch();
  }
  if (contentLength > ATTACHMENT_MAX_BYTES) {
    throw attachmentTooLarge();
  }
  if (parsePositiveId(rawId) === null) {
    throw workItemNotFound();
  }
  // (kullanıcı, ek) anahtarı HERHANGİ bir await'ten ÖNCE süreç içinde ayrılır: aynı kişinin aynı kayda yarışan ikinci PUT'u 409 (R9 F2 ile aynı kalkan; tek
  // süreç / fork kipi). Anahtar kullanıcı başınadır: yükleme hakkı yalnız kaydı açandadır, başkasının PUT'u hedef denetiminde 404 alır ve sahibini engellemez.
  const flightKey = flightKeyOf(scope.userCode, parseAttachmentId(rawAttId));
  if (inFlight.has(flightKey)) {
    throw uploadInProgress();
  }
  inFlight.add(flightKey);
  let counted = false;
  let tmp = null;
  try {
    const storage = await checkStorage();
    if (!storage.ok) {
      throw attachmentStorageUnavailable();
    }
    const free = await freeBytes(storage.root);
    if (free !== null && free < documentLimits().minFreeBytes + contentLength) {
      throw attachmentStorageUnavailable();
    }
    if (activeUploads >= ATTACHMENT_UPLOAD_CONCURRENCY) {
      const error = uploadBusy();
      error.extra = { retry_after_seconds: 5 };
      throw error;
    }
    activeUploads += 1;
    counted = true;

    const target = await findAttachmentUploadTarget({ scope, rawId, rawAttId, userCode: scope.userCode });
    if (contentLength !== target.sizeBytes) {
      throw attachmentSizeMismatch();
    }

    await ensureSiteDir(storage.root, target.siteCode, ATTACHMENT_SUBTREE);
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

    const final = pathForKey(storage.root, target.storageKey, ATTACHMENT_SUBTREE);
    try {
      await commitUploadedFile({ tmp, final, versionId: target.attId, key: target.storageKey, loadState: loadAttachmentState });
    } catch (error) {
      if (error?.code === 'DOCUMENT_VERSION_NOT_FOUND') throw attachmentNotFound();
      throw error;
    }
    tmp = null;

    try {
      return await completeAttachmentUpload({ scope, target, actor, sha256 });
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
 * GET .../attachments/:attId/content: görünür talep + HAZIR ek -> bayt akışı (Content-Type = DB mime, Content-Disposition inline + güvenli ad, Cache-Control
 * private, no-store, nosniff, CSP sandbox). Hazır değil / yabancı / yok -> 404. Dosya kayıpsa 500 ATTACHMENT_FILE_MISSING (+ errorId); silme × indirme yarışı 404.
 * Hata yanıtını kendisi yazmaz: çağıran respondError ile yazar (başlıklar gönderildiyse bağlantı kapatılır).
 */
export async function sendAttachmentContent(req, res, { scope, rawId, rawAttId }) {
  const target = await resolveAttachmentDownload(scope, rawId, rawAttId);
  const storage = await checkStorage();
  if (!storage.ok) {
    throw attachmentStorageUnavailable();
  }
  // [work_tracking] attachment item=<id> att=<id> user=<kod>: kimlikler; dosya adı YOK
  // eslint-disable-next-line no-console
  console.log(`[work_tracking] attachment item=${target.itemId} att=${target.id} user=${scope.userCode ?? 0}`);
  await sendDocument(req, res, {
    root: storage.root,
    version: { storageKey: target.storageKey, sizeBytes: target.sizeBytes, displayName: target.fileName, mimeType: target.mimeType },
    limit: ATTACHMENT_DOWNLOAD_CONCURRENCY,
    slots: downloadSlots,
    disposition: 'inline',
    subtree: ATTACHMENT_SUBTREE,
    onMissing: async (reason) => {
      const still = await pool.query(`SELECT 1 FROM work_item_attachments WHERE id = $1 AND status = 'ready' LIMIT 1`, [target.id]);
      return still.rows?.[0] ? attachmentFileMissing(`item=${target.itemId} att=${target.id} neden=${reason}`) : attachmentNotFound();
    },
  });
}
