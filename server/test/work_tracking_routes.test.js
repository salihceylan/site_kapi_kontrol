// İş Takibi uçları (DB'siz, KATI sahte veritabanı): rota zinciri + hız sınırları, yetki / modül kapısı sırası (biçim -> yetki -> site -> modül), doğrulama hatalarının
// veritabanına hiç gitmeden dönmesi, gövde boyutu. Kimlik katmanı sahte (x-test-user); gerçek HTTP, gerçek Express.
// Gerçek PostgreSQL doğrulaması (rol matrisi, IDOR, geçişler, idempotans, sınırlar, 40P01 = 0): scripts/qa_platform_pg.mjs "work_tracking".
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import { workAttachmentUploadLimiter, workItemReadLimiter, workItemWriteLimiter, workTrackingRouter } from '../src/modules/work_tracking_routes.js';

const SITE = 1000000001;
const OTHER_SITE = 1000000002;
const mk = (id, role, name) => ({ id, user_code: id, userCode: id, role, full_name: name, email: `u${id}@example.com` });
const users = {
  superUser: mk(1, 'super_user', 'Süper'),
  manager: mk(20001, 'site_manager', 'Yönetici'),
  otherManager: mk(20002, 'site_manager', 'Başka Yönetici'),
  resident: mk(20004, 'apartment_owner', 'Sakin'),
  staff: mk(20005, 'individual', 'Görevli'),
  board: mk(20006, 'individual', 'Kurul'),
  outsider: mk(20008, 'individual', 'İlgisiz'),
};

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
let state;
let log;

function makeState() {
  return {
    sites: new Set([SITE, OTHER_SITE]),
    managerLinks: [{ site_code: SITE, user_code: 20001 }, { site_code: OTHER_SITE, user_code: 20002 }],
    memberships: [
      { site_code: SITE, user_code: 20005, role: 'STAFF', is_active: true },
      { site_code: SITE, user_code: 20006, role: 'BOARD_MEMBER', is_active: true },
    ],
    moduleEnabled: true,
  };
}

function fakeQuery(text, params = []) {
  const sql = norm(text);
  log.push(sql);
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(state.managerLinks.filter((l) => l.site_code === Number(params[0]) && l.user_code === Number(params[1])).map(() => ({ x: 1 })));
  }
  if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) return ok();
  if (/^SELECT EXISTS \( SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'BOARD_MEMBER'/.test(sql)) {
    const [site, user] = params.map(Number);
    const here = state.memberships.filter((m) => m.site_code === site && m.user_code === user && m.is_active);
    const otherRole = state.managerLinks.some((l) => l.user_code === user) || state.memberships.some((m) => m.user_code === user && m.is_active && m.role === 'BOARD_MEMBER');
    return ok([{ is_board_here: here.some((m) => m.role === 'BOARD_MEMBER'), is_member_here: here.length > 0, has_other_role: otherRole }]);
  }
  if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'STAFF' AND is_active = TRUE LIMIT 1$/.test(sql)) {
    return ok(state.memberships.filter((m) => m.site_code === Number(params[0]) && m.user_code === Number(params[1]) && m.role === 'STAFF').map(() => ({ x: 1 })));
  }
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/.test(sql)) return ok(state.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(params[1] === 'work_tracking' ? [{ enabled: state.moduleEnabled }] : []);
  }
  throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
}

const ORIGINAL_ROUTES = workTrackingRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({ path: layer.route.path, method: Object.keys(layer.route.methods)[0], handlers: layer.route.stack.map((entry) => entry.handle) }));

let server;
let baseUrl;

