import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { readFileSync } from 'node:fs';
import express from 'express';
import '../src/utils/async_errors.js';
import { pool } from '../src/db.js';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { OAUTH_DDL, OAUTH_TABLES, ensureOAuthSchema } from '../src/modules/oauth_schema.js';
import {
  authenticateWithOAuth,
  clearJwksCache,
  getOAuthConfig,
  oauthHooks,
  oauthStatus,
  verifyOAuthJwt,
} from '../src/modules/oauth_login.js';
import { oauthCodeRequestLimiter, oauthRouter, oauthVerifyLimiter } from '../src/modules/oauth_routes.js';

const SECRET = 'oauth-test-secret-value-0123456789abcdef0123456789';

const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
const publicJwk = {
  ...publicKey.export({ format: 'jwk' }),
  kid: 'test-key-1',
  alg: 'RS256',
  use: 'sig',
};

function signTestRs256Jwt(payload, { kid = 'test-key-1', alg = 'RS256', key = privateKey } = {}) {
  const headerB64 = Buffer.from(JSON.stringify({ alg, typ: 'JWT', kid })).toString('base64url');
  const payloadB64 = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signingInput = `${headerB64}.${payloadB64}`;
  const sig = crypto.sign('RSA-SHA256', Buffer.from(signingInput, 'utf8'), key).toString('base64url');
  return `${signingInput}.${sig}`;
}

describe('migration 076 ve oauth_schema', () => {
  it('076_oauth_identities.sql mevcut, guvenli ve OAUTH_DDL ile ayni', () => {
    const list = listMigrations(DEFAULT_MIGRATIONS_DIR);
    const entry = list.find((m) => m.number === 76);
    assert.ok(entry, '076 numarali migration olmali');
    assert.equal(entry.file, '076_oauth_identities.sql');
    const sql = readFileSync(new URL('../migrations/076_oauth_identities.sql', import.meta.url), 'utf8');
    assert.deepEqual(findUnsafeStatements(sql), []);
    for (const stmt of OAUTH_DDL) {
      const name = /(?:TABLE|INDEX) IF NOT EXISTS (\w+)/.exec(stmt)[1];
      assert.ok(sql.includes(`IF NOT EXISTS ${name}`), name);
    }
  });

  it('ensureOAuthSchema tablo zaten varsa DDL calistirmaz, yoksa olusturur', async () => {
    const executed = [];
    const clientPresent = {
      query: async (q) => {
        executed.push(q);
        return { rows: [{ n: OAUTH_TABLES.length }] };
      },
    };
    await ensureOAuthSchema(clientPresent);
    assert.equal(executed.length, 1);

    const executedMissing = [];
    const clientMissing = {
      query: async (q) => {
        executedMissing.push(q);
        return { rows: [{ n: 0 }] };
      },
    };
    await ensureOAuthSchema(clientMissing);
    assert.equal(executedMissing.length, 1 + OAUTH_DDL.length);
  });
});

