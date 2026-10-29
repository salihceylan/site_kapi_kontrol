import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import {
  evaluateJwtSecret,
  isPasswordVersionRequired,
  resolveJwtExpiresSeconds,
  resolvePreviousJwtSecret,
} from './config/env.js';

// Erisim tokeni ilkeleri (S-C):
// - Algoritma HS256'ya SABIT (imzalama ve dogrulama); "none"/HS384/RS* reddedilir.
// - `exp` ZORUNLU: exp'siz (suresiz) token, imzasi dogru olsa bile reddedilir.
// - Asgari claim: sub (user_code) + pv (parola surumu) + iat/exp. E-posta / rol tokena YAZILMAZ (kisisel veri tokende
//   tasinmaz; rol her istekte DB'den taze okunur). Eski tokenlardaki email/role claim'leri yok sayilir.
// - Omur: JWT_EXPIRES_IN (yalniz rakam = saniye), varsayilan 30 gun, ust sinir 90 gun (config/env.js).
// - Sir dondurme: JWT_SECRET_PREVIOUS yalnizca DOGRULAMADA ve JWT_SECRET_PREVIOUS_UNTIL anina kadar denenir.

export const JWT_ALGORITHM = 'HS256';
export const DEFAULT_JWT_EXPIRES_IN = '30d';

const VERIFY_OPTIONS = Object.freeze({ algorithms: [JWT_ALGORITHM] });

let shortSecretWarned = false;

// Test yardimcisi: kisa secret uyarisini yeniden uretilebilir hale getirir.
export function resetJwtSecretWarning() {
  shortSecretWarned = false;
}

function getJwtSecret() {
  const secret = process.env.JWT_SECRET;
  const check = evaluateJwtSecret(secret);
  if (!check.ok) {
    throw new Error(check.message);
  }
  if (check.warning && !shortSecretWarned) {
    shortSecretWarned = true;
    // Kisa (<32) secret yalnizca uyarilir; uretimde sunucu ACILMALI (bkz. config/env.js jwtHardeningWarnings).
    // eslint-disable-next-line no-console
    console.warn(`[JWT] ${check.warning}`);
  }
  return String(secret);
}

/**
 * Parola surumu (pv): parola hash'inden turetilen, geri cevrilemez kisa parmak izi.
 * Parola degisince (hash degisir) pv de degisir ve eski pv'li tokenlar gecersiz olur.
 */
export function passwordVersionOf(passwordHash) {
  const hash = String(passwordHash ?? '');
  if (!hash) {
    return null;
  }
  return crypto.createHash('sha256').update(`pv1:${hash}`).digest('base64url').slice(0, 16);
}

/**
 * Token'daki pv claim'i guncel parola hash'iyle uyusuyor mu?
 * Claim'i olmayan (eski) tokenlar REDDEDILIR (varsayilan; NODE_ENV'den bagimsiz). Yalniz acikca JWT_REQUIRE_PV=0 ise
 * suresi dolana kadar gecerli sayilir (acilista GUVENLIK uyarisi).
 */
export function isPasswordVersionValid(claims, passwordHash) {
  if (claims === null || claims === undefined || claims.pv === undefined) {
    return !isPasswordVersionRequired(process.env);
  }
  if (typeof claims.pv !== 'string') {
    return false;
  }
  const expected = passwordVersionOf(passwordHash);
  if (!expected) {
    return false;
  }
  const a = Buffer.from(claims.pv);
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function effectiveExpiresSeconds(requested) {
  const configured = resolveJwtExpiresSeconds(process.env);
  const short = Number(requested);
  if (requested === undefined || requested === null || !Number.isFinite(short) || short <= 0) {
    return configured;
  }
  return Math.min(Math.max(1, Math.floor(short)), configured);
}

/**
 * @param user  { id, ... }  (yalnizca id kullanilir; email/role tokena yazilmaz)
 * @param options.expiresInSeconds  istege bagli KISA omur (deneme oturumu: 72 saat); yapilandirilmis omru ASLA uzatmaz (kucuk olan secilir)
 * @param options.passwordHash  pv claim'i icin guncel parola hash'i (yoksa user.password_hash,
 *                              o da yoksa token pv'siz uretilir; pv zorunluyken boyle bir token dogrulamada reddedilir)
 */
export function signAccessToken(user, options = {}) {
  const payload = {
    sub: String(user.id),
  };
  const passwordHash = options?.passwordHash ?? user?.password_hash;
  const pv = passwordVersionOf(passwordHash);
  if (pv) {
    payload.pv = pv;
  }
  return jwt.sign(payload, getJwtSecret(), {
    algorithm: JWT_ALGORITHM,
    expiresIn: effectiveExpiresSeconds(options?.expiresInSeconds),
  });
}

function requireExpiry(claims) {
  if (!claims || typeof claims !== 'object' || typeof claims.exp !== 'number' || !Number.isFinite(claims.exp)) {
    throw new jwt.JsonWebTokenError('jwt exp claim required');
  }
  return claims;
}

function isSignatureMismatch(error) {
  return error?.name === 'JsonWebTokenError' && error?.message === 'invalid signature';
}

/**
 * Dogrulama: once guncel sir; imza uyusmazsa ve gecis penceresi aciksa JWT_SECRET_PREVIOUS. Hata turleri
 * jsonwebtoken'inkilerdir (JsonWebTokenError / TokenExpiredError) -> authRequired bunlari 401'e cevirir.
 */
export function verifyAccessToken(token) {
  const secret = getJwtSecret();
  try {
    return requireExpiry(jwt.verify(token, secret, VERIFY_OPTIONS));
  } catch (error) {
    if (!isSignatureMismatch(error)) {
      throw error;
    }
    const previous = resolvePreviousJwtSecret(process.env);
    if (!previous.secret) {
      throw error;
    }
    return requireExpiry(jwt.verify(token, previous.secret, VERIFY_OPTIONS));
  }
}
