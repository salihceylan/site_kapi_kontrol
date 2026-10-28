import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import { pool } from '../db.js';
import { signAccessToken } from '../jwt.js';
import { sendIndividualVerificationEmail } from '../mailer.js';
import { BCRYPT_COST } from '../security/password_hashing.js';
import {
  ATTEMPT_POLICIES,
  codeLockedError,
  emailCodeTarget,
  peekAttemptLock,
  registerAttemptFailure,
  resetAttempts,
} from '../security/attempt_limits.js';
import { reissueDeviceToken } from '../security/login_device_token.js';
import { mapUserRow, normalizeEmail } from '../utils/helpers.js';
import { isValidEmail } from '../utils/validators.js';
import { isReservedEmail } from '../utils/reserved_email.js';
import {
  SQL_CLAIM_VERIFICATION_ATTEMPT,
  SQL_CONSUME_VERIFICATION_CODE,
  SQL_SUPERSEDE_OLDER_VERIFICATION_CODES,
  SQL_SUPERSEDE_VERIFICATION_CODES,
  SQL_VERIFICATION_ISSUE_STATE,
  SQL_VERIFICATION_STATE,
  VERIFICATION_CODE_DIGITS,
  VERIFICATION_CODE_TTL_MINUTES,
  VERIFICATION_MAX_ATTEMPTS_PER_CODE,
  VERIFICATION_MAX_ATTEMPTS_PER_WINDOW,
  VERIFICATION_WINDOW_MINUTES,
  classifyVerificationDenial,
  decideVerificationIssue,
  generateEmailVerificationCode,
  isValidVerificationCodeFormat,
  verificationDenialError,
  verificationIssueError,
} from '../services/membership_rules.js';
import { resolveAcceptedDocuments, recordConsents } from './legal_consent_service.js';
import { PlatformError } from './errors.js';

export const OAUTH_PROVIDERS = Object.freeze(['google', 'apple']);

const GOOGLE_JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';
const GOOGLE_ISSUERS = new Set(['accounts.google.com', 'https://accounts.google.com']);
const APPLE_ISSUERS = new Set(['https://appleid.apple.com']);
const JWKS_CACHE_TTL_MS = 60 * 60 * 1000;
const CLOCK_SKEW_SECONDS = 60;
const MAX_ID_TOKEN_LENGTH = 8192;
const NAME_MAX_LENGTH = 80;
const OAUTH_WEB_SESSION_TTL_MS = 10 * 60 * 1000;

const jwksCache = new Map();
const oauthWebSessions = new Map();

function httpError(statusCode, message, code = null, details = undefined) {
  if (code) {
    return new PlatformError(statusCode, code, message, details);
  }
  const err = new Error(message);
  err.statusCode = statusCode;
  err.expose = statusCode >= 400 && statusCode < 500;
  return err;
}

function parseClientIds(rawPrimary, rawList) {
  const combined = [rawPrimary, rawList]
    .filter((v) => typeof v === 'string' && v.trim() !== '')
    .flatMap((v) => v.split(','))
    .map((v) => v.trim())
    .filter(Boolean);
  return [...new Set(combined)];
}

export function getOAuthConfig(env = process.env) {
  const googleClientIds = parseClientIds(env.GOOGLE_CLIENT_ID, env.GOOGLE_CLIENT_IDS);
  const appleClientIds = parseClientIds(
    env.APPLE_CLIENT_ID || env.APPLE_SERVICE_ID || env.APPLE_BUNDLE_ID,
    env.APPLE_CLIENT_IDS,
  );
  const publicBaseUrl = String(env.PUBLIC_APP_URL || 'https://api.gudeteknoloji.com.tr')
    .trim()
    .replace(/\/+$/, '');
  return {
    publicBaseUrl,
    google: {
      enabled: googleClientIds.length > 0,
      clientIds: googleClientIds,
      clientId: googleClientIds[0] || null,
    },
    apple: {
      enabled: appleClientIds.length > 0,
      clientIds: appleClientIds,
      clientId: appleClientIds[0] || null,
    },
  };
}

export function oauthStatus(env = process.env) {
  const cfg = getOAuthConfig(env);
  return {
    google: {
      enabled: cfg.google.enabled,
      client_id: cfg.google.clientId,
    },
    apple: {
      enabled: cfg.apple.enabled,
      client_id: cfg.apple.clientId,
    },
  };
}