describe('OAuth yapilandirma ve RS256 JWKS dogrulama', () => {
  beforeEach(() => {
    clearJwksCache();
    oauthHooks.fetchJwks = async () => [publicJwk];
  });

  it('anahtar yoksa Google ve Apple kapali gorunur, varsa acilir', () => {
    assert.deepEqual(oauthStatus({}), {
      google: { enabled: false, client_id: null },
      apple: { enabled: false, client_id: null },
    });
    const cfg = getOAuthConfig({
      GOOGLE_CLIENT_ID: 'google-client-1.apps.googleusercontent.com',
      APPLE_CLIENT_ID: 'tr.com.gudeteknoloji.kapi',
    });
    assert.equal(cfg.google.enabled, true);
    assert.equal(cfg.apple.enabled, true);
    assert.equal(cfg.google.clientId, 'google-client-1.apps.googleusercontent.com');
    assert.equal(cfg.apple.clientId, 'tr.com.gudeteknoloji.kapi');
  });

  it('RS256 imzali gecerli Google ve Apple JWT dogrulanir, suresi gecmis veya yanlis aud reddedilir', async () => {
    const nowSec = Math.floor(Date.now() / 1000);
    const validToken = signTestRs256Jwt({
      iss: 'https://accounts.google.com',
      aud: 'google-client-1',
      sub: 'google-sub-123',
      email: 'Ayse.Yilmaz@example.com',
      email_verified: true,
      name: 'Ayşe Yılmaz',
      iat: nowSec - 10,
      exp: nowSec + 3600,
    });

    const claims = await verifyOAuthJwt(validToken, {
      jwksUrl: 'https://www.googleapis.com/oauth2/v3/certs',
      allowedIssuers: new Set(['accounts.google.com', 'https://accounts.google.com']),
      allowedAudiences: ['google-client-1'],
    });
    assert.equal(claims.sub, 'google-sub-123');
    assert.equal(claims.email, 'ayse.yilmaz@example.com');
    assert.equal(claims.emailVerified, true);
    assert.equal(claims.name, 'Ayşe Yılmaz');

    // Yanlış audience
    await assert.rejects(
      () =>
        verifyOAuthJwt(validToken, {
          jwksUrl: 'https://www.googleapis.com/oauth2/v3/certs',
          allowedIssuers: new Set(['https://accounts.google.com']),
          allowedAudiences: ['baska-client'],
        }),
      (err) => err.statusCode === 401 && err.code === 'INVALID_OAUTH_AUDIENCE',
    );

    // Süresi geçmiş token
    const expiredToken = signTestRs256Jwt({
      iss: 'https://appleid.apple.com',
      aud: 'apple-client-1',
      sub: 'apple-sub-999',
      email: 'ali@icloud.com',
      email_verified: 'true',
      iat: nowSec - 7200,
      exp: nowSec - 3600,
    });
    await assert.rejects(
      () =>
        verifyOAuthJwt(expiredToken, {
          jwksUrl: 'https://appleid.apple.com/auth/keys',
          allowedIssuers: new Set(['https://appleid.apple.com']),
          allowedAudiences: ['apple-client-1'],
        }),
      (err) => err.statusCode === 401 && err.code === 'OAUTH_TOKEN_EXPIRED',
    );
  });
});

