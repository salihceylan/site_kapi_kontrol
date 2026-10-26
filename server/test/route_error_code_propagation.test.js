// Katılım başvurusu / onayı rotaları hata yanıtına makine okunur `code` (ve PlatformError ek alanlarını) taşır; böylece istemci ACCESS_SUSPENDED gibi durumları
// metne bakmadan ayırt eder. DB'siz (sahte havuz); kimlik doğrulama katmanı yerine sabit kullanıcı konur.
//  - POST /membership/join-request (askıdaki kişi): 403 ACCESS_SUSPENDED (neden gösterilmez)
//  - POST /manager/join-requests/:id/approve (askıdaki kişinin başvurusu): 409 ACCESS_SUSPENDED
//  - PlatformError: { error, code, ...extra }
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import '../src/utils/async_errors.js';
import { pool } from '../src/db.js';
import { membershipRouter } from '../src/routes/membership_routes.js';
import { managerRouter } from '../src/routes/manager_routes.js';
import { PlatformError } from '../src/modules/errors.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
const SUSPENSION = /^SELECT 1 FROM apartment_access_suspensions WHERE apartment_id = \$1 AND user_code = \$2 AND lifted_at IS NULL LIMIT 1$/;
const SUPER = { id: 1, user_code: 1, userCode: 1, role: 'super_user', full_name: 'Süper', is_active: true };

function scripted(handlers) {
  const log = [];
  return {
    log,
    query: async (text, params) => {
      const sql = norm(text);
      log.push({ sql, params });
      for (const [pattern, result] of handlers) {
        if (pattern.test(sql)) return typeof result === 'function' ? result(sql, params) : result;
      }
      return ok();
    },
  };
}

