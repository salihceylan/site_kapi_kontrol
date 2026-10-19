// S-C: §1.7 parola ilkesi tüm kayıt / sıfırlama / değiştirme uçlarında 400 WEAK_PASSWORD; girişte UYGULANMAZ.
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import bcrypt from 'bcryptjs';
import express from 'express';
import '../src/utils/async_errors.js';
import { pool } from '../src/db.js';
import { authRouter } from '../src/routes/auth_routes.js';
import { membershipRouter } from '../src/routes/membership_routes.js';
import { adminRouter } from '../src/routes/admin_routes.js';
import { createErrorHandler } from '../src/middlewares/error_handler.js';
import { loginFailureTracker, passwordChangeFailureTracker } from '../src/middlewares/login_throttle.js';
import * as rateLimiters from '../src/middlewares/rate_limiters.js';
import { signAccessToken, passwordVersionOf } from '../src/jwt.js';
import { deviceTokenMatchesPassword, issueDeviceToken, verifyDeviceToken } from '../src/security/login_device_token.js';
import { BCRYPT_COST, bcryptCostOf } from '../src/security/password_hashing.js';

const { loginRateLimiter, registerLimiter, resetPasswordLimiter } = rateLimiters;
// PATCH /me sinirlayicisi (S-A ekledi); yoksa yok sayilir.
const profileUpdateLimiter = rateLimiters.profileUpdateLimiter ?? { reset() {} };

const SECRET = 'k9Fz-test-only-long-secret-value-0123456789abcdef';
const LEGACY_WEAK = '123456'; // eski kurallarla açılmış (6 karakter) mevcut parola
const LEGACY_HASH = bcrypt.hashSync(LEGACY_WEAK, 4);
const STRONG = 'Mavi-Kapi-77-Ruzgar';

const baseUser = {
  db_id: 7,
  id: 42,
  user_code: 42,
  full_name: 'Ayşe Yılmaz',
  email: 'ayse@example.com',
  login_name: null,
  role: 'individual',
  is_active: true,
  email_verified: true,
  approval_status: 'approved',
  phone_number: null,
  created_at: new Date('2026-01-01T00:00:00Z'),
};