async function defaultFetchJwks(url) {
  const response = await fetch(url, {
    method: 'GET',
    headers: { Accept: 'application/json' },
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) {
    throw httpError(503, 'Kimlik doğrulama sağlayıcısına şu anda ulaşılamıyor.', 'OAUTH_JWKS_UNAVAILABLE');
  }
  const body = await response.json();
  if (!body || !Array.isArray(body.keys)) {
    throw httpError(503, 'Kimlik doğrulama anahtarları geçersiz.', 'OAUTH_JWKS_INVALID');
  }
  return body.keys;
}

export const oauthHooks = {
  fetchJwks: defaultFetchJwks,
  verifyProviderToken: null,
  sendVerificationEmail: sendIndividualVerificationEmail,
};

export function clearJwksCache() {
  jwksCache.clear();
  oauthWebSessions.clear();
}

async function getJwkByKid(jwksUrl, kid, nowMs = Date.now()) {
  const cached = jwksCache.get(jwksUrl);
  if (cached && nowMs - cached.fetchedAt < JWKS_CACHE_TTL_MS) {
    const found = cached.keys.find((k) => k.kid === kid);
    if (found) return found;
  }
  const keys = await oauthHooks.fetchJwks(jwksUrl);
  jwksCache.set(jwksUrl, { keys, fetchedAt: nowMs });
  return keys.find((k) => k.kid === kid) || null;
}

function decodeJwtParts(idToken) {
  if (typeof idToken !== 'string' || idToken.trim() === '' || idToken.length > MAX_ID_TOKEN_LENGTH) {
    throw httpError(400, 'Geçersiz kimlik doğrulama belirteci.', 'INVALID_OAUTH_TOKEN');
  }
  const parts = idToken.trim().split('.');
  if (parts.length !== 3 || !parts[0] || !parts[1] || !parts[2]) {
    throw httpError(400, 'Kimlik doğrulama belirteci biçimi geçersiz.', 'INVALID_OAUTH_TOKEN');
  }
  let header;
  let payload;
  try {
    header = JSON.parse(Buffer.from(parts[0], 'base64url').toString('utf8'));
    payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
  } catch (_err) {
    throw httpError(400, 'Kimlik doğrulama belirteci çözümlenemedi.', 'INVALID_OAUTH_TOKEN');
  }
  return {
    header,
    payload,
    signingInput: `${parts[0]}.${parts[1]}`,
    signature: Buffer.from(parts[2], 'base64url'),
  };
}

export async function verifyOAuthJwt(idToken, { jwksUrl, allowedIssuers, allowedAudiences, nowMs = Date.now() }) {
  const { header, payload, signingInput, signature } = decodeJwtParts(idToken);
  if (header?.alg !== 'RS256' || typeof header?.kid !== 'string' || !header.kid) {
    throw httpError(401, 'Desteklenmeyen veya eksik imzalama algoritması.', 'INVALID_OAUTH_TOKEN');
  }

  let jwk;
  try {
    jwk = await getJwkByKid(jwksUrl, header.kid, nowMs);
  } catch (error) {
    // Anahtar listesine ulaşılamadı (ağ / zaman aşımı / sağlayıcı hatası): belirteç hakkında karar DEĞİLDİR; çağıran (yalnız bu durumda)
    // sağlayıcının kendi doğrulama ucuna düşebilir. İmza / iss / aud / süre hataları ise asla bu koda dönüşmez (kesin red).
    if (error?.code === 'OAUTH_JWKS_UNAVAILABLE' || error?.code === 'OAUTH_JWKS_INVALID') {
      throw error;
    }
    throw httpError(503, 'Kimlik doğrulama sağlayıcısına şu anda ulaşılamıyor.', 'OAUTH_JWKS_UNAVAILABLE');
  }
  if (!jwk) {
    throw httpError(401, 'Kimlik doğrulama imzası doğrulanamadı (anahtar bulunamadı).', 'INVALID_OAUTH_TOKEN');
  }

  let verified;
  try {
    const publicKey = crypto.createPublicKey({ key: jwk, format: 'jwk' });
    verified = crypto.verify('RSA-SHA256', Buffer.from(signingInput, 'utf8'), publicKey, signature);
  } catch (_err) {
    verified = false;
  }
  if (!verified) {
    throw httpError(401, 'Kimlik doğrulama belirteci imzası geçersiz.', 'INVALID_OAUTH_TOKEN');
  }

  const nowSec = Math.floor(nowMs / 1000);
  const exp = Number(payload?.exp);
  if (!Number.isFinite(exp) || exp + CLOCK_SKEW_SECONDS <= nowSec) {
    throw httpError(401, 'Kimlik doğrulama belirtecinin süresi dolmuş.', 'OAUTH_TOKEN_EXPIRED');
  }
  if (payload?.iat !== undefined) {
    const iat = Number(payload.iat);
    if (!Number.isFinite(iat) || iat - CLOCK_SKEW_SECONDS > nowSec) {
      throw httpError(401, 'Kimlik doğrulama belirteci zaman damgası geçersiz.', 'INVALID_OAUTH_TOKEN');
    }
  }

  const iss = typeof payload?.iss === 'string' ? payload.iss : '';
  if (!allowedIssuers.has(iss)) {
    throw httpError(401, 'Kimlik doğrulama sağlayıcısı (iss) geçersiz.', 'INVALID_OAUTH_TOKEN');
  }

  // Audience denetimi ZORUNLUDUR (fail-closed): istemci kimliği listesi boşsa belirteç kabul edilmez (başka uygulamaya verilmiş belirteç kimlik kanıtı olmaz).
  if (!Array.isArray(allowedAudiences) || allowedAudiences.length === 0) {
    throw httpError(503, 'Bu kimlik sağlayıcısıyla giriş şu anda kapalı (sunucu yapılandırması eksik).', 'OAUTH_NOT_CONFIGURED');
  }
  if (!audienceMatches(payload?.aud, allowedAudiences)) {
    throw httpError(401, 'Kimlik doğrulama hedef istemcisi (aud) eşleşmiyor.', 'INVALID_OAUTH_AUDIENCE');
  }

  return claimsFromPayload(payload);
}

/** Doğrulanmış belirteç yükünden (JWT payload / tokeninfo yanıtı) sağlayıcıdan bağımsız talep nesnesi. sub yoksa 401. */
function claimsFromPayload(payload) {
  const sub = typeof payload?.sub === 'string' ? payload.sub.trim() : '';
  if (!sub || sub.length > 255) {
    throw httpError(401, 'Kimlik doğrulama kullanıcı tanımlayıcısı (sub) geçersiz.', 'INVALID_OAUTH_TOKEN');
  }

  const email = typeof payload?.email === 'string' && payload.email.trim() !== ''
    ? normalizeEmail(payload.email)
    : null;
  const emailVerified = payload?.email_verified === true || payload?.email_verified === 'true';

  return {
    sub,
    email,
    emailVerified,
    name: typeof payload?.name === 'string' ? payload.name.trim() : '',
    givenName: typeof payload?.given_name === 'string' ? payload.given_name.trim() : '',
    familyName: typeof payload?.family_name === 'string' ? payload.family_name.trim() : '',
    nonce: typeof payload?.nonce === 'string' ? payload.nonce : null,
  };
}

const GOOGLE_TOKENINFO_URL = 'https://oauth2.googleapis.com/tokeninfo';
const GOOGLE_USERINFO_URL = 'https://www.googleapis.com/oauth2/v3/userinfo';

function oauthUnavailable() {
  return httpError(503, 'Kimlik doğrulama sağlayıcısına şu anda ulaşılamıyor.', 'OAUTH_JWKS_UNAVAILABLE');
}

function oauthInvalidToken() {
  return httpError(401, 'Google kimlik doğrulama belirteci geçersiz veya süresi dolmuş.', 'INVALID_OAUTH_TOKEN');
}

/** Google JSON ucu: ağ hatası / zaman aşımı / 5xx -> 503 (belirteç hakkında karar değil); diğer başarısız yanıt (400 invalid_token) -> 401. */
async function fetchGoogleJson(url, init = {}) {
  let response;
  try {
    response = await fetch(url, { ...init, signal: AbortSignal.timeout(7000) });
  } catch (_networkError) {
    throw oauthUnavailable();
  }
  if (response.status >= 500) {
    throw oauthUnavailable();
  }
  if (!response.ok) {
    throw oauthInvalidToken();
  }
  try {
    return await response.json();
  } catch (_parseError) {
    throw oauthUnavailable();
  }
}

function audienceMatches(aud, allowedAudiences) {
  const list = Array.isArray(aud) ? aud : [aud];
  return list.some((value) => typeof value === 'string' && allowedAudiences.includes(value));
}

/**
 * YEDEK doğrulama (yalnız JWKS'e ulaşılamadığında): Google'ın tokeninfo ucu imza ve süreyi doğrular, hedef istemciyi (aud) DOĞRULAMAZ; bu yüzden
 * aud (yapılandırılmış istemci kimlikleri), iss ve exp BURADA denetlenir. Bunlardan biri tutmazsa kesin red (başka uygulamaya verilmiş belirteç kabul edilmez).
 */
async function verifyGoogleIdTokenWithApi(idToken, allowedAudiences, nowMs = Date.now()) {
  const data = await fetchGoogleJson(`${GOOGLE_TOKENINFO_URL}?id_token=${encodeURIComponent(idToken)}`);
  const iss = typeof data?.iss === 'string' ? data.iss : '';
  if (!GOOGLE_ISSUERS.has(iss)) {
    throw httpError(401, 'Kimlik doğrulama sağlayıcısı (iss) geçersiz.', 'INVALID_OAUTH_TOKEN');
  }
  if (!audienceMatches(data?.aud, allowedAudiences)) {
    throw httpError(401, 'Kimlik doğrulama hedef istemcisi (aud) eşleşmiyor.', 'INVALID_OAUTH_AUDIENCE');
  }
  const exp = Number(data?.exp);
  if (!Number.isFinite(exp) || exp + CLOCK_SKEW_SECONDS <= Math.floor(nowMs / 1000)) {
    throw httpError(401, 'Kimlik doğrulama belirtecinin süresi dolmuş.', 'OAUTH_TOKEN_EXPIRED');
  }
  return claimsFromPayload(data);
}

/**
 * Opak Google ERİŞİM belirteci (web'de id_token yoksa istemci erişim belirteci gönderir): tokeninfo belirtecin hangi istemciye verildiğini (aud) söyler;
 * yapılandırılmış istemci kimliklerinden biri DEĞİLSE kesin red (başka uygulamanın belirteci kimlik kanıtı sayılmaz). Ad / e-posta tokeninfo'da yoksa
 * userinfo'dan alınır, ancak yalnız aud doğrulandıktan sonra ve aynı kullanıcı (sub) için.
 */
async function verifyGoogleAccessToken(accessToken, allowedAudiences, nowMs = Date.now()) {
  const info = await fetchGoogleJson(`${GOOGLE_TOKENINFO_URL}?access_token=${encodeURIComponent(accessToken)}`);
  if (!audienceMatches(info?.aud, allowedAudiences)) {
    throw httpError(401, 'Kimlik doğrulama hedef istemcisi (aud) eşleşmiyor.', 'INVALID_OAUTH_AUDIENCE');
  }
  const expiresIn = Number(info?.expires_in);
  const exp = Number(info?.exp);
  const expired = Number.isFinite(expiresIn)
    ? expiresIn <= 0
    : !Number.isFinite(exp) || exp + CLOCK_SKEW_SECONDS <= Math.floor(nowMs / 1000);
  if (expired) {
    throw httpError(401, 'Kimlik doğrulama belirtecinin süresi dolmuş.', 'OAUTH_TOKEN_EXPIRED');
  }
  let payload = info;
  if (typeof info?.email !== 'string' || info.email.trim() === '') {
    const profile = await fetchGoogleJson(GOOGLE_USERINFO_URL, { headers: { Authorization: `Bearer ${accessToken}` } });
    if (info?.sub && profile?.sub && String(info.sub) !== String(profile.sub)) {
      throw oauthInvalidToken();
    }
    payload = { ...profile, sub: profile?.sub ?? info?.sub };
  }
  return claimsFromPayload(payload);
}

function looksLikeJwt(token) {
  return typeof token === 'string' && token.trim().split('.').length === 3;
}

/** Sağlayıcı istemci kimliği tanımlı DEĞİLSE giriş kapalıdır (fail-closed): audience denetimi yapılamayan belirteç kabul edilmez. */
function requireClientIds(provider, cfg) {
  const clientIds = cfg?.[provider]?.clientIds ?? [];
  if (clientIds.length === 0) {
    throw httpError(
      503,
      'Bu kimlik sağlayıcısıyla giriş şu anda kapalı (sunucu yapılandırması eksik). E-posta doğrulama koduyla devam edebilirsiniz.',
      'OAUTH_NOT_CONFIGURED',
    );
  }
  return clientIds;
}

const isJwksUnavailable = (error) => error?.code === 'OAUTH_JWKS_UNAVAILABLE' || error?.code === 'OAUTH_JWKS_INVALID';

export async function verifyProviderIdToken(provider, idToken, env = process.env) {
  if (typeof oauthHooks.verifyProviderToken === 'function') {
    return oauthHooks.verifyProviderToken(provider, idToken, env);
  }
  const cfg = getOAuthConfig(env);
  if (provider === 'google') {
    const clientIds = requireClientIds('google', cfg);
    if (!looksLikeJwt(idToken)) {
      return verifyGoogleAccessToken(idToken, clientIds);
    }
    try {
      return await verifyOAuthJwt(idToken, {
        jwksUrl: GOOGLE_JWKS_URL,
        allowedIssuers: GOOGLE_ISSUERS,
        allowedAudiences: clientIds,
      });
    } catch (jwtError) {
      // YALNIZ anahtar listesine ulaşılamadıysa yedeğe düşülür; imza / aud / iss / süre hatasında kesin red.
      if (!isJwksUnavailable(jwtError)) {
        throw jwtError;
      }
      if (typeof oauthHooks.verifyWithGoogleApi === 'function') {
        return oauthHooks.verifyWithGoogleApi(idToken, clientIds);
      }
      return verifyGoogleIdTokenWithApi(idToken, clientIds);
    }
  }
  if (provider === 'apple') {
    return verifyOAuthJwt(idToken, {
      jwksUrl: APPLE_JWKS_URL,
      allowedIssuers: APPLE_ISSUERS,
      allowedAudiences: requireClientIds('apple', cfg),
    });
  }
  throw httpError(400, 'Desteklenmeyen kimlik sağlayıcısı.', 'INVALID_OAUTH_PROVIDER');
}

function buildDisplayName({ claims, fullName, firstName, lastName, email }) {
  const candidates = [
    typeof fullName === 'string' ? fullName.trim() : '',
    [firstName, lastName]
      .map((s) => (typeof s === 'string' ? s.trim() : ''))
      .filter(Boolean)
      .join(' '),
    claims?.name || '',
    [claims?.givenName, claims?.familyName].filter(Boolean).join(' '),
  ];
  for (const candidate of candidates) {
    const cleaned = candidate.replace(/\s+/g, ' ').trim();
    if (cleaned.length >= 2) {
      return cleaned.slice(0, NAME_MAX_LENGTH);
    }
  }
  if (typeof email === 'string' && email.includes('@')) {
    const localPart = email.split('@')[0].replace(/[._-]+/g, ' ').trim();
    if (localPart.length >= 2) {
      return localPart.slice(0, NAME_MAX_LENGTH);
    }
  }
  return 'Kullanıcı';
}

const USER_SELECT_COLUMNS = `
  user_code AS id,
  id AS db_id,
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
  password_hash,
  deleted_at
`;

// Yönetimin verdiği parola henüz değişmedi mi: users.must_change_password YA DA hesap bir dairenin sakin göstergesi ve "PIN verildi" işaretli
// (auth_middleware / POST /auth/login ile AYNI tanım). OAuth girişinde bayrak TRUE ise yönetimin bildiği parola döndürülür (aşağıda).
const MUST_CHANGE_SQL = `(COALESCE(users.must_change_password, FALSE) OR EXISTS (
  SELECT 1 FROM apartments a WHERE a.resident_user_code = users.user_code AND a.resident_pin_issued = TRUE
)) AS must_change_password`;

async function completeVerifiedSocialLogin({
  cleanProvider,
  claims,
  fullName = null,
  firstName = null,
  lastName = null,
  acceptedDocuments = undefined,
  rawDeviceToken = null,
  db = pool,
}) {
  const sub = typeof claims?.sub === 'string' ? claims.sub.trim() : '';
  if (!sub) {
    throw httpError(401, 'Kimlik doğrulama kullanıcı tanımlayıcısı alınamadı.', 'INVALID_OAUTH_TOKEN');
  }

  const cleanEmail = typeof claims?.email === 'string' && claims.email.trim() !== ''
    ? normalizeEmail(claims.email)
    : null;

  if (cleanEmail && (!isValidEmail(cleanEmail) || isReservedEmail(cleanEmail))) {
    throw httpError(400, 'Sağlayıcıdan gelen e-posta adresi geçersiz.', 'INVALID_OAUTH_EMAIL');
  }

  const client = await db.connect();
  let committed = false;
  let user = null;
  let isNewUser = false;
  let wasUnverified = false;
  let passwordRotated = false;

  try {
    await client.query('BEGIN');

    // 1. Önce (provider, provider_sub) eşleşmesini kontrol et
    const linkedRes = await client.query(
      `
        SELECT o.id AS identity_id, o.user_code AS linked_user_code,
               u.user_code AS id, u.id AS db_id, u.user_code, u.full_name, u.email, u.login_name,
               u.role, u.is_active, u.email_verified, u.approval_status, u.phone_number,
               u.created_at, u.password_hash, u.deleted_at,
               (COALESCE(u.must_change_password, FALSE) OR EXISTS (
                 SELECT 1 FROM apartments a WHERE a.resident_user_code = u.user_code AND a.resident_pin_issued = TRUE
               )) AS must_change_password
        FROM user_oauth_identities o
        LEFT JOIN users u ON u.user_code = o.user_code
        WHERE o.provider = $1 AND o.provider_sub = $2
        FOR UPDATE OF o
      `,
      [cleanProvider, sub],
    );

    if (linkedRes.rowCount > 0) {
      const row = linkedRes.rows[0];
      if (!row.user_code || row.deleted_at !== null) {
        await client.query('DELETE FROM user_oauth_identities WHERE id = $1', [row.identity_id]);
      } else {
        user = row;
        await client.query(
          `UPDATE user_oauth_identities SET last_login_at = NOW(), email = COALESCE($2, email) WHERE id = $1`,
          [row.identity_id, cleanEmail],
        );
      }
    }

    // 2. Henüz bağlı aktif kullanıcı yoksa e-posta ile eşleştir veya yeni kullanıcı oluştur
    if (!user) {
      if (!cleanEmail || !claims.emailVerified) {
        throw httpError(
          400,
          'Kimlik sağlayıcısından doğrulanmış bir e-posta adresi alınamadı. Lütfen e-posta paylaşımına izin veriniz.',
          'OAUTH_EMAIL_REQUIRED',
        );
      }

      const existingRes = await client.query(
        `SELECT ${USER_SELECT_COLUMNS}, ${MUST_CHANGE_SQL} FROM users WHERE LOWER(email) = LOWER($1) AND deleted_at IS NULL ORDER BY user_code FOR UPDATE`,
        [cleanEmail],
      );

      // E-posta eşleşmesi TEKİL olmalı: aynı adresin büyük/küçük harf farkıyla birden çok hesabı varsa hangisine bağlanacağı belirsizdir (fail-closed).
      if (existingRes.rowCount > 1) {
        throw httpError(
          409,
          'Bu e-posta adresiyle birden fazla hesap kayıtlı; giriş yapılamadı. Lütfen destek ile iletişime geçin.',
          'OAUTH_ACCOUNT_AMBIGUOUS',
        );
      }

      if (existingRes.rowCount > 0) {
        user = existingRes.rows[0];
        // Doğrulanmamış hesap: e-posta sahipliği sağlayıcıyla şimdi kanıtlandı; ama hesabın parolasını başkası (kayıt öncesi sahte kayıt, yönetim) belirlemiş
        // olabilir -> aşağıda parola döndürülür ve e-posta doğrulanır (önceden-ele-geçirme koruması).
        wasUnverified = !user.email_verified;
        if (acceptedDocuments !== undefined) {
          const consentPlan = await resolveAcceptedDocuments({ raw: acceptedDocuments, context: 'register', db: client });
          await recordConsents(client, user.user_code, consentPlan.records, 'register');
        }
      } else {
        isNewUser = true;
        const consentPlan = await resolveAcceptedDocuments({
          raw: acceptedDocuments,
          context: 'register',
          db: client,
        });
        const displayName = buildDisplayName({
          claims,
          fullName,
          firstName,
          lastName,
          email: cleanEmail,
        });
        const randomPassword = crypto.randomBytes(32).toString('hex');
        const passwordHash = await bcrypt.hash(randomPassword, BCRYPT_COST);

        const createdRes = await client.query(
          `
            INSERT INTO users (full_name, email, role, is_active, email_verified, approval_status, password_hash)
            VALUES ($1, $2, 'individual', TRUE, TRUE, 'approved', $3)
            RETURNING ${USER_SELECT_COLUMNS}
          `,
          [displayName, cleanEmail, passwordHash],
        );
        user = createdRes.rows[0];

        await recordConsents(client, user.user_code, consentPlan.records, 'register');
        await client.query('DELETE FROM pending_registrations WHERE LOWER(email) = LOWER($1)', [cleanEmail]);
        await client.query('DELETE FROM email_verifications WHERE LOWER(email) = LOWER($1)', [cleanEmail]);

        const pendingMgrInvRes = await client.query(
          `SELECT id, site_code FROM site_manager_invitations WHERE LOWER(email) = LOWER($1) AND status = 'PENDING' AND expires_at > NOW() FOR UPDATE`,
          [cleanEmail],
        );
        if (pendingMgrInvRes.rowCount > 0) {
          for (const inv of pendingMgrInvRes.rows) {
            await client.query(
              `INSERT INTO site_manager_sites (site_code, manager_user_code, link_source) VALUES ($1, $2, 'invited') ON CONFLICT DO NOTHING`,
              [Number(inv.site_code), user.user_code],
            );
            await client.query(
              `INSERT INTO site_memberships (site_code, user_code, role, is_active) VALUES ($1, $2, 'SITE_ADMIN', TRUE)
               ON CONFLICT (site_code, user_code) DO UPDATE SET role = 'SITE_ADMIN', is_active = TRUE, updated_at = NOW()`,
              [Number(inv.site_code), user.user_code],
            );
            await client.query(
              `UPDATE site_manager_invitations SET status = 'ACCEPTED' WHERE id = $1 AND status = 'PENDING'`,
              [Number(inv.id)],
            );
          }
          if (user.role !== 'super_user') {
            await client.query(
              `UPDATE users SET role = 'site_manager', updated_at = NOW() WHERE user_code = $1 AND deleted_at IS NULL`,
              [user.user_code],
            );
            user.role = 'site_manager';
          }
        }
      }

      await client.query(
        `
          INSERT INTO user_oauth_identities (user_code, provider, provider_sub, email, last_login_at)
          VALUES ($1, $2, $3, $4, NOW())
          ON CONFLICT (provider, provider_sub)
          DO UPDATE SET user_code = EXCLUDED.user_code, email = COALESCE(EXCLUDED.email, user_oauth_identities.email), last_login_at = NOW()
        `,
        [user.user_code, cleanProvider, sub, cleanEmail],
      );
    }

    if (user.approval_status === 'pending') {
      throw httpError(403, 'Hesabınız henüz yönetici tarafından onaylanmamıştır.');
    }
    if (user.approval_status === 'rejected') {
      throw httpError(403, 'Kaydınız reddedilmiştir.');
    }
    if (!user.is_active) {
      throw httpError(403, 'Hesabiniz pasif durumda. Yonetici ile iletisime gecin.');
    }

    // Yönetimin verdiği geçici parola (must_change_password) ya da doğrulanmamış hesabın parolası: sağlayıcı e-posta sahipliğini kanıtladığı için
    // parola RASTGELE bir değerle değiştirilir (yönetimin / kayıt öncesi sahte kaydın bildiği parola artık işe yaramaz), bayrak kapanır, e-posta doğrulanır.
    // Açık oturumlar ve güvenilir cihaz belirteçleri parola özeti değiştiği için geçersizleşir; bu girişin jetonu yeni özetle imzalanır.
    if (user.must_change_password === true || wasUnverified) {
      const rotatedHash = await bcrypt.hash(crypto.randomBytes(32).toString('hex'), BCRYPT_COST);
      const rotated = await client.query(
        `
          UPDATE users
          SET password_hash = $2, must_change_password = FALSE, email_verified = TRUE, updated_at = NOW()
          WHERE user_code = $1 AND deleted_at IS NULL
          RETURNING password_hash
        `,
        [user.user_code, rotatedHash],
      );
      if (!rotated.rows?.[0]) {
        throw httpError(401, 'Bu hesap silinmis.', 'ACCOUNT_DELETED');
      }
      user.password_hash = rotated.rows[0].password_hash;
      user.email_verified = true;
      user.must_change_password = false;
      passwordRotated = true;
    }

    await client.query('COMMIT');
    committed = true;
  } catch (err) {
    if (!committed) {
      try {
        await client.query('ROLLBACK');
      } catch (_rbErr) {
        // ignore rollback error
      }
    }
    throw err;
  } finally {
    client.release();
  }

  if (passwordRotated) {
    // Yönetimin verdiği PIN artık geçerli değil -> daire sakin göstergesindeki "PIN verildi" işareti kalkar (PATCH /me ile aynı). users satırı yukarıda
    // commit edildi; bu ifade AYRI otomatik onaylı (kilit sırası apartments -> users bozulmasın). Başarısızlık girişi engellemez (bayrak yalnız istemci ipucudur).
    try {
      await db.query(
        'UPDATE apartments SET resident_pin_issued = FALSE, resident_pin_code = NULL WHERE resident_user_code = $1 AND (resident_pin_issued OR resident_pin_code IS NOT NULL)',
        [user.user_code],
      );
    } catch (clearError) {
      // eslint-disable-next-line no-console
      console.error('[oauth] daire PIN isareti temizlenemedi:', clearError?.code || 'hata');
    }
  }

  const passwordHash = user.password_hash;
  const token = signAccessToken(user, { passwordHash });
  const deviceToken = reissueDeviceToken({
    presented: rawDeviceToken,
    userCode: user.id ?? user.user_code,
    passwordHash,
  });
  delete user.password_hash;
  delete user.deleted_at;

  return {
    ok: true,
    is_new_user: isNewUser,
    provider: cleanProvider,
    message: isNewUser
      ? `${cleanProvider === 'apple' ? 'iCloud (Apple)' : 'Google'} hesabınızla kaydınız tamamlandı.`
      : 'Giriş başarılı.',
    token,
    user: mapUserRow(user),
    ...(deviceToken ? { device_token: deviceToken } : {}),
  };
}

/** Sabit zamanlı metin eşitliği (uzunluk farkı sızmasın diye özetler karşılaştırılır). */
function safeEqualStrings(a, b) {
  const left = crypto.createHash('sha256').update(String(a ?? '')).digest();
  const right = crypto.createHash('sha256').update(String(b ?? '')).digest();
  return crypto.timingSafeEqual(left, right);
}

// Yerel (mobil) istemcinin gönderdiği HAM nonce: uygulamanın her girişte ürettiği rastgele değer (base64url, en az 16 karakter). Sağlayıcıya ham değer
// DEĞİL SHA-256 özeti (onaltılı, küçük harf) verilir; belirteçteki `nonce` talebi bu özettir. Ham değeri yalnız uygulama bilir: belirteç tek başına
// (günlük, ara katman, sızıntı) ele geçirilse bile özetten ham değer çıkarılamaz, dolayısıyla belirteç yeniden oynatılamaz. (Ham değeri doğrudan sağlayıcıya
// verip aynısını göndermek bu korumayı sağlamazdı: nonce belirteç yükünde okunabilir olduğundan saldıran belirteçten kopyalardı.)
const CLIENT_NONCE_PATTERN = /^[A-Za-z0-9._~-]{16,128}$/;

/**
 * İstemcinin gövdede gönderdiği ham `nonce` -> `authenticateWithOAuth({ expectedNonce })` değeri (SHA-256 onaltılı özet). Yok / boş -> null (eski
 * istemci; OAUTH_REQUIRE_NONCE açıksa authenticateWithOAuth reddeder). Biçimsiz değer 400 INVALID_OAUTH_NONCE.
 */
export function expectedNonceFromClient(rawNonce) {
  if (rawNonce === undefined || rawNonce === null || rawNonce === '') {
    return null;
  }
  if (typeof rawNonce !== 'string' || !CLIENT_NONCE_PATTERN.test(rawNonce.trim())) {
    throw httpError(400, 'Giriş doğrulama değeri (nonce) geçersiz.', 'INVALID_OAUTH_NONCE');
  }
  return crypto.createHash('sha256').update(rawNonce.trim(), 'utf8').digest('hex');
}

/**
 * Nonce'suz yerel girişin reddedilip reddedilmeyeceği (`OAUTH_REQUIRE_NONCE`). Varsayılan KAPALI: nonce göndermeyen eski istemci şimdilik kabul edilir.
 * Değer `1` / `true` / `all` -> tüm sağlayıcılar; virgüllü liste (`apple` ya da `google,apple`) -> yalnız listedeki sağlayıcılar. Sağlayıcı bazlı açma
 * gerekir: google_sign_in 6.x paketi nonce'u sağlayıcıya iletemez (yalnız Apple istemcisi nonce gönderir), bu yüzden `all` ancak Google istemcisi de
 * nonce destekleyince açılmalıdır.
 */
export function isOAuthNonceRequired(provider, env = process.env) {
  const raw = String(env?.OAUTH_REQUIRE_NONCE ?? '').trim().toLowerCase();
  if (raw === '') {
    return false;
  }
  if (raw === '1' || raw === 'true' || raw === 'yes' || raw === 'on' || raw === 'all') {
    return true;
  }
  return raw.split(',').map((part) => part.trim()).includes(String(provider).toLowerCase());
}

/**
 * `expectedNonce`: yetkilendirme isteğine konan nonce'un BELİRTEÇTE görünmesi beklenen değeri. Verilirse belirteçteki `nonce` talebi AYNI olmalıdır (aksi halde
 * 401 INVALID_OAUTH_NONCE: başka oturum için alınmış belirteç yeniden oynatılamaz). Sunucunun başlattığı web oturumunda (completeOAuthWebCallback) her zaman
 * verilir. Yerel (mobil) akışta istemci ham nonce'u gönderir, rota bunu `expectedNonceFromClient` ile özete çevirip buraya geçirir. Verilmezse (eski istemci)
 * denetim yapılmaz; ancak `OAUTH_REQUIRE_NONCE` o sağlayıcı için açıksa 400 OAUTH_NONCE_REQUIRED (sağlayıcıya hiç gidilmez).
 */
export async function authenticateWithOAuth({
  provider,
  idToken,
  fullName = null,
  firstName = null,
  lastName = null,
  acceptedDocuments = undefined,
  rawDeviceToken = null,
  expectedNonce = null,
  db = pool,
  env = process.env,
}) {
  const cleanProvider = typeof provider === 'string' ? provider.trim().toLowerCase() : '';
  if (!OAUTH_PROVIDERS.includes(cleanProvider)) {
    throw httpError(400, 'Geçersiz kimlik doğrulama sağlayıcısı.', 'INVALID_OAUTH_PROVIDER');
  }
  if ((expectedNonce === null || expectedNonce === undefined) && isOAuthNonceRequired(cleanProvider, env)) {
    throw httpError(
      400,
      'Güvenli giriş için uygulamanın güncel sürümü gerekiyor. Lütfen uygulamayı güncelleyin.',
      'OAUTH_NONCE_REQUIRED',
    );
  }
  const claims = await verifyProviderIdToken(cleanProvider, idToken, env);
  if (expectedNonce !== null && expectedNonce !== undefined) {
    if (typeof claims?.nonce !== 'string' || !safeEqualStrings(claims.nonce, expectedNonce)) {
      throw httpError(401, 'Kimlik doğrulama belirteci bu oturum için üretilmemiş (nonce eşleşmiyor).', 'INVALID_OAUTH_NONCE');
    }
  }
  return completeVerifiedSocialLogin({
    cleanProvider,
    claims,
    fullName,
    firstName,
    lastName,
    acceptedDocuments,
    rawDeviceToken,
    db,
  });
}

/**
 * Google veya iCloud (Apple) e-posta adresine 6 haneli doğrulama kodu gönderir.
 * Böylece sunucuda OAuth yönlendirme anahtarı olmasa veya masaüstü/mobil istemcide doğrudan
 * Google/iCloud e-postasıyla kayıt/giriş yapılmak istense bile tek adımda doğrulama kodu gider.
 */
export async function requestOAuthEmailCode({
  provider,
  email,
  fullName = null,
  firstName = null,
  lastName = null,
  db = pool,
}) {
  const cleanProvider = typeof provider === 'string' ? provider.trim().toLowerCase() : '';
  if (!OAUTH_PROVIDERS.includes(cleanProvider)) {
    throw httpError(400, 'Geçersiz kimlik doğrulama sağlayıcısı.', 'INVALID_OAUTH_PROVIDER');
  }
  const cleanEmail = normalizeEmail(email);
  if (!cleanEmail || !isValidEmail(cleanEmail) || isReservedEmail(cleanEmail)) {
    throw httpError(
      400,
      `Lütfen geçerli bir ${cleanProvider === 'apple' ? 'iCloud / Apple' : 'Google (Gmail)'} e-posta adresi giriniz.`,
    );
  }

  const displayName = buildDisplayName({
    claims: null,
    fullName,
    firstName,
    lastName,
    email: cleanEmail,
  });

  const client = await db.connect();
  let code;
  let codeRowId;
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`email_verify:${cleanEmail}`]);

    const stateRes = await client.query(SQL_VERIFICATION_ISSUE_STATE, [cleanEmail]);
    const state = stateRes.rows[0] || {};
    const decision = decideVerificationIssue({
      secondsSinceLast:
        state.seconds_since_last === null || state.seconds_since_last === undefined
          ? null
          : Number(state.seconds_since_last),
      codesLastHour: Number(state.codes_last_hour || 0),
    });
    if (!decision.allowed) {
      await client.query('ROLLBACK');
      throw verificationIssueError({
        sent: false,
        reason: decision.reason,
        retryAfterSeconds: decision.retryAfterSeconds,
      });
    }

    code = generateEmailVerificationCode();
    const codeHash = await bcrypt.hash(code, 10);
    const inserted = await client.query(
      `INSERT INTO email_verifications (email, code_hash, attempt_count, is_verified) VALUES ($1, $2, 0, FALSE) RETURNING id`,
      [cleanEmail, codeHash],
    );
    codeRowId = inserted.rows[0]?.id;
    await client.query('COMMIT');
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_rb) {
      // ignore
    }
    throw err;
  } finally {
    client.release();
  }

  try {
    await oauthHooks.sendVerificationEmail({
      to: cleanEmail,
      fullName: displayName,
      code,
      ttlMinutes: VERIFICATION_CODE_TTL_MINUTES,
      requestedAt: new Date(),
    });
  } catch (_mailErr) {
    if (codeRowId) {
      try {
        await db.query('DELETE FROM email_verifications WHERE id = $1', [codeRowId]);
      } catch (_delErr) {
        // ignore
      }
    }
    throw verificationIssueError({ sent: false, reason: 'MAIL_FAILED' });
  }

  if (codeRowId) {
    try {
      await db.query(SQL_SUPERSEDE_OLDER_VERIFICATION_CODES, [cleanEmail, codeRowId]);
    } catch (_supErr) {
      // ignore
    }
  }

  return {
    ok: true,
    provider: cleanProvider,
    email: cleanEmail,
    code_length: VERIFICATION_CODE_DIGITS,
    expires_in_minutes: VERIFICATION_CODE_TTL_MINUTES,
    message: `${cleanEmail} adresine ${VERIFICATION_CODE_DIGITS} haneli doğrulama kodu gönderildi.`,
  };
}

