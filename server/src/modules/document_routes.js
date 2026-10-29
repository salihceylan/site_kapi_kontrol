// Belgeler (Faz 3b-A, dosya deposu) uçları.
//
//   Yönetici  GET/POST   /manager/sites/:siteCode/documents                       GET/PATCH/DELETE .../documents/:id
//             POST       .../documents/:id/restore | /purge | /versions           DELETE .../documents/:id/versions/:no
//             PUT        .../documents/:id/versions/:no/content   (ham gövde akışı, application/octet-stream)
//             GET        .../documents/:id/download?version=
//   Sakin     GET        /app/documents   /app/documents/:id   /app/documents/:id/download
//             GET        /app/announcements/:id/attachments/:documentId/download
//
// Yetki (people_access.js ile AYNI): yazma = yönetici/süper; okuma = yönetici/süper + BOARD_MEMBER (salt okunur); STAFF/sakin 403 FORBIDDEN_ROLE; başka sitenin
// yöneticisi 403 FORBIDDEN_SITE; `documents` modülü kapalıysa yönetici uçları 403 MODULE_DISABLED. Sözleşme: docs/PLATFORM_BELGELER.md. Hata gövdesi { error, code }.

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { HOUR_MS, ipKey, respondError, userKey } from './route_helpers.js';
import { actorFromAuthUser } from './audit_service.js';
import { pool } from '../db.js';
import { resolveDocumentAccess } from './document_access.js';
import {
  documentLimits,
  documentNotFound,
  parseVersionQuery,
  storageFull,
  storageNotConfigured,
} from './document_common.js';
import {
  addVersion,
  createDocument,
  deleteDocument,
  deleteVersion,
  getDocumentDetail,
  listDocuments,
  purgeDocument,
  resolveManagerDownload,
  restoreDocument,
  updateDocument,
} from './document_service.js';
import { bumpDownloadCount, getMyDocument, listMyDocuments, resolveAnnouncementAttachmentDownload, resolveResidentDownload } from './document_resident.js';
import { fileMissingError, sendDocument, sendDriveDocument } from './document_download.js';
import { assertDriveConnected, documentTransferring } from './document_drive.js';
import { checkStorage, freeBytes } from './document_storage.js';
import { isClientAborted, receiveUpload } from './document_upload.js';

export const documentRouter = express.Router();

// Yönetici yazma: kullanıcı başına 120/saat.
export const documentWriteLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 120, key: userKey },
    { windowMs: HOUR_MS, max: 1200, key: ipKey },
  ],
  message: 'Çok fazla belge işlemi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// İçerik yükleme: kullanıcı başına 30/saat + IP başına 300/saat (kimlikli ama büyük gövde: taşıma kötüye kullanımını daraltır).
export const documentUploadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 30, key: userKey },
    { windowMs: HOUR_MS, max: 300, key: ipKey },
  ],
  message: 'Çok fazla dosya yükleme denemesi. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Okuma (liste / ayrıntı / yönetici indirme / sakin liste): kullanıcı başına 1200/saat.
export const documentReadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 1200, key: userKey },
    { windowMs: HOUR_MS, max: 12000, key: ipKey },
  ],
  message: 'Çok fazla istek. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

// Sakin indirme: kullanıcı başına 300/saat + IP başına 5000/saat (NAT).
export const documentDownloadLimiter = createRuleLimiter({
  rules: [
    { windowMs: HOUR_MS, max: 300, key: userKey },
    { windowMs: HOUR_MS, max: 5000, key: ipKey },
  ],
  message: 'Çok fazla indirme isteği. Biraz sonra tekrar deneyin.',
  includeRetryBody: true,
});

const bodyOf = (req) => (req.body && typeof req.body === 'object' && !Array.isArray(req.body) ? req.body : {});

function setRetryAfter(res, error) {
  if (error?.code === 'UPLOAD_BUSY' || error?.code === 'DOWNLOAD_BUSY') {
    res.setHeader('Retry-After', '5');
  }
}

/** Depolama kullanılabilir mi (503) ve yeni dosya için boş alan var mı (503 DOCUMENT_STORAGE_FULL). */
async function assertStorageUsable(limits, incomingBytes = 0) {
  const storage = await checkStorage();
  if (!storage.ok) {
    throw storageNotConfigured();
  }
  const free = await freeBytes(storage.root);
  if (free !== null && free < limits.minFreeBytes + incomingBytes) {
    throw storageFull();
  }
  return storage;
}

/** Yönetici sarmalayıcı: yetki + modül -> iş -> JSON. `allowBoard: false`: kurul üyesi 403. */
function managerHandler({ context, fallback, write = false }, run) {
  return async (req, res) => {
    try {
      const access = await resolveDocumentAccess(req, res, { write });
      if (!access) {
        return undefined;
      }
      const { status = 200, body } = await run({ req, access, limits: documentLimits() });
      return res.status(status).json(body);
    } catch (error) {
      setRetryAfter(res, error);
      return respondError(res, context, error, fallback);
    }
  };
}

