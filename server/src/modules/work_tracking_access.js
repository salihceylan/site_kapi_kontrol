// İş Takibi yönetim uçlarının yetki ve modül denetimi.
//
// Sözleşme: docs/PLATFORM_IS_TAKIBI.md "Yetki matrisi". Çağıranın bu sitedeki ilişkisi: 'super' | 'manager' | 'staff' | 'board' | 'other_site' | 'none'.
//  - YAZMA = yönetici / süper / görevli (STAFF; yalnız kendine atanmış VEYA atanmamış talepler). OKUMA = yazanlar + BOARD_MEMBER (salt okunur).
//  - Sakin ve ilgisiz: 403 FORBIDDEN_ROLE; başka sitenin yöneticisi / kurulu: 403 FORBIDDEN_SITE; modül kapalıysa 403 MODULE_DISABLED ({ module: 'work_tracking' }).
// Sıra: biçim (400) -> yetki (403) -> site varlığı (404) -> modül (403), people_access / document_access ile aynı.

import { pool } from '../db.js';
import { parseId } from '../utils/ids.js';
import { actorFromAuthUser } from './audit_service.js';
import { FORBIDDEN_ROLE_BODY, FORBIDDEN_SITE_BODY, SITE_NOT_FOUND_BODY, getPeopleAccessKind } from './people_access.js';
import { isModuleEnabled } from './module_service.js';
import { WORK_TRACKING_MODULE, moduleDisabled } from './work_tracking_common.js';

/** Kullanıcının bu sitedeki iş takibi rolü. STAFF, people_access'te 'none' döner; burada ayrıca aranır. */
export async function getWorkAccessKind(authUser, siteCode, db = pool) {
  const kind = await getPeopleAccessKind(authUser, siteCode);
  if (kind === 'super' || kind === 'manager' || kind === 'board') {
    return kind;
  }
  const userCode = actorFromAuthUser(authUser).userCode;
  if (userCode !== null) {
    const staff = await db.query(
      `SELECT 1 FROM site_memberships WHERE site_code = $1 AND user_code = $2 AND role = 'STAFF' AND is_active = TRUE LIMIT 1`,
      [Number(siteCode), userCode],
    );
    if (staff.rows?.[0]) {
      return 'staff';
    }
  }
  return kind;
}

/**
 * :siteCode parametresini doğrular, yetkiyi ve `work_tracking` modülünü denetler. Hata yanıtını kendisi yazar ve null döner.
 * @param {{ write?: boolean }} [options] write: kurul üyesi 403 (yönetici / süper / görevli geçer)
 * @returns {Promise<{ siteCode: number, kind: string, userCode: number|null, canManage: boolean } | null>}
 */
export async function resolveWorkAccess(req, res, { write = false } = {}) {
  const siteCode = parseId(req.params.siteCode);
  if (siteCode === null) {
    res.status(400).json({ error: 'Geçersiz site kodu.', code: 'INVALID_SITE_CODE' });
    return null;
  }
  const kind = await getWorkAccessKind(req.authUser, siteCode);
  const canRead = ['super', 'manager', 'staff', 'board'].includes(kind);
  if (!canRead || (write && kind === 'board')) {
    res.status(403).json(kind === 'other_site' ? FORBIDDEN_SITE_BODY : FORBIDDEN_ROLE_BODY);
    return null;
  }
  const exists = await pool.query(`SELECT site_code FROM sites WHERE site_code = $1 LIMIT 1`, [siteCode]);
  if (!exists.rows?.[0]) {
    res.status(404).json(SITE_NOT_FOUND_BODY);
    return null;
  }
  if (!(await isModuleEnabled(siteCode, WORK_TRACKING_MODULE))) {
    const error = moduleDisabled();
    res.status(error.statusCode).json({ error: error.message, code: error.code, ...(error.extra ?? {}) });
    return null;
  }
  return { siteCode, kind, userCode: actorFromAuthUser(req.authUser).userCode, canManage: kind === 'super' || kind === 'manager' };
}
