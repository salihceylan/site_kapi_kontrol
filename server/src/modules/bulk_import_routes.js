// Toplu yükleme ve dışa aktarma uçları (Faz 2b).
//
//   GET   /manager/sites/:siteCode/imports/spec
//   POST  /manager/sites/:siteCode/imports/:kind/preview      (yazmaz)
//   POST  /manager/sites/:siteCode/imports/:kind/commit
//   POST  /manager/sites/:siteCode/imports/:kind/accounts     (yazmaz; önizleme tablosundaki kullanıcı adı önerileri, yalnız people / all_in_one)
//   POST  /manager/sites/:siteCode/imports/login-names/check  (yazmaz; yöneticinin yazdığı tek kullanıcı adının biçimi + sistemdeki kullanılabilirliği)
//   GET   /manager/sites/:siteCode/exports/:kind
//
// Yetki: yalnız site yöneticisi / süper kullanıcı (people_access: resolvePeopleAccess write:true). Kurul, görevli, sakin 403 FORBIDDEN_ROLE; başka sitenin
// yöneticisi 403 FORBIDDEN_SITE; kimliksiz 401. `people` çekirdek modüldür (MODULE_DISABLED yok). Hata gövdesi { error, code }; 5xx { error, errorId }.
// Sözleşme: docs/PLATFORM_TOPLU_ISLEMLER.md. Günlüğe kişisel veri yazılmaz (yalnız hata kodu ve errorId).
//
// Gövde sınırı: preview/commit için 5 MB, YALNIZ authRequired + yetki + hız sınırlayıcıdan SONRA (anonim istek 5 MB okutamaz). `bulkPreviewGate` /
// `bulkCommitGate` server.js'te genel 1 MB'lık ayrıştırıcıdan ÖNCE bağlanır (labeled-devices kalıbı) ve aynı zincir router'da da bulunur; çift işlem
// bayraklarla engellenir (ikinci geçiş yalnızca atlar: kimlik, sayaç ve ayrıştırma ikinci kez çalışmaz).

import express from 'express';
import { authRequired } from '../middlewares/auth_middleware.js';
import { newErrorId } from '../middlewares/error_handler.js';
import { createRuleLimiter } from '../middlewares/rate_limiters.js';
import { isPlatformError } from './errors.js';
import { resolvePeopleAccess } from './people_access.js';
import { buildExport } from './bulk_import_export.js';
import { checkImportLoginName, commitImport, previewAccounts, previewImport } from './bulk_import_service.js';
import { isModuleEnabled } from './module_service.js';
import { KIND_MODULE, MAX_BODY_BYTES, buildSpec, isBulkKind, isImportDisabled } from './bulk_import_spec.js';
import { HOUR_MS, ipKey, userKey } from './route_helpers.js';

export const bulkImportRouter = express.Router();

const limiter = (userMax, ipMax, message) =>
  createRuleLimiter({
    rules: [
      { windowMs: HOUR_MS, max: userMax, key: userKey },
      { windowMs: HOUR_MS, max: ipMax, key: ipKey },
    ],
    message,
    includeRetryBody: true,
  });

export const importSpecLimiter = limiter(1200, 12000, 'Çok fazla istek. Biraz sonra tekrar deneyin.');
export const importPreviewLimiter = limiter(30, 120, 'Çok fazla önizleme isteği. Biraz sonra tekrar deneyin.');
export const importCommitLimiter = limiter(10, 60, 'Çok fazla yükleme isteği. Biraz sonra tekrar deneyin.');
// Kullanıcı adı önerisi ve tek ad denetimi tablo düzenlemelerinde sık çağrılır (istemci bekletmeli çağırır): önizlemeden AYRI, daha geniş sınır.
// Sistem genelinde ad var/yok sorusu olduğundan sınırsız bırakılmaz (yalnız site yöneticisi/süper kullanıcı erişir).
export const importAccountsLimiter = limiter(240, 1200, 'Çok fazla kullanıcı adı isteği. Biraz sonra tekrar deneyin.');
export const loginNameCheckLimiter = limiter(600, 3000, 'Çok fazla kullanıcı adı denetimi. Biraz sonra tekrar deneyin.');
export const exportLimiter = limiter(30, 300, 'Çok fazla dışa aktarma isteği. Biraz sonra tekrar deneyin.');

