// Aidat ve Finans (Faz 4a) uçlarının yetki ve modül denetimi.
//
// Sözleşme: docs/PLATFORM_FINANS.md ("İlkeler" madde 6). Yetki people_access.js ile AYNIDIR: yazma = yönetici/süper; okuma = yönetici/süper + BOARD_MEMBER
// (salt okunur); STAFF ve sakin 403 FORBIDDEN_ROLE; başka sitenin yöneticisi 403 FORBIDDEN_SITE. `finance` modülü site için KAPALIYSA tüm finans
// uçları 403 MODULE_DISABLED ({ module: 'finance' }). Sıra: biçim/yetki/site (people_access) -> modül.

import { FORBIDDEN_ROLE_BODY, resolvePeopleAccess } from './people_access.js';
import { isModuleEnabled } from './module_service.js';
import { FINANCE_MODULE, moduleDisabled } from './finance_common.js';

/** Modül kapalıysa 403 MODULE_DISABLED (PlatformError) fırlatır. */
export async function assertFinanceEnabled(siteCode, db) {
  if (!(await isModuleEnabled(siteCode, FINANCE_MODULE, db))) {
    throw moduleDisabled();
  }
}

/**
 * :siteCode parametresini doğrular, yetkiyi ve `finance` modülünü denetler. Hata yanıtını kendisi yazar ve null döner.
 * @param {{ write?: boolean, superOnly?: boolean }} [options] write: yalnız yönetici/süper; superOnly: yalnız süper kullanıcı
 * @returns {Promise<{ siteCode: number, kind: string, canWrite: boolean } | null>}
 */
export async function resolveFinanceAccess(req, res, { write = false, superOnly = false } = {}) {
  const access = await resolvePeopleAccess(req, res, { write: write || superOnly });
  if (!access) {
    return null;
  }
  if (superOnly && access.kind !== 'super') {
    res.status(403).json(FORBIDDEN_ROLE_BODY);
    return null;
  }
  if (!(await isModuleEnabled(access.siteCode, FINANCE_MODULE))) {
    const error = moduleDisabled();
    res.status(error.statusCode).json({ error: error.message, code: error.code, ...(error.extra ?? {}) });
    return null;
  }
  return access;
}