function appHandler({ context, fallback }, run) {
  return async (req, res) => {
    try {
      return res.status(200).json(await run(req));
    } catch (error) {
      return respondError(res, context, error, fallback);
    }
  };
}

const userLabel = (req) => actorFromAuthUser(req.authUser).userCode ?? 0;

/** İndirme akışı ortak yolu (yönetici / sakin / duyuru eki). */
async function streamDownload(req, res, { version, context, countDownload }) {
  const limits = documentLimits();
  try {
    // Yalnız-Drive modeli: sunucu kopyası yoksa dosya Drive'dadır (yalnız TEYİTLİYSE akıtılır; aktarılıyorsa 409 DOCUMENT_TRANSFERRING).
    const fromDrive = version.serverCopy === false;
    if (fromDrive && version.driveStatus !== 'stored') {
      throw documentTransferring();
    }
    const storage = fromDrive ? null : await checkStorage();
    if (storage && !storage.ok) {
      throw storageNotConfigured();
    }
    // [documents] download doc=<id> v=<no> user=<kod>: kimlik/numara, dosya adı YOK
    // eslint-disable-next-line no-console
    console.log(`[documents] download doc=${version.documentId} v=${version.versionNo} user=${userLabel(req)}`);
    if (countDownload && req.method !== 'HEAD') {
      bumpDownloadCount(version.documentId);
    }
    if (fromDrive) {
      await sendDriveDocument(req, res, { siteCode: version.siteCode, version, limit: limits.downloadConcurrency });
      return undefined;
    }
    await sendDocument(req, res, {
      root: storage.root,
      version,
      limit: limits.downloadConcurrency,
      onMissing: async (reason) => {
        // silme × indirme yarışı: satır artık yoksa (ya da sürüm kaldırıldıysa) 404; gerçek kayıpta 500 DOCUMENT_FILE_MISSING
        const still = await pool.query(
          `SELECT 1 FROM document_versions v INNER JOIN documents d ON d.id = v.document_id WHERE v.id = $1 AND v.status = 'ready' AND d.status <> 'pending' LIMIT 1`,
          [version.versionId],
        );
        return still.rows?.[0]
          ? fileMissingError(`doc=${version.documentId} v=${version.versionNo} neden=${reason}`)
          : documentNotFound();
      },
    });
  } catch (error) {
    setRetryAfter(res, error);
    if (res.headersSent) {
      res.destroy();
      return undefined;
    }
    return respondError(res, context, error, 'Belge indirilemedi.');
  }
  return undefined;
}

// --- Yönetici ----------------------------------------------------------------------------------------------------------

const BASE = '/manager/sites/:siteCode/documents';

documentRouter.get(
  BASE,
  authRequired,
  documentReadLimiter,
  managerHandler({ context: 'documents_list', fallback: 'Belgeler yüklenemedi.' }, async ({ req, access, limits }) => ({
    body: await listDocuments(access.siteCode, req.query, { kind: access.kind, limits }),
  })),
);

documentRouter.post(
  BASE,
  authRequired,
  documentWriteLimiter,
  managerHandler({ context: 'documents_create', fallback: 'Belge kaydedilemedi.', write: true }, async ({ req, access, limits }) => {
    const body = bodyOf(req);
    await assertDriveConnected(access.siteCode); // yalnız-Drive modeli: Drive bağlı değilse yükleme kapalı (409 DRIVE_REQUIRED)
    await assertStorageUsable(limits, Number.isSafeInteger(body?.file?.size) ? body.file.size : 0);
    return { status: 201, body: await createDocument({ siteCode: access.siteCode, actor: req.authUser, body, limits }) };
  }),
);

documentRouter.get(
  `${BASE}/:id`,
  authRequired,
  documentReadLimiter,
  managerHandler({ context: 'documents_get', fallback: 'Belge yüklenemedi.' }, async ({ req, access, limits }) => ({
    body: await getDocumentDetail(access.siteCode, req.params.id, { kind: access.kind, limits }),
  })),
);

documentRouter.patch(
  `${BASE}/:id`,
  authRequired,
  documentWriteLimiter,
  managerHandler({ context: 'documents_update', fallback: 'Belge güncellenemedi.', write: true }, async ({ req, access, limits }) => ({
    body: await updateDocument({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, body: bodyOf(req), limits }),
  })),
);

documentRouter.delete(
  `${BASE}/:id`,
  authRequired,
  documentWriteLimiter,
  managerHandler({ context: 'documents_delete', fallback: 'Belge silinemedi.', write: true }, async ({ req, access, limits }) => ({
    body: await deleteDocument({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, body: bodyOf(req), limits }),
  })),
);

documentRouter.post(
  `${BASE}/:id/restore`,
  authRequired,
  documentWriteLimiter,
  managerHandler({ context: 'documents_restore', fallback: 'Belge geri alınamadı.', write: true }, async ({ req, access, limits }) => ({
    body: await restoreDocument({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, limits }),
  })),
);

