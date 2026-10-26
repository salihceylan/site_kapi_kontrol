import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import { readFileSync } from 'node:fs';
import express from 'express';
import '../src/utils/async_errors.js';
import { pool } from '../src/db.js';
import { DEFAULT_MIGRATIONS_DIR, findUnsafeStatements, listMigrations } from '../scripts/migrate.js';
import { OAUTH_DDL, OAUTH_TABLES, ensureOAuthSchema } from '../src/modules/oauth_schema.js';
import {
  authenticateWithOAuth,
  clearJwksCache,
  expectedNonceFromClient,
  getOAuthConfig,
  isOAuthNonceRequired,
  oauthHooks,
  oauthStatus,
  startOAuthWebSession,
  completeOAuthWebCallback,
  verifyOAuthJwt,
  verifyProviderIdToken,
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

describe('verifyProviderIdToken: istemci kimligi yoksa KAPALI; aud / iss / imza hatasinda kesin red; yalniz JWKS erisim hatasinda yedek (aud + iss + exp yine denetlenir)', () => {
  const GOOGLE_ENV = { GOOGLE_CLIENT_ID: 'google-client-1', APPLE_CLIENT_ID: 'apple-client-1' };
  let fetchCalls;
  let fetchReply;
  let originalHooks;

  const nowSec = () => Math.floor(Date.now() / 1000);
  const googleToken = (overrides = {}, options) =>
    signTestRs256Jwt(
      {
        iss: 'https://accounts.google.com',
        aud: 'google-client-1',
        sub: 'g-sub-9',
        email: 'Deniz@Gmail.com',
        email_verified: true,
        iat: nowSec() - 10,
        exp: nowSec() + 3600,
        ...overrides,
      },
      options,
    );
  const appleToken = (overrides = {}) =>
    signTestRs256Jwt({
      iss: 'https://appleid.apple.com',
      aud: 'apple-client-1',
      sub: 'a-sub-9',
      email: 'selin@icloud.com',
      email_verified: 'true',
      iat: nowSec() - 10,
      exp: nowSec() + 3600,
      ...overrides,
    });
  const tokeninfo = (overrides = {}) => ({
    iss: 'https://accounts.google.com',
    aud: 'google-client-1',
    sub: 'g-sub-9',
    email: 'Deniz@Gmail.com',
    email_verified: 'true',
    exp: String(nowSec() + 3600),
    ...overrides,
  });

  beforeEach(() => {
    clearJwksCache();
    originalHooks = { ...oauthHooks };
    oauthHooks.verifyProviderToken = null;
    oauthHooks.verifyWithGoogleApi = undefined;
    oauthHooks.fetchJwks = async () => [publicJwk];
    fetchCalls = [];
    fetchReply = () => ({ status: 200, body: {} });
    mock.method(globalThis, 'fetch', async (url) => {
      fetchCalls.push(String(url));
      const reply = fetchReply(String(url));
      if (reply instanceof Error) throw reply;
      return { ok: reply.status >= 200 && reply.status < 300, status: reply.status, json: async () => reply.body };
    });
  });

  afterEach(() => {
    mock.restoreAll();
    Object.assign(oauthHooks, originalHooks);
  });

  it('istemci kimligi TANIMSIZ ise Google ve Apple girisi KAPALI (fail-closed): 503 OAUTH_NOT_CONFIGURED, JWKS / ag cagrisi yok', async () => {
    for (const provider of ['google', 'apple']) {
      await assert.rejects(
        () => verifyProviderIdToken(provider, provider === 'google' ? googleToken() : appleToken(), {}),
        (error) => error.statusCode === 503 && error.code === 'OAUTH_NOT_CONFIGURED',
        provider,
      );
    }
    // Opak (erisim) belirteci de ayni sekilde kapali
    await assert.rejects(
      () => verifyProviderIdToken('google', 'ya29.opak-erisim-belirteci', {}),
      (error) => error.code === 'OAUTH_NOT_CONFIGURED',
    );
    assert.deepEqual(fetchCalls, []);
  });

  it('verifyOAuthJwt audience listesi bos / yok ise belirteci KABUL ETMEZ (audience denetimi atlanamaz)', async () => {
    for (const allowedAudiences of [null, undefined, []]) {
      await assert.rejects(
        () => verifyOAuthJwt(googleToken(), { jwksUrl: 'https://www.googleapis.com/oauth2/v3/certs', allowedIssuers: new Set(['https://accounts.google.com']), allowedAudiences }),
        (error) => error.statusCode === 503 && error.code === 'OAUTH_NOT_CONFIGURED',
      );
    }
  });

  it('gecerli Google JWT JWKS ile dogrulanir; ag yedegi KULLANILMAZ; nonce talebi claims icinde doner', async () => {
    const claims = await verifyProviderIdToken('google', googleToken({ nonce: 'n-123' }), GOOGLE_ENV);
    assert.equal(claims.sub, 'g-sub-9');
    assert.equal(claims.email, 'deniz@gmail.com');
    assert.equal(claims.nonce, 'n-123');
    assert.deepEqual(fetchCalls, []);
  });

  it('aud / iss / imza / sure hatasi KESIN red: tokeninfo yedegine DUSULMEZ (ag cagrisi yok, yedek kanca cagrilmaz)', async () => {
    let hookCalled = false;
    oauthHooks.verifyWithGoogleApi = async () => {
      hookCalled = true;
      return { sub: 'x' };
    };
    const cases = [
      [googleToken({ aud: 'baska-uygulama' }), 'INVALID_OAUTH_AUDIENCE'],
      [googleToken({ aud: ['baska-1', 'baska-2'] }), 'INVALID_OAUTH_AUDIENCE'],
      [googleToken({ iss: 'https://evil.example.com' }), 'INVALID_OAUTH_TOKEN'],
      [googleToken({ exp: nowSec() - 3600 }), 'OAUTH_TOKEN_EXPIRED'],
      [googleToken({}, { key: crypto.generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey }), 'INVALID_OAUTH_TOKEN'],
      [googleToken({}, { kid: 'bilinmeyen-kid' }), 'INVALID_OAUTH_TOKEN'],
      [googleToken({}, { alg: 'HS256' }), 'INVALID_OAUTH_TOKEN'],
    ];
    for (const [token, code] of cases) {
      await assert.rejects(() => verifyProviderIdToken('google', token, GOOGLE_ENV), (error) => error.statusCode >= 400 && error.statusCode < 500 && error.code === code, code);
    }
    assert.equal(hookCalled, false);
    assert.deepEqual(fetchCalls, [], 'JWT hatalarinda tokeninfo yedegi YOK');
  });

  it('JWKS\'e ulasilamazsa (ag hatasi) tokeninfo yedegine dusulur; aud / iss / exp BURADA denetlenir ve gecerliyse kabul edilir', async () => {
    oauthHooks.fetchJwks = async () => {
      throw new Error('ECONNREFUSED');
    };
    fetchReply = () => ({ status: 200, body: tokeninfo() });
    const claims = await verifyProviderIdToken('google', googleToken(), GOOGLE_ENV);
    assert.equal(claims.sub, 'g-sub-9');
    assert.equal(claims.email, 'deniz@gmail.com');
    assert.equal(claims.emailVerified, true);
    assert.equal(fetchCalls.length, 1);
    assert.match(fetchCalls[0], /^https:\/\/oauth2\.googleapis\.com\/tokeninfo\?id_token=/);
  });

  it('yedekte aud / iss / exp tutmazsa KESIN red (baska uygulamaya verilmis belirteci tokeninfo "gecerli" dese de)', async () => {
    oauthHooks.fetchJwks = async () => {
      throw new Error('ETIMEDOUT');
    };
    const cases = [
      [tokeninfo({ aud: 'baska-uygulama' }), 'INVALID_OAUTH_AUDIENCE'],
      [tokeninfo({ aud: undefined }), 'INVALID_OAUTH_AUDIENCE'],
      [tokeninfo({ iss: 'https://evil.example.com' }), 'INVALID_OAUTH_TOKEN'],
      [tokeninfo({ exp: String(nowSec() - 3600) }), 'OAUTH_TOKEN_EXPIRED'],
      [tokeninfo({ exp: 'yok' }), 'OAUTH_TOKEN_EXPIRED'],
      [tokeninfo({ sub: '' }), 'INVALID_OAUTH_TOKEN'],
    ];
    for (const [body, code] of cases) {
      fetchReply = () => ({ status: 200, body });
      await assert.rejects(() => verifyProviderIdToken('google', googleToken(), GOOGLE_ENV), (error) => error.code === code, code);
    }
  });

  it('yedek ucu da yanit vermezse: ag hatasi / 5xx -> 503 OAUTH_JWKS_UNAVAILABLE; 400 invalid_token -> 401', async () => {
    oauthHooks.fetchJwks = async () => {
      throw new Error('ECONNRESET');
    };
    fetchReply = () => new Error('fetch failed');
    await assert.rejects(() => verifyProviderIdToken('google', googleToken(), GOOGLE_ENV), (error) => error.statusCode === 503 && error.code === 'OAUTH_JWKS_UNAVAILABLE');
    fetchReply = () => ({ status: 502, body: {} });
    await assert.rejects(() => verifyProviderIdToken('google', googleToken(), GOOGLE_ENV), (error) => error.statusCode === 503);
    fetchReply = () => ({ status: 400, body: { error: 'invalid_token' } });
    await assert.rejects(() => verifyProviderIdToken('google', googleToken(), GOOGLE_ENV), (error) => error.statusCode === 401 && error.code === 'INVALID_OAUTH_TOKEN');
  });

  it('opak Google ERISIM belirteci (web: id_token yok): tokeninfo aud\'u yapilandirilmis istemci degilse kesin red; degilse kabul', async () => {
    fetchReply = () => ({ status: 200, body: { aud: 'baska-uygulama', sub: 'g-sub-9', email: 'deniz@gmail.com', email_verified: 'true', expires_in: '3000' } });
    await assert.rejects(() => verifyProviderIdToken('google', 'ya29.opak', GOOGLE_ENV), (error) => error.code === 'INVALID_OAUTH_AUDIENCE');
    assert.equal(fetchCalls.length, 1, 'userinfo\'ya gidilmedi (aud tutmadi)');
    assert.match(fetchCalls[0], /tokeninfo\?access_token=/);

    fetchCalls.length = 0;
    fetchReply = () => ({ status: 200, body: { aud: 'google-client-1', sub: 'g-sub-9', email: 'Deniz@Gmail.com', email_verified: 'true', expires_in: '3000' } });
    const claims = await verifyProviderIdToken('google', 'ya29.opak', GOOGLE_ENV);
    assert.equal(claims.sub, 'g-sub-9');
    assert.equal(claims.email, 'deniz@gmail.com');

    fetchReply = () => ({ status: 200, body: { aud: 'google-client-1', sub: 'g-sub-9', expires_in: '0' } });
    await assert.rejects(() => verifyProviderIdToken('google', 'ya29.opak', GOOGLE_ENV), (error) => error.code === 'OAUTH_TOKEN_EXPIRED');
  });

  it('opak erisim belirtecinde e-posta tokeninfo\'da yoksa userinfo\'dan alinir; ama yalniz aud dogrulandiktan sonra ve AYNI kullanici icin', async () => {
    const replies = [
      { status: 200, body: { aud: 'google-client-1', sub: 'g-sub-9', expires_in: '3000' } },
      { status: 200, body: { sub: 'g-sub-9', email: 'deniz@gmail.com', email_verified: true, name: 'Deniz Kaya' } },
    ];
    fetchReply = () => replies.shift();
    const claims = await verifyProviderIdToken('google', 'ya29.opak', GOOGLE_ENV);
    assert.equal(claims.email, 'deniz@gmail.com');
    assert.equal(claims.name, 'Deniz Kaya');

    const other = [
      { status: 200, body: { aud: 'google-client-1', sub: 'g-sub-9', expires_in: '3000' } },
      { status: 200, body: { sub: 'BASKA-KULLANICI', email: 'x@gmail.com', email_verified: true } },
    ];
    fetchReply = () => other.shift();
    await assert.rejects(() => verifyProviderIdToken('google', 'ya29.opak', GOOGLE_ENV), (error) => error.code === 'INVALID_OAUTH_TOKEN');
  });

  it('Apple: yanlis aud kesin red; JWKS erisilemezse YEDEK YOK (503)', async () => {
    const ok = await verifyProviderIdToken('apple', appleToken({ nonce: 'abc' }), GOOGLE_ENV);
    assert.equal(ok.sub, 'a-sub-9');
    assert.equal(ok.nonce, 'abc');
    await assert.rejects(() => verifyProviderIdToken('apple', appleToken({ aud: 'baska' }), GOOGLE_ENV), (error) => error.code === 'INVALID_OAUTH_AUDIENCE');
    await assert.rejects(() => verifyProviderIdToken('apple', appleToken({ iss: 'https://accounts.google.com' }), GOOGLE_ENV), (error) => error.code === 'INVALID_OAUTH_TOKEN');

    clearJwksCache();
    oauthHooks.fetchJwks = async () => {
      throw new Error('ENOTFOUND');
    };
    await assert.rejects(() => verifyProviderIdToken('apple', appleToken(), GOOGLE_ENV), (error) => error.statusCode === 503 && error.code === 'OAUTH_JWKS_UNAVAILABLE');
    assert.deepEqual(fetchCalls, []);
  });

  it('web oturumu: sunucunun urettigi nonce belirteçte AYNEN bulunmali (eksik / farkli nonce 401 INVALID_OAUTH_NONCE)', async () => {
    const started = startOAuthWebSession({ provider: 'google', env: GOOGLE_ENV });
    assert.equal(started.mode, 'redirect');
    const nonce = new URL(started.auth_url).searchParams.get('nonce');
    assert.ok(nonce && nonce.length >= 16);

    // nonce'suz belirtec (baska oturum icin alinmis olabilir): reddedilir
    await assert.rejects(
      () => completeOAuthWebCallback({ provider: 'google', state: started.session_id, idToken: googleToken(), env: GOOGLE_ENV }),
      (error) => error.statusCode === 401 && error.code === 'INVALID_OAUTH_NONCE',
    );
    // farkli nonce
    const second = startOAuthWebSession({ provider: 'google', env: GOOGLE_ENV });
    await assert.rejects(
      () => completeOAuthWebCallback({ provider: 'google', state: second.session_id, idToken: googleToken({ nonce: 'baska-oturumun-nonce-degeri' }), env: GOOGLE_ENV }),
      (error) => error.code === 'INVALID_OAUTH_NONCE',
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
  let ambiguousEmails;
  let pinClears;
  let rotations;

  function resetFakeStore() {
    ambiguousEmails = new Set();
    pinClears = [];
    rotations = [];
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
          if (ambiguousEmails.has(email)) return { rows: [{ ...u }, { ...u, user_code: u.user_code + 1000, id: u.id + 1000 }], rowCount: 2 };
          return { rows: [{ ...u }], rowCount: 1 };
        }
        if (sql.startsWith('UPDATE users SET password_hash = $2, must_change_password = FALSE, email_verified = TRUE')) {
          const u = usersByCode.get(params[0]);
          if (!u || u.deleted_at !== null) return { rows: [], rowCount: 0 };
          u.password_hash = params[1];
          u.must_change_password = false;
          u.email_verified = true;
          rotations.push(params[0]);
          return { rows: [{ password_hash: u.password_hash }], rowCount: 1 };
        }
        if (sql.startsWith('UPDATE apartments SET resident_pin_issued = FALSE')) {
          pinClears.push(params[0]);
          return { rows: [], rowCount: 1 };
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
  const seedUser = (extra = {}) => {
    const code = nextUserCode++;
    const u = {
      id: code,
      db_id: code,
      user_code: code,
      full_name: 'Hazir Kullanici',
      email: 'sakin@example.com',
      login_name: 'sakin.k',
      role: 'apartment_owner',
      is_active: true,
      email_verified: true,
      approval_status: 'approved',
      phone_number: null,
      created_at: new Date(),
      password_hash: bcrypt.hashSync('1234', 4),
      must_change_password: false,
      deleted_at: null,
      ...extra,
    };
    usersByCode.set(code, u);
    usersByEmail.set(u.email.toLowerCase(), u);
    return u;
  };

  it('yonetimin verdigi gecici parola (must_change_password): ilk OAuth girisinde parola RASTGELE dondurulur, bayrak kapanir, e-posta dogrulanir; eski parola isler OLMAZ', async () => {
    const seeded = seedUser({ email: 'deniz@gmail.com', must_change_password: true, email_verified: false });
    const result = await authenticateWithOAuth({ provider: 'google', idToken: 'valid-google-token' });
    assert.equal(result.is_new_user, false);
    assert.equal(result.user.id, seeded.user_code);
    assert.equal(result.user.must_change_password, false, 'yanitta bayrak kapali');
    assert.equal(result.user.email_verified, true);
    assert.deepEqual(rotations, [seeded.user_code]);
    assert.equal(await bcrypt.compare('1234', seeded.password_hash), false, 'yonetimin bildigi parola artik gecersiz');
    assert.equal(seeded.must_change_password, false);
    assert.deepEqual(pinClears, [seeded.user_code], 'dairedeki "PIN verildi" isareti temizlenir (COMMIT sonrasi ayri ifade)');
    assert.ok(result.token);
  });

  it('bayrak bagli kimlik (provider_sub) yolunda da uygulanir', async () => {
    const seeded = seedUser({ email: 'deniz@gmail.com', must_change_password: true });
    identities.set('google:g-sub-1', { id: 1, user_code: seeded.user_code, provider: 'google', provider_sub: 'g-sub-1', email: 'deniz@gmail.com' });
    const result = await authenticateWithOAuth({ provider: 'google', idToken: 'valid-google-token' });
    assert.equal(result.user.must_change_password, false);
    assert.deepEqual(rotations, [seeded.user_code]);
  });

  it('DOGRULANMAMIS hesap (kayit oncesi sahte kayit / yonetim): sahiplik sagliyiciyla kanitlaninca parola dondurulur (onceden-ele-gecirme korumasi)', async () => {
    const seeded = seedUser({ email: 'deniz@gmail.com', email_verified: false, password_hash: bcrypt.hashSync('saldirgan-parolasi', 4) });
    await authenticateWithOAuth({ provider: 'google', idToken: 'valid-google-token' });
    assert.deepEqual(rotations, [seeded.user_code]);
    assert.equal(await bcrypt.compare('saldirgan-parolasi', seeded.password_hash), false);
    assert.equal(seeded.email_verified, true);
  });

  it('bayraksiz ve dogrulanmis hesapta parola DONDURULMEZ (normal giris etkilenmez)', async () => {
    const seeded = seedUser({ email: 'deniz@gmail.com' });
    const before = seeded.password_hash;
    const result = await authenticateWithOAuth({ provider: 'google', idToken: 'valid-google-token' });
    assert.equal(seeded.password_hash, before);
    assert.deepEqual(rotations, []);
    assert.deepEqual(pinClears, []);
    assert.ok(result.token);
  });

  it('pasif / onay bekleyen hesapta giris reddedilir ve parola DONDURULMEZ (rollback)', async () => {
    const seeded = seedUser({ email: 'deniz@gmail.com', must_change_password: true, is_active: false });
    await assert.rejects(() => authenticateWithOAuth({ provider: 'google', idToken: 'valid-google-token' }), (error) => error.statusCode === 403);
    assert.deepEqual(rotations, []);
    assert.equal(seeded.must_change_password, true);
  });

  it('ayni e-postanin birden cok hesabi varsa (buyuk/kucuk harf farki) fail-closed: 409 OAUTH_ACCOUNT_AMBIGUOUS, hicbir hesaba baglanmaz', async () => {
    seedUser({ email: 'deniz@gmail.com' });
    ambiguousEmails.add('deniz@gmail.com');
    await assert.rejects(
      () => authenticateWithOAuth({ provider: 'google', idToken: 'valid-google-token' }),
      (error) => error.statusCode === 409 && error.code === 'OAUTH_ACCOUNT_AMBIGUOUS',
    );
    assert.equal(identities.size, 0);
  });

  it('nonce: expectedNonce verilirse belirteçteki nonce AYNI olmali (eksik / farkli 401 INVALID_OAUTH_NONCE); verilmezse denetlenmez', async () => {
    const original = oauthHooks.verifyProviderToken;
    oauthHooks.verifyProviderToken = async (provider, idToken, env) => ({ ...(await original(provider, idToken, env)), nonce: 'oturum-nonce-1' });
    const ok = await authenticateWithOAuth({ provider: 'google', idToken: 'valid-google-token', expectedNonce: 'oturum-nonce-1' });
    assert.equal(ok.ok, true);
    await assert.rejects(
      () => authenticateWithOAuth({ provider: 'google', idToken: 'valid-google-token', expectedNonce: 'baska-nonce' }),
      (error) => error.statusCode === 401 && error.code === 'INVALID_OAUTH_NONCE',
    );
    oauthHooks.verifyProviderToken = original;
    await assert.rejects(
      () => authenticateWithOAuth({ provider: 'google', idToken: 'valid-google-token', expectedNonce: 'oturum-nonce-1' }),
      (error) => error.code === 'INVALID_OAUTH_NONCE',
      'belirteçte nonce yok',
    );
    const noCheck = await authenticateWithOAuth({ provider: 'google', idToken: 'valid-google-token' });
    assert.equal(noCheck.ok, true);
  });

  // --- Yerel (mobil) nonce: istemci HAM nonce'u gonderir, saglayiciya SHA-256 ozetini verir; belirtecteki nonce talebi ozettir ---
  const RAW_NONCE = 'Zk3-q_Wl9xT0aB7cD1eF2gH4iJ5kL6mN8oP';
  const digestOf = (value) => crypto.createHash('sha256').update(value).digest('hex');
  const withNonceClaim = (claim) => {
    const original = oauthHooks.verifyProviderToken;
    oauthHooks.verifyProviderToken = async (provider, idToken, env) => ({ ...(await original(provider, idToken, env)), nonce: claim });
    return () => {
      oauthHooks.verifyProviderToken = original;
    };
  };
  const postOAuth = (provider, body) =>
    fetch(`${baseUrl}/auth/oauth/${provider}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  let savedRequireNonce;
  beforeEach(() => {
    savedRequireNonce = process.env.OAUTH_REQUIRE_NONCE;
    delete process.env.OAUTH_REQUIRE_NONCE;
  });
  afterEach(() => {
    if (savedRequireNonce === undefined) delete process.env.OAUTH_REQUIRE_NONCE;
    else process.env.OAUTH_REQUIRE_NONCE = savedRequireNonce;
  });

  it('HTTP: ham nonce gonderilirse belirtecteki nonce talebi SHA-256(ham) olmali; ayni ham deger belirtecte gorunuyorsa (ozetlenmemis) REDDEDILIR', async () => {
    const restore = withNonceClaim(digestOf(RAW_NONCE));
    try {
      const ok = await postOAuth('apple', { id_token: 'valid-apple-token', nonce: RAW_NONCE });
      assert.equal(ok.status, 200);
      assert.equal((await ok.json()).ok, true);
    } finally {
      restore();
    }

    // belirtecte ozet degil HAM deger var: nonce belirtec yukunden okunup kopyalanabilirdi, bu yuzden kabul edilmez
    const restoreRaw = withNonceClaim(RAW_NONCE);
    try {
      const rawRes = await postOAuth('apple', { id_token: 'valid-apple-token', nonce: RAW_NONCE });
      assert.equal(rawRes.status, 401);
      assert.equal((await rawRes.json()).code, 'INVALID_OAUTH_NONCE');
    } finally {
      restoreRaw();
    }
  });

  it('HTTP: baska oturumun belirteci (farkli nonce) ve nonce talebi OLMAYAN belirtec 401 INVALID_OAUTH_NONCE; hesap olusmaz', async () => {
    const restore = withNonceClaim(digestOf('baska-oturumun-nonce-degeri-0123'));
    try {
      const other = await postOAuth('apple', { id_token: 'valid-apple-token', nonce: RAW_NONCE });
      assert.equal(other.status, 401);
      assert.equal((await other.json()).code, 'INVALID_OAUTH_NONCE');
    } finally {
      restore();
    }
    // belirtecte hic nonce yok (ornek: Google 6.x istemcisi nonce iletemez) ama istemci nonce gonderdi
    const missing = await postOAuth('apple', { id_token: 'valid-apple-token', nonce: RAW_NONCE });
    assert.equal(missing.status, 401);
    assert.equal((await missing.json()).code, 'INVALID_OAUTH_NONCE');
    assert.equal(usersByCode.size, 0);
    assert.equal(identities.size, 0);
  });

  it('HTTP: bicimsiz nonce (kisa / yasak karakter / dizi / sayi) 400 INVALID_OAUTH_NONCE; bos nonce "gonderilmedi" sayilir', async () => {
    for (const nonce of ['kisa', 'bosluk iceren nonce degeri 123456', 'a'.repeat(129), ['x'], 42, { a: 1 }]) {
      const res = await postOAuth('apple', { id_token: 'valid-apple-token', nonce });
      assert.equal(res.status, 400, JSON.stringify(nonce));
      assert.equal((await res.json()).code, 'INVALID_OAUTH_NONCE');
    }
    assert.equal(usersByCode.size, 0);
    const empty = await postOAuth('apple', { id_token: 'valid-apple-token', nonce: '' });
    assert.equal(empty.status, 200, 'bos nonce = eski istemci: varsayilan (zorunlu degil) kipte kabul');
  });

  it('GERIYE UYUM: nonce gondermeyen eski istemci varsayilan kipte kabul edilir (Google ve Apple)', async () => {
    const google = await postOAuth('google', { id_token: 'valid-google-token' });
    assert.equal(google.status, 200);
    const apple = await postOAuth('apple', { id_token: 'valid-apple-token' });
    assert.equal(apple.status, 200);
  });

  it('OAUTH_REQUIRE_NONCE=1: nonce olmayan istek 400 OAUTH_NONCE_REQUIRED (saglayiciya gidilmez, hesap olusmaz); nonce olan istek gecer', async () => {
    process.env.OAUTH_REQUIRE_NONCE = '1';
    let providerCalls = 0;
    const original = oauthHooks.verifyProviderToken;
    oauthHooks.verifyProviderToken = async (...args) => {
      providerCalls += 1;
      return { ...(await original(...args)), nonce: digestOf(RAW_NONCE) };
    };
    try {
      for (const provider of ['google', 'apple']) {
        const res = await postOAuth(provider, { id_token: `valid-${provider}-token` });
        assert.equal(res.status, 400);
        assert.equal((await res.json()).code, 'OAUTH_NONCE_REQUIRED');
      }
      assert.equal(providerCalls, 0, 'nonce kontrolu belirtec dogrulamasindan ONCE');
      assert.equal(usersByCode.size, 0);
      const ok = await postOAuth('apple', { id_token: 'valid-apple-token', nonce: RAW_NONCE });
      assert.equal(ok.status, 200);
    } finally {
      oauthHooks.verifyProviderToken = original;
    }
  });

  it('OAUTH_REQUIRE_NONCE=apple: yalniz Apple zorunlu, Google (google_sign_in 6.x nonce iletemez) eskisi gibi kabul', async () => {
    process.env.OAUTH_REQUIRE_NONCE = 'apple';
    const apple = await postOAuth('apple', { id_token: 'valid-apple-token' });
    assert.equal(apple.status, 400);
    assert.equal((await apple.json()).code, 'OAUTH_NONCE_REQUIRED');
    const google = await postOAuth('google', { id_token: 'valid-google-token' });
    assert.equal(google.status, 200);
  });

  it('web oturumu etkilenmez: OAUTH_REQUIRE_NONCE=1 iken sunucunun urettigi oturum nonce degeri yine zorunlu ve yeterli', async () => {
    process.env.OAUTH_REQUIRE_NONCE = '1';
    const env = { GOOGLE_CLIENT_ID: 'google-client-1', OAUTH_REQUIRE_NONCE: '1' };
    const started = startOAuthWebSession({ provider: 'google', env });
    const nonce = new URL(started.auth_url).searchParams.get('nonce');
    const original = oauthHooks.verifyProviderToken;
    oauthHooks.verifyProviderToken = async (provider, idToken, e) => ({ ...(await original(provider, idToken, e)), nonce });
    try {
      const out = await completeOAuthWebCallback({ provider: 'google', state: started.session_id, idToken: 'valid-google-token', env });
      assert.equal(out.ok, true);
    } finally {
      oauthHooks.verifyProviderToken = original;
    }
  });
});

describe('expectedNonceFromClient ve isOAuthNonceRequired', () => {
  it('expectedNonceFromClient: yok / bos -> null; gecerli ham deger -> SHA-256 onaltili ozet; bicimsiz -> 400', () => {
    assert.equal(expectedNonceFromClient(undefined), null);
    assert.equal(expectedNonceFromClient(null), null);
    assert.equal(expectedNonceFromClient(''), null);
    const raw = 'abcDEF0123456789_-abcDEF0123456789_-abc';
    const digest = crypto.createHash('sha256').update(raw).digest('hex');
    assert.equal(expectedNonceFromClient(raw), digest);
    assert.equal(expectedNonceFromClient(`  ${raw}  `), digest, 'kenar bosluklari kirpilir');
    for (const bad of ['a'.repeat(15), 'a'.repeat(129), 'bosluk var 1234567890', 'turkce-ğüşiöç-1234567890', 5, true, {}, []]) {
      assert.throws(() => expectedNonceFromClient(bad), (error) => error.statusCode === 400 && error.code === 'INVALID_OAUTH_NONCE', String(bad));
    }
  });

  it('isOAuthNonceRequired: varsayilan KAPALI; 1/true/all hepsi; virgullu liste yalniz listedekiler; 0/false/bilinmeyen kapali', () => {
    for (const provider of ['google', 'apple']) {
      for (const off of [undefined, '', '  ', '0', 'false', 'off', 'none']) {
        assert.equal(isOAuthNonceRequired(provider, { OAUTH_REQUIRE_NONCE: off }), false, `${provider}:${off}`);
      }
      for (const on of ['1', 'true', 'TRUE', 'yes', 'on', 'all', ' 1 ']) {
        assert.equal(isOAuthNonceRequired(provider, { OAUTH_REQUIRE_NONCE: on }), true, `${provider}:${on}`);
      }
    }
    assert.equal(isOAuthNonceRequired('apple', { OAUTH_REQUIRE_NONCE: 'apple' }), true);
    assert.equal(isOAuthNonceRequired('google', { OAUTH_REQUIRE_NONCE: 'apple' }), false);
    assert.equal(isOAuthNonceRequired('google', { OAUTH_REQUIRE_NONCE: 'Google, Apple' }), true);
    assert.equal(isOAuthNonceRequired('apple', {}), false);
  });

  it('authenticateWithOAuth: zorunlu kipte expectedNonce yoksa saglayici dogrulamasina GIDILMEDEN 400 OAUTH_NONCE_REQUIRED', async () => {
    let called = false;
    const saved = oauthHooks.verifyProviderToken;
    oauthHooks.verifyProviderToken = async () => {
      called = true;
      return { sub: 's', email: 'a@gmail.com', emailVerified: true };
    };
    try {
      await assert.rejects(
        () => authenticateWithOAuth({ provider: 'apple', idToken: 'x', env: { OAUTH_REQUIRE_NONCE: 'apple' } }),
        (error) => error.statusCode === 400 && error.code === 'OAUTH_NONCE_REQUIRED',
      );
      assert.equal(called, false);
    } finally {
      oauthHooks.verifyProviderToken = saved;
    }
  });
});
