// SX2 duzeltmeleri (DB'siz, HTTP): sifre sifirlama hesap kilitlerini acar; current_password trim edilir.
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import express from 'express';
import '../src/utils/async_errors.js';
import { pool } from '../src/db.js';
import { authRouter } from '../src/routes/auth_routes.js';
import { createErrorHandler } from '../src/middlewares/error_handler.js';
import {
  clearAccountLocks,
  loginFailureTracker,
  passwordChangeFailureTracker,
  passwordChangeThrottleKey,
} from '../src/middlewares/login_throttle.js';
import { loginRateLimiter, resetPasswordLimiter } from '../src/middlewares/rate_limiters.js';
import { signAccessToken } from '../src/jwt.js';

const SECRET = 'k9Fz-test-only-long-secret-value-0123456789abcdef';
const PASSWORD = 'Dogru-Parola-1';
const PASSWORD_HASH = bcrypt.hashSync(PASSWORD, 4);
const NEW_PASSWORD = 'Yeni-Parola-2';

const baseUser = {
  id: 42,
  db_id: 7,
  user_code: 42,
  full_name: 'Test Kullanici',
  email: 'ali@example.com',
  login_name: 'ali.k',
  role: 'individual',
  is_active: true,
  email_verified: true,
  approval_status: 'approved',
  phone_number: null,
  created_at: new Date('2026-01-01T00:00:00Z'),
  password_hash: PASSWORD_HASH,
};

