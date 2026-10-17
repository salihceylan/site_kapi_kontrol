// Belgeler (Faz 3b-A) yönetici uçlarının yetki ve modül denetimi.
//
// Sözleşme: docs/PLATFORM_BELGELER.md ortak ilke 3. Yetki people_access.js ile AYNIDIR: yazma = yönetici/süper; okuma = yönetici/süper + BOARD_MEMBER
// (salt okunur); STAFF / sakin / ilgisiz 403 FORBIDDEN_ROLE; başka sitenin yöneticisi 403 FORBIDDEN_SITE. `documents` modülü site için KAPALIYSA tüm
// yönetici uçları 403 MODULE_DISABLED ({ module: 'documents' }). Sıra: biçim/yetki/site (people_access) -> modül.

import { resolvePeopleAccess } from './people_access.js';
import { isModuleEnabled } from './module_service.js';
import { DOCUMENTS_MODULE, moduleDisabled } from './document_common.js';

/** Modül kapalıysa 403 MODULE_DISABLED (PlatformError) fırlatır. */
export async function assertDocumentsEnabled(siteCode, db) {
  if (!(await isModuleEnabled(siteCode, DOCUMENTS_MODULE, db))) {
    throw moduleDisabled();
  }
}

/**
 * :siteCode parametresini doğrular, yetkiyi ve `documents` modülünü denetler. Hata yanıtını kendisi yazar ve null döner.
 * @param {{ write?: boolean }} [options] write: yalnız yönetici/süper
 * @returns {Promise<{ siteCode: number, kind: string, canWrite: boolean } | null>}
 */
export async function resolveDocumentAccess(req, res, { write = false } = {}) {
  const access = await resolvePeopleAccess(req, res, { write });
  if (!access) {
    return null;
  }
  if (!(await isModuleEnabled(access.siteCode, DOCUMENTS_MODULE))) {
    const error = moduleDisabled();
    res.status(error.statusCode).json({ error: error.message, code: error.code, ...(error.extra ?? {}) });
    return null;
  }
  return access;
}
