import { pool } from '../db.js';
import { verifyAccessToken } from '../jwt.js';

export async function authRequired(req, res, next) {
  const header = String(req.headers.authorization || '');
  if (!header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Yetkisiz erisim.' });
  }

  try {
    const token = header.slice('Bearer '.length).trim();
    req.auth = verifyAccessToken(token);
    const userCode = Number(req.auth?.sub);
    if (!Number.isInteger(userCode)) {
      return res.status(401).json({ error: 'Gecersiz token.' });
    }

    const result = await pool.query(
      `
      SELECT
        user_code AS id,
        full_name,
        email,
        login_name,
        role,
        is_active,
        email_verified,
        approval_status,
        phone_number,
        created_at
      FROM users
      WHERE user_code = $1
      LIMIT 1
      `,
      [userCode],
    );

    if (result.rowCount === 0) {
      return res.status(401).json({ error: 'Kullanici bulunamadi.' });
    }

    const authUser = result.rows[0];
    if (!authUser.is_active) {
      return res.status(403).json({ error: 'Hesap aktif degil.' });
    }
    if (!authUser.email_verified) {
      return res.status(403).json({ error: 'E-posta adresiniz dogrulanmadi.' });
    }
    if (authUser.approval_status === 'pending') {
      return res.status(403).json({ error: 'Abonelik talebiniz onay bekliyor.' });
    }
    if (authUser.approval_status === 'rejected') {
      return res.status(403).json({ error: 'Abonelik talebiniz reddedildi.' });
    }

    req.authUser = authUser;
    return next();
  } catch (_e) {
    return res.status(401).json({ error: 'Gecersiz veya suresi dolmus token.' });
  }
}

export function requireSuperUser(req, res, next) {
  if (req.authUser?.role !== 'super_user') {
    return res
      .status(403)
      .json({ error: 'Bu islem icin super user yetkisi gerekir.' });
  }
  return next();
}

export function requireSiteManager(req, res, next) {
  if (!['site_manager', 'super_user'].includes(req.authUser?.role)) {
    return res
      .status(403)
      .json({ error: 'Bu islem icin site yoneticisi yetkisi gerekir.' });
  }
  return next();
}

export function getAuthUserCode(req) {
  const userCode = Number(req.authUser?.id);
  return Number.isInteger(userCode) ? userCode : null;
}
