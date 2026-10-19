// Kartlı Geçiş yönetim uçlarının yetki ve modül denetimi.
//
// Sözleşme: docs/PLATFORM_GECIS_GENISLEME.md "Yetki". Çağıranın bu sitedeki ilişkisi (people_access): 'super' | 'manager' | 'board' | 'other_site' | 'none'.
//  - YAZMA = yönetici / süper. OKUMA = yazanlar + BOARD_MEMBER (salt okunur). STAFF ve sakin: 403 FORBIDDEN_ROLE (görevli kart tanımlayamaz).
//  - Başka sitenin yöneticisi / kurulu: 403 FORBIDDEN_SITE; modül kapalıysa 403 MODULE_DISABLED ({ module: 'card_access' }).
// Sıra: biçim (400) -> yetki (403) -> site varlığı (404) -> modül (403), people_access / work_tracking_access ile aynı.

import { pool } from '../db.js';
import { parseId } from '../utils/ids.js';
import { actorFromAuthUser } from './audit_service.js';
import { FORBIDDEN_ROLE_BODY, FORBIDDEN_SITE_BODY, SITE_NOT_FOUND_BODY, getPeopleAccessKind } from './people_access.js';
import { isModuleEnabled } from './module_service.js';
import { CARD_ACCESS_MODULE, moduleDisabled } from './card_access_common.js';

/**
 * :siteCode parametresini doğrular, yetkiyi ve `card_access` modülünü denetler. Hata yanıtını kendisi yazar ve null döner.
 * @param {{ write?: boolean }} [options] write: kurul üyesi 403 (yönetici / süper geçer)
 * @returns {Promise<{ siteCode: number, kind: string, userCode: number|null, canManage: boolean } | null>}
 */
export async function resolveCardAccess(req, res, { write = false } = {}) {
  const siteCode = parseId(req.params.siteCode);
  if (siteCode === null) {
    res.status(400).json({ error: 'Geçersiz site kodu.', code: 'INVALID_SITE_CODE' });
    return null;
  }
  const kind = await getPeopleAccessKind(req.authUser, siteCode);
  const canRead = ['super', 'manager', 'board'].includes(kind);
  if (!canRead || (write && kind === 'board')) {
    res.status(403).json(kind === 'other_site' ? FORBIDDEN_SITE_BODY : FORBIDDEN_ROLE_BODY);
    return null;
  }
  const exists = await pool.query(`SELECT site_code FROM sites WHERE site_code = $1 LIMIT 1`, [siteCode]);
  if (!exists.rows?.[0]) {
    res.status(404).json(SITE_NOT_FOUND_BODY);
    return null;
  }
  if (!(await isModuleEnabled(siteCode, CARD_ACCESS_MODULE))) {
    const error = moduleDisabled();
    res.status(error.statusCode).json({ error: error.message, code: error.code, ...(error.extra ?? {}) });
    return null;
  }
  return { siteCode, kind, userCode: actorFromAuthUser(req.authUser).userCode, canManage: kind === 'super' || kind === 'manager' };
}