describe('auth_routes SX2: sifre sifirlama kilitleri acar, current_password trim', () => {
  let server;
  let baseUrl;
  let poolHandler;
  let calls;
  const saved = {};
  const originalConsoleError = console.error;

  before(async () => {
    const app = express();
    app.set('env', 'test');
    app.set('trust proxy', 1);
    app.use(express.json({ limit: '1mb' }));
    app.use(authRouter);
    app.use(createErrorHandler({ logger: { error: () => {}, log: () => {}, warn: () => {} } }));
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(() => new Promise((resolve) => {
    delete pool.query;
    server.closeAllConnections?.();
    server.close(resolve);
  }));

  beforeEach(() => {
    saved.JWT_SECRET = process.env.JWT_SECRET;
    process.env.JWT_SECRET = SECRET;
    calls = [];
    poolHandler = async () => ({ rows: [], rowCount: 0 });
    pool.query = async (text, params) => {
      calls.push({ text: String(text), params: params ?? [] });
      return poolHandler(String(text), params ?? []);
    };
    console.error = () => {};
    loginRateLimiter.reset();
    resetPasswordLimiter.reset();
    loginFailureTracker.reset();
    passwordChangeFailureTracker.reset();
  });

  afterEach(() => {
    delete pool.query;
    console.error = originalConsoleError;
    if (saved.JWT_SECRET === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = saved.JWT_SECRET;
  });

  const post = (path, body) =>
    fetch(`${baseUrl}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

  // ------------------------------------------------------------- reset-password
  describe('POST /auth/reset-password', () => {
    const token = crypto.randomBytes(32).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const future = () => new Date(Date.now() + 10 * 60 * 1000);

    const resetHandler = (updateRows) => async (text) => {
      if (text.includes('SELECT user_code, full_name, email, password_reset_expires_at')) {
        return {
          rows: [{ user_code: 42, full_name: 'Ali', email: 'Ali@Example.com', password_reset_expires_at: future() }],
          rowCount: 1,
        };
      }
      if (text.includes('UPDATE users')) {
        return { rows: updateRows, rowCount: updateRows.length };
      }
      return { rows: [], rowCount: 0 };
    };

    function lockAccount() {
      for (let i = 0; i < 5; i += 1) {
        loginFailureTracker.recordFailure('ali@example.com');
        loginFailureTracker.recordFailure('ali.k');
        passwordChangeFailureTracker.recordFailure(passwordChangeThrottleKey(42));
      }
      assert.equal(loginFailureTracker.check('ali@example.com').locked, true);
      assert.equal(loginFailureTracker.check('ali.k').locked, true);
      assert.equal(passwordChangeFailureTracker.check('u:42').locked, true);
    }

    it('basarili sifirlama: e-posta + kullanici adi giris kilitleri ve mevcut-parola kilidi acilir', async () => {
      lockAccount();
      poolHandler = resetHandler([{ user_code: 42, login_name: 'ali.k' }]);
      const response = await post('/auth/reset-password', { token, password: NEW_PASSWORD });
      assert.equal(response.status, 200);
      assert.equal(loginFailureTracker.check('ali@example.com').locked, false);
      assert.equal(loginFailureTracker.check('ali.k').locked, false);
      assert.equal(passwordChangeFailureTracker.check('u:42').locked, false);
      const update = calls.find((call) => call.text.includes('UPDATE users'));
      assert.match(update.text, /RETURNING user_code, login_name/);
      assert.equal(update.params[2], tokenHash);
    });

    it('basarisiz sifirlama (token baska istekle tuketildi) kilitleri ACMAZ', async () => {
      lockAccount();
      poolHandler = resetHandler([]);
      const response = await post('/auth/reset-password', { token, password: NEW_PASSWORD });
      assert.equal(response.status, 400);
      assert.equal(loginFailureTracker.check('ali@example.com').locked, true);
      assert.equal(passwordChangeFailureTracker.check('u:42').locked, true);

      // gecersiz bicimli token da kilidi acmaz
      const bad = await post('/auth/reset-password', { token: 'abc', password: NEW_PASSWORD });
      assert.equal(bad.status, 400);
      assert.equal(loginFailureTracker.check('ali.k').locked, true);
    });

    it('uctan uca: 5 hatali giris -> 429 LOGIN_LOCKED; sifirlamadan sonra giris 200 (kilit suresi beklenmez)', async () => {
      const loginHandler = async (text, params) => {
        if (text.includes('LOWER(login_name)')) {
          const ident = String(params[0]).toLowerCase();
          return ident === baseUser.email || ident === baseUser.login_name
            ? { rows: [{ ...baseUser }], rowCount: 1 }
            : { rows: [], rowCount: 0 };
        }
        return { rows: [], rowCount: 0 };
      };
      poolHandler = loginHandler;
      let last;
      for (let i = 1; i <= 5; i += 1) {
        last = await post('/auth/login', { email: baseUser.email, password: `yanlis-${i}` });
      }
      assert.equal(last.status, 429);
      assert.equal((await last.json()).code, 'LOGIN_LOCKED');
      assert.equal((await post('/auth/login', { email: baseUser.email, password: PASSWORD })).status, 429);

      const reset = resetHandler([{ user_code: 42, login_name: null }]);
      poolHandler = async (text, params) => (text.includes('LOWER(login_name)') ? loginHandler(text, params) : reset(text, params));
      assert.equal((await post('/auth/reset-password', { token, password: NEW_PASSWORD })).status, 200);

      const after = await post('/auth/login', { email: baseUser.email, password: PASSWORD });
      assert.equal(after.status, 200, 'sifirlama sonrasi kilit acik olmali');
    });

    it('clearAccountLocks: bos/eksik girdiyle patlamaz, yalniz ilgili hesabin anahtarlarini siler', () => {
      loginFailureTracker.recordFailure('baska@example.com');
      for (let i = 0; i < 5; i += 1) loginFailureTracker.recordFailure('ali@example.com');
      clearAccountLocks();
      clearAccountLocks({ email: null, loginName: '', userCode: undefined });
      assert.equal(loginFailureTracker.check('ali@example.com').locked, true);
      clearAccountLocks({ email: ' ALI@example.com ' });
      assert.equal(loginFailureTracker.check('ali@example.com').locked, false);
      assert.equal(loginFailureTracker.size(), 1, 'baska hesabin sayaci korunur');
    });
  });

  // ------------------------------------------------------------------ PATCH /me
  describe('PATCH /me: current_password trim edilir (giris ile tutarli)', () => {
    let currentHash;
    const authHeader = () => ({
      Authorization: `Bearer ${signAccessToken({ id: 42, email: baseUser.email, role: 'individual' }, { passwordHash: PASSWORD_HASH })}`,
    });
    const meHandler = async (text, params) => {
      if (text.includes('db_id')) return { rows: [{ ...baseUser, password_hash: currentHash }], rowCount: 1 };
      if (text.startsWith('SELECT password_hash FROM users')) return { rows: [{ password_hash: currentHash }], rowCount: 1 };
      if (text.includes('UPDATE users')) {
        const pwIndex = params.findIndex((p) => typeof p === 'string' && p.startsWith('$2'));
        if (pwIndex >= 0) currentHash = params[pwIndex];
        return {
          rows: [{ id: 42, full_name: 'Test Kullanici', email: baseUser.email, login_name: null, role: 'individual', is_active: true, email_verified: true, approval_status: 'approved', phone_number: null, created_at: baseUser.created_at }],
          rowCount: 1,
        };
      }
      return { rows: [], rowCount: 0 };
    };
    const patch = (body) =>
      fetch(`${baseUrl}/me`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json', ...authHeader() },
        body: JSON.stringify(body),
      });

    beforeEach(() => {
      currentHash = PASSWORD_HASH;
      poolHandler = meHandler;
    });

    it('basinda/sonunda bosluk olan DOGRU mevcut parola kabul edilir (400/kilit sayaci yok)', async () => {
      const response = await patch({ password: NEW_PASSWORD, current_password: `  ${PASSWORD} ` });
      assert.equal(response.status, 200);
      assert.ok(bcrypt.compareSync(NEW_PASSWORD, currentHash));
      assert.equal(passwordChangeFailureTracker.size(), 0);
    });

    it('yalniz bosluktan olusan mevcut parola "eksik" sayilir (CURRENT_PASSWORD_REQUIRED)', async () => {
      const response = await patch({ password: NEW_PASSWORD, current_password: '   ' });
      assert.equal(response.status, 400);
      assert.equal((await response.json()).code, 'CURRENT_PASSWORD_REQUIRED');
    });

    it('yanlis parola 400 CURRENT_PASSWORD_INVALID ve ortak sayaca yazilir (anahtar u:<user_code>)', async () => {
      const response = await patch({ password: NEW_PASSWORD, current_password: 'yanlis' });
      assert.equal(response.status, 400);
      assert.equal((await response.json()).code, 'CURRENT_PASSWORD_INVALID');
      assert.equal(passwordChangeFailureTracker.size(), 1);
      for (let i = 0; i < 4; i += 1) {
        passwordChangeFailureTracker.recordFailure(passwordChangeThrottleKey(42));
      }
      assert.equal(passwordChangeFailureTracker.check('u:42').locked, true);
    });
  });

  // ---------------------------------------------------- 5xx: genel mesaj + errorId (error-contract#7)
  describe('5xx yanitlari errorId uretir ve errorId ile loglanir', () => {
    const logged = [];
    const dbError = () => Object.assign(new Error('relation "users" does not exist at /srv/app/secret-path.js'), { code: '42P01', severity: 'ERROR' });

    beforeEach(() => {
      logged.length = 0;
      console.error = (...args) => {
        logged.push(args.map((arg) => String(arg)).join(' '));
      };
      poolHandler = async () => {
        throw dbError();
      };
    });

    it('POST /auth/login: DB hatasi 500 + { error, errorId }; log satirinda ayni errorId; ayrinti istemciye gitmez', async () => {
      const response = await post('/auth/login', { email: baseUser.email, password: PASSWORD });
      assert.equal(response.status, 500);
      const body = await response.json();
      assert.equal(body.error, 'Giris islemi basarisiz.');
      assert.match(body.errorId, /^[0-9a-f]{12}$/);
      const raw = JSON.stringify(body);
      assert.equal(raw.includes('secret-path'), false);
      assert.equal(raw.includes('users'), false);
      assert.ok(logged.some((line) => line.includes('[login]') && line.includes(body.errorId)), 'errorId ile loglanmali');
    });

    it('POST /auth/reset-password: DB hatasi 500 + { error, errorId }; log satirinda ayni errorId', async () => {
      const token = crypto.randomBytes(32).toString('hex');
      const response = await post('/auth/reset-password', { token, password: NEW_PASSWORD });
      assert.equal(response.status, 500);
      const body = await response.json();
      assert.match(body.errorId, /^[0-9a-f]{12}$/);
      assert.equal(JSON.stringify(body).includes('secret-path'), false);
      assert.ok(logged.some((line) => line.includes('[reset-password:post]') && line.includes(body.errorId)));
    });

    it('farkli istekler farkli errorId alir; 4xx yanitlari errorId tasimaz', async () => {
      const first = await (await post('/auth/login', { email: baseUser.email, password: PASSWORD })).json();
      const second = await (await post('/auth/login', { email: baseUser.email, password: PASSWORD })).json();
      assert.notEqual(first.errorId, second.errorId);
      const badRequest = await post('/auth/login', { email: '', password: '' });
      assert.equal(badRequest.status, 400);
      assert.equal('errorId' in (await badRequest.json()), false);
    });
  });
});
