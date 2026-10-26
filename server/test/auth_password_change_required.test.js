// Zorunlu parola degisimi (must_change_password) SUNUCUDA uygulanir: bayrak TRUE iken GET /me, PATCH /me, yasal onay, daire sakini kendi parola
// ucu ve cikis (push cihaz silme) disindaki TUM kimlik dogrulamali uclar 403 PASSWORD_CHANGE_REQUIRED doner. Parola degistiren her yol bayragi kapatir;
// PATCH /me yeni parolanin eskisiyle ayni olmasini reddeder; giris sorgusu deterministik (e-posta eslesmesi oncelikli) ve tekil satir doner. DB'siz (sahte havuz).
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcryptjs';
import express from 'express';
import '../src/utils/async_errors.js';
import { pool } from '../src/db.js';
import { signAccessToken } from '../src/jwt.js';
import { passwordChangeFailureTracker } from '../src/middlewares/login_throttle.js';
import { authRequired, isPasswordChangeExempt } from '../src/middlewares/auth_middleware.js';
import { loginRateLimiter, profileUpdateLimiter, resetPasswordLimiter } from '../src/middlewares/rate_limiters.js';
import { authRouter } from '../src/routes/auth_routes.js';

const SECRET = 'k9Fz-test-only-long-secret-value-0123456789abcdef';
const PASSWORD = 'Gecici-Parola-9xQ';
const PASSWORD_HASH = bcrypt.hashSync(PASSWORD, 4);
const NEW_PASSWORD = 'Yeni-Parola-2xQ';
const baseUser = {
  id: 42,
  db_id: 7,
  user_code: 42,
  full_name: 'Test Kullanici',
  email: 'ali@example.com',
  login_name: 'ali.k',
  role: 'apartment_owner',
  is_active: true,
  email_verified: true,
  approval_status: 'approved',
  phone_number: null,
  created_at: new Date('2026-01-01T00:00:00Z'),
  deleted_at: null,
  password_hash: PASSWORD_HASH,
  must_change_password: true,
};

let user;
let log;
let server;
let baseUrl;
let originalQuery;
let savedSecret;

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();

function install() {
  log = [];
  pool.query = async (text, params = []) => {
    const sql = norm(text);
    log.push({ sql, params });
    if (sql.includes('db_id')) return { rows: [{ ...user }], rowCount: 1 };
    if (sql.startsWith('SELECT password_hash FROM users')) return { rows: [{ password_hash: PASSWORD_HASH }], rowCount: 1 };
    if (/^UPDATE users SET password_hash/.test(sql) || /^UPDATE users\b.*RETURNING user_code AS id/.test(sql)) {
      return { rows: [{ id: 42, user_code: 42, email: user.email, role: user.role, full_name: user.full_name, is_active: true }], rowCount: 1 };
    }
    if (/^UPDATE users SET must_change_password = FALSE/.test(sql)) return { rows: [], rowCount: 1 };
    if (/^UPDATE apartments SET resident_pin_issued = FALSE/.test(sql)) return { rows: [], rowCount: 1 };
    if (sql.includes('LOWER(login_name)')) return { rows: [{ ...user, id: 42, password_hash: PASSWORD_HASH }], rowCount: 1 };
    if (/^SELECT user_code, full_name, email, password_reset_expires_at FROM users WHERE password_reset_token_hash/.test(sql)) {
      return { rows: [{ user_code: 42, full_name: 'Test Kullanici', email: user.email, password_reset_expires_at: new Date(Date.now() + 600000) }], rowCount: 1 };
    }
    if (/^UPDATE users SET password_hash = \$1, password_reset_token_hash = NULL/.test(sql)) {
      return { rows: [{ user_code: 42, login_name: 'ali.k' }], rowCount: 1 };
    }
    return { rows: [], rowCount: 0 };
  };
}

before(async () => {
  savedSecret = process.env.JWT_SECRET;
  process.env.JWT_SECRET = SECRET;
  originalQuery = pool.query;
  const app = express();
  app.use(express.json());
  app.use(authRouter);
  // Kimlik dogrulamali herhangi bir uc (gercek rotalarin yerine): zorunlu degisim kapisini dener.
  app.get('/app/anything', authRequired, (req, res) => res.json({ ok: true }));
  app.post('/app/anything', authRequired, (req, res) => res.json({ ok: true }));
  app.get('/me/consents', authRequired, (req, res) => res.json({ ok: true }));
  app.post('/me/consents', authRequired, (req, res) => res.json({ ok: true }));
  app.delete('/app/push/devices/:installId', authRequired, (req, res) => res.json({ ok: true }));
  app.post('/membership/apartments/:a/members/:u/change-password', authRequired, (req, res) => res.json({ ok: true }));
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  pool.query = originalQuery;
  if (savedSecret === undefined) delete process.env.JWT_SECRET;
  else process.env.JWT_SECRET = savedSecret;
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
});

