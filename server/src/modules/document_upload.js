// Belgeler (Faz 3b-A): ham gövde akışıyla dosya yükleme (PUT .../versions/:no/content).
//
// Sözleşme: docs/PLATFORM_BELGELER.md A3/A4. Akış: Content-Type application/octet-stream + ZORUNLU Content-Length (= bildirilen boyut) -> süreç genelinde
// eşzamanlılık sınırı -> sürüm satırı (uploading, bu kullanıcı/süper) -> req -> UploadInspector (bayt sayar, sha256, ilk baytlarda ERKEN tür kararı) ->
// _tmp/<uuid>.part (wx, 0600). Biter: bayt = bildirilen -> fsync -> içerik doğrulaması (diskten) -> `link` ile son yola (ÜZERİNE YAZMAZ; son yol varsa DB'den
// durum okunur: ready ise 409 ve dosyaya dokunulmaz) -> TEK DB işlemi. Aynı (site, belge, sürüm) için eşzamanlı ikinci PUT en başta 409 UPLOAD_IN_PROGRESS alır.
// Bellek sabit (64 KB parçalar). İstemci kopar / hata: _tmp silinir, sürüm `uploading` kalır (2 saat sonra bakım işi). `req` ile `stream.pipeline`
// KULLANILMAZ: pipeline hata durumunda IncomingMessage'ı yok eder ve soketi koparır -> 4xx yanıtı istemciye ulaşmaz; elle bağlanır.

import fs from 'node:fs';
import { promises as fsp } from 'node:fs';
import {
  invalidContentType,
  lengthRequired,
  sizeMismatch,
  storageFull,
  storageNotConfigured,
  tooLarge,
  uploadBusy,
  uploadAlreadyCompleted,
  uploadInProgress,
  versionNotFound,
} from './document_common.js';
import { assertHeadAcceptable, validateStoredFile } from './document_validation.js';
import {
  UploadInspector,
  checkStorage,
  commitTempFile,
  ensureSiteDir,
  freeBytes,
  fsyncFile,
  pathForKey,
  removeStoredFile,
  removeTempFile,
  tmpFilePath,
} from './document_storage.js';
import { completeUpload, findUploadTarget, loadSummary, parseDocumentId, parseVersionNo } from './document_service.js';
import { pool } from '../db.js';

let activeUploads = 0;
const inFlight = new Set();

/** Test yardımcıları. */
export const uploadState = {
  active: () => activeUploads,
  inFlight: () => inFlight.size,
};

const CLIENT_ABORTED = 'CLIENT_ABORTED';
const clientAborted = () => Object.assign(new Error('istemci baglantisi kesildi'), { code: CLIENT_ABORTED });
export const isClientAborted = (error) => error?.code === CLIENT_ABORTED;

/** Zorunlu Content-Length (chunked kabul edilmez): sayı ya da 411 LENGTH_REQUIRED. İş takibi fotoğraf yüklemesi de kullanır. */
export function contentLengthOf(req) {
  const raw = req.headers['content-length'];
  if (req.headers['transfer-encoding'] !== undefined || raw === undefined || !/^\d{1,15}$/.test(String(raw).trim())) {
    throw lengthRequired();
  }
  return Number(String(raw).trim());
}

/**
 * İstek gövdesini inspector üzerinden geçici dosyaya yazar. Başarıda 'close' (dosya kapalı) beklenir. Hatada akışlar yok edilir, dosya kapanır,
 * gövdenin kalanı boşaltılır (`req.resume`) ve hata reddedilir. İş takibi fotoğraf yüklemesi (work_attachments_upload.js) de kullanır.
 */