describe('§1.7 WEAK_PASSWORD uçları (HTTP)', () => {
  let server;
  let baseUrl;
  let calls;
  let poolHandler;
  const saved = {};
  const originalConsoleError = console.error;

  before(async () => {
    const app = express();
    app.set('env', 'test');
    app.use(express.json({ limit: '1mb' }));
    // change-password ucu: authRequired yerine sabit oturum (route testi; JWT yolu ayrı testlerde).
    for (const layer of membershipRouter.stack) {
      if (layer.route?.path?.endsWith('/change-password')) {
        layer.route.stack[0].handle = (req, _res, next) => {
          req.authUser = { ...baseUser, userCode: 42 };
          next();
        };
      }
    }
    app.use(authRouter);
    app.use(membershipRouter);
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
    for (const limiter of [loginRateLimiter, registerLimiter, resetPasswordLimiter, profileUpdateLimiter]) limiter.reset();
    loginFailureTracker.reset();
    passwordChangeFailureTracker.reset();
  });

  afterEach(() => {
    delete pool.query;
    console.error = originalConsoleError;
    if (saved.JWT_SECRET === undefined) delete process.env.JWT_SECRET;
    else process.env.JWT_SECRET = saved.JWT_SECRET;
  });

  const send = (method, path, body, headers = {}) =>
    fetch(`${baseUrl}${path}`, {
      method,
      headers: { 'Content-Type': 'application/json', ...headers },
      body: JSON.stringify(body),
    });

  async function expectWeak(response, reason) {
    assert.equal(response.status, 400);
    const body = await response.json();
    assert.equal(body.code, 'WEAK_PASSWORD');
    if (reason) assert.equal(body.reason, reason);
    assert.equal(typeof body.error, 'string');
    return body;
  }

  it('POST /auth/register-individual: kısa / yaygın / e-postayla aynı -> 400 WEAK_PASSWORD; DB’ye hiç gidilmez', async () => {
    const base = { first_name: 'Ayşe', last_name: 'Yılmaz', email: 'ayse.yilmaz@example.com' };
    await expectWeak(await send('POST', '/auth/register-individual', { ...base, password: 'Ab1!xyz' }), 'too_short');
    await expectWeak(await send('POST', '/auth/register-individual', { ...base, password: 'Sifre1234' }), 'common');
    await expectWeak(await send('POST', '/auth/register-individual', { ...base, password: 'ayse.yilmaz' }), 'same_as_email');
    await expectWeak(await send('POST', '/auth/register-individual', { ...base, email: 'iletisim@example.com', password: 'Ayşe Yılmaz' }), 'same_as_name');
    await expectWeak(await send('POST', '/auth/register-individual', { ...base }), 'required');
    assert.equal(calls.length, 0);
  });

  it('POST /auth/reset-password: yaygın parola DB’den önce; e-postayla aynı parola hesap bulunduktan sonra, UPDATE yok', async () => {
    const token = crypto.randomBytes(32).toString('hex');
    await expectWeak(await send('POST', '/auth/reset-password', { token, password: 'password123' }), 'common');
    assert.equal(calls.length, 0);

    poolHandler = async (text) => {
      if (text.includes('SELECT user_code, full_name, email, password_reset_expires_at')) {
        return {
          rows: [{ user_code: 42, full_name: 'Ayşe Yılmaz', email: 'ayse.yilmaz2024@example.com', password_reset_expires_at: new Date(Date.now() + 600000) }],
          rowCount: 1,
        };
      }
      return { rows: [], rowCount: 0 };
    };
    await expectWeak(await send('POST', '/auth/reset-password', { token, password: 'Ayse.Yilmaz2024' }), 'same_as_email');
    assert.equal(calls.some((call) => call.text.includes('UPDATE users')), false);
  });

  describe('PATCH /me', () => {
    let currentHash;
    const auth = () => ({ Authorization: `Bearer ${signAccessToken({ id: 42 }, { passwordHash: currentHash })}` });

    beforeEach(() => {
      currentHash = LEGACY_HASH;
      poolHandler = async (text) => {
        if (text.includes('db_id')) return { rows: [{ ...baseUser, password_hash: currentHash }], rowCount: 1 };
        if (text.startsWith('SELECT password_hash FROM users')) return { rows: [{ password_hash: currentHash }], rowCount: 1 };
        if (text.includes('UPDATE users')) return { rows: [{ ...baseUser }], rowCount: 1 };
        return { rows: [], rowCount: 0 };
      };
    });

    it('zayıf yeni parola -> 400 WEAK_PASSWORD; mevcut parola sayacına YAZILMAZ; UPDATE yok', async () => {
      await expectWeak(await send('PATCH', '/me', { password: 'qwerty123', current_password: 'yanlis' }, auth()), 'common');
      await expectWeak(await send('PATCH', '/me', { password: 'ayse@example.com', current_password: LEGACY_WEAK }, auth()), 'same_as_email');
      await expectWeak(await send('PATCH', '/me', { password: 'Yeni Ad Soyad', full_name: 'Yeni Ad Soyad', current_password: LEGACY_WEAK }, auth()), 'same_as_name');
      await expectWeak(await send('PATCH', '/me', { password: 'kisa', current_password: LEGACY_WEAK }, auth()), 'too_short');
      assert.equal(passwordChangeFailureTracker.size(), 0);
      assert.equal(calls.some((call) => call.text.includes('UPDATE users')), false);
    });

    it('eski 6 karakterlik parolası olan kullanıcı güçlü yeni parolaya geçebilir (200 + yeni token)', async () => {
      const response = await send('PATCH', '/me', { password: STRONG, current_password: LEGACY_WEAK }, auth());
      assert.equal(response.status, 200);
      assert.ok((await response.json()).token);
    });

    it('R7#2: parola değişimi yanıtında YENİ parolaya bağlı device_token; gönderilen belirtecin cihaz kimliği korunur', async () => {
      poolHandler = async (text, params) => {
        if (text.includes('db_id')) return { rows: [{ ...baseUser, password_hash: currentHash }], rowCount: 1 };
        if (text.startsWith('SELECT password_hash')) return { rows: [{ password_hash: currentHash, deleted_at: null }], rowCount: 1 };
        if (text.includes('UPDATE users')) {
          const newHash = params.find((value) => typeof value === 'string' && value.startsWith('$2'));
          if (newHash) currentHash = newHash;
          return { rows: [{ ...baseUser }], rowCount: 1 };
        }
        return { rows: [], rowCount: 0 };
      };
      const presented = issueDeviceToken({ userCode: 42, passwordHash: LEGACY_HASH, deviceId: 'cihaz-AAAAAAAAAAAAAAAAAAAA' });
      const response = await send('PATCH', '/me', { password: STRONG, current_password: LEGACY_WEAK }, { ...auth(), 'X-Device-Token': presented });
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.ok(body.user && body.token, 'yanıt şekli geriye uyumlu (user + token)');
      const device = verifyDeviceToken(body.device_token);
      assert.equal(device.userCode, 42);
      assert.equal(device.deviceId, 'cihaz-AAAAAAAAAAAAAAAAAAAA', 'cihaz kimliği korundu');
      assert.notEqual(currentHash, LEGACY_HASH);
      assert.equal(deviceTokenMatchesPassword(device, currentHash), true, 'yeni parola sürümüne bağlı');
      assert.equal(deviceTokenMatchesPassword(device, LEGACY_HASH), false);
      assert.equal(bcryptCostOf(currentHash), BCRYPT_COST, 'R7#4: updateUserByCode maliyeti BCRYPT_COST');

      // Belirteç gönderilmezse (ya da başka hesabınsa) girişteki gibi yeni cihaz kimliği.
      const second = await (await send('PATCH', '/me', { password: 'Mor-Kapi-55-Ruzgar', current_password: STRONG }, auth())).json();
      const fresh = verifyDeviceToken(second.device_token);
      assert.notEqual(fresh.deviceId, 'cihaz-AAAAAAAAAAAAAAAAAAAA');
      assert.equal(deviceTokenMatchesPassword(fresh, currentHash), true);
    });

    it('parola değişmeyen güncellemede device_token dönmez', async () => {
      const body = await (await send('PATCH', '/me', { full_name: 'Yeni Ad Soyad' }, auth())).json();
      assert.equal(body.device_token, undefined);
      assert.equal(body.token, undefined);
    });
  });

  it('POST /auth/login: ilke girişte UYGULANMAZ (eski 6 karakterlik parola çalışmaya devam eder)', async () => {
    poolHandler = async (text) =>
      text.includes('LOWER(login_name)') ? { rows: [{ ...baseUser, password_hash: LEGACY_HASH }], rowCount: 1 } : { rows: [], rowCount: 0 };
    const response = await send('POST', '/auth/login', { email: 'ayse@example.com', password: LEGACY_WEAK });
    assert.equal(response.status, 200);
  });

  it('POST /membership/.../change-password: zayıf parola 400 WEAK_PASSWORD (eski 4 karakter alt sınırı atlatılamaz)', async () => {
    const url = '/membership/apartments/5/members/42/change-password';
    await expectWeak(await send('POST', url, { new_password: '1234', current_password: LEGACY_WEAK }), 'too_short');
    await expectWeak(await send('POST', url, { new_password: '11111111', current_password: LEGACY_WEAK }), 'common');
    assert.equal(calls.length, 0, 'servis / DB çağrılmaz');
    assert.equal(passwordChangeFailureTracker.size(), 0);
  });
});