/**
 * E-postaya gönderilen 6 haneli doğrulama kodunu onaylayarak Google / iCloud ile kaydı veya girişi tamamlar.
 */
export async function verifyOAuthEmailCode({
  provider,
  email,
  code,
  fullName = null,
  firstName = null,
  lastName = null,
  acceptedDocuments = undefined,
  rawDeviceToken = null,
  db = pool,
}) {
  const cleanProvider = typeof provider === 'string' ? provider.trim().toLowerCase() : '';
  if (!OAUTH_PROVIDERS.includes(cleanProvider)) {
    throw httpError(400, 'Geçersiz kimlik doğrulama sağlayıcısı.', 'INVALID_OAUTH_PROVIDER');
  }
  const cleanEmail = normalizeEmail(email);
  const cleanCode = String(code ?? '').trim();

  if (!cleanEmail || !isValidEmail(cleanEmail) || isReservedEmail(cleanEmail)) {
    throw httpError(400, 'Geçerli bir e-posta adresi giriniz.');
  }
  if (!isValidVerificationCodeFormat(cleanCode)) {
    throw httpError(400, `Doğrulama kodu ${VERIFICATION_CODE_DIGITS} haneli sayı olmalıdır.`);
  }

  const client = await db.connect();
  let committed = false;
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`email_verify:${cleanEmail}`]);

    // Kalıcı birikimli kilit (kodlar arası; /auth/verify-code ile AYNI sayaç ve kod havuzu): kilitliyken kod karşılaştırılmaz (423; işlem geri alınır).
    const codeLimitTarget = emailCodeTarget(cleanEmail);
    const lock = await peekAttemptLock(ATTEMPT_POLICIES.emailCode, codeLimitTarget, client);
    if (lock.locked) {
      throw codeLockedError('email', lock.retryAfterSeconds);
    }

    const claim = await client.query(SQL_CLAIM_VERIFICATION_ATTEMPT, [
      cleanEmail,
      VERIFICATION_CODE_TTL_MINUTES,
      VERIFICATION_MAX_ATTEMPTS_PER_CODE,
      VERIFICATION_WINDOW_MINUTES,
      VERIFICATION_MAX_ATTEMPTS_PER_WINDOW,
    ]);

    if (claim.rowCount === 0) {
      const stateRes = await client.query(SQL_VERIFICATION_STATE, [
        cleanEmail,
        VERIFICATION_CODE_TTL_MINUTES,
        VERIFICATION_WINDOW_MINUTES,
      ]);
      const state = stateRes.rows[0] || {};
      const hasActiveCode = state.code_attempts !== null && state.code_attempts !== undefined;
      await client.query('COMMIT');
      committed = true;
      throw verificationDenialError(
        classifyVerificationDenial({
          hasActiveCode,
          codeAttempts: Number(state.code_attempts || 0),
          windowAttempts: Number(state.window_attempts || 0),
        }),
      );
    }

    const record = claim.rows[0];
    const isMatch = await bcrypt.compare(cleanCode, record.code_hash);
    if (!isMatch) {
      // Birikimli sayaç da aynı işlemde yazılır; bu yanlış kilidi koyduysa 423 (aksi halde 400).
      const failure = await registerAttemptFailure(ATTEMPT_POLICIES.emailCode, codeLimitTarget, client);
      await client.query('COMMIT');
      committed = true;
      if (failure.locked) {
        throw codeLockedError('email', failure.retryAfterSeconds);
      }
      throw httpError(400, `Girdiğiniz ${VERIFICATION_CODE_DIGITS} haneli kod hatalıdır.`);
    }

    const consumed = await client.query(SQL_CONSUME_VERIFICATION_CODE, [record.id]);
    if (consumed.rowCount === 0) {
      throw httpError(400, 'Bu doğrulama kodu zaten kullanılmış. Lütfen yeni kod talep ediniz.');
    }
    await client.query(SQL_SUPERSEDE_VERIFICATION_CODES, [cleanEmail]);
    // Doğru kod: birikimli sayaç ve kilit seviyesi sıfırlanır.
    await resetAttempts(ATTEMPT_POLICIES.emailCode, codeLimitTarget, client);
    await client.query('COMMIT');
    committed = true;
  } catch (err) {
    if (!committed) {
      try {
        await client.query('ROLLBACK');
      } catch (_rb) {
        // ignore
      }
    }
    throw err;
  } finally {
    client.release();
  }

  return completeVerifiedSocialLogin({
    cleanProvider,
    claims: {
      sub: `email:${cleanEmail}`,
      email: cleanEmail,
      emailVerified: true,
      name: fullName || '',
      givenName: firstName || '',
      familyName: lastName || '',
    },
    fullName,
    firstName,
    lastName,
    acceptedDocuments,
    rawDeviceToken,
    db,
  });
}

