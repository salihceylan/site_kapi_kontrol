// Ek roller: BOARD_MEMBER (Yönetim Kurulu / Denetçi) ve STAFF (Görevli) — site_memberships.role değerleridir.
//
// Sözleşme: docs/PLATFORM_MODUL_SISTEMI.md ("Ek roller"). Kullanıcının genel rolü (users.role) DEĞİŞMEZ.
// requireSiteManager / hasSiteManagementAccess bu rolleri YÖNETİCİ saymaz (yalnız SITE_OWNER/SITE_ADMIN sayılır).
// Kapı/daire yetkisi apartment_memberships'te ayrıdır; burada dokunulmaz.

import { pool } from '../db.js';
import { isValidEmail } from '../utils/validators.js';
import { actorFromAuthUser, recordAudit } from './audit_service.js';
import { PlatformError } from './errors.js';

export const STAFF_ROLES = Object.freeze(['BOARD_MEMBER', 'STAFF']);

function toIso(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function mapStaffRoleRow(row) {
  return {
    user_code: Number(row.user_code),
    full_name: row.full_name ?? null,
    email: row.email ?? null,
    role: row.role,
    created_at: toIso(row.created_at),
  };
}

const INT32_MAX = 2147483647;

function positiveInt(value, max = Number.MAX_SAFE_INTEGER) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 && parsed <= max ? parsed : null;
}

async function rollbackQuietly(client) {
  try {
    await client.query('ROLLBACK');
  } catch (_error) {
    // bağlantı zaten kopmuş olabilir; asıl hata yukarıda fırlatılır
  }
}

/** GET: yalnız aktif kurul/görevli üyelikleri. */
export async function listStaffRoles(siteCode, db = pool) {
  const code = positiveInt(siteCode);
  if (code === null) {
    throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  }
  const siteResult = await db.query(`SELECT site_code FROM sites WHERE site_code = $1 LIMIT 1`, [code]);
  if (!siteResult.rows?.[0]) {
    throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  }
  const result = await db.query(
    `
      SELECT
        sm.user_code,
        u.full_name,
        u.email,
        sm.role,
        sm.created_at
      FROM site_memberships sm
      INNER JOIN users u ON u.user_code = sm.user_code
      WHERE sm.site_code = $1
        AND sm.role IN ('BOARD_MEMBER', 'STAFF')
        AND sm.is_active = TRUE
      ORDER BY sm.created_at ASC, sm.user_code ASC
    `,
    [code],
  );
  return (result.rows ?? []).map(mapStaffRoleRow);
}

/**
 * PUT: e-postaya göre mevcut hesaba kurul/görevli rolü ver (yoksa 404 USER_NOT_FOUND).
 * Aynı kişide mevcut kurul/görevli rolü GÜNCELLENİR (tek satır); RESIDENT ise yükseltilir.
 * Değişiklik varsa audit `staff_role.assigned`; hiçbir şey değişmediyse yazılmaz.
 * @returns {Promise<{ item: object, changed: boolean }>}
 */