before(async () => {
  for (const layer of workTrackingRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    layer.route.stack[1].handle = (_req, _res, next) => next(); // hız sınırlayıcılar ayrı testte sınanır
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(workTrackingRouter);
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
  delete pool.query;
  delete pool.connect;
});

beforeEach(() => {
  state = makeState();
  log = [];
  pool.query = async (text, params) => fakeQuery(text, params);
  pool.connect = async () => {
    throw new Error('işlem açılmamalıydı (doğrulama / yetki hatası veritabanına gitmeden dönmeli)');
  };
});

async function call(method, urlPath, { user = null, body } = {}) {
  const init = { method, headers: {} };
  if (user) init.headers['x-test-user'] = encodeURIComponent(JSON.stringify(user));
  if (body !== undefined) {
    init.body = typeof body === 'string' ? body : JSON.stringify(body);
    init.headers['content-type'] = 'application/json';
  }
  const res = await fetch(`${baseUrl}${urlPath}`, init);
  let json = null;
  try {
    json = await res.json();
  } catch (_error) {
    // gövdesiz
  }
  return { status: res.status, body: json, headers: res.headers };
}

const url = (suffix = '', site = SITE) => `/manager/sites/${site}/work-items${suffix}`;
const GOOD = { site_code: SITE, category: 'ariza', location_type: 'ortak_alan', title: 'Başlık', description: 'Açıklama', idempotency_key: 'abc-12345-xyz' };

describe('rota zinciri ve hız sınırları', () => {
  it('sözleşmedeki 20 uç vardır (11 + 8 fotoğraf eki + rapor); her biri authRequired ile BAŞLAR, ikinci halka hız sınırlayıcıdır; /assignees ve /report, /:id\'den ÖNCE tanımlıdır', () => {
    const routes = ORIGINAL_ROUTES.map((route) => `${route.method.toUpperCase()} ${route.path}`);
    assert.deepEqual([...routes].sort(), [
      'DELETE /app/work-items/:id/attachments/:attId',
      'DELETE /manager/sites/:siteCode/work-items/:id/attachments/:attId',
      'GET /app/work-items',
      'GET /app/work-items/:id',
      'GET /app/work-items/:id/attachments/:attId/content',
      'GET /manager/sites/:siteCode/work-items',
      'GET /manager/sites/:siteCode/work-items/:id',
      'GET /manager/sites/:siteCode/work-items/:id/attachments/:attId/content',
      'GET /manager/sites/:siteCode/work-items/assignees',
      'GET /manager/sites/:siteCode/work-items/report',
      'PATCH /manager/sites/:siteCode/work-items/:id',
      'POST /app/work-items',
      'POST /app/work-items/:id/attachments',
      'POST /app/work-items/:id/cancel',
      'POST /app/work-items/:id/comments',
      'POST /app/work-items/:id/seen',
      'POST /manager/sites/:siteCode/work-items/:id/attachments',
      'POST /manager/sites/:siteCode/work-items/:id/comments',
      'PUT /app/work-items/:id/attachments/:attId/content',
      'PUT /manager/sites/:siteCode/work-items/:id/attachments/:attId/content',
    ].sort());
    assert.ok(routes.indexOf('GET /manager/sites/:siteCode/work-items/assignees') < routes.indexOf('GET /manager/sites/:siteCode/work-items/:id'));
    assert.ok(routes.indexOf('GET /manager/sites/:siteCode/work-items/report') < routes.indexOf('GET /manager/sites/:siteCode/work-items/:id'));
    for (const route of ORIGINAL_ROUTES) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}`);
      const expected = route.method === 'put' ? workAttachmentUploadLimiter : route.method === 'get' || route.path.endsWith('/seen') ? workItemReadLimiter : workItemWriteLimiter;
      assert.equal(route.handlers[1], expected, `${route.method} ${route.path}`);
    }
  });

  it('yazma 120/saat, okuma 1200/saat (429 + Retry-After)', () => {
    const fire = (limiter, userCode, times) => {
      const statuses = [];
      for (let i = 0; i < times; i += 1) {
        const req = { authUser: { user_code: userCode }, ip: `10.0.1.${userCode % 200}`, headers: {}, socket: { remoteAddress: `10.0.1.${userCode % 200}` } };
        const headers = {};
        const res = {
          setHeader: (key, value) => { headers[key] = value; },
          status(code) { statuses.push([code, headers['Retry-After']]); return { json() {} }; },
        };
        limiter(req, res, () => statuses.push([200]));
      }
      return statuses;
    };
    for (const [limiter, max, user] of [[workItemWriteLimiter, 120, 777001], [workItemReadLimiter, 1200, 777002]]) {
      const statuses = fire(limiter, user, max + 1);
      assert.equal(statuses.slice(0, max).every(([code]) => code === 200), true);
      assert.equal(statuses[max][0], 429);
      assert.ok(Number(statuses[max][1]) > 0);
    }
  });
});

describe('yönetim uçları: sıra biçim -> yetki -> site -> modül', () => {
  it('geçersiz site kodu 400 INVALID_SITE_CODE (veritabanına gitmeden)', async () => {
    const res = await call('GET', '/manager/sites/abc/work-items', { user: users.manager });
    assert.equal(res.status, 400);
    assert.equal(res.body.code, 'INVALID_SITE_CODE');
    assert.equal(log.length, 0);
  });

  it('sakin / ilgisiz FORBIDDEN_ROLE; başka sitenin yöneticisi FORBIDDEN_SITE; olmayan site (yetkili) 404 SITE_NOT_FOUND', async () => {
    assert.equal((await call('GET', url(), { user: users.resident })).body.code, 'FORBIDDEN_ROLE');
    assert.equal((await call('GET', url(), { user: users.outsider })).body.code, 'FORBIDDEN_ROLE');
    const other = await call('GET', url(), { user: users.otherManager });
    assert.deepEqual([other.status, other.body.code], [403, 'FORBIDDEN_SITE']);
    const missing = await call('GET', '/manager/sites/1999999999/work-items', { user: users.superUser });
    assert.deepEqual([missing.status, missing.body.code], [404, 'SITE_NOT_FOUND']);
  });

  it('modül KAPALI: yetkili herkes 403 MODULE_DISABLED { module: work_tracking }; yetki modülden ÖNCE denetlenir', async () => {
    state.moduleEnabled = false;
    for (const user of [users.superUser, users.manager, users.staff, users.board]) {
      const res = await call('GET', url(), { user });
      assert.deepEqual([res.status, res.body.code, res.body.module], [403, 'MODULE_DISABLED', 'work_tracking']);
    }
    assert.equal((await call('GET', url(), { user: users.outsider })).body.code, 'FORBIDDEN_ROLE');
  });

  it('kurul salt okur: PATCH / yorum / assignees 403 FORBIDDEN_ROLE (iş mantığına hiç girmeden)', async () => {
    const patch = await call('PATCH', url('/5'), { user: users.board, body: { priority: 'acil' } });
    const commented = await call('POST', url('/5/comments'), { user: users.board, body: { body: 'x', visibility: 'public', idempotency_key: 'abc-12345-xyz' } });
    const assignees = await call('GET', url('/assignees'), { user: users.board });
    for (const res of [patch, commented, assignees]) assert.deepEqual([res.status, res.body.code], [403, 'FORBIDDEN_ROLE']);
  });

  it('PATCH / yorum doğrulama hataları (yetkili kullanıcı) işlem açmadan 400 INVALID_BODY; görünmez kimlik 404', async () => {
    const empty = await call('PATCH', url('/5'), { user: users.manager, body: {} });
    const badStatus = await call('PATCH', url('/5'), { user: users.manager, body: { status: 'bitti' } });
    const noKey = await call('POST', url('/5/comments'), { user: users.manager, body: { body: 'x', visibility: 'public' } });
    for (const res of [empty, badStatus, noKey]) assert.deepEqual([res.status, res.body.code], [400, 'INVALID_BODY']);
    const badId = await call('PATCH', url('/abc'), { user: users.manager, body: { priority: 'acil' } });
    assert.deepEqual([badId.status, badId.body.code], [404, 'WORK_ITEM_NOT_FOUND']);
  });

  it('liste sorgusu geçersizse 400 INVALID_QUERY', async () => {
    const res = await call('GET', url('?status=bogus'), { user: users.manager });
    assert.deepEqual([res.status, res.body.code], [400, 'INVALID_QUERY']);
  });
});

describe('sakin uçları: doğrulama veritabanına gitmeden döner', () => {
  it('talep açma: eksik / geçersiz alanlar 400 INVALID_BODY; hiçbir sorgu gitmez', async () => {
    for (const over of [{ title: '' }, { category: 'x' }, { idempotency_key: 'k' }, { site_code: 'x' }, { urgent: 1 }, { apartment_id: 3 }]) {
      const res = await call('POST', '/app/work-items', { user: users.resident, body: { ...GOOD, ...over } });
      assert.deepEqual([res.status, res.body.code], [400, 'INVALID_BODY'], JSON.stringify(over));
    }
    assert.equal(log.length, 0);
  });

  it('16 KB üstü gövde 413 BODY_TOO_LARGE', async () => {
    const res = await call('POST', '/app/work-items', { user: users.resident, body: { ...GOOD, description: 'z'.repeat(20000) } });
    assert.deepEqual([res.status, res.body.code], [413, 'BODY_TOO_LARGE']);
  });

  it('yorum: sakin internal gönderemez (400); geçersiz kimlikler 404; liste sorgusu geçersizse 400', async () => {
    const internal = await call('POST', '/app/work-items/5/comments', { user: users.resident, body: { body: 'x', visibility: 'internal', idempotency_key: 'abc-12345-xyz' } });
    assert.deepEqual([internal.status, internal.body.code], [400, 'INVALID_BODY']);
    for (const [method, path] of [['GET', '/app/work-items/abc'], ['POST', '/app/work-items/abc/cancel'], ['POST', '/app/work-items/abc/seen']]) {
      const res = await call(method, path, { user: users.resident, body: method === 'POST' ? {} : undefined });
      assert.deepEqual([res.status, res.body.code], [404, 'WORK_ITEM_NOT_FOUND'], path);
    }
    const badList = await call('GET', '/app/work-items?status=bogus', { user: users.resident });
    assert.deepEqual([badList.status, badList.body.code], [400, 'INVALID_QUERY']);
  });
});