describe('changeApartmentMemberPassword: sakinin kendi seçtiği parola düz metin SAKLANMAZ', () => {
  afterEach(() => {
    delete pool.query;
    passwordChangeFailureTracker.reset();
  });

  it('legacy daire hesabında apartments.resident_pin_code yeni parolayla değil NULL ile güncellenir', async () => {
    const { changeApartmentMemberPassword } = await import('../src/services/membership_service.js');
    const log = [];
    pool.query = async (text, params = []) => {
      const sql = String(text).replace(/\s+/g, ' ').trim();
      log.push({ sql, params });
      if (sql.startsWith('SELECT id, site_code, resident_user_code FROM apartments')) {
        return { rowCount: 1, rows: [{ id: 5, site_code: 101, resident_user_code: 42 }] };
      }
      if (sql.startsWith('SELECT 1 FROM apartment_memberships')) return { rowCount: 1, rows: [{}] };
      if (sql.startsWith('SELECT password_hash FROM users')) return { rowCount: 1, rows: [{ password_hash: LEGACY_HASH }] };
      if (sql.startsWith('UPDATE users SET password_hash')) return { rowCount: 1, rows: [{ id: 42, email: 'x@ahbu.local', role: 'apartment_owner' }] };
      return { rowCount: 1, rows: [] };
    };
    const saved = process.env.JWT_SECRET;
    process.env.JWT_SECRET = SECRET;
    try {
      const result = await changeApartmentMemberPassword({
        apartmentId: 5,
        targetUserCode: 42,
        newPassword: STRONG,
        currentPassword: LEGACY_WEAK,
        authUser: { id: 42, user_code: 42, userCode: 42 },
      });
      assert.equal(result.ok, true);
    } finally {
      if (saved === undefined) delete process.env.JWT_SECRET;
      else process.env.JWT_SECRET = saved;
    }
    // Migration 051: PIN zaten saklanmaz; sakin kendi parolasını belirleyince "PIN verildi" işareti kalkar (olası eski düz kopya da NULL).
    const pinUpdate = log.find((entry) => entry.sql.startsWith('UPDATE apartments SET resident_pin_issued'));
    assert.ok(pinUpdate, 'legacy PIN işareti temizlenmeli');
    assert.match(pinUpdate.sql, /resident_pin_issued = FALSE, resident_pin_code = NULL/);
    assert.equal(log.some((entry) => entry.params.includes(STRONG)), false, 'parola hiçbir sorguya düz metin gitmez');
  });

  it('R7#2: yanıtta YENİ parolaya bağlı device_token (gönderilen belirtecin cihaz kimliği korunur); maliyet BCRYPT_COST', async () => {
    const { changeApartmentMemberPassword } = await import('../src/services/membership_service.js');
    const log = [];
    pool.query = async (text, params = []) => {
      const sql = String(text).replace(/\s+/g, ' ').trim();
      log.push({ sql, params });
      if (sql.startsWith('SELECT id, site_code, resident_user_code FROM apartments')) {
        return { rowCount: 1, rows: [{ id: 5, site_code: 101, resident_user_code: null }] };
      }
      if (sql.startsWith('SELECT 1 FROM apartment_memberships')) return { rowCount: 1, rows: [{}] };
      if (sql.startsWith('SELECT password_hash')) return { rowCount: 1, rows: [{ password_hash: LEGACY_HASH, deleted_at: null }] };
      if (sql.startsWith('UPDATE users SET password_hash')) return { rowCount: 1, rows: [{ id: 42, email: 'a@example.com', role: 'individual' }] };
      return { rowCount: 1, rows: [] };
    };
    const saved = process.env.JWT_SECRET;
    process.env.JWT_SECRET = SECRET;
    try {
      const presented = issueDeviceToken({ userCode: 42, passwordHash: LEGACY_HASH, deviceId: 'cihaz-BBBBBBBBBBBBBBBBBBBB' });
      const result = await changeApartmentMemberPassword({
        apartmentId: 5,
        targetUserCode: 42,
        newPassword: STRONG,
        currentPassword: LEGACY_WEAK,
        authUser: { id: 42, user_code: 42, userCode: 42 },
        deviceToken: presented,
      });
      const newHash = log.find((entry) => entry.sql.startsWith('UPDATE users SET password_hash')).params[0];
      const device = verifyDeviceToken(result.device_token);
      assert.equal(device.deviceId, 'cihaz-BBBBBBBBBBBBBBBBBBBB');
      assert.equal(device.pv, passwordVersionOf(newHash));
      assert.ok(result.token, 'mevcut yanıt alanları korunur');

      // Başka hesabın belirteci cihaz kimliği aktarmaz.
      const foreign = issueDeviceToken({ userCode: 43, passwordHash: LEGACY_HASH, deviceId: 'cihaz-CCCCCCCCCCCCCCCCCCCC' });
      passwordChangeFailureTracker.reset();
      const other = await changeApartmentMemberPassword({
        apartmentId: 5,
        targetUserCode: 42,
        newPassword: STRONG,
        currentPassword: LEGACY_WEAK,
        authUser: { id: 42, user_code: 42, userCode: 42 },
        deviceToken: foreign,
      });
      assert.notEqual(verifyDeviceToken(other.device_token).deviceId, 'cihaz-CCCCCCCCCCCCCCCCCCCC');
      assert.equal(bcryptCostOf(newHash), BCRYPT_COST);
    } finally {
      if (saved === undefined) delete process.env.JWT_SECRET;
      else process.env.JWT_SECRET = saved;
    }
  });
});

