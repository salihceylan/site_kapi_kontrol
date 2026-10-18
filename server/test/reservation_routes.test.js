// Rezervasyon ve Konsiyerj uçları (DB'siz, KATI sahte veritabanı): rota zinciri + hız sınırları, yetki / modül kapısı sırası (biçim -> yetki -> site -> modül), doğrulama
// hatalarının veritabanına hiç gitmeden dönmesi, gövde boyutu. Kimlik katmanı sahte (x-test-user); gerçek HTTP, gerçek Express.
// Gerçek PostgreSQL doğrulaması (kapasite yarışı, rol matrisi, IDOR, iptal penceresi, limitler, 40P01 = 0): scripts/qa_platform_pg.mjs "reservation".
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import { reservationReadLimiter, reservationRouter, reservationWriteLimiter } from '../src/modules/reservation_routes.js';

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
    return ok(params[1] === 'reservation' ? [{ enabled: state.moduleEnabled }] : []);
  }
  throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
}

const ORIGINAL_ROUTES = reservationRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({ path: layer.route.path, method: Object.keys(layer.route.methods)[0], handlers: layer.route.stack.map((entry) => entry.handle) }));

let server;
let baseUrl;

before(async () => {
  for (const layer of reservationRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    layer.route.stack[1].handle = (_req, _res, next) => next(); // hız sınırlayıcılar ayrı testte sınanır
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(reservationRouter);
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

const M = (suffix = '', site = SITE) => `/manager/sites/${site}${suffix}`;
const AREA = { name: 'Havuz', capacity: 2, slot_minutes: 60, weekly_hours: [{ weekday: 1, start: '09:00', end: '12:00' }] };
const GOOD = { site_code: SITE, area_id: 5, date: '2030-01-07', start: '10:00', slots: 1, idempotency_key: 'abc-12345-xyz' };
const GOOD_REQ = { site_code: SITE, category: 'paket_teslim', note: 'Kapıda', idempotency_key: 'abc-12345-xyz' };

describe('rota zinciri ve hız sınırları', () => {
  it('sözleşmedeki 18 uç vardır; her biri authRequired ile BAŞLAR, ikinci halka hız sınırlayıcıdır (GET: okuma; yazan: yazma)', () => {
    const routes = ORIGINAL_ROUTES.map((route) => `${route.method.toUpperCase()} ${route.path}`);
    assert.deepEqual([...routes].sort(), [
      'GET /app/concierge-requests',
      'GET /app/reservation-areas',
      'GET /app/reservation-areas/:id/availability',
      'GET /app/reservations',
      'GET /app/reservations/:id',
      'GET /manager/sites/:siteCode/concierge-requests',
      'GET /manager/sites/:siteCode/concierge-requests/:id',
      'GET /manager/sites/:siteCode/reservation-areas',
      'GET /manager/sites/:siteCode/reservations',
      'GET /manager/sites/:siteCode/reservations/:id',
      'PATCH /manager/sites/:siteCode/concierge-requests/:id',
      'PATCH /manager/sites/:siteCode/reservation-areas/:id',
      'POST /app/concierge-requests',
      'POST /app/concierge-requests/:id/cancel',
      'POST /app/reservations',
      'POST /app/reservations/:id/cancel',
      'POST /manager/sites/:siteCode/reservation-areas',
      'POST /manager/sites/:siteCode/reservations/:id/decision',
    ].sort());
    for (const route of ORIGINAL_ROUTES) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}`);
      const expected = route.method === 'get' ? reservationReadLimiter : reservationWriteLimiter;
      assert.equal(route.handlers[1], expected, `${route.method} ${route.path}`);
    }
  });

  it('yazma 120/saat, okuma 1200/saat (429 + Retry-After)', () => {
    const fire = (limiter, userCode, times) => {
      const statuses = [];
      for (let i = 0; i < times; i += 1) {
        const req = { authUser: { user_code: userCode }, ip: `10.0.2.${userCode % 200}`, headers: {}, socket: { remoteAddress: `10.0.2.${userCode % 200}` } };
        const headers = {};
        const res = {
          setHeader: (key, value) => { headers[key] = value; },
          status(code) { statuses.push([code, headers['Retry-After']]); return { json() {} }; },
        };
        limiter(req, res, () => statuses.push([200]));
      }
      return statuses;
    };
    for (const [limiter, max, user] of [[reservationWriteLimiter, 120, 778001], [reservationReadLimiter, 1200, 778002]]) {
      const statuses = fire(limiter, user, max + 1);
      assert.equal(statuses.slice(0, max).every(([code]) => code === 200), true);
      assert.equal(statuses[max][0], 429);
      assert.ok(Number(statuses[max][1]) > 0);
    }
  });
});

describe('yönetim uçları: sıra biçim -> yetki -> site -> modül', () => {
  it('geçersiz site kodu 400 INVALID_SITE_CODE (veritabanına gitmeden)', async () => {
    const res = await call('GET', '/manager/sites/abc/reservations', { user: users.manager });
    assert.equal(res.status, 400);
    assert.equal(res.body.code, 'INVALID_SITE_CODE');
    assert.equal(log.length, 0);
  });

  it('sakin / ilgisiz FORBIDDEN_ROLE; başka sitenin yöneticisi FORBIDDEN_SITE; olmayan site (yetkili) 404 SITE_NOT_FOUND', async () => {
    for (const path of ['/reservations', '/reservation-areas', '/concierge-requests']) {
      assert.equal((await call('GET', M(path), { user: users.resident })).body.code, 'FORBIDDEN_ROLE', path);
      assert.equal((await call('GET', M(path), { user: users.outsider })).body.code, 'FORBIDDEN_ROLE', path);
      const other = await call('GET', M(path), { user: users.otherManager });
      assert.deepEqual([other.status, other.body.code], [403, 'FORBIDDEN_SITE'], path);
    }
    const missing = await call('GET', '/manager/sites/1999999999/reservations', { user: users.superUser });
    assert.deepEqual([missing.status, missing.body.code], [404, 'SITE_NOT_FOUND']);
  });

  it('modül KAPALI: yetkili herkes 403 MODULE_DISABLED { module: reservation }; yetki modülden ÖNCE denetlenir', async () => {
    state.moduleEnabled = false;
    for (const user of [users.superUser, users.manager, users.staff, users.board]) {
      for (const path of ['/reservations', '/reservation-areas', '/concierge-requests']) {
        const res = await call('GET', M(path), { user });
        assert.deepEqual([res.status, res.body.code, res.body.module], [403, 'MODULE_DISABLED', 'reservation'], path);
      }
    }
    assert.equal((await call('GET', M('/reservations'), { user: users.outsider })).body.code, 'FORBIDDEN_ROLE');
  });

  it('alan TANIMI yalnız yönetici / süper: görevli ve kurul POST / PATCH 403 FORBIDDEN_ROLE (iş mantığına hiç girmeden)', async () => {
    for (const user of [users.staff, users.board, users.resident]) {
      const created = await call('POST', M('/reservation-areas'), { user, body: AREA });
      const patched = await call('PATCH', M('/reservation-areas/5'), { user, body: { capacity: 3 } });
      for (const res of [created, patched]) assert.deepEqual([res.status, res.body.code], [403, 'FORBIDDEN_ROLE']);
    }
    // görevli alanları OKUR (takvim süzgeci için): yetki geçer, sorgu yok edilince sahte DB katı olduğu için yalnız erişim denetimi sorguları görülür
    assert.equal((await call('GET', M('/reservations?status=bogus'), { user: users.staff })).body.code, 'INVALID_QUERY');
  });

  it('kurul salt okur: karar / konsiyerj PATCH 403 FORBIDDEN_ROLE', async () => {
    const decision = await call('POST', M('/reservations/5/decision'), { user: users.board, body: { action: 'approve' } });
    const concierge = await call('PATCH', M('/concierge-requests/5'), { user: users.board, body: { status: 'iptal' } });
    for (const res of [decision, concierge]) assert.deepEqual([res.status, res.body.code], [403, 'FORBIDDEN_ROLE']);
  });

  it('alan / karar / konsiyerj doğrulama hataları (yetkili kullanıcı) işlem açmadan 400 INVALID_BODY; görünmez kimlik 404', async () => {
    const badArea = await call('POST', M('/reservation-areas'), { user: users.manager, body: { ...AREA, capacity: 0 } });
    const missingHours = await call('POST', M('/reservation-areas'), { user: users.manager, body: { name: 'A', capacity: 1, slot_minutes: 60 } });
    const emptyPatch = await call('PATCH', M('/reservation-areas/5'), { user: users.manager, body: {} });
    const noReason = await call('POST', M('/reservations/5/decision'), { user: users.staff, body: { action: 'reject' } });
    const badAction = await call('POST', M('/reservations/5/decision'), { user: users.manager, body: { action: 'x' } });
    const emptyConcierge = await call('PATCH', M('/concierge-requests/5'), { user: users.staff, body: {} });
    for (const res of [badArea, missingHours, emptyPatch, noReason, badAction, emptyConcierge]) assert.deepEqual([res.status, res.body.code], [400, 'INVALID_BODY']);
    assert.equal((await call('PATCH', M('/reservation-areas/abc'), { user: users.manager, body: { capacity: 2 } })).body.code, 'AREA_NOT_FOUND');
    assert.equal((await call('POST', M('/reservations/abc/decision'), { user: users.manager, body: { action: 'approve' } })).body.code, 'RESERVATION_NOT_FOUND');
    assert.equal((await call('GET', M('/reservations/abc'), { user: users.manager })).body.code, 'RESERVATION_NOT_FOUND');
    assert.equal((await call('GET', M('/concierge-requests/abc'), { user: users.manager })).body.code, 'CONCIERGE_NOT_FOUND');
    assert.equal((await call('PATCH', M('/concierge-requests/abc'), { user: users.manager, body: { status: 'iptal' } })).body.code, 'CONCIERGE_NOT_FOUND');
  });

  it('liste sorguları geçersizse 400 INVALID_QUERY', async () => {
    for (const path of ['/reservations?status=bogus', '/reservations?from=2030-02-31', '/reservations?cursor=abc', '/reservations?limit=0', '/concierge-requests?status=bogus', '/concierge-requests?category=x']) {
      const res = await call('GET', M(path), { user: users.manager });
      assert.deepEqual([res.status, res.body.code], [400, 'INVALID_QUERY'], path);
    }
  });

  it('yönetim sakin adına rezervasyon / talep AÇAMAZ: bu uçlar yoktur', async () => {
    assert.equal((await call('POST', M('/reservations'), { user: users.manager, body: GOOD })).status, 404);
    assert.equal((await call('POST', M('/concierge-requests'), { user: users.manager, body: GOOD_REQ })).status, 404);
  });
});

describe('sakin uçları: doğrulama veritabanına gitmeden döner', () => {
  it('rezervasyon açma: eksik / geçersiz alanlar 400 INVALID_BODY; hiçbir sorgu gitmez', async () => {
    for (const over of [{ site_code: 'x' }, { area_id: 0 }, { date: '2030-02-31' }, { start: '25:00' }, { slots: 0 }, { idempotency_key: 'k' }, { note: 'n'.repeat(201) }]) {
      const res = await call('POST', '/app/reservations', { user: users.resident, body: { ...GOOD, ...over } });
      assert.deepEqual([res.status, res.body.code], [400, 'INVALID_BODY'], JSON.stringify(over));
    }
    assert.equal(log.length, 0);
  });

  it('konsiyerj talebi: eksik / geçersiz alanlar 400 INVALID_BODY; hiçbir sorgu gitmez', async () => {
    for (const over of [{ category: 'x' }, { category: 'diger', note: undefined }, { idempotency_key: 'k' }, { site_code: 'x' }, { requested_for: 'yarın' }]) {
      const res = await call('POST', '/app/concierge-requests', { user: users.resident, body: { ...GOOD_REQ, ...over } });
      assert.deepEqual([res.status, res.body.code], [400, 'INVALID_BODY'], JSON.stringify(over));
    }
    assert.equal(log.length, 0);
  });

  it('16 KB üstü gövde 413 BODY_TOO_LARGE', async () => {
    for (const [path, body] of [['/app/reservations', { ...GOOD, note: 'z'.repeat(20000) }], ['/app/concierge-requests', { ...GOOD_REQ, note: 'z'.repeat(20000) }]]) {
      const res = await call('POST', path, { user: users.resident, body });
      assert.deepEqual([res.status, res.body.code], [413, 'BODY_TOO_LARGE'], path);
    }
  });

  it('geçersiz kimlikler 404; liste sorguları geçersizse 400 INVALID_QUERY', async () => {
    for (const [method, path, code] of [
      ['GET', '/app/reservations/abc', 'RESERVATION_NOT_FOUND'],
      ['POST', '/app/reservations/abc/cancel', 'RESERVATION_NOT_FOUND'],
      ['POST', '/app/concierge-requests/abc/cancel', 'CONCIERGE_NOT_FOUND'],
      ['GET', '/app/reservation-areas/abc/availability', 'AREA_NOT_FOUND'],
    ]) {
      const res = await call(method, path, { user: users.resident, body: method === 'POST' ? {} : undefined });
      assert.deepEqual([res.status, res.body.code], [404, code], path);
    }
    for (const path of ['/app/reservations?scope=x', '/app/reservations?before_id=x', '/app/concierge-requests?status=bogus', '/app/reservation-areas?site_code=x']) {
      const res = await call('GET', path, { user: users.resident });
      assert.deepEqual([res.status, res.body.code], [400, 'INVALID_QUERY'], path);
    }
  });
});