beforeEach(() => {
  user = { ...baseUser };
  install();
  passwordChangeFailureTracker.reset();
  profileUpdateLimiter.reset();
  loginRateLimiter.reset?.();
  resetPasswordLimiter.reset?.();
});

afterEach(() => {
  pool.query = originalQuery;
});

const auth = () => ({ Authorization: `Bearer ${signAccessToken({ id: 42 }, { passwordHash: PASSWORD_HASH })}` });
const call = (method, path, body) =>
  fetch(`${baseUrl}${path}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...auth() },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

describe('isPasswordChangeExempt: zorunlu degisim sirasinda yapilabilecek uclar', () => {
  const req = (method, url) => ({ method, originalUrl: url });

  it('izinli: GET|PATCH /me, GET|POST /me/consents, daire sakini kendi parola ucu, push cihaz silme (sorgu dizesi ve sondaki / yok sayilir)', () => {
    for (const [method, url] of [
      ['GET', '/me'],
      ['PATCH', '/me'],
      ['PATCH', '/me?x=1'],
      ['GET', '/me/'],
      ['GET', '/me/consents'],
      ['POST', '/me/consents'],
      ['POST', '/membership/apartments/5/members/42/change-password'],
      ['DELETE', '/app/push/devices/abcdef0123456789abcdef'],
    ]) {
      assert.equal(isPasswordChangeExempt(req(method, url)), true, `${method} ${url}`);
    }
  });

  it('diger HER SEY yasak: yanlis yontem, benzer ama farkli yol, baska uclar', () => {
    for (const [method, url] of [
      ['POST', '/me'],
      ['DELETE', '/me'],
      ['GET', '/me/account-deletion/preview'],
      ['POST', '/me/data-export'],
      ['GET', '/me/consents/extra'],
      ['PUT', '/me/consents'],
      ['GET', '/membership/apartments/5/members/42/change-password'],
      ['POST', '/membership/apartments/x/members/42/change-password'],
      ['POST', '/membership/apartments/5/members/42/remove'],
      ['GET', '/app/push/devices'],
      ['PUT', '/app/push/devices'],
      ['POST', '/app/push/test'],
      ['GET', '/manager/sites/1/people'],
      ['POST', '/doors/1/open'],
      ['GET', '/'],
      ['GET', '/me/../manager/sites'],
    ]) {
      assert.equal(isPasswordChangeExempt(req(method, url)), false, `${method} ${url}`);
    }
    assert.equal(isPasswordChangeExempt({}), false);
  });
});

describe('authRequired: must_change_password iken 403 PASSWORD_CHANGE_REQUIRED', () => {
  it('izinli olmayan uclar 403 + code; handler CALISMAZ', async () => {
    for (const [method, path] of [['GET', '/app/anything'], ['POST', '/app/anything']]) {
      const res = await call(method, path, method === 'POST' ? {} : undefined);
      assert.equal(res.status, 403, `${method} ${path}`);
      const body = await res.json();
      assert.equal(body.code, 'PASSWORD_CHANGE_REQUIRED');
      assert.match(body.error, /şifre|sifre/i);
      assert.equal(body.ok, undefined);
    }
  });

  it('izinli uclar gecer: GET /me (bayrak yanitta), yasal onay, daire sakini kendi parola ucu, push cihaz silme', async () => {
    const me = await call('GET', '/me');
    assert.equal(me.status, 200);
    assert.equal((await me.json()).user.must_change_password, true);
    assert.equal((await call('GET', '/me/consents')).status, 200);
    assert.equal((await call('POST', '/me/consents', {})).status, 200);
    assert.equal((await call('POST', '/membership/apartments/5/members/42/change-password', {})).status, 200);
    assert.equal((await call('DELETE', '/app/push/devices/abcdef0123456789abcdef')).status, 200);
  });

  it('bayrak yoksa (FALSE / eksik) hicbir uc engellenmez', async () => {
    user = { ...baseUser, must_change_password: false };
    assert.equal((await call('GET', '/app/anything')).status, 200);
    user = { ...baseUser };
    delete user.must_change_password;
    assert.equal((await call('GET', '/app/anything')).status, 200);
  });

  it('diger kapilar ONCE: pasif hesap yine 403 (kodsuz), silinmis hesap 401', async () => {
    user = { ...baseUser, is_active: false };
    const inactive = await call('GET', '/app/anything');
    assert.equal(inactive.status, 403);
    assert.equal((await inactive.json()).code, undefined);
    user = { ...baseUser, deleted_at: new Date() };
    assert.equal((await call('GET', '/app/anything')).status, 401);
  });

  it('bayrak DB\'den HER istekte taze okunur (ayri sorgu / onbellek yok: kullanici sorgusunun parcasi)', async () => {
    await call('GET', '/app/anything');
    const userQueries = log.filter((q) => q.sql.includes('db_id'));
    assert.equal(userQueries.length, 1);
    assert.match(userQueries[0].sql, /COALESCE\(users\.must_change_password, FALSE\) OR EXISTS/);
  });
});

describe('PATCH /me: zorunlu degisimi tamamlama', () => {
  it('yeni parola mevcut parolayla AYNI olamaz: 400 PASSWORD_UNCHANGED; parola yazilmaz, bayrak kapanmaz', async () => {
    const res = await call('PATCH', '/me', { password: PASSWORD, current_password: PASSWORD });
    assert.equal(res.status, 400);
    assert.equal((await res.json()).code, 'PASSWORD_UNCHANGED');
    assert.equal(log.some((q) => /^UPDATE users/.test(q.sql)), false);
  });

  it('gecerli yeni parola: 200 + yeni token; users.must_change_password FALSE (deleted_at korumali) ve dairedeki PIN isareti temizlenir', async () => {
    const res = await call('PATCH', '/me', { password: NEW_PASSWORD, current_password: PASSWORD });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.ok(body.token);
    const flag = log.find((q) => /^UPDATE users SET must_change_password = FALSE/.test(q.sql));
    assert.ok(flag, 'bayrak kapatildi');
    assert.match(flag.sql, /WHERE user_code = \$1 AND deleted_at IS NULL$/);
    assert.deepEqual(flag.params, [42]);
    assert.ok(log.some((q) => /^UPDATE apartments SET resident_pin_issued = FALSE, resident_pin_code = NULL WHERE resident_user_code = \$1/.test(q.sql)));
  });

  it('ad degisikligi (parolasiz) bayragi KAPATMAZ', async () => {
    const res = await call('PATCH', '/me', { full_name: 'Yeni Ad Soyad' });
    assert.equal(res.status, 200);
    assert.equal(log.some((q) => /^UPDATE users SET must_change_password/.test(q.sql)), false);
  });
});

describe('POST /auth/reset-password: sifirlama bayragi kapatir', () => {
  it('ayni UPDATE\'te must_change_password = FALSE ve email_verified = TRUE (posta kutusu kanitlandi); dairedeki PIN isareti kalkar', async () => {
    const res = await fetch(`${baseUrl}/auth/reset-password`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: 'a'.repeat(64), password: NEW_PASSWORD }),
    });
    assert.equal(res.status, 200);
    const update = log.find((q) => /^UPDATE users SET password_hash = \$1, password_reset_token_hash = NULL/.test(q.sql));
    assert.ok(update);
    assert.match(update.sql, /must_change_password = FALSE/);
    assert.match(update.sql, /email_verified = TRUE/);
    assert.match(update.sql, /deleted_at IS NULL/);
    const pin = log.find((q) => /^UPDATE apartments SET resident_pin_issued = FALSE/.test(q.sql));
    assert.ok(pin, 'PIN verildi isareti temizlenir (aksi halde sifirlamadan sonra yine zorunlu degisim cikardi)');
    assert.deepEqual(pin.params, [42]);
  });
});

describe('POST /auth/login: giris sorgusu deterministik ve tekil', () => {
  it('e-posta eslesmesi ONCELIKLI siralanir, user_code ile kirilir ve tek satirla sinirlanir', async () => {
    const res = await fetch(`${baseUrl}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: 'ali@example.com', password: PASSWORD }),
    });
    assert.ok([200, 401, 403, 429].includes(res.status));
    const query = log.find((q) => q.sql.includes('LOWER(login_name)'));
    assert.ok(query, 'giris sorgusu calisti');
    assert.match(query.sql, /WHERE LOWER\(email\) = LOWER\(\$1\) OR LOWER\(login_name\) = LOWER\(\$1\) ORDER BY \(LOWER\(email\) = LOWER\(\$1\)\) DESC, user_code ASC LIMIT 1$/);
    assert.deepEqual(query.params, ['ali@example.com']);
  });
});