export async function assignStaffRole({ siteCode, email, role, actor }) {
  const roleText = typeof role === 'string' ? role.trim() : '';
  if (!STAFF_ROLES.includes(roleText)) {
    throw new PlatformError(400, 'ROLE_INVALID', 'Geçersiz rol.');
  }
  const emailText = typeof email === 'string' ? email.trim().toLowerCase() : '';
  if (!isValidEmail(emailText)) {
    throw new PlatformError(400, 'INVALID_BODY', 'Geçerli bir e-posta adresi giriniz.');
  }
  const code = positiveInt(siteCode);
  if (code === null) {
    throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  }
  const actorInfo = actorFromAuthUser(actor);

  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');

    const siteResult = await client.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR SHARE`, [code]);
    if (!siteResult.rows?.[0]) {
      throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
    }

    const userResult = await client.query(
      `
        SELECT user_code, full_name, email, role, is_active, email_verified, approval_status
        FROM users
        WHERE LOWER(email) = $1
        LIMIT 1
      `,
      [emailText],
    );
    const user = userResult.rows?.[0];
    if (!user) {
      throw new PlatformError(
        404,
        'USER_NOT_FOUND',
        'Bu e-posta ile kayıtlı hesap yok. Kişi kayıtları sonraki aşamada gelecek.',
      );
    }
    if (user.is_active !== true || user.email_verified !== true || user.approval_status !== 'approved') {
      throw new PlatformError(409, 'USER_NOT_ACTIVE', 'Bu hesap henüz etkin değil.');
    }
    const userCode = Number(user.user_code);

    // Aynı (site, kişi) için eşzamanlı atamalar sıraya girer.
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`staff_role:${code}:${userCode}`]);

    const managerResult = await client.query(
      `
        SELECT 1 AS present
        FROM site_manager_sites
        WHERE site_code = $1 AND manager_user_code = $2
        UNION ALL
        SELECT 1
        FROM site_memberships
        WHERE site_code = $1 AND user_code = $2 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE
        LIMIT 1
      `,
      [code, userCode],
    );
    if (user.role === 'super_user' || (managerResult.rows?.length ?? 0) > 0) {
      throw new PlatformError(409, 'ALREADY_SITE_MANAGER', 'Bu kişi zaten site yöneticisi.');
    }

    const existingResult = await client.query(
      `
        SELECT role, is_active
        FROM site_memberships
        WHERE site_code = $1 AND user_code = $2
        LIMIT 1
        FOR UPDATE
      `,
      [code, userCode],
    );
    const existing = existingResult.rows?.[0] ?? null;
    const changed = !existing || existing.role !== roleText || existing.is_active !== true;

    // Yarış koruması: yukarıdaki yönetici denetimi ile bu yazma arasında kişi AKTİF SITE_OWNER/SITE_ADMIN yapıldıysa
    // (başka bir istek), o satır asla kurul/görevliye düşürülmez: WHERE koşulu yüzünden güncelleme olmaz, satır dönmez.
    const upsertResult = await client.query(
      `
        INSERT INTO site_memberships (site_code, user_code, role, is_active)
        VALUES ($1, $2, $3, TRUE)
        ON CONFLICT (site_code, user_code)
        DO UPDATE SET role = EXCLUDED.role, is_active = TRUE, updated_at = NOW()
        WHERE site_memberships.role NOT IN ('SITE_OWNER', 'SITE_ADMIN') OR site_memberships.is_active = FALSE
        RETURNING created_at
      `,
      [code, userCode, roleText],
    );
    if (!upsertResult.rows?.[0]) {
      throw new PlatformError(409, 'ALREADY_SITE_MANAGER', 'Bu kişi zaten site yöneticisi.');
    }

    if (changed) {
      await recordAudit(
        client,
        {
          actor: actorInfo,
          action: 'staff_role.assigned',
          siteCode: code,
          targetType: 'user',
          targetId: String(userCode),
          details: { role: roleText },
        },
        { inTransaction: true },
      );
    }

    await client.query('COMMIT');
    committed = true;
    return {
      changed,
      item: mapStaffRoleRow({
        user_code: userCode,
        full_name: user.full_name,
        email: user.email,
        role: roleText,
        created_at: upsertResult.rows[0].created_at ?? null,
      }),
    };
  } catch (error) {
    if (!committed) {
      await rollbackQuietly(client);
    }
    throw error;
  } finally {
    client.release();
  }
}

/**
 * DELETE: kurul/görevli satırını siler (RESIDENT'a düşürülmez; kişi dairesindeki yetkileriyle kalır).
 * Satır yoksa 404 ROLE_NOT_FOUND. Audit `staff_role.removed`.
 */
export async function removeStaffRole({ siteCode, userCode, actor }) {
  const code = positiveInt(siteCode);
  const targetCode = positiveInt(userCode, INT32_MAX); // users.user_code INTEGER
  if (code === null) {
    throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
  }
  if (targetCode === null) {
    throw new PlatformError(404, 'ROLE_NOT_FOUND', 'Bu kişide kurul veya görevli rolü yok.');
  }
  const actorInfo = actorFromAuthUser(actor);

  const client = await pool.connect();
  let committed = false;
  try {
    await client.query('BEGIN');
    const siteResult = await client.query(`SELECT site_code FROM sites WHERE site_code = $1 FOR SHARE`, [code]);
    if (!siteResult.rows?.[0]) {
      throw new PlatformError(404, 'SITE_NOT_FOUND', 'Site bulunamadı.');
    }

    const deleted = await client.query(
      `
        DELETE FROM site_memberships
        WHERE site_code = $1 AND user_code = $2 AND role IN ('BOARD_MEMBER', 'STAFF')
        RETURNING role
      `,
      [code, targetCode],
    );
    const removed = deleted.rows?.[0];
    if (!removed) {
      throw new PlatformError(404, 'ROLE_NOT_FOUND', 'Bu kişide kurul veya görevli rolü yok.');
    }

    await recordAudit(
      client,
      {
        actor: actorInfo,
        action: 'staff_role.removed',
        siteCode: code,
        targetType: 'user',
        targetId: String(targetCode),
        details: { role: removed.role },
      },
      { inTransaction: true },
    );

    await client.query('COMMIT');
    committed = true;
    return { ok: true };
  } catch (error) {
    if (!committed) {
      await rollbackQuietly(client);
    }
    throw error;
  } finally {
    client.release();
  }
}