function purgeExpiredWebSessions(nowMs = Date.now()) {
  for (const [k, v] of oauthWebSessions.entries()) {
    if (nowMs - v.createdAt > OAUTH_WEB_SESSION_TTL_MS) {
      oauthWebSessions.delete(k);
    }
  }
}

export function startOAuthWebSession({ provider, acceptedDocuments = undefined, env = process.env }) {
  const cleanProvider = typeof provider === 'string' ? provider.trim().toLowerCase() : '';
  if (!OAUTH_PROVIDERS.includes(cleanProvider)) {
    throw httpError(400, 'Geçersiz kimlik doğrulama sağlayıcısı.', 'INVALID_OAUTH_PROVIDER');
  }
  const cfg = getOAuthConfig(env);
  const providerCfg = cfg[cleanProvider];
  if (!providerCfg?.enabled || !providerCfg.clientId) {
    return {
      mode: 'email_code',
      provider: cleanProvider,
      redirect_enabled: false,
    };
  }

  purgeExpiredWebSessions();
  const sessionId = crypto.randomBytes(24).toString('base64url');
  const nonce = crypto.randomBytes(16).toString('base64url');
  const redirectUri = `${cfg.publicBaseUrl}/auth/oauth/${cleanProvider}/callback`;

  oauthWebSessions.set(sessionId, {
    provider: cleanProvider,
    nonce,
    acceptedDocuments,
    createdAt: Date.now(),
    status: 'pending',
    result: null,
    error: null,
  });

  let authUrl;
  if (cleanProvider === 'google') {
    const params = new URLSearchParams({
      client_id: providerCfg.clientId,
      redirect_uri: redirectUri,
      response_type: 'id_token',
      response_mode: 'form_post',
      scope: 'openid email profile',
      state: sessionId,
      nonce,
      prompt: 'select_account',
    });
    authUrl = `https://accounts.google.com/o/oauth2/v2/auth?${params.toString()}`;
  } else {
    const params = new URLSearchParams({
      client_id: providerCfg.clientId,
      redirect_uri: redirectUri,
      response_type: 'code id_token',
      response_mode: 'form_post',
      scope: 'name email',
      state: sessionId,
      nonce,
    });
    authUrl = `https://appleid.apple.com/auth/authorize?${params.toString()}`;
  }

  return {
    mode: 'redirect',
    provider: cleanProvider,
    redirect_enabled: true,
    session_id: sessionId,
    auth_url: authUrl,
  };
}