const BODY_SIZE_LABEL = `${MAX_BODY_BYTES / (1024 * 1024)} MB`;

function respond(res, context, error, fallback) {
  if (isPlatformError(error)) {
    return res.status(error.statusCode).json({ error: error.message, code: error.code, ...(error.extra ?? {}) });
  }
  const errorId = newErrorId();
  // Günlüğe kişisel veri yazılmaz: hata iletisi/yığın (hücre değeri içerebilir) yerine yalnız hata sınıfı ve PG kodu.
  console.error(`[bulk_import] ${context} (errorId=${errorId}) code=${error?.code ?? 'none'} name=${error?.name ?? 'Error'} constraint=${error?.constraint ?? '-'}`);
  return res.status(500).json({ error: fallback, errorId });
}

/** Bir kez çalışan sarmalayıcı: aynı istekte ikinci geçişte atlar (server.js + router çift bağlantısı). */
function once(flag, middleware) {
  return (req, res, next) => {
    if (req[flag] === true) {
      return next();
    }
    req[flag] = true;
    return middleware(req, res, next);
  };
}

/** Kimlik doğrulama: zaten doğrulanmışsa (server.js kapısı) atlar. `req.authUser` yalnız authRequired tarafından doldurulur. */
export const authOnce = (req, res, next) => (req.authUser ? next() : authRequired(req, res, next));

/** Yetki (yönetici/süper) + tür + kapatma anahtarı. Başarıda req.bulkAccess doldurulur; hatada yanıtı kendisi yazar. */
function accessStep({ needsKind }) {
  return async (req, res, next) => {
    try {
      if (req.bulkAccess) {
        return next();
      }
      const access = await resolvePeopleAccess(req, res, { write: true });
      if (!access) {
        return undefined;
      }
      if (isImportDisabled()) {
        return res.status(503).json({ error: 'Toplu işlemler geçici olarak kapalı.', code: 'IMPORT_DISABLED' });
      }
      if (needsKind && !isBulkKind(req.params.kind)) {
        return res.status(404).json({ error: 'Yükleme türü bulunamadı.', code: 'IMPORT_KIND_NOT_FOUND' });
      }
      const moduleCode = KIND_MODULE[req.params.kind];
      if (needsKind && moduleCode && !(await isModuleEnabled(access.siteCode, moduleCode))) {
        return res.status(403).json({ error: 'Bu modül site için kapalı.', code: 'MODULE_DISABLED', module: moduleCode });
      }
      req.bulkAccess = access;
      return next();
    } catch (error) {
      return respond(res, 'access', error, 'İstek işlenemedi.');
    }
  };
}

const jsonParser = express.json({ limit: '5mb' });

/** 5 MB JSON ayrıştırıcı; hata gövdeleri { error, code }. Gövde zaten ayrıştırıldıysa atlar. */
function parseStep(req, res, next) {
  if (req._body === true) {
    return next();
  }
  return jsonParser(req, res, (error) => {
    if (!error) {
      return next();
    }
    if (error.type === 'entity.too.large') {
      return res.status(413).json({ error: `Dosya çok büyük. Bir seferde en çok ${BODY_SIZE_LABEL} gönderilebilir.`, code: 'PAYLOAD_TOO_LARGE' });
    }
    return res.status(400).json({ error: 'İstek gövdesi geçersiz.', code: 'INVALID_BODY' });
  });
}

/** server.js için: genel 1 MB'lık ayrıştırıcıdan ÖNCE bağlanır. Sıra: kimlik -> hız sınırı -> yetki -> 5 MB ayrıştırma. */
export const bulkPreviewGate = Object.freeze([
  once('bulkAuthDone', authOnce),
  once('bulkPreviewLimited', importPreviewLimiter),
  accessStep({ needsKind: true }),
  parseStep,
]);
export const bulkCommitGate = Object.freeze([
  once('bulkAuthDone', authOnce),
  once('bulkCommitLimited', importCommitLimiter),
  accessStep({ needsKind: true }),
  parseStep,
]);