documentRouter.post(
  `${BASE}/:id/purge`,
  authRequired,
  documentWriteLimiter,
  managerHandler({ context: 'documents_purge', fallback: 'Belge kalıcı olarak silinemedi.', write: true }, async ({ req, access }) => ({
    body: await purgeDocument({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, body: bodyOf(req) }),
  })),
);

documentRouter.post(
  `${BASE}/:id/versions`,
  authRequired,
  documentWriteLimiter,
  managerHandler({ context: 'documents_add_version', fallback: 'Yeni sürüm kaydedilemedi.', write: true }, async ({ req, access, limits }) => {
    const body = bodyOf(req);
    await assertDriveConnected(access.siteCode);
    await assertStorageUsable(limits, Number.isSafeInteger(body?.file?.size) ? body.file.size : 0);
    return { status: 201, body: await addVersion({ siteCode: access.siteCode, rawId: req.params.id, actor: req.authUser, body, limits }) };
  }),
);

documentRouter.delete(
  `${BASE}/:id/versions/:no`,
  authRequired,
  documentWriteLimiter,
  managerHandler({ context: 'documents_delete_version', fallback: 'Sürüm silinemedi.', write: true }, async ({ req, access, limits }) => ({
    body: await deleteVersion({ siteCode: access.siteCode, rawId: req.params.id, rawVersionNo: req.params.no, actor: req.authUser, limits }),
  })),
);

/**
 * İstemci gövdeyi hâlâ gönderirken erken hata yanıtı: Content-Length yok ya da dosya sınırından büyükse gövdenin okunmasını BEKLEMEDEN bağlantı
 * kapatılır (kimliksiz taşıma kötüye kullanımı: 5 GB iddialı gövde boşaltılmaz). Küçük gövdeler Node tarafından boşaltılır (keep-alive korunur).
 */
function guardUnreadBody(req, res, limits) {
  const declared = Number(req.headers['content-length']);
  if (!Number.isFinite(declared) || declared > limits.maxFileBytes) {
    res.setHeader('Connection', 'close');
  }
}

documentRouter.put(`${BASE}/:id/versions/:no/content`, authRequired, documentUploadLimiter, async (req, res) => {
  const limits = documentLimits();
  guardUnreadBody(req, res, limits);
  try {
    const access = await resolveDocumentAccess(req, res, { write: true });
    if (!access) {
      return undefined;
    }
    await assertDriveConnected(access.siteCode);
    const result = await receiveUpload(req, {
      siteCode: access.siteCode,
      rawId: req.params.id,
      rawVersionNo: req.params.no,
      actor: req.authUser,
      limits,
    });
    return res.status(200).json(result.warnings?.length ? { document: result.document, warnings: result.warnings } : { document: result.document });
  } catch (error) {
    if (isClientAborted(error)) {
      return undefined; // istemci kopmuş: yanıt yazılacak yer yok (geçici dosya silindi)
    }
    setRetryAfter(res, error);
    return respondError(res, 'documents_upload', error, 'Dosya yüklenemedi.');
  }
});

documentRouter.get(`${BASE}/:id/download`, authRequired, documentReadLimiter, async (req, res) => {
  try {
    const access = await resolveDocumentAccess(req, res, { write: false });
    if (!access) {
      return undefined;
    }
    const version = await resolveManagerDownload({
      siteCode: access.siteCode,
      rawId: req.params.id,
      versionNo: parseVersionQuery(req.query.version),
      kind: access.kind === 'board' ? 'board' : 'manager',
    });
    return await streamDownload(req, res, { version, context: 'documents_download', countDownload: false });
  } catch (error) {
    return respondError(res, 'documents_download', error, 'Belge indirilemedi.');
  }
});

// --- Sakin -------------------------------------------------------------------------------------------------------------

documentRouter.get(
  '/app/documents',
  authRequired,
  documentReadLimiter,
  appHandler({ context: 'my_documents', fallback: 'Belgeler yüklenemedi.' }, (req) => listMyDocuments(req.authUser, req.query)),
);

documentRouter.get(
  '/app/documents/:id',
  authRequired,
  documentReadLimiter,
  appHandler({ context: 'my_document', fallback: 'Belge yüklenemedi.' }, (req) => getMyDocument(req.authUser, req.params.id)),
);

documentRouter.get('/app/documents/:id/download', authRequired, documentDownloadLimiter, async (req, res) => {
  try {
    const version = await resolveResidentDownload(req.authUser, req.params.id);
    return await streamDownload(req, res, { version, context: 'my_document_download', countDownload: true });
  } catch (error) {
    return respondError(res, 'my_document_download', error, 'Belge indirilemedi.');
  }
});

documentRouter.get('/app/announcements/:id/attachments/:documentId/download', authRequired, documentDownloadLimiter, async (req, res) => {
  try {
    const version = await resolveAnnouncementAttachmentDownload(req.authUser, req.params.id, req.params.documentId);
    return await streamDownload(req, res, { version, context: 'announcement_attachment_download', countDownload: true });
  } catch (error) {
    return respondError(res, 'announcement_attachment_download', error, 'Ek indirilemedi.');
  }
});

