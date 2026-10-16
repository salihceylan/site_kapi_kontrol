// R2 F-5 / R6: kullanıcı isteğiyle SİLİNMİŞ (kimliksizleştirilmiş) hesap ve yönetici (süper kullanıcı) uçları - DB'siz.
//  - DELETE /admin/users/:id tombstone'a: 409 ACCOUNT_ALREADY_DELETED (kalıcı silinmez; onay kayıtları ve kimliksiz iz yasal saklama için kalır)
//  - PATCH /admin/users/:id/activation ve PATCH /admin/users/:id tombstone'a: 409 ACCOUNT_DELETED (yeniden etkinleştirilemez / düzenlenemez); olmayan kullanıcı 404
//  - GET /admin/users: varsayılan `deleted_at IS NULL` (silinmişler listelenmez); ?include_deleted=true ile görülür
// Gerçek PostgreSQL davranışı (CHECK kısıtı, yarış): scripts/qa_platform_pg.mjs "account".
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import '../src/utils/async_errors.js';
import { pool } from '../src/db.js';
import { adminRouter } from '../src/routes/admin_routes.js';
import { createErrorHandler } from '../src/middlewares/error_handler.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const SUPER = { id: 1, user_code: 1, role: 'super_user', full_name: 'Süper', is_active: true };

