// POST /admin/users ve PATCH /admin/users/:id: süper kullanıcının BAŞKASI için belirlediği parola GEÇİCİDİR (users.must_change_password = TRUE, kullanıcı yazımıyla
// AYNI işlemde). Kullanıcı kendi parolasını PATCH /me ile değiştirince bayrak FALSE olur (auth_routes; test/account_password_paths.test.js).
// Ayrıca: ACCESS_SUSPENDED gibi makine okunur hata kodu / PlatformError ek alanları admin sendServiceError yanıtına taşınır. DB'siz.
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import '../src/utils/async_errors.js';
import { pool } from '../src/db.js';
import { adminRouter, sendServiceError } from '../src/routes/admin_routes.js';
import { createErrorHandler } from '../src/middlewares/error_handler.js';
import { PlatformError } from '../src/modules/errors.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const SUPER = { id: 1, user_code: 1, role: 'super_user', full_name: 'Süper', is_active: true };
const STRONG = 'Zarif-Parola-2026!x';

describe('admin kullanıcı uçları: yönetimin belirlediği parola geçicidir', () => {
  let server;
  let baseUrl;
  let poolCalls;
  let clientCalls;
  let clientHandler;
  let poolHandler;
  let released;
  const originalConnect = pool.connect;
  const originalQuery = pool.query;
  const originalConsole = { error: console.error, warn: console.warn };

  before(async () => {
    for (const layer of adminRouter.stack) {
      if (!layer.route) continue;
      layer.route.stack[0].handle = (req, _res, next) => {
        req.authUser = { ...SUPER };
        next();
      };
    }
    const app = express();
    app.set('env', 'test');
    app.use(express.json());
    app.use(adminRouter);
    app.use(createErrorHandler({ logger: { error: () => {}, log: () => {}, warn: () => {} } }));
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(() => new Promise((resolve) => {
    pool.query = originalQuery;
    pool.connect = originalConnect;
    server.closeAllConnections?.();
    server.close(resolve);
  }));

  beforeEach(() => {
    poolCalls = [];
    clientCalls = [];
    released = 0;
    poolHandler = async () => ({ rows: [], rowCount: 0 });
    clientHandler = async () => ({ rows: [], rowCount: 0 });
    pool.query = async (text, params) => {
      const sql = norm(text);
      poolCalls.push({ sql, params: params ?? [] });
      return poolHandler(sql, params ?? []);
    };
    pool.connect = async () => ({
      query: async (text, params) => {
        const sql = norm(text);
        clientCalls.push({ sql, params: params ?? [] });
        return clientHandler(sql, params ?? []);
      },
      release() {
        released += 1;
      },
    });
    console.error = () => {};
    console.warn = () => {};
  });

  afterEach(() => {
    pool.query = originalQuery;
    pool.connect = originalConnect;
    console.error = originalConsole.error;
    console.warn = originalConsole.warn;
  });

  const send = async (method, path, body) => {
    const response = await fetch(`${baseUrl}${path}`, {
      method,
      headers: { 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    let json = null;
    try {
      json = JSON.parse(text);
    } catch (_e) {
      // gövdesiz yanıt
    }
    return { status: response.status, body: json };
  };
  const at = (pattern) => clientCalls.findIndex((c) => pattern.test(c.sql));
  const userRow = (extra = {}) => ({ id: 41001, full_name: 'Yeni Kişi', email: 'yeni@example.com', login_name: null, role: 'individual', is_active: false, email_verified: true, approval_status: 'approved', phone_number: '05321112233', created_at: new Date('2026-10-26T10:00:00Z'), ...extra });

  it('POST /admin/users: kullanıcı INSERT\'i ve must_change_password = TRUE aynı işlemde (BEGIN -> INSERT -> bayrak UPDATE -> COMMIT); yanıtta bayrak true', async () => {
    clientHandler = async (sql) => (/^INSERT INTO users/.test(sql) ? { rows: [userRow()], rowCount: 1 } : { rows: [], rowCount: 0 });
    const res = await send('POST', '/admin/users', {
      full_name: 'Yeni Kişi',
      email: 'yeni@example.com',
      password: STRONG,
      role: 'individual',
      phone_number: '05321112233',
    });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(res.body.user.must_change_password, true);
    assert.equal(res.body.user.id, 41001);
    const begin = at(/^BEGIN$/);
    const insert = at(/^INSERT INTO users/);
    const flag = at(/^UPDATE users SET must_change_password = TRUE, updated_at = NOW\(\) WHERE user_code = \$1 AND deleted_at IS NULL$/);
    const commit = at(/^COMMIT$/);
    assert.ok(begin === 0 && begin < insert && insert < flag && flag < commit, JSON.stringify(clientCalls.map((c) => c.sql.slice(0, 40))));
    assert.deepEqual(clientCalls[flag].params, [41001]);
    assert.equal(poolCalls.some((c) => /^INSERT INTO users/.test(c.sql)), false, 'INSERT havuzdan değil işlemin bağlantısından');
    assert.equal(released, 1);
  });

  it('POST /admin/users: INSERT hatasında (çakışma) ROLLBACK, bayrak UPDATE\'i ve COMMIT yok; bağlantı bırakılır', async () => {
    clientHandler = async (sql) => {
      if (/^INSERT INTO users/.test(sql)) {
        throw Object.assign(new Error('dup'), { code: '23505', constraint: 'users_email_key' });
      }
      return { rows: [], rowCount: 0 };
    };
    const res = await send('POST', '/admin/users', { full_name: 'Yeni Kişi', email: 'yeni@example.com', password: STRONG, role: 'individual', phone_number: '05321112233' });
    assert.equal(res.status, 409);
    assert.ok(at(/^ROLLBACK$/) > 0);
    assert.equal(at(/^COMMIT$/), -1);
    assert.equal(at(/^UPDATE users SET must_change_password/), -1);
    assert.equal(released, 1);
  });

  it('PATCH /admin/users/:id + parola (başkası için): parola özeti ve must_change_password = TRUE aynı işlemde; yanıtta bayrak true', async () => {
    poolHandler = async (sql) => (/^SELECT role FROM users WHERE user_code = \$1$/.test(sql) ? { rows: [{ role: 'site_manager' }], rowCount: 1 } : { rows: [], rowCount: 0 });
    clientHandler = async (sql) => (/^UPDATE users SET .*password_hash/.test(sql) ? { rows: [userRow({ id: 41002, role: 'site_manager' })], rowCount: 1 } : { rows: [], rowCount: 0 });
    const res = await send('PATCH', '/admin/users/41002', { password: STRONG });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.user.must_change_password, true);
    const begin = at(/^BEGIN$/);
    const write = at(/^UPDATE users SET password_hash = \$1 WHERE user_code = \$2 AND deleted_at IS NULL/);
    const flag = at(/^UPDATE users SET must_change_password = TRUE, updated_at = NOW\(\) WHERE user_code = \$1 AND deleted_at IS NULL$/);
    const commit = at(/^COMMIT$/);
    assert.ok(begin === 0 && begin < write && write < flag && flag < commit, JSON.stringify(clientCalls.map((c) => c.sql.slice(0, 50))));
    assert.deepEqual(clientCalls[flag].params, [41002]);
    assert.equal(released, 1);
  });

  it('PATCH /admin/users/:id parola YOK: bayrak (must_change_password) YAZILMAZ; yazım ve denetim kaydı yine tek işlemde (artık havuzdan değil bağlantıdan); bayrak yanıtta false', async () => {
    clientHandler = async (sql) => (/^UPDATE users SET/.test(sql) ? { rows: [userRow({ id: 41003 })], rowCount: 1 } : { rows: [], rowCount: 0 });
    const res = await send('PATCH', '/admin/users/41003', { full_name: 'Yeni Ad Soyad' });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.user.must_change_password, false);
    assert.equal(at(/must_change_password/), -1, 'bayrak yazımı yok');
    assert.equal(poolCalls.some((c) => /^UPDATE users/.test(c.sql)), false, 'kullanıcı yazımı havuzdan değil işlem bağlantısından');
    const begin = at(/^BEGIN$/);
    const write = at(/^UPDATE users SET full_name = \$1 WHERE user_code = \$2 AND deleted_at IS NULL/);
    const audit = at(/^INSERT INTO audit_log/);
    const commit = at(/^COMMIT$/);
    assert.ok(begin === 0 && begin < write && write < audit && audit < commit, JSON.stringify(clientCalls.map((c) => c.sql.slice(0, 40))));
    assert.equal(released, 1);
  });

  it('PATCH + parola, kullanıcı yok / silinmiş: bayrak UPDATE\'i yazılmaz, 404 (silinmişse 409 ACCOUNT_DELETED)', async () => {
    poolHandler = async (sql) => {
      if (/^SELECT role FROM users/.test(sql)) return { rows: [], rowCount: 0 };
      if (/^SELECT deleted_at FROM users/.test(sql)) return { rows: [{ deleted_at: new Date('2026-10-01T10:00:00Z') }], rowCount: 1 };
      return { rows: [], rowCount: 0 };
    };
    const res = await send('PATCH', '/admin/users/41004', { password: STRONG });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'ACCOUNT_DELETED');
    assert.equal(at(/^UPDATE users SET must_change_password/), -1);
    assert.ok(at(/^COMMIT$/) > 0, 'boş işlem sorunsuz kapanır');
    assert.equal(released, 1);
  });

  it('daire sakini / bireysel hesabın parolası yöneticilerce değiştirilemez kuralı korunur (403, işlem açılmaz)', async () => {
    poolHandler = async (sql) => (/^SELECT role FROM users WHERE user_code = \$1$/.test(sql) ? { rows: [{ role: 'individual' }], rowCount: 1 } : { rows: [], rowCount: 0 });
    const res = await send('PATCH', '/admin/users/41005', { password: STRONG });
    assert.equal(res.status, 403);
    assert.equal(clientCalls.length, 0);
  });

  it('abonelik talebi UPDATE\'i silinmiş hesabı dışlar (`AND deleted_at IS NULL`)', async () => {
    clientHandler = async () => ({ rows: [], rowCount: 0 });
    const res = await send('PATCH', '/admin/subscription-requests/41006', { action: 'approve' });
    assert.equal(res.status, 404);
    // Karar yazımı ve denetim kaydı tek işlemde olduğundan UPDATE işlem bağlantısından gider.
    const update = clientCalls.find((c) => /^UPDATE users SET approval_status/.test(c.sql));
    assert.match(update.sql, /AND approval_status = 'pending' AND deleted_at IS NULL RETURNING/);
    assert.equal(at(/^INSERT INTO audit_log/), -1, 'satır yok -> denetim kaydı yok');
  });
});

describe('admin sendServiceError: makine okunur hata kodu ve PlatformError ek alanları', () => {
  const capture = () => {
    const res = {
      statusCode: 200,
      body: undefined,
      headers: {},
      status(code) {
        this.statusCode = code;
        return this;
      },
      setHeader(name, value) {
        this.headers[name.toLowerCase()] = value;
      },
      json(payload) {
        this.body = payload;
        return this;
      },
    };
    return res;
  };

  it('kasıtlı 4xx hata: error + code (BÜYÜK_HARF) taşınır; ACCESS_SUSPENDED 409', () => {
    const res = capture();
    const error = Object.assign(new Error('Bu kişinin bu daire için kapı erişimi askıya alınmış.'), { statusCode: 409, code: 'ACCESS_SUSPENDED' });
    sendServiceError(res, error, 'yedek');
    assert.equal(res.statusCode, 409);
    assert.deepEqual(res.body, { error: 'Bu kişinin bu daire için kapı erişimi askıya alınmış.', code: 'ACCESS_SUSPENDED' });
  });

  it('PlatformError: code + extra alanları (PERSON_EXISTS -> person_id); kodsuz hata yalnız error', () => {
    const res = capture();
    sendServiceError(res, new PlatformError(409, 'PERSON_EXISTS', 'Kişi zaten var.', { person_id: 77 }), 'yedek');
    assert.equal(res.statusCode, 409);
    assert.deepEqual(res.body, { error: 'Kişi zaten var.', code: 'PERSON_EXISTS', person_id: 77 });

    const plain = capture();
    sendServiceError(plain, Object.assign(new Error('Geçersiz değer.'), { statusCode: 400 }), 'yedek');
    assert.deepEqual(plain.body, { error: 'Geçersiz değer.' });
  });

  it('pg hata kodları (23505, 42P01) ve beklenmeyen hatalar koda DÖNÜŞMEZ; 5xx genel mesaj + errorId', () => {
    const original = console.error;
    console.error = () => {};
    try {
      const res = capture();
      sendServiceError(res, Object.assign(new Error('boom'), { code: '42P01' }), 'Genel hata.');
      assert.equal(res.statusCode, 500);
      assert.equal(res.body.error, 'Genel hata.');
      assert.equal(res.body.code, undefined);
      assert.ok(res.body.errorId);
    } finally {
      console.error = original;
    }
  });
});