describe('katılım rotaları: hata yanıtında code', () => {
  let server;
  let baseUrl;
  let currentUser;
  const originalConnect = pool.connect;
  const originalQuery = pool.query;
  const originalConsole = { error: console.error, warn: console.warn };

  before(async () => {
    const stub = (req, _res, next) => {
      req.authUser = { ...currentUser };
      next();
    };
    // Yalnız bu rotalar: authRequired (+ requireSiteManager) yerine sabit kullanıcı; işleyici gerçek kalır.
    for (const layer of membershipRouter.stack) {
      if (layer.route) layer.route.stack[0].handle = stub;
    }
    for (const layer of managerRouter.stack) {
      if (layer.route && layer.route.path === '/manager/join-requests/:requestId/approve') {
        layer.route.stack[0].handle = stub;
        layer.route.stack[1].handle = (_req, _res, next) => next();
      }
    }
    const app = express();
    app.set('env', 'test');
    app.use(express.json());
    app.use(membershipRouter);
    app.use(managerRouter);
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
    currentUser = { ...SUPER };
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
    return { status: response.status, body: await response.json() };
  };

  function joinClient({ suspended }) {
    const client = scripted([
      [/^SELECT id FROM apartments WHERE id = \$1 FOR KEY SHARE/, ok([{ id: 3 }])],
      [/FROM users WHERE user_code = \$1 AND deleted_at IS NULL LIMIT 1 FOR KEY SHARE/, ok([{ user_code: 77, full_name: 'Ali', email: 'ali@example.com', email_verified: true, is_active: true }])],
      [/FROM site_join_tokens t/, ok([{ site_code: '101', site_name: 'Gül Sitesi' }])],
      [/^SELECT a\.id, a\.site_code, a\.block_id, a\.unit_label, b\.block_name FROM apartments a/, ok([{ id: 3, site_code: 101, block_id: 5, unit_label: 'Daire 3', block_name: 'A' }])],
      [SUSPENSION, ok(suspended ? [{ x: 1 }] : [])],
      [/^INSERT INTO join_requests/, ok([{ id: 9, site_code: 101, block_id: 5, apartment_id: 3, user_code: 77, status: 'PENDING', notes: null, created_at: new Date() }])],
    ]);
    pool.query = async () => ok();
    pool.connect = async () => ({ query: client.query, release() {} });
    return client.log;
  }

  it('POST /membership/join-request: askıdaki kişi 403 + code ACCESS_SUSPENDED; neden (mahkeme / güvenlik) metinde YOK; INSERT yok', async () => {
    currentUser = { id: 77, user_code: 77, userCode: 77, role: 'individual' };
    const log = joinClient({ suspended: true });
    const res = await send('POST', '/membership/join-request', { token: 'SJT-ABC', apartmentId: 3 });
    assert.equal(res.status, 403);
    assert.equal(res.body.code, 'ACCESS_SUSPENDED');
    assert.ok(typeof res.body.error === 'string' && res.body.error.length > 10);
    assert.doesNotMatch(res.body.error, /mahkeme|güvenlik/i);
    assert.equal(log.some((entry) => /^INSERT INTO join_requests/.test(entry.sql)), false);
  });

  it('POST /membership/join-request: askı yoksa 201 (davranış aynı)', async () => {
    currentUser = { id: 77, user_code: 77, userCode: 77, role: 'individual' };
    joinClient({ suspended: false });
    const res = await send('POST', '/membership/join-request', { token: 'SJT-ABC', apartmentId: 3 });
    assert.equal(res.status, 201, JSON.stringify(res.body));
  });

  it('POST /manager/join-requests/:id/approve: askıdaki kişinin başvurusu 409 + code ACCESS_SUSPENDED (eskiden yalnız error)', async () => {
    const client = scripted([
      [/FOR UPDATE OF jr FOR KEY SHARE OF u$/, ok([{ id: 9, site_code: 101, apartment_id: 3, block_id: 5, user_code: 77, status: 'PENDING', site_name: 'S', unit_label: 'Daire 3', block_name: 'A', full_name: 'Ali', email: 'ali@example.com' }])],
      [SUSPENSION, ok([{ x: 1 }])],
    ]);
    pool.query = async () => ok();
    pool.connect = async () => ({ query: client.query, release() {} });
    const res = await send('POST', '/manager/join-requests/9/approve');
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'ACCESS_SUSPENDED');
    assert.match(res.body.error, /askıya alınmış/);
    assert.equal(client.log.some((entry) => /^INSERT INTO apartment_memberships|^UPDATE join_requests/.test(entry.sql)), false);
  });

  it('PlatformError: membership rotaları code ve ek alanları (extra) taşır', async () => {
    currentUser = { id: 77, user_code: 77, userCode: 77, role: 'individual' };
    pool.query = async () => {
      throw new PlatformError(409, 'PERSON_EXISTS', 'Kişi zaten kayıtlı.', { person_id: 55 });
    };
    pool.connect = async () => ({
      query: async () => {
        throw new PlatformError(409, 'PERSON_EXISTS', 'Kişi zaten kayıtlı.', { person_id: 55 });
      },
      release() {},
    });
    const res = await send('GET', '/membership/my-apartments');
    assert.equal(res.status, 409);
    assert.deepEqual(res.body, { error: 'Kişi zaten kayıtlı.', code: 'PERSON_EXISTS', person_id: 55 });
  });

  it('beklenmeyen (DB) hata koda dönüşmez: genel mesaj, code yok, ayrıntı sızmaz', async () => {
    currentUser = { id: 77, user_code: 77, userCode: 77, role: 'individual' };
    const failing = async () => {
      throw Object.assign(new Error('relation "x" does not exist'), { code: '42P01' });
    };
    pool.query = failing;
    pool.connect = async () => ({ query: failing, release() {} });
    const res = await send('GET', '/membership/my-apartments');
    assert.equal(res.status, 500);
    assert.equal(res.body.code, undefined);
    assert.doesNotMatch(JSON.stringify(res.body), /relation/);
  });
});