describe('admin uçları: silinmiş (tombstone) hesap', () => {
  let server;
  let baseUrl;
  let calls;
  let clientCalls;
  let poolHandler;
  let clientHandler;
  const originalConnect = pool.connect;
  const originalQuery = pool.query;
  const originalConsole = { error: console.error, warn: console.warn };

  before(async () => {
    // Yalnız admin uçları: kimlik doğrulama sabit süper kullanıcıyla; rol koruması gerçek kalır.
    for (const layer of adminRouter.stack) {
      if (!layer.route) continue;
      const stack = layer.route.stack;
      stack[0].handle = (req, _res, next) => {
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
    calls = [];
    clientCalls = [];
    poolHandler = async () => ({ rows: [], rowCount: 0 });
    clientHandler = async () => ({ rows: [], rowCount: 0 });
    pool.query = async (text, params) => {
      const sql = norm(text);
      calls.push({ sql, params: params ?? [] });
      return poolHandler(sql, params ?? []);
    };
    pool.connect = async () => ({
      query: async (text, params) => {
        const sql = norm(text);
        clientCalls.push({ sql, params: params ?? [] });
        return clientHandler(sql, params ?? []);
      },
      release() {},
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
      // gövdesiz yanıt (204)
    }
    return { status: response.status, body: json };
  };
  const isDeletedLookup = (sql) => /^SELECT deleted_at FROM users WHERE user_code = \$1$/.test(sql);

  it('DELETE tombstone: 409 ACCOUNT_ALREADY_DELETED; işlem BAŞLAMAZ (BEGIN / DELETE FROM users yok), bağlantı bile alınmaz', async () => {
    poolHandler = async (sql) => (isDeletedLookup(sql) ? { rows: [{ deleted_at: new Date('2026-10-01T10:00:00Z') }], rowCount: 1 } : { rows: [], rowCount: 0 });
    const res = await send('DELETE', '/admin/users/40001');
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'ACCOUNT_ALREADY_DELETED');
    assert.match(res.body.error, /kalıcı silinemez/);
    assert.equal(clientCalls.length, 0, 'transaction açılmadı');
    assert.equal(calls.some((c) => /DELETE FROM users/.test(c.sql)), false);
  });

  it('DELETE normal kullanıcı: son silme ifadesi `AND deleted_at IS NULL` taşır -> 204', async () => {
    clientHandler = async (sql) => (/^DELETE FROM users WHERE user_code = \$1/.test(sql) ? { rows: [], rowCount: 1 } : { rows: [], rowCount: 0 });
    const res = await send('DELETE', '/admin/users/40002');
    assert.equal(res.status, 204);
    const finalDelete = clientCalls.find((c) => /^DELETE FROM users WHERE user_code = \$1/.test(c.sql));
    assert.equal(finalDelete.sql, 'DELETE FROM users WHERE user_code = $1 AND deleted_at IS NULL');
    assert.deepEqual(finalDelete.params, [40002]);
    assert.ok(clientCalls.some((c) => c.sql === 'COMMIT'));
  });

  it('DELETE yarışı: ön kontrolde silinmemişti, kullanıcı silme bu arada commit etti -> son DELETE 0 satır, ROLLBACK, 409 ACCOUNT_ALREADY_DELETED (tombstone kalıcı silinmez)', async () => {
    let lookups = 0;
    poolHandler = async (sql) => {
      if (isDeletedLookup(sql)) {
        lookups += 1;
        return lookups === 1 ? { rows: [{ deleted_at: null }], rowCount: 1 } : { rows: [{ deleted_at: new Date() }], rowCount: 1 };
      }
      return { rows: [], rowCount: 0 };
    };
    clientHandler = async () => ({ rows: [], rowCount: 0 }); // DELETE ... deleted_at IS NULL -> 0 satır
    const res = await send('DELETE', '/admin/users/40003');
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'ACCOUNT_ALREADY_DELETED');
    assert.ok(clientCalls.some((c) => c.sql === 'ROLLBACK'));
    assert.equal(clientCalls.some((c) => c.sql === 'COMMIT'), false);
  });

  it('DELETE olmayan kullanıcı: 404 (409 değil)', async () => {
    const res = await send('DELETE', '/admin/users/40004');
    assert.equal(res.status, 404);
    assert.equal(res.body.code, undefined);
  });

  it('PATCH activation tombstone\'a: 409 ACCOUNT_DELETED (etkinleştirme reddedilir); UPDATE `deleted_at IS NULL` ister, sonra silinmişlik sorgulanır', async () => {
    poolHandler = async (sql) => (isDeletedLookup(sql) ? { rows: [{ deleted_at: new Date() }], rowCount: 1 } : { rows: [], rowCount: 0 });
    const res = await send('PATCH', '/admin/users/40005/activation', { is_active: true });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'ACCOUNT_DELETED');
    const update = calls.find((c) => /^UPDATE users SET/.test(c.sql));
    assert.ok(update, 'UPDATE denendi');
    assert.match(update.sql, /WHERE user_code = \$\d+ AND deleted_at IS NULL/);
    assert.ok(calls.findIndex((c) => isDeletedLookup(c.sql)) > calls.indexOf(update));
  });

  it('PATCH activation olmayan kullanıcı: 404; PATCH düzenleme tombstone\'a: 409 ACCOUNT_DELETED', async () => {
    let res = await send('PATCH', '/admin/users/40006/activation', { is_active: false });
    assert.equal(res.status, 404);
    assert.equal(res.body.code, undefined);

    poolHandler = async (sql) => (isDeletedLookup(sql) ? { rows: [{ deleted_at: new Date() }], rowCount: 1 } : { rows: [], rowCount: 0 });
    res = await send('PATCH', '/admin/users/40007', { full_name: 'Yeni Ad Soyad' });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'ACCOUNT_DELETED');
  });

  it('GET /admin/users: varsayılan silinmişleri LİSTELEMEZ (`deleted_at IS NULL` sayım ve liste sorgusunda); ?include_deleted=true ile süzgeç kalkar', async () => {
    poolHandler = async (sql) => (/COUNT\(\*\)/.test(sql) ? { rows: [{ total: 0 }], rowCount: 1 } : { rows: [], rowCount: 0 });
    let res = await send('GET', '/admin/users?role=all');
    assert.equal(res.status, 200);
    const listSqls = calls.filter((c) => /FROM users/.test(c.sql));
    assert.equal(listSqls.length, 2);
    assert.ok(listSqls.every((c) => /WHERE deleted_at IS NULL/.test(c.sql)), listSqls.map((c) => c.sql).join(' | '));

    calls.length = 0;
    res = await send('GET', '/admin/users?include_deleted=true');
    assert.equal(res.status, 200);
    assert.ok(calls.filter((c) => /FROM users/.test(c.sql)).every((c) => !/deleted_at/.test(c.sql)));

    calls.length = 0;
    res = await send('GET', '/admin/users?search=ada&role=site_manager');
    assert.equal(res.status, 200);
    const filtered = calls.find((c) => /SELECT COUNT\(\*\)/.test(c.sql));
    assert.match(filtered.sql, /WHERE deleted_at IS NULL AND role = \$1/);
    assert.match(filtered.sql, /full_name ILIKE/);
  });
});
