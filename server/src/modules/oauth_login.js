import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import { pool } from '../db.js';
import { signAccessToken } from '../jwt.js';
import { sendIndividualVerificationEmail } from '../mailer.js';
import { BCRYPT_COST } from '../security/password_hashing.js';
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

  const jwk = await getJwkByKid(jwksUrl, header.kid, nowMs);
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

  if (Array.isArray(allowedAudiences) && allowedAudiences.length > 0) {
    const audList = Array.isArray(payload?.aud) ? payload.aud : [payload?.aud];
    const audMatched = audList.some((a) => typeof a === 'string' && allowedAudiences.includes(a));
    if (!audMatched) {
      throw httpError(401, 'Kimlik doğrulama hedef istemcisi (aud) eşleşmiyor.', 'INVALID_OAUTH_AUDIENCE');
    }
  }

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
  };
}

async function verifyGoogleTokenWithApi(idToken) {
  try {
    const url = `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(idToken)}`;
    const resp = await fetch(url, { signal: AbortSignal.timeout(7000) });
    if (resp.ok) {
      const data = await resp.json();
      const sub = String(data.sub || '').trim();
      const email = data.email ? normalizeEmail(data.email) : null;
      const emailVerified = data.email_verified === 'true' || data.email_verified === true;
      if (sub && email && emailVerified) {
        return {
          sub,
          email,
          emailVerified,
          name: data.name || '',
          givenName: data.given_name || '',
          familyName: data.family_name || '',
        };
      }
    }
  } catch (_e) {
    // continue
  }

  try {
    const userinfoResp = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
      headers: { Authorization: `Bearer ${idToken}` },
      signal: AbortSignal.timeout(7000),
    });
    if (userinfoResp.ok) {
      const data = await userinfoResp.json();
      const sub = String(data.sub || '').trim();
      const email = data.email ? normalizeEmail(data.email) : null;
      const emailVerified = data.email_verified === 'true' || data.email_verified === true;
      if (sub && email && emailVerified) {
        return {
          sub,
          email,
          emailVerified,
          name: data.name || '',
          givenName: data.given_name || '',
          familyName: data.family_name || '',
        };
      }
    }
  } catch (_e) {
    // continue
  }

  throw httpError(401, 'Google kimlik doğrulama belirteci geçersiz veya süresi dolmuş.', 'INVALID_OAUTH_TOKEN');
}

export async function verifyProviderIdToken(provider, idToken, env = process.env) {
  if (typeof oauthHooks.verifyProviderToken === 'function') {
    return oauthHooks.verifyProviderToken(provider, idToken, env);
  }
  const cfg = getOAuthConfig(env);
  if (provider === 'google') {
    try {
      return await verifyOAuthJwt(idToken, {
        jwksUrl: GOOGLE_JWKS_URL,
        allowedIssuers: GOOGLE_ISSUERS,
        allowedAudiences: cfg.google.clientIds.length > 0 ? cfg.google.clientIds : null,
      });
    } catch (jwkErr) {
      if (typeof oauthHooks.verifyWithGoogleApi === 'function') {
        return oauthHooks.verifyWithGoogleApi(idToken);
      }
      return verifyGoogleTokenWithApi(idToken);
    }
  }
  if (provider === 'apple') {
    return verifyOAuthJwt(idToken, {
      jwksUrl: APPLE_JWKS_URL,
      allowedIssuers: APPLE_ISSUERS,
      allowedAudiences: cfg.apple.clientIds.length > 0 ? cfg.apple.clientIds : null,
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

  try {
    await client.query('BEGIN');

    // 1. Önce (provider, provider_sub) eşleşmesini kontrol et
    const linkedRes = await client.query(
      `
        SELECT o.id AS identity_id, o.user_code AS linked_user_code,
               u.user_code AS id, u.id AS db_id, u.user_code, u.full_name, u.email, u.login_name,
               u.role, u.is_active, u.email_verified, u.approval_status, u.phone_number,
               u.created_at, u.password_hash, u.deleted_at
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
        `SELECT ${USER_SELECT_COLUMNS} FROM users WHERE LOWER(email) = LOWER($1) AND deleted_at IS NULL FOR UPDATE`,
        [cleanEmail],
      );

      if (existingRes.rowCount > 0) {
        user = existingRes.rows[0];
        if (!user.email_verified) {
          await client.query(
            `UPDATE users SET email_verified = TRUE, updated_at = NOW() WHERE user_code = $1 AND deleted_at IS NULL`,
            [user.user_code],
          );
          user.email_verified = true;
        }
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

export async function authenticateWithOAuth({
  provider,
  idToken,
  fullName = null,
  firstName = null,
  lastName = null,
  acceptedDocuments = undefined,
  rawDeviceToken = null,
  db = pool,
  env = process.env,
}) {
  const cleanProvider = typeof provider === 'string' ? provider.trim().toLowerCase() : '';
  if (!OAUTH_PROVIDERS.includes(cleanProvider)) {
    throw httpError(400, 'Geçersiz kimlik doğrulama sağlayıcısı.', 'INVALID_OAUTH_PROVIDER');
  }
  const claims = await verifyProviderIdToken(cleanProvider, idToken, env);
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
      await client.query('COMMIT');
      committed = true;
      throw httpError(400, `Girdiğiniz ${VERIFICATION_CODE_DIGITS} haneli kod hatalıdır.`);
    }

    const consumed = await client.query(SQL_CONSUME_VERIFICATION_CODE, [record.id]);
    if (consumed.rowCount === 0) {
      throw httpError(400, 'Bu doğrulama kodu zaten kullanılmış. Lütfen yeni kod talep ediniz.');
    }
    await client.query(SQL_SUPERSEDE_VERIFICATION_CODES, [cleanEmail]);
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
