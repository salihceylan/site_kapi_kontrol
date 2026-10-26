// Beyaz etiket tema (G9) servisi. Çözümleme sırası: site teması > bağlı olduğu firmanın teması > varsayılan (null).
// Düzenleme: süper kullanıcı (her kapsam) ya da firma SAHİBİ (kendi firması ve ona bağlı siteler). Sözleşme: docs/PLATFORM_BEYAZ_ETIKET.md.

import { pool } from '../db.js';
import { recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';
import { companyRoleOf, userCodeOf } from './management_company_service.js';
import { themeFromRow, validateThemeBody } from './brand_theme_common.js';

export const SCOPE_TYPES = Object.freeze(['company', 'site']);

const SELECT_THEME = `SELECT scope_type, scope_id, display_name, color_primary, color_accent, color_background, color_surface, color_text, logo_data, updated_at
  FROM brand_themes WHERE scope_type = $1 AND scope_id = $2`;

async function themeRow(db, scopeType, scopeId) {
  const res = await db.query(SELECT_THEME, [scopeType, scopeId]);
  return res.rows[0] ?? null;
}

/** Sitenin bağlı olduğu AKTİF firma kimliği (yoksa ya da firma pasifse null: pasif firmanın teması siteye miras kalmaz, firma sahibi siteyi düzenleyemez). */
async function companyOfSite(db, siteCode) {
  const res = await db.query(
    `SELECT cs.company_id FROM management_company_sites cs
     JOIN management_companies c ON c.id = cs.company_id AND c.is_active = TRUE
     WHERE cs.site_code = $1`,
    [siteCode],
  );
  return res.rows[0] ? Number(res.rows[0].company_id) : null;
}

/** Site için etkin tema: { theme|null }. */
export async function resolveSiteTheme(db, siteCode) {
  const own = await themeRow(db, 'site', siteCode);
  if (own) return themeFromRow(own, 'site');
  const companyId = await companyOfSite(db, siteCode);
  if (companyId !== null) {
    const inherited = await themeRow(db, 'company', companyId);
    if (inherited) return themeFromRow(inherited, 'company');
  }
  return null;
}

/** Oturumdaki kullanıcının teması: ilk etkin üyelik / yönetilen site, yoksa firma üyeliği; süper kullanıcı ve bağsız kullanıcı varsayılanı alır. */
export async function themeForUser(user, db = pool) {
  const code = userCodeOf(user);
  if (code === null || user?.role === 'super_user') return { theme: null };
  const site = await db.query(
    `SELECT site_code FROM (
       SELECT site_code FROM site_memberships WHERE user_code = $1 AND is_active = TRUE
       UNION
       SELECT site_code FROM site_manager_sites WHERE manager_user_code = $1
     ) s ORDER BY site_code LIMIT 1`,
    [code],
  );
  if (site.rows[0]) return { theme: await resolveSiteTheme(db, Number(site.rows[0].site_code)) };
  // Yalnız AKTİF firmanın üyeliği sayılır (pasif firmanın teması üyesine uygulanmaz).
  const member = await db.query(
    `SELECT m.company_id FROM management_company_members m
     JOIN management_companies c ON c.id = m.company_id AND c.is_active = TRUE
     WHERE m.user_code = $1 ORDER BY m.company_id LIMIT 1`,
    [code],
  );
  if (member.rows[0]) {
    const row = await themeRow(db, 'company', Number(member.rows[0].company_id));
    return { theme: themeFromRow(row, 'company') };
  }
  return { theme: null };
}

function parseScope(scopeTypeRaw, scopeIdRaw) {
  if (!SCOPE_TYPES.includes(scopeTypeRaw)) throw new PlatformError(400, 'INVALID_SCOPE', 'Kapsam company ya da site olmalı.');
  const id = /^\d{1,15}$/.test(String(scopeIdRaw ?? '')) ? Number(scopeIdRaw) : null;
  if (!Number.isSafeInteger(id) || id <= 0) throw new PlatformError(400, 'INVALID_ID', 'Kimlik geçersiz.');
  return { scopeType: scopeTypeRaw, scopeId: id };
}

/** Düzenleme yetkisi; kapsam yoksa 404, yetki yoksa 403. */
async function requireEditor(user, scopeType, scopeId) {
  const isSuper = user?.role === 'super_user';
  if (scopeType === 'company') {
    const exists = await pool.query('SELECT 1 FROM management_companies WHERE id = $1', [scopeId]);
    if (!exists.rows[0]) throw new PlatformError(404, 'COMPANY_NOT_FOUND', 'Yönetim firması bulunamadı.');
    if (isSuper) return;
    // Pasif firma: companyRoleOf null döner -> 404 (süper kullanıcı hariç firma teması düzenlenemez).
    const role = await companyRoleOf(pool, scopeId, user);
    if (role === null) throw new PlatformError(404, 'COMPANY_NOT_FOUND', 'Yönetim firması bulunamadı.');
    if (role !== 'owner') throw new PlatformError(403, 'FORBIDDEN_COMPANY', 'Bu işlem için firma sahibi yetkisi gerekir.');
    return;
  }
  const site = await pool.query('SELECT 1 FROM sites WHERE site_code = $1', [scopeId]);
  if (!site.rows[0]) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  if (isSuper) return;
  const companyId = await companyOfSite(pool, scopeId);
  const role = companyId === null ? null : await companyRoleOf(pool, companyId, user);
  if (role === null) throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  if (role !== 'owner') throw new PlatformError(403, 'FORBIDDEN_COMPANY', 'Bu işlem için firma sahibi yetkisi gerekir.');
}

export async function getEditableTheme({ scopeType: t, scopeId: i, user }) {
  const { scopeType, scopeId } = parseScope(t, i);
  await requireEditor(user, scopeType, scopeId);
  return { theme: themeFromRow(await themeRow(pool, scopeType, scopeId), scopeType), can_edit: true };
}

export async function saveTheme({ scopeType: t, scopeId: i, body, user }) {
  const { scopeType, scopeId } = parseScope(t, i);
  await requireEditor(user, scopeType, scopeId);
  const v = validateThemeBody(body);
  const c = v.colors;
  // logo_data undefined = mevcut logoyu koru; null = kaldır; dize = değiştir.
  const keepLogo = v.logo_data === undefined;
  const res = await pool.query(
    `INSERT INTO brand_themes (scope_type, scope_id, display_name, color_primary, color_accent, color_background, color_surface, color_text, logo_data, updated_by, updated_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW())
     ON CONFLICT (scope_type, scope_id) DO UPDATE SET
       display_name = EXCLUDED.display_name, color_primary = EXCLUDED.color_primary, color_accent = EXCLUDED.color_accent,
       color_background = EXCLUDED.color_background, color_surface = EXCLUDED.color_surface, color_text = EXCLUDED.color_text,
       logo_data = CASE WHEN $11 THEN brand_themes.logo_data ELSE EXCLUDED.logo_data END,
       updated_by = EXCLUDED.updated_by, updated_at = NOW()
     RETURNING scope_type, scope_id, display_name, color_primary, color_accent, color_background, color_surface, color_text, logo_data, updated_at`,
    [scopeType, scopeId, v.display_name, c.primary, c.accent, c.background, c.surface, c.text, keepLogo ? null : v.logo_data, userCodeOf(user), keepLogo],
  );
  await recordAudit(pool, {
    actor: user,
    action: 'brand_theme.saved',
    siteCode: scopeType === 'site' ? scopeId : undefined,
    targetType: 'brand_theme',
    targetId: `${scopeType}:${scopeId}`,
    details: { colors: c, display_name: v.display_name, logo: keepLogo ? 'kept' : v.logo_data ? 'set' : 'removed' },
  });
  return { theme: themeFromRow(res.rows[0], scopeType) };
}

export async function resetTheme({ scopeType: t, scopeId: i, user }) {
  const { scopeType, scopeId } = parseScope(t, i);
  await requireEditor(user, scopeType, scopeId);
  await pool.query('DELETE FROM brand_themes WHERE scope_type = $1 AND scope_id = $2', [scopeType, scopeId]);
  await recordAudit(pool, {
    actor: user,
    action: 'brand_theme.reset',
    siteCode: scopeType === 'site' ? scopeId : undefined,
    targetType: 'brand_theme',
    targetId: `${scopeType}:${scopeId}`,
    details: {},
  });
  return { theme: null };
}
