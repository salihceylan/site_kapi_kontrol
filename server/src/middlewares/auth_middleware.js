import { pool } from '../db.js';
import { isPasswordVersionValid, verifyAccessToken } from '../jwt.js';

// jsonwebtoken dogrulama hatalari (gecersiz/suresi dolmus/imza hatali) -> 401.
// Bunun disindaki hatalar (DB kesintisi, yapilandirma) 401 DEGIL 5xx olmalidir; aksi halde
// gecici bir DB sorunu tum istemcileri "oturum gecersiz" diye cikisa zorlar.
function isTokenVerificationError(error) {
  const name = error?.name;
  return name === 'JsonWebTokenError' || name === 'TokenExpiredError' || name === 'NotBeforeError';
}

// Zorunlu parola degisimi (must_change_password): yonetimin verdigi gecici parola / PIN ile acilan oturum YALNIZ parolayi degistirebilsin diye bu
// uclar disindaki TUM kimlik dogrulamali uclar 403 PASSWORD_CHANGE_REQUIRED doner (eskiden bayrak yalniz yanita konan bir ipucuydu; API dogrudan
// kullanilarak atlanabilirdi). Izinli: oturum bilgisi (GET /me), parola degistirme (PATCH /me ve daire sakini kendi parolasi), yasal onay uclari
// (GET|POST /me/consents) ve cikis (sunucuda oturum yoktur; telefon bildirimi cihaz kaydi silinebilir: DELETE /app/push/devices/:id).
// Token yenileme ucu yoktur (JWT sure sonunda yeniden giris).
const PASSWORD_CHANGE_EXEMPT = Object.freeze([
  { method: 'GET', pattern: /^\/me$/ },
  { method: 'PATCH', pattern: /^\/me$/ },
  { method: 'GET', pattern: /^\/me\/consents$/ },
  { method: 'POST', pattern: /^\/me\/consents$/ },
  { method: 'POST', pattern: /^\/membership\/apartments\/\d+\/members\/\d+\/change-password$/ },
  { method: 'DELETE', pattern: /^\/app\/push\/devices\/[^/]+$/ },
]);

/** Istek, zorunlu parola degisimi bekleyen oturumun yapabilecegi uclardan biri mi? (sorgu dizesi ve sondaki egik cizgi yok sayilir) */
export function isPasswordChangeExempt(req) {
  const path = String(req?.originalUrl ?? req?.url ?? '').split('?')[0].replace(/\/+$/, '') || '/';
  const method = String(req?.method ?? '').toUpperCase();
  return PASSWORD_CHANGE_EXEMPT.some((rule) => rule.method === method && rule.pattern.test(path));
}

export async function authRequired(req, res, next) {
  const header = String(req.headers.authorization || '');
  if (!header.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Yetkisiz erisim.' });
  }

  const token = header.slice('Bearer '.length).trim();
  let claims;
  try {
    claims = verifyAccessToken(token);
  } catch (error) {
    if (isTokenVerificationError(error)) {
      return res.status(401).json({ error: 'Gecersiz veya suresi dolmus token.' });
    }
    return next(error);
  }
  req.auth = claims;

  const userCode = Number(claims?.sub);
  if (!Number.isSafeInteger(userCode) || userCode <= 0) {
    return res.status(401).json({ error: 'Gecersiz token.' });
  }

  try {
    // Rol / aktiflik / onay durumu HER istekte DB'den TAZE okunur (token'daki role guvenilmez).
    const result = await pool.query(
      `
      SELECT
        id AS db_id,
        user_code AS id,
        user_code,
        full_name,
        email,
        login_name,
        role,
        is_active,
        email_verified,
        approval_status,
        phone_number,
        created_at,
        deleted_at,
        password_hash,
        (COALESCE(users.must_change_password, FALSE) OR EXISTS (
          SELECT 1 FROM apartments a WHERE a.resident_user_code = users.user_code AND a.resident_pin_issued = TRUE
        )) AS must_change_password
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
    const passwordHash = authUser.password_hash;
    // Parola hash'i istek nesnesine tasinmaz (yanlislikla yanita sizmasin).
    delete authUser.password_hash;

    // Silinmis (kimliksizlestirilmis) hesap: pv claim'i olmayan eski tokenlar dahil HER token 401 ile reddedilir (istemci oturumu kapatir).
    // Hesap ayrica pasif + parola ozeti degismis olur; bu kontrol "Hesap aktif degil" (403) yerine acik bir kod verir.
    const accountDeleted = Boolean(authUser.deleted_at);
    delete authUser.deleted_at;
    if (accountDeleted) {
      return res.status(401).json({ error: 'Bu hesap silinmis.', code: 'ACCOUNT_DELETED' });
    }

    // pv zorunlu (JWT_REQUIRE_PV=0 ile kapatilmadikca): parola degisimi sonrasi eski tokenlar ve pv'siz tokenlar reddedilir.
    if (!isPasswordVersionValid(claims, passwordHash)) {
      return res
        .status(401)
        .json({ error: 'Oturum gecersiz. Lutfen tekrar giris yapin.', code: 'TOKEN_REVOKED' });
    }

    authUser.userCode = authUser.user_code;
    authUser.userId = authUser.db_id;
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

    if (authUser.must_change_password === true && !isPasswordChangeExempt(req)) {
      return res.status(403).json({
        error: 'Devam etmeden once yeni bir sifre belirlemelisiniz.',
        code: 'PASSWORD_CHANGE_REQUIRED',
      });
    }

    req.authUser = authUser;
    return next();
  } catch (error) {
    return next(error);
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

export async function requireSiteManager(req, res, next) {
  try {
    if (['site_manager', 'super_user'].includes(req.authUser?.role)) {
      return next();
    }
    const userCode = Number(req.authUser?.userCode || req.authUser?.id);
    if (Number.isInteger(userCode)) {
      const isManagerRes = await pool.query(
        `SELECT 1 FROM site_manager_sites WHERE manager_user_code = $1 LIMIT 1`,
        [userCode],
      );
      if (isManagerRes.rowCount > 0) {
        return next();
      }
      const isOwnerRes = await pool.query(
        `SELECT 1 FROM site_memberships WHERE user_code = $1 AND role IN ('SITE_OWNER', 'SITE_ADMIN') AND is_active = TRUE LIMIT 1`,
        [userCode],
      );
      if (isOwnerRes.rowCount > 0) {
        return next();
      }
    }
    return res
      .status(403)
      .json({ error: 'Bu islem icin site yoneticisi yetkisi gerekir.' });
  } catch (err) {
    return next(err);
  }
}

export function getAuthUserCode(req) {
  const userCode = Number(req.authUser?.id);
  return Number.isInteger(userCode) ? userCode : null;
}

