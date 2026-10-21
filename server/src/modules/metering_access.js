// Sayac Okuma uclarinin yetki ve modul denetimi. Yetki people_access ile AYNI: yazma = yonetici/super; okuma = + BOARD_MEMBER; STAFF ve sakin 403 FORBIDDEN_ROLE;
// baska site 403 FORBIDDEN_SITE. `metering` modulu kapaliysa 403 MODULE_DISABLED ({ module: 'metering' }). Sira: bicim -> yetki -> site -> modul.

import { resolvePeopleAccess } from './people_access.js';
import { isModuleEnabled } from './module_service.js';
import { METERING_MODULE, moduleDisabled } from './metering_common.js';

export async function resolveMeteringAccess(req, res, { write = false } = {}) {
  const access = await resolvePeopleAccess(req, res, { write });
  if (!access) return null;
  if (!(await isModuleEnabled(access.siteCode, METERING_MODULE))) {
    const error = moduleDisabled();
    res.status(error.statusCode).json({ error: error.message, code: error.code, ...(error.extra ?? {}) });
    return null;
  }
  return access;
}
