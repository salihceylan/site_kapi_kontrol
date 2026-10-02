import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import { evaluateJwtSecret } from './config/env.js';

export const JWT_ALGORITHM = 'HS256';
export const DEFAULT_JWT_EXPIRES_IN = '30d';

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
    // Kisa (<32) secret yalnizca uyarilir; uretimde sunucu ACILMALI.
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
 * Token'daki pv claim'i (varsa) guncel parola hash'iyle uyusuyor mu?
 * Claim'i olmayan (eski) tokenlar suresi dolana kadar gecerli kalir (geriye donuk uyum).
 */
export function isPasswordVersionValid(claims, passwordHash) {
  if (claims === null || claims === undefined || claims.pv === undefined) {
    return true;
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

/**
 * @param user  { id, email, role, password_hash? }
 * @param options.passwordHash  pv claim'i icin guncel parola hash'i (yoksa user.password_hash,
 *                              o da yoksa token pv'siz uretilir = eski davranis)
 */
export function signAccessToken(user, options = {}) {
  const payload = {
    sub: String(user.id),
    email: user.email,
    role: user.role,
  };
  const passwordHash = options?.passwordHash ?? user?.password_hash;
  const pv = passwordVersionOf(passwordHash);
  if (pv) {
    payload.pv = pv;
  }
  return jwt.sign(payload, getJwtSecret(), {
    algorithm: JWT_ALGORITHM,
    expiresIn: process.env.JWT_EXPIRES_IN || DEFAULT_JWT_EXPIRES_IN,
  });
}

export function verifyAccessToken(token) {
  return jwt.verify(token, getJwtSecret(), { algorithms: [JWT_ALGORITHM] });
}