export function receiveBody(req, inspector, tmp) {
  return new Promise((resolve, reject) => {
    const ws = fs.createWriteStream(tmp, { flags: 'wx', mode: 0o600 });
    let finished = false;
    let settled = false;
    const fail = (error) => {
      if (settled) return;
      settled = true;
      req.unpipe(inspector);
      inspector.unpipe(ws);
      inspector.destroy();
      req.resume();
      const done = () => reject(error);
      if (ws.closed || ws.destroyed) {
        done();
      } else {
        ws.once('close', done);
        ws.destroy();
      }
    };
    ws.on('finish', () => {
      finished = true;
    });
    ws.on('error', fail);
    ws.on('close', () => {
      if (settled) return;
      if (finished) {
        settled = true;
        resolve();
      } else {
        fail(clientAborted());
      }
    });
    inspector.on('error', fail);
    req.on('error', fail);
    req.on('aborted', () => fail(clientAborted()));
    req.on('close', () => {
      if (!req.complete) fail(clientAborted());
    });
    req.pipe(inspector).pipe(ws);
  });
}

const defaultLoadState = async (versionId) => {
  const state = await pool.query(`SELECT status, storage_key FROM document_versions WHERE id = $1`, [versionId]);
  return state.rows?.[0] ?? null;
};

/**
 * Doğrulanmış geçici dosyayı son yola koyar. Son yol zaten VARSA (EEXIST) hazır bir dosyanın silinip ezilmesi ASLA olmaz:
 *  - DB'de sürüm yok ya da anahtarı başka (yenilendi) -> 404 DOCUMENT_VERSION_NOT_FOUND, son dosyaya dokunulmaz
 *  - sürüm `ready` -> 409 UPLOAD_ALREADY_COMPLETED, son dosyaya dokunulmaz (iki yazıcı hiçbir zaman karışmaz)
 *  - sürüm hâlâ `uploading` -> son yoldaki dosya başarısız bir önceki denemenin (DB adımı çökmüş) artığıdır; SİLİNMEZ, `rename` ile ATOMİK değiştirilir
 *    (silme-sonra-bağlama penceresi yok: ENOSPC gibi bir hata dosyayı kaybettiremez)
 * @param {{ tmp: string, final: string, versionId: number, key: string, loadState?: (versionId: number) => Promise<{ status: string, storage_key: string } | null> }} options
 */
export async function commitUploadedFile({ tmp, final, versionId, key, loadState = defaultLoadState }) {
  try {
    await commitTempFile(tmp, final);
    return;
  } catch (error) {
    if (error?.code !== 'EEXIST') throw error;
  }
  const state = await loadState(versionId);
  if (!state || state.storage_key !== key) {
    throw versionNotFound();
  }
  if (state.status === 'ready') {
    throw uploadAlreadyCompleted();
  }
  await fsp.rename(tmp, final);
  try {
    await fsp.chmod(final, 0o600);
  } catch (_error) {
    // Windows'ta anlamsız olabilir
  }
}

/** İstek anahtarı: (site, belge, sürüm) — AYNI sürüme eşzamanlı ikinci PUT hedef sorgusundan ÖNCE reddedilir. */
const flightKeyOf = (siteCode, rawId, rawVersionNo) => `${Number(siteCode)}:${parseDocumentId(rawId)}:${parseVersionNo(rawVersionNo)}`;

/**
 * Yüklemeyi alır ve tamamlar. Başarıda { document, warnings } döner; hata PlatformError (ya da CLIENT_ABORTED) olarak fırlar.
 * @param {{ siteCode: number, rawId: string, rawVersionNo: string, actor: object, limits: object }} context
 */
