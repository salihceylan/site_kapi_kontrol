import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import express from 'express';
import nodemailer from 'nodemailer';
import '../src/utils/async_errors.js';
import { pool } from '../src/db.js';
import { authRouter } from '../src/routes/auth_routes.js';
import { createErrorHandler } from '../src/middlewares/error_handler.js';
import { loginFailureTracker, passwordChangeFailureTracker } from '../src/middlewares/login_throttle.js';
import {
  forgotPasswordLimiter,
  loginRateLimiter,
  resendCodeLimiter,
  resetPasswordLimiter,
  verifyCodeLimiter,
} from '../src/middlewares/rate_limiters.js';
import { passwordVersionOf, signAccessToken, verifyAccessToken } from '../src/jwt.js';

const SECRET = 'k9Fz-test-only-long-secret-value-0123456789abcdef';
const PASSWORD = 'Dogru-Parola-1';
const PASSWORD_HASH = bcrypt.hashSync(PASSWORD, 4);
const NEW_PASSWORD = 'Yeni-Parola-2';
const DB_SECRET_DETAIL = 'relation "users" does not exist at /srv/app/secret-path.js';

const baseUser = {
  id: 42,
  db_id: 7,
  user_code: 42,
  full_name: 'Test Kullanici',
  email: 'ali@example.com',
  login_name: null,
  role: 'individual',
  is_active: true,
  email_verified: true,
  approval_status: 'approved',
  phone_number: null,
  created_at: new Date('2026-01-01T00:00:00Z'),
  password_hash: PASSWORD_HASH,
};

function pgError(message = DB_SECRET_DETAIL) {
  return Object.assign(new Error(message), { code: '42P01', severity: 'ERROR' });
}

const calls = [];
let poolHandler = async () => ({ rows: [], rowCount: 0 });
const sent = [];

