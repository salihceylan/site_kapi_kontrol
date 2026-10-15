// Kişi ve Daire Kayıtları (CRM) uçlarının yetki yardımcısı.
//
// Sözleşme: docs/PLATFORM_KISILER.md ("Sunucu uçları" yetki kuralı):
//  - YAZMA = site yöneticisi (site_manager_sites / aktif SITE_OWNER-SITE_ADMIN) veya süper kullanıcı.
//  - OKUMA = yönetici/süper + o sitenin BOARD_MEMBER'ı (salt okunur).
//  - STAFF ve sakin: 403 FORBIDDEN_ROLE. Başka sitenin yöneticisi/kurul üyesi: 403 FORBIDDEN_SITE.
// requireSiteManager BOARD_MEMBER'ı geçirmediği için okuma uçlarında bu yardımcı kullanılır.

import { pool } from '../db.js';
import { hasSiteManagementAccess } from '../services/site_service.js';
import { parseId } from '../utils/ids.js';

export const FORBIDDEN_ROLE_BODY = Object.freeze({ error: 'Bu işlem için yetkiniz yok.', code: 'FORBIDDEN_ROLE' });
export const FORBIDDEN_SITE_BODY = Object.freeze({
  error: 'Bu site üzerinde yönetim yetkiniz bulunmuyor.',
  code: 'FORBIDDEN_SITE',
});
export const SITE_NOT_FOUND_BODY = Object.freeze({ error: 'Site bulunamadı.', code: 'SITE_NOT_FOUND' });

function userCodeOf(authUser) {
  const parsed = Number(authUser?.userCode ?? authUser?.user_code ?? authUser?.id);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

/**
 * Kullanıcının bu sitedeki ilişkisi: 'super' | 'manager' | 'board' | 'other_site' | 'none' (STAFF/sakin/ilgisiz dahil).
 * Dönen `kind` yetki kararını verir; sorgu sayısı sabittir (2).
 */
export async function getPeopleAccessKind(authUser, siteCode) {
  if (authUser?.role === 'super_user') {
    return 'super';
  }
  if (await hasSiteManagementAccess(authUser, siteCode)) {
    return 'manager';
  }
  const userCode = userCodeOf(authUser);
  if (userCode === null) {
    return 'none';
  }
  const result = await pool.query(
    `
      SELECT
        EXISTS (
          SELECT 1 FROM site_memberships
          WHERE site_code = $1 AND user_code = $2 AND role = 'BOARD_MEMBER' AND is_active = TRUE
        ) AS is_board_here,
        EXISTS (
          SELECT 1 FROM site_memberships
          WHERE site_code = $1 AND user_code = $2 AND is_active = TRUE
        ) AS is_member_here,
        (
          EXISTS (SELECT 1 FROM site_manager_sites WHERE manager_user_code = $2)
          OR EXISTS (
            SELECT 1 FROM site_memberships
            WHERE user_code = $2 AND is_active = TRUE AND role IN ('SITE_OWNER', 'SITE_ADMIN', 'BOARD_MEMBER')
          )
        ) AS has_other_role
    `,
    [Number(siteCode), userCode],
  );
  const row = result.rows?.[0] ?? {};
  if (row.is_board_here === true) {
    return 'board';
  }
  if (row.is_member_here === true) {
    return 'none';
  }
  return row.has_other_role === true ? 'other_site' : 'none';
}

/**
 * :siteCode parametresini doğrular, yetkiyi denetler ve sitenin varlığını doğrular. Hata yanıtını kendisi yazar ve null döner.
 * @param {{ write?: boolean }} [options] write: true ise yalnız yönetici/süper
 * @returns {Promise<{ siteCode: number, kind: string, canWrite: boolean } | null>}
 */
export async function resolvePeopleAccess(req, res, { write = false } = {}) {
  const siteCode = parseId(req.params.siteCode);
  if (siteCode === null) {
    res.status(400).json({ error: 'Geçersiz site kodu.', code: 'INVALID_SITE_CODE' });
    return null;
  }
  const kind = await getPeopleAccessKind(req.authUser, siteCode);
  const canWrite = kind === 'super' || kind === 'manager';
  const canRead = canWrite || kind === 'board';
  if (!canRead || (write && !canWrite)) {
    res.status(403).json(kind === 'other_site' ? FORBIDDEN_SITE_BODY : FORBIDDEN_ROLE_BODY);
    return null;
  }
  const exists = await pool.query(`SELECT site_code FROM sites WHERE site_code = $1 LIMIT 1`, [siteCode]);
  if (!exists.rows?.[0]) {
    res.status(404).json(SITE_NOT_FOUND_BODY);
    return null;
  }
  return { siteCode, kind, canWrite };
}