export async function receiveUpload(req, context) {
  const { siteCode, rawId, rawVersionNo, actor, limits } = context;
  const type = String(req.headers['content-type'] ?? '').split(';')[0].trim().toLowerCase();
  if (type !== 'application/octet-stream') {
    throw invalidContentType();
  }
  const contentLength = contentLengthOf(req);
  if (contentLength === 0) {
    throw sizeMismatch();
  }
  if (contentLength > limits.maxFileBytes) {
    throw tooLarge(limits.maxFileBytes);
  }
  // (site, belge, sürüm) anahtarı HERHANGİ bir await'ten ÖNCE, eşzamanlı olarak ayrılır: aynı sürüme yarışan ikinci PUT `uploading` anlık görüntüsüyle
  // gövdeyi alıp tamamlanmış (ready) dosyanın üzerine yazamaz (R9 F2).
  const flightKey = flightKeyOf(siteCode, rawId, rawVersionNo);
  if (inFlight.has(flightKey)) {
    throw uploadInProgress();
  }
  inFlight.add(flightKey);
  let counted = false;
  let tmp = null;
  try {
    const storage = await checkStorage();
    if (!storage.ok) {
      throw storageNotConfigured();
    }
    const free = await freeBytes(storage.root);
    if (free !== null && free < limits.minFreeBytes + contentLength) {
      throw storageFull();
    }
    if (activeUploads >= limits.uploadConcurrency) {
      const error = uploadBusy();
      error.extra = { retry_after_seconds: 5 };
      throw error;
    }
    activeUploads += 1;
    counted = true;

    const target = await findUploadTarget({ siteCode, rawId, rawVersionNo, actor, limits });
    if (contentLength !== target.declaredSize) {
      throw sizeMismatch();
    }

    await ensureSiteDir(storage.root, siteCode);
    tmp = tmpFilePath(storage.root);
    const inspector = new UploadInspector({
      declaredSize: target.declaredSize,
      onHead: (head) => assertHeadAcceptable(head, { expectedKind: target.kind, declared: target.declared }, limits),
    });
    try {
      await receiveBody(req, inspector, tmp);
    } catch (error) {
      await removeTempFile(tmp);
      tmp = null;
      if (error?.code === 'ENOSPC') throw storageFull();
      throw error;
    }
    const bytes = inspector.bytes;
    const sha256 = inspector.digest();

    await fsyncFile(tmp);
    let kind;
    const handle = await fsp.open(tmp, 'r');
    try {
      kind = await validateStoredFile(handle, bytes, { expectedKind: target.kind, declared: target.declared }, limits);
    } finally {
      await handle.close();
    }

    const finalKey = target.storageKey;
    const final = pathForKey(storage.root, finalKey);
    try {
      await commitUploadedFile({ tmp, final, versionId: target.versionId, key: finalKey });
    } catch (error) {
      if (error?.code === 'UPLOAD_ALREADY_COMPLETED' && !error.extra?.document) {
        // son dosyaya DOKUNULMADI; istemciye güncel belge verilir (findUploadTarget yolundaki yanıtla aynı biçim)
        const document = await loadSummary(pool, siteCode, target.documentId, limits).catch(() => null);
        if (document) error.extra = { document };
      }
      throw error;
    }
    tmp = null;

    try {
      return await completeUpload({ siteCode, target, actor, size: bytes, sha256, kind, limits });
    } catch (error) {
      // DB adımı başarısız: son dosya yalnız sürüm `ready` DEĞİLSE silinir (belirsiz sonuçta dosya korunur; bakım işi süpürür).
      await dropFinalIfNotReady(target.versionId, storage.root, finalKey);
      throw error;
    }
  } finally {
    if (tmp) await removeTempFile(tmp);
    inFlight.delete(flightKey);
    if (counted) activeUploads -= 1;
  }
}

async function dropFinalIfNotReady(versionId, root, key) {
  try {
    const state = await pool.query(`SELECT status, storage_key FROM document_versions WHERE id = $1`, [versionId]);
    const row = state.rows?.[0];
    if (row && row.status === 'ready' && row.storage_key === key) {
      return;
    }
    await removeStoredFile(root, key);
  } catch (_error) {
    // DB'ye ulaşılamıyor: dosya korunur (sürüm uploading kalır; 2 saat sonra bakım işi satırı ve dosyayı siler)
  }
}
