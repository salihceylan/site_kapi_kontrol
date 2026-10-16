// Güvenilir cihaz belirteci (OWASP "device cookie" yaklaşımı) — giriş kilidinin hizmet reddine dönüşmesini önler.
//
// Başarılı girişte sunucu, hesaba bağlı imzalı bir belirteç döner (`device_token`). İstemci bunu saklar ve sonraki
// girişlerde gövdede `device_token` ya da `X-Device-Token` başlığıyla gönderir. Belirteç PAROLA YERİNE GEÇMEZ; yalnızca
// hesap geneli ve IP geneli kilitlerden muaf tutar (dağıtık saldırgan hesabı kilitlese bile sahibinin kayıtlı cihazı
// giriş yapabilir). Bu cihazın kendi (hesap+cihaz) deneme kilidi yine uygulanır.
//
// Parola sürümüne (pv) bağlıdır: parola sıfırlanınca / değişince eski belirteç muafiyet SAĞLAMAZ (istemci yok sayılan
// belirteci sorun etmez; bir sonraki başarılı girişte yenisi verilir).
// Biçim: ldt1.<base64url(JSON {u,d,p,iat,exp})>.<base64url(HMAC-SHA256)>; anahtar JWT_SECRET'tan (ve geçiş penceresinde
// JWT_SECRET_PREVIOUS'tan) ayrı bir etiketle TÜRETİLİR (ham sır kullanılmaz / loglanmaz). JWT_SECRET döndürülünce
// eski belirteçler pencere sonunda düşer; ilk başarılı girişte yenisi verilir.

import crypto from 'node:crypto';
import { evaluateJwtSecret, resolvePreviousJwtSecret } from '../config/env.js';
import { passwordVersionOf } from '../jwt.js';

const PREFIX = 'ldt1';
const KEY_LABEL = 'kapi-login-device-token/v1';
export const DEVICE_TOKEN_TTL_SECONDS = 180 * 24 * 60 * 60;
const MAX_TOKEN_LENGTH = 512;
const DEVICE_ID_PATTERN = /^[A-Za-z0-9_-]{16,64}$/;

function deriveKey(secret) {
  return crypto.createHmac('sha256', String(secret)).update(KEY_LABEL).digest();
}

function currentKey(env) {
  const check = evaluateJwtSecret(env.JWT_SECRET);
  return check.ok ? deriveKey(env.JWT_SECRET) : null;
}

function verificationKeys(env, nowMs) {
  const keys = [];
  const current = currentKey(env);
  if (current) {
    keys.push(current);
  }
  const previous = resolvePreviousJwtSecret(env, nowMs);
  if (previous.secret) {
    keys.push(deriveKey(previous.secret));
  }
  return keys;
}

function sign(key, body) {
  return crypto.createHmac('sha256', key).update(`${PREFIX}.${body}`).digest('base64url');
}

export function newDeviceId() {
  return crypto.randomBytes(18).toString('base64url');
}

/**
 * @returns {string|null} belirteç; JWT_SECRET kullanılamıyorsa null (giriş yine de çalışır).
 */
export function issueDeviceToken({ userCode, deviceId, passwordHash }, { env = process.env, nowMs = Date.now() } = {}) {
  const code = Number(userCode);
  const id = DEVICE_ID_PATTERN.test(String(deviceId ?? '')) ? String(deviceId) : newDeviceId();
  // pv: parola sürümü (jwt.js passwordVersionOf). Parola sıfırlanınca / değişince belirteç kendiliğinden geçersizleşir.
  const pv = passwordVersionOf(passwordHash);
  if (!Number.isSafeInteger(code) || code <= 0 || !pv) {
    return null;
  }
  const key = currentKey(env);
  if (!key) {
    return null;
  }
  const iat = Math.floor(nowMs / 1000);
  const body = Buffer.from(JSON.stringify({ u: code, d: id, p: pv, iat, exp: iat + DEVICE_TOKEN_TTL_SECONDS })).toString('base64url');
  return `${PREFIX}.${body}.${sign(key, body)}`;
}

/**
 * İmza + süre doğrulaması. Geçersiz/eksik/süresi dolmuşsa null (hata fırlatmaz: giriş akışı belirteçsiz devam eder).
 * @returns {{ userCode: number, deviceId: string } | null}
 */
export function verifyDeviceToken(token, { env = process.env, nowMs = Date.now() } = {}) {
  if (typeof token !== 'string' || token.length === 0 || token.length > MAX_TOKEN_LENGTH) {
    return null;
  }
  const parts = token.split('.');
  if (parts.length !== 3 || parts[0] !== PREFIX || !parts[1] || !parts[2]) {
    return null;
  }
  const [, body, signature] = parts;
  const given = Buffer.from(signature);
  const matched = verificationKeys(env, nowMs).some((key) => {
    const expected = Buffer.from(sign(key, body));
    return expected.length === given.length && crypto.timingSafeEqual(expected, given);
  });
  if (!matched) {
    return null;
  }
  let payload;
  try {
    payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
  } catch (_error) {
    return null;
  }
  const userCode = Number(payload?.u);
  const nowSeconds = Math.floor(nowMs / 1000);
  if (
    !Number.isSafeInteger(userCode) ||
    userCode <= 0 ||
    !DEVICE_ID_PATTERN.test(String(payload?.d ?? '')) ||
    typeof payload?.p !== 'string' ||
    payload.p.length === 0 ||
    typeof payload?.exp !== 'number' ||
    payload.exp <= nowSeconds
  ) {
    return null;
  }
  return { userCode, deviceId: String(payload.d), pv: payload.p };
}

/**
 * Belirteç bu hesabın GÜNCEL parola sürümüne mi ait? (sabit zamanlı). Parola değişmiş/sıfırlanmışsa false.
 */
export function deviceTokenMatchesPassword(device, passwordHash) {
  const expected = passwordVersionOf(passwordHash);
  if (!device || typeof device.pv !== 'string' || !expected) {
    return false;
  }
  const a = Buffer.from(device.pv);
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/** İstekten belirteç: gövde `device_token` ya da `X-Device-Token` başlığı. */
export function readDeviceToken(req) {
  const fromBody = req?.body?.device_token;
  if (typeof fromBody === 'string' && fromBody) {
    return fromBody;
  }
  const fromHeader = req?.headers?.['x-device-token'];
  return typeof fromHeader === 'string' && fromHeader ? fromHeader : null;
}

/**
 * Parola değişiminden sonra (kimliği doğrulanmış oturum + mevcut parola kanıtı) YENİ parola sürümüne bağlı belirteç.
 * İstemcinin gönderdiği belirteç (imzası geçerli ve aynı hesaba aitse) cihaz kimliği korunur; eski pv'ye bağlı olması
 * beklenir ve sorun değildir. Gönderilmemiş / geçersizse girişteki gibi yeni cihaz kimliği. Sır yoksa null.
 */
export function reissueDeviceToken({ presented, userCode, passwordHash }, options = {}) {
  const device = verifyDeviceToken(presented, options);
  const code = Number(userCode);
  const deviceId = device && device.userCode === code ? device.deviceId : undefined;
  return issueDeviceToken({ userCode: code, deviceId, passwordHash }, options);
}