describe('authenticateWithOAuth ve HTTP rotalari (/auth/oauth/google & /auth/oauth/apple)', () => {
  let server;
  let baseUrl;
  let savedSecret;
  let originalConnect;
  let originalQuery;

  // Sahte bellek içi veritabanı durumu
  let usersByEmail;
  let usersByCode;
  let identities;
  let pendingInvitations;
  let emailVerifications;
  let sentEmails;
  let nextUserCode;

  function resetFakeStore() {
    usersByEmail = new Map();
    usersByCode = new Map();
    identities = new Map(); // `${provider}:${sub}` -> { id, user_code, provider, provider_sub, email }
    pendingInvitations = [];
    emailVerifications = [];
    sentEmails = [];
    nextUserCode = 500;
  }

  function makeFakeClient() {
    return {
      query: async (text, params = []) => {
        const sql = String(text).replace(/\s+/g, ' ').trim();
        if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || sql.startsWith('SELECT pg_advisory_xact_lock')) {
          return { rows: [], rowCount: 0 };
        }
        if (sql.includes('FROM email_verifications') && sql.includes('seconds_since_last')) {
          return { rows: [{ seconds_since_last: null, codes_last_hour: 0 }], rowCount: 1 };
        }
        if (sql.startsWith('INSERT INTO email_verifications')) {
          const [email, codeHash] = params;
          const id = emailVerifications.length + 1;
          emailVerifications.push({
            id,
            email: String(email).toLowerCase(),
            code_hash: codeHash,
            attempt_count: 0,
            is_verified: false,
          });
          return { rows: [{ id }], rowCount: 1 };
        }
        if (sql.startsWith('UPDATE email_verifications ev SET attempt_count = ev.attempt_count + 1')) {
          const email = String(params[0]).toLowerCase();
          const active = [...emailVerifications].reverse().find((r) => r.email === email && !r.is_verified);
          if (!active) return { rows: [], rowCount: 0 };
          active.attempt_count += 1;
          return {
            rows: [{ id: active.id, code_hash: active.code_hash, attempt_count: active.attempt_count }],
            rowCount: 1,
          };
        }
        if (sql.startsWith('UPDATE email_verifications SET is_verified = TRUE, verified_at = NOW()')) {
          const id = params[0];
          const row = emailVerifications.find((r) => r.id === id && !r.is_verified);
          if (!row) return { rows: [], rowCount: 0 };
          row.is_verified = true;
          return { rows: [{ id }], rowCount: 1 };
        }
        if (sql.startsWith('UPDATE email_verifications SET is_verified = TRUE WHERE LOWER(email)')) {
          return { rows: [], rowCount: 1 };
        }
        if (sql.includes('FROM platform_settings')) {
          return { rows: [], rowCount: 0 };
        }
        if (sql.includes('FROM user_oauth_identities o')) {
          const [provider, sub] = params;
          const idRow = identities.get(`${provider}:${sub}`);
          if (!idRow) return { rows: [], rowCount: 0 };
          const u = usersByCode.get(idRow.user_code);
          return {
            rows: [
              {
                identity_id: idRow.id,
                linked_user_code: idRow.user_code,
                ...(u || { user_code: null, deleted_at: null }),
              },
            ],
            rowCount: 1,
          };
        }
        if (sql.startsWith('DELETE FROM user_oauth_identities WHERE id = $1')) {
          const targetId = params[0];
          for (const [k, v] of identities.entries()) {
            if (v.id === targetId) identities.delete(k);
          }
          return { rows: [], rowCount: 1 };
        }
        if (sql.startsWith('UPDATE user_oauth_identities SET last_login_at')) {
          return { rows: [], rowCount: 1 };
        }
        if (sql.includes('FROM users WHERE LOWER(email) = LOWER($1) AND deleted_at IS NULL')) {
          const email = String(params[0]).toLowerCase();
          const u = usersByEmail.get(email);
          if (!u || u.deleted_at !== null) return { rows: [], rowCount: 0 };
          return { rows: [{ ...u }], rowCount: 1 };
        }
        if (sql.startsWith('UPDATE users SET email_verified = TRUE')) {
          const u = usersByCode.get(params[0]);
          if (u && u.deleted_at === null) u.email_verified = true;
          return { rows: [], rowCount: u ? 1 : 0 };
        }
        if (sql.startsWith('INSERT INTO users')) {
          const [fullName, email, passwordHash] = params;
          const code = nextUserCode++;
          const u = {
            id: code,
            db_id: code,
            user_code: code,
            full_name: fullName,
            email: email.toLowerCase(),
            login_name: null,
            role: 'individual',
            is_active: true,
            email_verified: true,
            approval_status: 'approved',
            phone_number: null,
            created_at: new Date(),
            password_hash: passwordHash,
            deleted_at: null,
          };
          usersByCode.set(code, u);
          usersByEmail.set(u.email, u);
          return { rows: [{ ...u }], rowCount: 1 };
        }
        if (sql.startsWith('INSERT INTO user_oauth_identities')) {
          const [userCode, provider, sub, email] = params;
          identities.set(`${provider}:${sub}`, {
            id: identities.size + 1,
            user_code: userCode,
            provider,
            provider_sub: sub,
            email,
          });
          return { rows: [], rowCount: 1 };
        }
        if (sql.includes('FROM site_manager_invitations')) {
          const email = String(params[0]).toLowerCase();
          const matched = pendingInvitations.filter((inv) => inv.email.toLowerCase() === email && inv.status === 'PENDING');
          return { rows: matched, rowCount: matched.length };
        }
        if (sql.startsWith("UPDATE users SET role = 'site_manager'")) {
          const u = usersByCode.get(params[0]);
          if (u && u.deleted_at === null) u.role = 'site_manager';
          return { rows: [], rowCount: 1 };
        }
        return { rows: [], rowCount: 0 };
      },
      release() {},
    };
  }

  before(async () => {
    savedSecret = process.env.JWT_SECRET;
    process.env.JWT_SECRET = SECRET;
    originalConnect = pool.connect;
    originalQuery = pool.query;

    const app = express();
    app.use(express.json());
    app.use(oauthRouter);
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(async () => {
    pool.connect = originalConnect;
    pool.query = originalQuery;
    oauthHooks.verifyProviderToken = null;
    if (savedSecret === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = savedSecret;
    server.closeAllConnections?.();
    await new Promise((resolve) => server.close(resolve));
  });

  beforeEach(() => {
    resetFakeStore();
    oauthVerifyLimiter.reset();
    oauthCodeRequestLimiter.reset();
    pool.connect = async () => makeFakeClient();
    pool.query = async (t, p) => makeFakeClient().query(t, p);
    oauthHooks.sendVerificationEmail = async (payload) => {
      sentEmails.push(payload);
    };
    oauthHooks.verifyProviderToken = async (provider, idToken) => {
      if (idToken === 'valid-google-token') {
        return {
          sub: 'g-sub-1',
          email: 'deniz@gmail.com',
          emailVerified: true,
          name: 'Deniz Kaya',
          givenName: 'Deniz',
          familyName: 'Kaya',
        };
      }
      if (idToken === 'valid-apple-token') {
        return {
          sub: 'a-sub-1',
          email: 'selin@icloud.com',
          emailVerified: true,
          name: '',
          givenName: '',
          familyName: '',
        };
      }
      if (idToken === 'valid-apple-token-no-email') {
        return {
          sub: 'a-sub-1',
          email: null,
          emailVerified: false,
          name: '',
          givenName: '',
          familyName: '',
        };
      }
      const err = new Error('Geçersiz token');
      err.statusCode = 401;
      err.expose = true;
      throw err;
    };
  });

  it('POST /auth/oauth/google yeni bireysel kullanici olusturur ve JWT doner', async () => {
    const res = await fetch(`${baseUrl}/auth/oauth/google`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id_token: 'valid-google-token' }),
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.is_new_user, true);
    assert.equal(body.provider, 'google');
    assert.ok(body.token);
    assert.equal(body.user.email, 'deniz@gmail.com');
    assert.equal(body.user.full_name, 'Deniz Kaya');
    assert.equal(body.user.role, 'individual');

    // İkinci girişte is_new_user: false döner
    const res2 = await fetch(`${baseUrl}/auth/oauth/google`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id_token: 'valid-google-token' }),
    });
    assert.equal(res2.status, 200);
    const body2 = await res2.json();
    assert.equal(body2.is_new_user, false);
    assert.equal(body2.user.id, body.user.id);
  });

  it('POST /auth/oauth/apple ilk kayitta ad-soyad alir ve sonraki giriste e-posta gelmese bile sub ile tanir', async () => {
    const res1 = await fetch(`${baseUrl}/auth/oauth/apple`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        id_token: 'valid-apple-token',
        first_name: 'Selin',
        last_name: 'Demir',
      }),
    });
    assert.equal(res1.status, 200);
    const body1 = await res1.json();
    assert.equal(body1.is_new_user, true);
    assert.equal(body1.provider, 'apple');
    assert.equal(body1.user.full_name, 'Selin Demir');
    assert.equal(body1.user.email, 'selin@icloud.com');

    // Apple sonraki girişlerde e-posta göndermediğinde (valid-apple-token-no-email) user_oauth_identities üzerinden tanır
    const res2 = await fetch(`${baseUrl}/auth/oauth/apple`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id_token: 'valid-apple-token-no-email' }),
    });
    assert.equal(res2.status, 200);
    const body2 = await res2.json();
    assert.equal(body2.is_new_user, false);
    assert.equal(body2.user.id, body1.user.id);
    assert.equal(body2.user.email, 'selin@icloud.com');
  });

  it('bekleyen site yoneticisi daveti olan kullanici Google ile kaydoldugunda site_manager olur', async () => {
    pendingInvitations.push({ id: 10, site_code: 1000000001, email: 'deniz@gmail.com', status: 'PENDING' });
    const result = await authenticateWithOAuth({
      provider: 'google',
      idToken: 'valid-google-token',
    });
    assert.equal(result.is_new_user, true);
    assert.equal(result.user.role, 'site_manager');
  });

  it('POST /auth/oauth/:provider/request-code ve /verify-code ile 6 haneli dogrulama kodu akisi calisir', async () => {
    const reqRes = await fetch(`${baseUrl}/auth/oauth/google/request-code`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'emre@gmail.com',
        first_name: 'Emre',
        last_name: 'Yıldız',
      }),
    });
    assert.equal(reqRes.status, 200);
    const reqBody = await reqRes.json();
    assert.equal(reqBody.ok, true);
    assert.equal(reqBody.email, 'emre@gmail.com');
    assert.equal(sentEmails.length, 1);
    const issuedCode = sentEmails[0].code;
    assert.match(issuedCode, /^\d{6}$/);

    const verRes = await fetch(`${baseUrl}/auth/oauth/google/verify-code`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'emre@gmail.com',
        code: issuedCode,
        first_name: 'Emre',
        last_name: 'Yıldız',
      }),
    });
    assert.equal(verRes.status, 200);
    const verBody = await verRes.json();
    assert.equal(verBody.ok, true);
    assert.equal(verBody.is_new_user, true);
    assert.equal(verBody.user.email, 'emre@gmail.com');
    assert.equal(verBody.user.full_name, 'Emre Yıldız');
    assert.ok(verBody.token);
  });
});