describe('R7#4: bcrypt maliyeti tek sabit (BCRYPT_COST)', () => {
  it('kaynakta parola / sahte özet üreten tüm bcrypt.hash(Sync) çağrıları BCRYPT_COST ile aynı maliyette', async () => {
    const fs = await import('node:fs');
    const path = await import('node:path');
    const { fileURLToPath } = await import('node:url');
    const srcRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'src');
    const offenders = [];
    const walk = (dir) => {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) walk(full);
        else if (entry.name.endsWith('.js')) {
          const source = fs.readFileSync(full, 'utf8');
          for (const match of source.matchAll(/bcrypt\.hash(?:Sync)?\([^;]*?,\s*([A-Za-z_0-9]+)\s*\)/g)) {
            const cost = match[1];
            if (cost !== 'BCRYPT_COST' && Number(cost) !== BCRYPT_COST) {
              offenders.push(`${path.relative(srcRoot, full)}: ${match[0]}`);
            }
          }
        }
      }
    };
    walk(srcRoot);
    assert.deepEqual(offenders, []);
    assert.equal(BCRYPT_COST, 10);
  });
});

describe('§1.7 WEAK_PASSWORD: süper kullanıcı uçları (rota işleyicisi)', () => {
  function findRoute(method, routePath) {
    const layer = adminRouter.stack.find((item) => item.route?.path === routePath && item.route.methods[method]);
    assert.ok(layer, `${method} ${routePath}`);
    return layer.route;
  }

  async function call(method, routePath, { params = {}, body = {} } = {}) {
    const route = findRoute(method, routePath);
    const handler = route.stack[route.stack.length - 1].handle;
    const req = { params, body, query: {}, headers: {}, authUser: { id: 1, user_code: 1, role: 'super_user', email: 'admin@example.test' } };
    const res = {
      statusCode: 200,
      body: undefined,
      status(code) {
        this.statusCode = code;
        return this;
      },
      setHeader() {},
      json(payload) {
        this.body = payload;
        return this;
      },
    };
    await handler(req, res);
    return res;
  }

  let queries;
  beforeEach(() => {
    queries = [];
    pool.query = async (text) => {
      queries.push(String(text));
      return { rows: [], rowCount: 0 };
    };
  });
  afterEach(() => {
    delete pool.query;
  });

  it('POST /admin/users: zayıf ilk parola 400 WEAK_PASSWORD (DB yok)', async () => {
    const res = await call('post', '/admin/users', {
      body: { full_name: 'Yeni Yonetici', email: 'yeni@example.com', password: 'yonetici123', role: 'site_manager', is_active: true },
    });
    assert.equal(res.statusCode, 400);
    assert.equal(res.body.code, 'WEAK_PASSWORD');
    assert.equal(queries.length, 0);
  });

  it('PATCH /admin/users/:id: başka kullanıcıya zayıf parola 400 WEAK_PASSWORD (DB yok)', async () => {
    const res = await call('patch', '/admin/users/:id', { params: { id: '2' }, body: { password: '12345678' } });
    assert.equal(res.statusCode, 400);
    assert.equal(res.body.code, 'WEAK_PASSWORD');
    assert.equal(queries.length, 0);
  });

  it('POST /admin/sites: site ile açılan yönetici hesabının zayıf parolası 400 WEAK_PASSWORD (DB yok)', async () => {
    const res = await call('post', '/admin/sites', {
      body: {
        name: 'Deneme Sitesi',
        block_count: 1,
        apartment_count: 1,
        door_count: 1,
        manager_user: { full_name: 'Site Yoneticisi', email: 'sy@example.com', password: 'password1', phone_number: '05551234567' },
      },
    });
    assert.equal(res.statusCode, 400);
    assert.equal(res.body.code, 'WEAK_PASSWORD');
    assert.equal(queries.length, 0);
  });
});