/** Kullanıcı adı önerisi: önizleme ile aynı gövde (5 MB) ve aynı kapı sırası, ayrı hız sınırı. */
export const bulkAccountsGate = Object.freeze([
  once('bulkAuthDone', authOnce),
  once('bulkAccountsLimited', importAccountsLimiter),
  accessStep({ needsKind: true }),
  parseStep,
]);

/** server.js'te bağlanacak yollar. */
export const BULK_PREVIEW_PATH = '/manager/sites/:siteCode/imports/:kind/preview';
export const BULK_COMMIT_PATH = '/manager/sites/:siteCode/imports/:kind/commit';
export const BULK_ACCOUNTS_PATH = '/manager/sites/:siteCode/imports/:kind/accounts';

function noStore(res) {
  res.setHeader('Cache-Control', 'no-store');
}

// --- spec -------------------------------------------------------------------------------------------------------

bulkImportRouter.get(
  '/manager/sites/:siteCode/imports/spec',
  authOnce,
  importSpecLimiter,
  accessStep({ needsKind: false }),
  (req, res) => {
    noStore(res);
    return res.status(200).json(buildSpec());
  },
);

// --- önizleme / commit ------------------------------------------------------------------------------------------

bulkImportRouter.post(BULK_PREVIEW_PATH, ...bulkPreviewGate, async (req, res) => {
  try {
    const body = await previewImport({ siteCode: req.bulkAccess.siteCode, kind: req.params.kind, body: req.body });
    noStore(res);
    return res.status(200).json(body);
  } catch (error) {
    return respond(res, 'preview', error, 'Önizleme hazırlanamadı.');
  }
});

bulkImportRouter.post(BULK_COMMIT_PATH, ...bulkCommitGate, async (req, res) => {
  try {
    const { status, body } = await commitImport({
      siteCode: req.bulkAccess.siteCode,
      kind: req.params.kind,
      body: req.body,
      actor: req.authUser,
    });
    noStore(res);
    return res.status(status).json(body);
  } catch (error) {
    return respond(res, 'commit', error, 'Yükleme tamamlanamadı.');
  }
});

bulkImportRouter.post(BULK_ACCOUNTS_PATH, ...bulkAccountsGate, async (req, res) => {
  try {
    const body = await previewAccounts({ siteCode: req.bulkAccess.siteCode, kind: req.params.kind, body: req.body });
    noStore(res);
    return res.status(200).json(body);
  } catch (error) {
    return respond(res, 'accounts', error, 'Kullanıcı adları hazırlanamadı.');
  }
});

// Tek kullanıcı adı denetimi: küçük gövde (genel 1 MB ayrıştırıcı yeter); kimlik -> hız sınırı -> yetki -> ayrıştırma sırası aynıdır.
bulkImportRouter.post(
  '/manager/sites/:siteCode/imports/login-names/check',
  authOnce,
  loginNameCheckLimiter,
  accessStep({ needsKind: false }),
  async (req, res) => {
    try {
      const body = await checkImportLoginName({ body: req.body });
      noStore(res);
      return res.status(200).json(body);
    } catch (error) {
      return respond(res, 'login_name_check', error, 'Kullanıcı adı denetlenemedi.');
    }
  },
);

// --- dışa aktarma -----------------------------------------------------------------------------------------------

bulkImportRouter.get(
  '/manager/sites/:siteCode/exports/:kind',
  authOnce,
  exportLimiter,
  accessStep({ needsKind: true }),
  async (req, res) => {
    try {
      const envelope = await buildExport({ siteCode: req.bulkAccess.siteCode, kind: req.params.kind, query: req.query, actor: req.authUser });
      noStore(res);
      return res.status(200).json(envelope);
    } catch (error) {
      return respond(res, 'export', error, 'Dışa aktarma hazırlanamadı.');
    }
  },
);