export async function completeOAuthWebCallback({
  provider,
  state,
  idToken,
  userJson = null,
  error = null,
  db = pool,
  env = process.env,
}) {
  purgeExpiredWebSessions();
  const session = oauthWebSessions.get(String(state ?? ''));
  if (!session || session.provider !== provider) {
    throw httpError(400, 'Oturum süresi dolmuş veya geçersiz. Lütfen uygulamadan tekrar deneyin.');
  }
  if (error) {
    session.status = 'error';
    session.error = 'Giriş işlemi iptal edildi.';
    return { ok: false, error: session.error };
  }

  let firstName = null;
  let lastName = null;
  if (typeof userJson === 'string' && userJson.trim() !== '') {
    try {
      const parsed = JSON.parse(userJson);
      firstName = parsed?.name?.firstName ?? null;
      lastName = parsed?.name?.lastName ?? null;
    } catch (_e) {
      // ignore
    }
  }

  try {
    const result = await authenticateWithOAuth({
      provider,
      idToken,
      firstName,
      lastName,
      acceptedDocuments: session.acceptedDocuments,
      // Sunucunun bu oturum için ürettiği nonce: belirteçteki nonce ile birebir eşleşmezse kabul edilmez.
      expectedNonce: session.nonce,
      db,
      env,
    });
    session.status = 'completed';
    session.result = result;
    return { ok: true, result };
  } catch (err) {
    session.status = 'error';
    session.error = err?.message || 'Giriş tamamlanamadı.';
    throw err;
  }
}

export function pollOAuthWebSession(sessionId) {
  purgeExpiredWebSessions();
  const key = String(sessionId ?? '');
  const session = oauthWebSessions.get(key);
  if (!session) {
    throw httpError(404, 'Oturum bulunamadı veya süresi doldu.');
  }
  if (session.status === 'completed' && session.result) {
    oauthWebSessions.delete(key);
    return {
      status: 'completed',
      ...session.result,
    };
  }
  if (session.status === 'error') {
    oauthWebSessions.delete(key);
    return {
      status: 'error',
      error: session.error || 'Giriş yapılamadı.',
    };
  }
  return { status: 'pending' };
}