async function waitFor(predicate, timeoutMs = 2000) {
  const start = Date.now();
  while (!predicate()) {
    if (Date.now() - start > timeoutMs) throw new Error('waitFor zaman asimi');
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

describe('auth_routes (C1/C8/C12, enumeration, sizinti)', () => {
  let server;
  let baseUrl;
  const originalQuery = pool.query;
  const originalCreateTransport = nodemailer.createTransport;
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
    pool.query = originalQuery;
    server.closeAllConnections?.();
    server.close(resolve);
  }));

  beforeEach(() => {
    for (const name of ['JWT_SECRET', 'JWT_EXPIRES_IN', 'SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD', 'SMTP_FROM', 'PUBLIC_APP_URL', 'PUBLIC_BASE_URL']) {
      saved[name] = process.env[name];
    }
    process.env.JWT_SECRET = SECRET;
    delete process.env.JWT_EXPIRES_IN;
    process.env.SMTP_HOST = 'smtp.invalid';
    process.env.SMTP_USER = 'user@example.invalid';
    process.env.SMTP_PASSWORD = 'test-only';
    process.env.SMTP_FROM = 'AHBU <noreply@example.invalid>';
    process.env.PUBLIC_BASE_URL = 'https://api.example.test';
    delete process.env.PUBLIC_APP_URL;

    calls.length = 0;
    sent.length = 0;
    poolHandler = async () => ({ rows: [], rowCount: 0 });
    pool.query = async (text, params) => {
      calls.push({ text: String(text), params: params ?? [] });
      return poolHandler(String(text), params ?? []);
    };
    nodemailer.createTransport = () => ({
      sendMail: async (message) => {
        sent.push(message);
      },
    });
    console.error = () => {};
    for (const limiter of [loginRateLimiter, forgotPasswordLimiter, resendCodeLimiter, resetPasswordLimiter, verifyCodeLimiter]) {
      limiter.reset();
    }
    loginFailureTracker.reset();
    passwordChangeFailureTracker.reset();
  });

  afterEach(() => {
    pool.query = originalQuery;
    nodemailer.createTransport = originalCreateTransport;
    console.error = originalConsoleError;
    for (const [name, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  });

  const post = (path, body, headers = {}) =>
    fetch(`${baseUrl}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...headers },
      body: JSON.stringify(body),
    });

  // ---------------------------------------------------------------- login
  describe('POST /auth/login', () => {
    const loginHandler = async (text, params) => {
      if (text.includes('LOWER(login_name)')) {
        const ident = String(params[0]).toLowerCase();
        return ident === baseUser.email
          ? { rows: [{ ...baseUser }], rowCount: 1 }
          : { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    };

    it('basarili giris: token pv claim i tasir, yanitta password_hash yok', async () => {
      poolHandler = loginHandler;
      const response = await post('/auth/login', { email: 'ALI@example.com', password: PASSWORD });
      assert.equal(response.status, 200);
      const body = await response.json();
      const claims = verifyAccessToken(body.token);
      assert.equal(claims.sub, '42');
      assert.equal(claims.pv, passwordVersionOf(PASSWORD_HASH));
      assert.equal(JSON.stringify(body).includes(PASSWORD_HASH), false);
      assert.equal('password_hash' in body.user, false);
    });

    it('yanlis parola ile var olmayan kullanici AYNI 401 yanitini verir (enumeration yok)', async () => {
      poolHandler = loginHandler;
      const wrong = await post('/auth/login', { email: baseUser.email, password: 'yanlis-parola' });
      const missing = await post('/auth/login', { email: 'yok@example.com', password: 'yanlis-parola' });
      assert.equal(wrong.status, 401);
      assert.equal(missing.status, 401);
      assert.deepEqual(await wrong.json(), await missing.json());
    });

    it('5 hatali denemeden sonra 429 LOGIN_LOCKED + Retry-After; dogru parola da kilit suresince reddedilir; baska hesap etkilenmez', async () => {
      poolHandler = loginHandler;
      let last;
      for (let i = 1; i <= 5; i += 1) {
        last = await post('/auth/login', { email: baseUser.email, password: `yanlis-${i}` });
        if (i < 5) assert.equal(last.status, 401, `${i}. deneme`);
      }
      assert.equal(last.status, 429, '5. hata kilitler');
      const lockedBody = await last.json();
      assert.equal(lockedBody.code, 'LOGIN_LOCKED');
      assert.ok(Number(last.headers.get('retry-after')) >= 800);

      const correctWhileLocked = await post('/auth/login', { email: baseUser.email, password: PASSWORD });
      assert.equal(correctWhileLocked.status, 429);

      const otherAccount = await post('/auth/login', { email: 'baska@example.com', password: 'x-parola' });
      assert.equal(otherAccount.status, 401);
    });

    it('basarili giris hata sayacini sifirlar', async () => {
      poolHandler = loginHandler;
      for (let i = 0; i < 4; i += 1) {
        await post('/auth/login', { email: baseUser.email, password: 'yanlis' });
      }
      assert.equal((await post('/auth/login', { email: baseUser.email, password: PASSWORD })).status, 200);
      for (let i = 0; i < 4; i += 1) {
        assert.equal((await post('/auth/login', { email: baseUser.email, password: 'yanlis' })).status, 401);
      }
    });

    it('DB hatasi: 500 genel mesaj, ayrinti sizmaz', async () => {
      poolHandler = async () => {
        throw pgError();
      };
      const response = await post('/auth/login', { email: baseUser.email, password: PASSWORD });
      const raw = await response.text();
      assert.equal(response.status, 500);
      assert.equal(raw.includes('secret-path'), false);
      assert.equal(raw.includes('users'), false);
    });

    it('zorunlu alanlar yoksa 400; hesap pasifse 403', async () => {
      assert.equal((await post('/auth/login', { email: '', password: '' })).status, 400);
      poolHandler = async (text) =>
        text.includes('LOWER(login_name)')
          ? { rows: [{ ...baseUser, is_active: false }], rowCount: 1 }
          : { rows: [], rowCount: 0 };
      assert.equal((await post('/auth/login', { email: baseUser.email, password: PASSWORD })).status, 403);
    });
  });

  // ------------------------------------------------- forgot / resend (enumeration)
  describe('forgot-password / resend-code', () => {
    it('forgot-password: var olan, olmayan ve pasif hesap AYNI yanit; yalnizca aktif hesaba e-posta gider', async () => {
      poolHandler = async (text, params) => {
        if (text.includes('SELECT user_code, full_name, email, is_active')) {
          const email = String(params[0]).toLowerCase();
          if (email === 'aktif@example.com') return { rows: [{ user_code: 1, full_name: 'Aktif', email, is_active: true }], rowCount: 1 };
          if (email === 'pasif@example.com') return { rows: [{ user_code: 2, full_name: 'Pasif', email, is_active: false }], rowCount: 1 };
          return { rows: [], rowCount: 0 };
        }
        return { rows: [], rowCount: 1 };
      };
      const results = [];
      for (const email of ['aktif@example.com', 'pasif@example.com', 'yok@example.com']) {
        const response = await post('/auth/forgot-password', { email });
        results.push({ status: response.status, body: await response.json() });
      }
      assert.deepEqual(results[1], results[0]);
      assert.deepEqual(results[2], results[0]);
      assert.equal(results[0].status, 200);

      await waitFor(() => sent.length >= 1);
      await new Promise((resolve) => setTimeout(resolve, 50));
      assert.equal(sent.length, 1);
      assert.equal(sent[0].to, 'aktif@example.com');
      assert.match(sent[0].html, /https:\/\/api\.example\.test\/auth\/reset-password\?token=[0-9a-f]{64}/);
    });

    it('forgot-password: e-posta gonderimi/DB hatasi yanitta gorunmez (ayni 200)', async () => {
      poolHandler = async () => {
        throw pgError();
      };
      const response = await post('/auth/forgot-password', { email: 'aktif@example.com' });
      assert.equal(response.status, 200);
      const raw = await response.text();
      assert.equal(raw.includes('secret-path'), false);

      poolHandler = async () => ({ rows: [{ user_code: 1, full_name: 'A', email: 'aktif2@example.com', is_active: true }], rowCount: 1 });
      let mailAttempts = 0;
      nodemailer.createTransport = () => ({
        sendMail: async () => {
          mailAttempts += 1;
          throw new Error('SMTP baglanti hatasi');
        },
      });
      const second = await post('/auth/forgot-password', { email: 'aktif2@example.com' });
      assert.equal(second.status, 200);
      await waitFor(() => mailAttempts >= 1); // arka plan gorevi bitmeden mock geri alinmasin
    });

    it('forgot-password: bos e-posta 400; 4. istek 429 (forgotPasswordLimiter)', async () => {
      assert.equal((await post('/auth/forgot-password', { email: '' })).status, 400);
      forgotPasswordLimiter.reset();
      poolHandler = async () => ({ rows: [], rowCount: 0 });
      const statuses = [];
      for (let i = 0; i < 4; i += 1) {
        statuses.push((await post('/auth/forgot-password', { email: 'a@example.com' })).status);
      }
      assert.deepEqual(statuses, [200, 200, 200, 429]);
    });

    it('resend-code: hesap yok / DB hatasi / dogrulanmis hesap -> AYNI 200 yanit', async () => {
      const bodies = [];

      poolHandler = async () => ({ rows: [], rowCount: 0 });
      let response = await post('/auth/resend-code', { email: 'yok@example.com' });
      bodies.push({ status: response.status, body: await response.json() });

      poolHandler = async () => {
        throw pgError();
      };
      response = await post('/auth/resend-code', { email: 'hata@example.com' });
      bodies.push({ status: response.status, body: await response.json() });

      poolHandler = async () => ({ rows: [{ user_code: 1, full_name: 'A', email_verified: true }], rowCount: 1 });
      response = await post('/auth/resend-code', { email: 'dogrulanmis@example.com' });
      bodies.push({ status: response.status, body: await response.json() });

      assert.equal(bodies[0].status, 200);
      assert.deepEqual(bodies[1], bodies[0]);
      assert.deepEqual(bodies[2], bodies[0]);
      assert.equal(bodies[0].body.already_verified, undefined);
      assert.equal((await post('/auth/resend-code', { email: '' })).status, 400);
    });

    it('verify-code / register-individual: DB hatasi 500 + genel mesaj (ayrinti yok)', async () => {
      poolHandler = async () => {
        throw pgError();
      };
      for (const [path, body] of [
        ['/auth/verify-code', { email: 'a@example.com', code: '123456' }],
        ['/auth/register-individual', { first_name: 'Ali', last_name: 'Veli', email: 'a@example.com', password: 'abcdef12' }],
      ]) {
        const response = await post(path, body);
        const raw = await response.text();
        assert.equal(response.status, 500, path);
        assert.equal(raw.includes('secret-path'), false, path);
        assert.equal(raw.includes('relation'), false, path);
      }
    });
  });

  // --------------------------------------------------------------- reset-password
  describe('reset-password', () => {
    const token = crypto.randomBytes(32).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    const future = () => new Date(Date.now() + 10 * 60 * 1000);

    it('GET: gecersiz bicimli token 404 HTML + sikI CSP + no-store', async () => {
      const response = await fetch(`${baseUrl}/auth/reset-password?token=${encodeURIComponent('<script>alert(1)</script>')}`);
      assert.equal(response.status, 404);
      assert.match(response.headers.get('content-security-policy') || '', /default-src 'none'/);
      assert.equal(response.headers.get('cache-control'), 'no-store');
      const html = await response.text();
      assert.equal(html.includes('<script>alert(1)</script>'), false);
      assert.equal(calls.length, 0, 'bicimi gecersiz token icin DB sorgusu yapilmamali');
    });

    it('GET: gecerli token -> 200 form; kullanici adi kacirilir; token yalnizca hex olarak gomulur', async () => {
      poolHandler = async () => ({
        rows: [{ user_code: 1, full_name: 'Ali <img src=x onerror=alert(1)>', email: 'a@example.com', password_reset_expires_at: future() }],
        rowCount: 1,
      });
      const response = await fetch(`${baseUrl}/auth/reset-password?token=${token}`);
      assert.equal(response.status, 200);
      const html = await response.text();
      assert.equal(html.includes('<img src=x'), false);
      assert.ok(html.includes('&lt;img src=x onerror=alert(1)&gt;'));
      assert.ok(html.includes(`token: '${token}'`));
    });

    it('GET: DB hatasi artik yakalanir -> 500 HTML sayfa (surec/istek asili kalmaz), ayrinti yok', async () => {
      poolHandler = async () => {
        throw pgError();
      };
      const response = await fetch(`${baseUrl}/auth/reset-password?token=${token}`);
      const html = await response.text();
      assert.equal(response.status, 500);
      assert.equal(html.includes('secret-path'), false);
    });

    it('GET: suresi dolmus token 410', async () => {
      poolHandler = async () => ({
        rows: [{ user_code: 1, full_name: 'Ali', email: 'a@example.com', password_reset_expires_at: new Date(Date.now() - 1000) }],
        rowCount: 1,
      });
      const response = await fetch(`${baseUrl}/auth/reset-password?token=${token}`);
      assert.equal(response.status, 410);
    });

    it('POST: atomik tek kullanim - UPDATE token hash ve sureyi kosul olarak icerir; 0 satir -> 400', async () => {
      poolHandler = async (text) => {
        if (text.includes('SELECT user_code, full_name, email, password_reset_expires_at')) {
          return { rows: [{ user_code: 1, full_name: 'Ali', email: 'a@example.com', password_reset_expires_at: future() }], rowCount: 1 };
        }
        if (text.includes('UPDATE users')) return { rows: [], rowCount: 0 };
        return { rows: [], rowCount: 0 };
      };
      const response = await post('/auth/reset-password', { token, password: NEW_PASSWORD });
      assert.equal(response.status, 400);
      const update = calls.find((call) => call.text.includes('UPDATE users'));
      assert.ok(update);
      assert.match(update.text, /password_reset_token_hash = \$3/);
      assert.match(update.text, /password_reset_expires_at > NOW\(\)/);
      assert.match(update.text, /RETURNING/);
      assert.equal(update.params[2], tokenHash);
    });

    it('POST: basarili sifirlama 200 (token tek kullanimlik: hash NULL a cekilir)', async () => {
      poolHandler = async (text) => {
        if (text.includes('SELECT user_code, full_name, email, password_reset_expires_at')) {
          return { rows: [{ user_code: 1, full_name: 'Ali', email: 'a@example.com', password_reset_expires_at: future() }], rowCount: 1 };
        }
        if (text.includes('UPDATE users')) return { rows: [{ user_code: 1 }], rowCount: 1 };
        return { rows: [], rowCount: 0 };
      };
      const response = await post('/auth/reset-password', { token, password: NEW_PASSWORD });
      assert.equal(response.status, 200);
      const update = calls.find((call) => call.text.includes('UPDATE users'));
      assert.match(update.text, /password_reset_token_hash = NULL/);
      assert.ok(bcrypt.compareSync(NEW_PASSWORD, update.params[0]));
    });

    it('POST: dogrulama hatalari (eksik token, kisa/uzun parola, bicimsiz token) ve DB hatasi sizdirmaz', async () => {
      assert.equal((await post('/auth/reset-password', { password: NEW_PASSWORD })).status, 400);
      assert.equal((await post('/auth/reset-password', { token, password: '123' })).status, 400);
      assert.equal((await post('/auth/reset-password', { token, password: 'x'.repeat(200) })).status, 400);
      assert.equal((await post('/auth/reset-password', { token: 'abc', password: NEW_PASSWORD })).status, 400);
      assert.equal(calls.length, 0);

      poolHandler = async () => {
        throw pgError();
      };
      const response = await post('/auth/reset-password', { token, password: NEW_PASSWORD });
      const raw = await response.text();
      assert.equal(response.status, 500);
      assert.equal(raw.includes('secret-path'), false);
      assert.equal(raw.includes('relation'), false);
    });
  });

  // --------------------------------------------------------------------- PATCH /me
  describe('PATCH /me (C8 current_password)', () => {
    const authHeader = () => ({
      Authorization: `Bearer ${signAccessToken({ id: 42, email: baseUser.email, role: 'individual' }, { passwordHash: PASSWORD_HASH })}`,
    });
    let currentHash;

    const meHandler = async (text, params) => {
      if (text.includes('db_id')) return { rows: [{ ...baseUser, password_hash: currentHash }], rowCount: 1 };
      if (text.startsWith('SELECT password_hash FROM users')) return { rows: [{ password_hash: currentHash }], rowCount: 1 };
      if (text.includes('UPDATE users')) {
        const pwIndex = text.includes('password_hash =') ? params.findIndex((p) => typeof p === 'string' && p.startsWith('$2')) : -1;
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

    it('current_password olmadan parola degisimi 400 CURRENT_PASSWORD_REQUIRED (UPDATE calismaz)', async () => {
      const response = await patch({ password: NEW_PASSWORD });
      assert.equal(response.status, 400);
      assert.equal((await response.json()).code, 'CURRENT_PASSWORD_REQUIRED');
      assert.equal(calls.some((call) => call.text.includes('UPDATE users')), false);
    });

    it('yanlis current_password 400 CURRENT_PASSWORD_INVALID (401/403 DEGIL: istemci oturumu kapatmasin)', async () => {
      const response = await patch({ password: NEW_PASSWORD, current_password: 'yanlis-parola' });
      assert.equal(response.status, 400);
      assert.equal((await response.json()).code, 'CURRENT_PASSWORD_INVALID');
      assert.equal(calls.some((call) => call.text.includes('UPDATE users')), false);
    });

    it('5 yanlis current_password denemesinden sonra 429', async () => {
      let last;
      for (let i = 0; i < 5; i += 1) {
        last = await patch({ password: NEW_PASSWORD, current_password: `yanlis-${i}` });
      }
      assert.equal(last.status, 429);
      assert.equal((await last.json()).code, 'CURRENT_PASSWORD_LOCKED');
      const afterLock = await patch({ password: NEW_PASSWORD, current_password: PASSWORD });
      assert.equal(afterLock.status, 429);
    });

    it('dogru current_password: 200 + yeni parolaya bagli YENI token (pv guncel), eski token artik uyusmaz', async () => {
      const response = await patch({ password: NEW_PASSWORD, current_password: PASSWORD });
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.ok(body.token);
      assert.equal(JSON.stringify(body).includes('password_hash'), false);
      assert.ok(bcrypt.compareSync(NEW_PASSWORD, currentHash));
      const claims = verifyAccessToken(body.token);
      assert.equal(claims.pv, passwordVersionOf(currentHash));
      assert.notEqual(claims.pv, passwordVersionOf(PASSWORD_HASH));

      // Eski (eski hash'e bagli) token artik 401 TOKEN_REVOKED
      const stale = await patch({ full_name: 'Yeni Ad Soyad' });
      assert.equal(stale.status, 401);
      assert.equal((await stale.json()).code, 'TOKEN_REVOKED');
    });

    it('parola disi guncellemeler current_password istemez ve token dondurmez', async () => {
      const response = await patch({ full_name: 'Yeni Ad Soyad' });
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.token, undefined);
    });

    it('bos parola alani "parola degismiyor" sayilir; cok uzun parola 400', async () => {
      const empty = await patch({ password: '', full_name: 'Yeni Ad Soyad' });
      assert.equal(empty.status, 200);
      const onlyEmpty = await patch({ password: '' });
      assert.equal(onlyEmpty.status, 400);
      const tooLong = await patch({ password: 'x'.repeat(200), current_password: PASSWORD });
      assert.equal(tooLong.status, 400);
    });

    it('e-posta degistirme hala reddedilir', async () => {
      const response = await patch({ email: 'baska@example.com' });
      assert.equal(response.status, 400);
    });
  });
});
