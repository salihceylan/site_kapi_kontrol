// Ziyaretçi ve Kargo uçları (DB'siz, KATI sahte veritabanı): rota zinciri + hız sınırları, yetki / modül kapısı sırası (biçim -> yetki -> site -> modül), yetki matrisi
// (STAFF yazar, kurul okur, sakin 403, başka site 403), durum geçişleri (409), daire sahipliği (404), sakin uçları (yalnız kendi dairesi, seen idempotent, summary unread),
// doğrulama hatalarının veritabanına gitmeden dönmesi, gövde boyutu. Kimlik katmanı sahte (x-test-user); gerçek HTTP, gerçek Express; yazma işlemi sahte transaction ile.
// Gerçek PostgreSQL doğrulaması (rol matrisi, IDOR, geçişler, idempotans, hesap silme, 40P01 = 0): scripts/qa_platform_pg.mjs "visitor_log".
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import { visitorLogRouter, visitorReadLimiter, visitorWriteLimiter } from '../src/modules/visitor_log_routes.js';

const SITE = 1000000001;
const OTHER_SITE = 1000000002;
const APT_A = 501;
const APT_B = 502;
const APT_OTHER = 601;
const mk = (id, role, name) => ({ id, user_code: id, userCode: id, role, full_name: name, email: `u${id}@example.com` });
const users = {
  superUser: mk(1, 'super_user', 'Süper'),
  manager: mk(20001, 'site_manager', 'Yönetici'),
  otherManager: mk(20002, 'site_manager', 'Başka Yönetici'),
  resident: mk(20004, 'apartment_owner', 'Sakin'),
  staff: mk(20005, 'individual', 'Görevli'),
  board: mk(20006, 'individual', 'Kurul'),
  outsider: mk(20008, 'individual', 'İlgisiz'),
  resident2: mk(20009, 'apartment_owner', 'İkinci Sakin'),
};
const NAMES = Object.fromEntries(Object.values(users).map((u) => [u.user_code, u.full_name]));
const SECRET = 'GIZLI-ZIYARETCI-5521';

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
    apartments: [
      { id: APT_A, site_code: SITE, block_name: 'A Blok', unit_label: 'Daire 1' },
      { id: APT_B, site_code: SITE, block_name: 'A Blok', unit_label: 'Daire 2' },
      { id: APT_OTHER, site_code: OTHER_SITE, block_name: 'B Blok', unit_label: 'Daire 9' },
    ],
    myApts: { 20004: [APT_A], 20009: [APT_B] },
    deletedUsers: new Set(),
    entries: [],
    nextId: 100,
    audits: [],
    updates: [],
    seenWrites: 0,
    tx: [],
  };
}

function seed(over = {}) {
  state.nextId += 1;
  const entry = {
    id: state.nextId, site_code: SITE, kind: 'cargo', apartment_id: APT_A, visitor_name: 'Aras Kargo', company: null, note: null, status: 'bekliyor',
    arrived_at: new Date(1760000000000 + state.nextId * 1000), completed_at: null, resident_seen_at: null, recorded_by: 20005, completed_by: null, ...over,
  };
  state.entries.push(entry);
  return entry;
}

const apartmentOf = (id) => state.apartments.find((a) => a.id === id) ?? null;
const nameOf = (code) => (code === null || code === undefined || state.deletedUsers.has(code) ? null : NAMES[code] ?? null);
function rowOf(entry) {
  const apt = apartmentOf(entry.apartment_id);
  return { ...entry, block_name: apt?.block_name ?? null, unit_label: apt?.unit_label ?? null, site_name: 'Deneme Sitesi', recorded_by_name: nameOf(entry.recorded_by), completed_by_name: nameOf(entry.completed_by) };
}
const byArrival = (a, b) => b.arrived_at - a.arrived_at || b.id - a.id;
const paramAt = (sql, pattern, params) => {
  const match = pattern.exec(sql);
  return match ? params[Number(match[1]) - 1] : undefined;
};

function managerRows(sql, params) {
  let rows = state.entries.filter((e) => e.site_code === Number(params[0]));
  const kind = paramAt(sql, /v\.kind = \$(\d+)/, params);
  if (kind !== undefined) rows = rows.filter((e) => e.kind === kind);
  const statuses = paramAt(sql, /v\.status = ANY\(\$(\d+)::TEXT\[\]\)/, params);
  if (statuses !== undefined) rows = rows.filter((e) => statuses.includes(e.status));
  const apartment = paramAt(sql, /v\.apartment_id = \$(\d+)/, params);
  if (apartment !== undefined) rows = rows.filter((e) => e.apartment_id === Number(apartment));
  return rows;
}

function residentRows(sql, params) {
  if (!state.moduleEnabled) return [];
  const own = new Set(state.myApts[Number(params[0])] ?? []);
  let rows = state.entries.filter((e) => e.apartment_id !== null && own.has(e.apartment_id));
  const site = paramAt(sql, /v\.site_code = \$(\d+)/, params);
  if (site !== undefined) rows = rows.filter((e) => e.site_code === Number(site));
  const before = paramAt(sql, /v\.id < \$(\d+)/, params);
  if (before !== undefined) rows = rows.filter((e) => e.id < Number(before));
  return rows;
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
    return ok(params[1] === 'visitor_log' ? [{ enabled: state.moduleEnabled }] : []);
  }
  if (/^SELECT v\.id, v\.site_code, v\.kind, .* FROM visitor_entries v LEFT JOIN apartments a .* WHERE v\.site_code = \$1 AND v\.id = \$2 LIMIT 1$/.test(sql)) {
    return ok(state.entries.filter((e) => e.site_code === Number(params[0]) && e.id === Number(params[1])).map(rowOf));
  }
  if (/^SELECT v\.id, v\.site_code, v\.kind, .* FROM visitor_entries v LEFT JOIN apartments a .* WHERE v\.site_code = \$1.* ORDER BY v\.arrived_at DESC, v\.id DESC LIMIT \$\d+ OFFSET \$\d+$/.test(sql)) {
    const limit = Number(params[params.length - 2]);
    const offset = Number(params[params.length - 1]);
    return ok(managerRows(sql, params).sort(byArrival).slice(offset, offset + limit).map(rowOf));
  }
  if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM visitor_entries v WHERE v\.site_code = \$1/.test(sql)) return ok([{ n: managerRows(sql, params).length }]);
  if (/^WITH my_apts AS MATERIALIZED \(.*\) SELECT v\.id, v\.site_code, s\.name AS site_name, .* ORDER BY v\.id DESC LIMIT \$\d+$/.test(sql)) {
    const limit = Number(params[params.length - 1]);
    return ok(residentRows(sql, params).sort((a, b) => b.id - a.id).slice(0, limit).map(rowOf));
  }
  if (/^WITH my_apts AS MATERIALIZED \(.*\) SELECT COUNT\(\*\)::INTEGER AS n FROM visitor_entries v INNER JOIN my_apts ma/.test(sql)) {
    return ok([{ n: residentRows(sql, params).filter((e) => e.resident_seen_at === null).length }]);
  }
  if (/^WITH my_apts AS MATERIALIZED \(.*\) UPDATE visitor_entries v SET resident_seen_at = NOW\(\) WHERE v\.id = \$2 AND v\.resident_seen_at IS NULL AND v\.apartment_id IN \(SELECT id FROM my_apts\)/.test(sql)) {
    const entry = residentRows(sql, params).find((e) => e.id === Number(params[1]) && e.resident_seen_at === null);
    if (!entry) return ok();
    entry.resident_seen_at = new Date();
    state.seenWrites += 1;
    return ok([{ id: entry.id }]);
  }
  if (/^WITH my_apts AS MATERIALIZED \(.*\) SELECT 1 FROM visitor_entries v INNER JOIN my_apts ma ON ma\.id = v\.apartment_id WHERE v\.id = \$2/.test(sql)) {
    return ok(residentRows(sql, params).filter((e) => e.id === Number(params[1])).map(() => ({ x: 1 })));
  }
  throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
}

/** Yazma transaction'ı (pool.connect): yalnız sözleşmedeki kilit sırası ve ifadeler; başka her şey hata. */
function txQuery(text, params = []) {
  const sql = norm(text);
  state.tx.push(sql);
  if (/^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT \w+|RELEASE SAVEPOINT \w+|ROLLBACK TO SAVEPOINT \w+)$/.test(sql)) return ok();
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return ok(state.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) {
    return ok(state.deletedUsers.has(Number(params[0])) ? [] : [{ user_code: Number(params[0]) }]);
  }
  if (/^SELECT id FROM apartments WHERE id = \$1 AND site_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(state.apartments.filter((a) => a.id === Number(params[0]) && a.site_code === Number(params[1])).map((a) => ({ id: a.id })));
  }
  if (/^INSERT INTO visitor_entries \(site_code, kind, apartment_id, visitor_name, company, note, status, recorded_by\) VALUES \(\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8\) RETURNING id$/.test(sql)) {
    const [siteCode, kind, apartmentId, visitorName, company, note, status, recordedBy] = params;
    const entry = seed({ site_code: Number(siteCode), kind, apartment_id: apartmentId === null ? null : Number(apartmentId), visitor_name: visitorName, company, note, status, recorded_by: Number(recordedBy) });
    return ok([{ id: String(entry.id) }]);
  }
  if (/^SELECT v\.status, v\.note FROM visitor_entries v WHERE v\.id = \$1 AND v\.site_code = \$2 FOR UPDATE OF v$/.test(sql)) {
    return ok(state.entries.filter((e) => e.id === Number(params[0]) && e.site_code === Number(params[1])).map((e) => ({ status: e.status, note: e.note })));
  }
  if (/^UPDATE visitor_entries SET updated_at = NOW\(\).* WHERE id = \$1 AND site_code = \$2$/.test(sql)) {
    const entry = state.entries.find((e) => e.id === Number(params[0]) && e.site_code === Number(params[1]));
    const status = paramAt(sql, /, status = \$(\d+)/, params);
    if (status !== undefined) entry.status = status;
    if (/completed_at = NOW\(\)/.test(sql)) entry.completed_at = new Date();
    const completedBy = paramAt(sql, /completed_by = \$(\d+)/, params);
    if (completedBy !== undefined) entry.completed_by = Number(completedBy);
    if (/, note = \$(\d+)/.test(sql)) entry.note = paramAt(sql, /, note = \$(\d+)/, params);
    state.updates.push(sql);
    return ok();
  }
  if (/^INSERT INTO audit_log/.test(sql)) {
    state.audits.push(params);
    return ok([{ id: 1 }]);
  }
  throw new Error(`BEKLENMEYEN İŞLEM SQL (sahte DB katı): ${sql.slice(0, 200)}`);
}
const allowTx = () => {
  pool.connect = async () => ({ query: async (text, params) => txQuery(text, params), release() {} });
};
// audit INSERT parametreleri (details sütunu JSON metni olarak gelir): ham metin birleşimi, çift kaçışsız arama için.
const auditText = () => state.audits.map((params) => params.map((value) => (value === null || value === undefined ? '' : String(value))).join(' ')).join('\n');

const ORIGINAL_ROUTES = visitorLogRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({ path: layer.route.path, method: Object.keys(layer.route.methods)[0], handlers: layer.route.stack.map((entry) => entry.handle) }));

let server;
let baseUrl;

before(async () => {
  for (const layer of visitorLogRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    layer.route.stack[1].handle = (_req, _res, next) => next(); // hız sınırlayıcılar ayrı testte sınanır
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(visitorLogRouter);
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

const url = (suffix = '', site = SITE) => `/manager/sites/${site}/visitor-entries${suffix}`;
const ENTRY_KEYS = ['id', 'kind', 'apartment_id', 'apartment_label', 'block_name', 'visitor_name', 'company', 'note', 'status', 'next_statuses', 'arrived_at', 'completed_at', 'resident_seen_at', 'recorded_by_name', 'completed_by_name'];

describe('rota zinciri ve hız sınırları', () => {
  it("sözleşmedeki 6 uç vardır; her biri authRequired ile BAŞLAR, ikinci halka hız sınırlayıcıdır (GET ve seen okuma, POST / PATCH yazma); /summary, /:id/seen'den ÖNCE; DELETE yok", () => {
    const routes = ORIGINAL_ROUTES.map((route) => `${route.method.toUpperCase()} ${route.path}`);
    assert.deepEqual([...routes].sort(), [
      'GET /app/visitor-entries',
      'GET /app/visitor-entries/summary',
      'GET /manager/sites/:siteCode/visitor-entries',
      'PATCH /manager/sites/:siteCode/visitor-entries/:id',
      'POST /app/visitor-entries/:id/seen',
      'POST /manager/sites/:siteCode/visitor-entries',
    ].sort());
    assert.ok(routes.indexOf('GET /app/visitor-entries/summary') < routes.indexOf('POST /app/visitor-entries/:id/seen'));
    for (const route of ORIGINAL_ROUTES) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}`);
      const expected = route.method === 'get' || route.path.endsWith('/seen') ? visitorReadLimiter : visitorWriteLimiter;
      assert.equal(route.handlers[1], expected, `${route.method} ${route.path}`);
    }
  });

  it('yazma 240/saat, okuma 1200/saat (429 + Retry-After)', () => {
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
    for (const [limiter, max, user] of [[visitorWriteLimiter, 240, 778001], [visitorReadLimiter, 1200, 778002]]) {
      const statuses = fire(limiter, user, max + 1);
      assert.equal(statuses.slice(0, max).every(([code]) => code === 200), true);
      assert.equal(statuses[max][0], 429);
      assert.ok(Number(statuses[max][1]) > 0);
    }
  });
});

describe('yönetim uçları: sıra biçim -> yetki -> site -> modül; yetki matrisi', () => {
  it('geçersiz site kodu 400 INVALID_SITE_CODE (veritabanına gitmeden)', async () => {
    const res = await call('GET', '/manager/sites/abc/visitor-entries', { user: users.manager });
    assert.deepEqual([res.status, res.body.code], [400, 'INVALID_SITE_CODE']);
    assert.equal(log.length, 0);
  });

  it('sakin / ilgisiz FORBIDDEN_ROLE (okuma ve yazma); başka sitenin yöneticisi FORBIDDEN_SITE; olmayan site (yetkili) 404 SITE_NOT_FOUND', async () => {
    assert.equal((await call('GET', url(), { user: users.resident })).body.code, 'FORBIDDEN_ROLE');
    assert.equal((await call('POST', url(), { user: users.resident, body: { kind: 'cargo', visitor_name: 'x' } })).body.code, 'FORBIDDEN_ROLE');
    assert.equal((await call('GET', url(), { user: users.outsider })).body.code, 'FORBIDDEN_ROLE');
    const other = await call('GET', url(), { user: users.otherManager });
    assert.deepEqual([other.status, other.body.code], [403, 'FORBIDDEN_SITE']);
    const otherWrite = await call('PATCH', url('/5'), { user: users.otherManager, body: { status: 'iptal' } });
    assert.deepEqual([otherWrite.status, otherWrite.body.code], [403, 'FORBIDDEN_SITE']);
    const missing = await call('GET', '/manager/sites/1999999999/visitor-entries', { user: users.superUser });
    assert.deepEqual([missing.status, missing.body.code], [404, 'SITE_NOT_FOUND']);
  });

  it('modül KAPALI: süper / yönetici / görevli / kurul 403 MODULE_DISABLED { module: visitor_log }; yetki modülden ÖNCE denetlenir', async () => {
    state.moduleEnabled = false;
    for (const user of [users.superUser, users.manager, users.staff, users.board]) {
      const res = await call('GET', url(), { user });
      assert.deepEqual([res.status, res.body.code, res.body.module], [403, 'MODULE_DISABLED', 'visitor_log']);
    }
    assert.equal((await call('GET', url(), { user: users.outsider })).body.code, 'FORBIDDEN_ROLE');
  });

  it('kurul salt okur: GET 200; POST / PATCH 403 FORBIDDEN_ROLE (iş mantığına ve işleme hiç girmeden)', async () => {
    seed();
    const list = await call('GET', url(), { user: users.board });
    assert.deepEqual([list.status, list.body.total], [200, 1]);
    const created = await call('POST', url(), { user: users.board, body: { kind: 'cargo', visitor_name: 'Aras' } });
    const patched = await call('PATCH', url('/101'), { user: users.board, body: { status: 'iptal' } });
    for (const res of [created, patched]) assert.deepEqual([res.status, res.body.code], [403, 'FORBIDDEN_ROLE']);
    assert.equal(state.tx.length, 0);
  });

  it('doğrulama hataları (yetkili kullanıcı) işlem açmadan 400 INVALID_BODY; görünmez kimlik 404; liste sorgusu geçersizse 400 INVALID_QUERY', async () => {
    for (const body of [{}, { kind: 'paket', visitor_name: 'x' }, { kind: 'cargo' }, { kind: 'cargo', visitor_name: '' }, { kind: 'cargo', visitor_name: 'x', apartment_id: 'abc' }, { kind: 'cargo', visitor_name: 'x'.repeat(121) }]) {
      const res = await call('POST', url(), { user: users.staff, body });
      assert.deepEqual([res.status, res.body.code], [400, 'INVALID_BODY'], JSON.stringify(body));
    }
    for (const body of [{}, { status: 'bitti' }, { visitor_name: 'x' }]) {
      const res = await call('PATCH', url('/101'), { user: users.manager, body });
      assert.deepEqual([res.status, res.body.code], [400, 'INVALID_BODY'], JSON.stringify(body));
    }
    const badId = await call('PATCH', url('/abc'), { user: users.manager, body: { status: 'iptal' } });
    assert.deepEqual([badId.status, badId.body.code], [404, 'VISITOR_ENTRY_NOT_FOUND']);
    const badList = await call('GET', url('?status=bogus'), { user: users.manager });
    assert.deepEqual([badList.status, badList.body.code], [400, 'INVALID_QUERY']);
    assert.equal(state.tx.length, 0);
  });

  it('8 KB üstü gövde 413 BODY_TOO_LARGE', async () => {
    const res = await call('POST', url(), { user: users.staff, body: { kind: 'cargo', visitor_name: 'x', note: 'z'.repeat(9000) } });
    assert.deepEqual([res.status, res.body.code], [413, 'BODY_TOO_LARGE']);
  });
});

describe('yönetim uçları: liste ve kayıt açma (görevli yazar)', () => {
  it('GET: Entry şekli, total, yalnız bu sitenin kayıtları, süzgeçler; silinmiş kaydeden "Silinmiş Kullanıcı"; görevli ve kurul da listeler', async () => {
    const cargo = seed();
    const visitor = seed({ kind: 'visitor', apartment_id: APT_B, status: 'iceride', visitor_name: 'Ayşe', recorded_by: 20001 });
    const done = seed({ apartment_id: null, status: 'teslim_edildi', completed_at: new Date(), completed_by: 20001 });
    seed({ site_code: OTHER_SITE, apartment_id: APT_OTHER });
    const res = await call('GET', url(), { user: users.manager });
    assert.equal(res.status, 200);
    assert.equal(res.body.total, 3);
    assert.deepEqual(res.body.items.map((item) => item.id), [done.id, visitor.id, cargo.id]);
    assert.deepEqual(Object.keys(res.body.items[2]), ENTRY_KEYS);
    assert.deepEqual([res.body.items[2].apartment_label.includes('Daire 1'), res.body.items[2].block_name, res.body.items[2].recorded_by_name, res.body.items[2].next_statuses], [true, 'A Blok', 'Görevli', ['teslim_edildi', 'iptal']]);
    assert.deepEqual([res.body.items[0].apartment_id, res.body.items[0].apartment_label, res.body.items[0].completed_by_name, res.body.items[0].next_statuses], [null, null, 'Yönetici', []]);
    assert.equal((await call('GET', url('?kind=cargo'), { user: users.manager })).body.total, 2);
    assert.equal((await call('GET', url('?status=open'), { user: users.manager })).body.total, 2);
    assert.equal((await call('GET', url('?status=closed'), { user: users.manager })).body.total, 1);
    assert.equal((await call('GET', url(`?apartment_id=${APT_B}`), { user: users.manager })).body.total, 1);
    state.deletedUsers.add(20005);
    assert.equal((await call('GET', url(), { user: users.staff })).body.items[2].recorded_by_name, 'Silinmiş Kullanıcı');
    assert.equal((await call('GET', url(), { user: users.board })).status, 200);
  });

  it('POST (görevli): kargo -> bekliyor, ziyaretçi -> iceride; 201 Entry; kaydeden görevli; daire olmadan da açılır; audit visitor_entry.created ad / firma sızdırmaz', async () => {
    allowTx();
    const cargo = await call('POST', url(), { user: users.staff, body: { kind: 'cargo', apartment_id: APT_A, visitor_name: SECRET, company: 'Aras', status: 'ayrildi' } });
    assert.equal(cargo.status, 201);
    assert.deepEqual(Object.keys(cargo.body), ENTRY_KEYS);
    assert.deepEqual([cargo.body.status, cargo.body.next_statuses, cargo.body.recorded_by_name, cargo.body.company, cargo.body.apartment_id], ['bekliyor', ['teslim_edildi', 'iptal'], 'Görevli', 'Aras', APT_A]);
    const visitor = await call('POST', url(), { user: users.manager, body: { kind: 'visitor', visitor_name: 'Ayşe Yılmaz' } });
    assert.deepEqual([visitor.status, visitor.body.status, visitor.body.apartment_id, visitor.body.apartment_label, visitor.body.recorded_by_name], [201, 'iceride', null, null, 'Yönetici']);
    assert.ok(state.tx[0] === 'BEGIN' && state.tx.includes('COMMIT') && !state.tx.includes('ROLLBACK'));
    assert.ok(state.tx.indexOf('SELECT site_code FROM sites WHERE site_code = $1 FOR KEY SHARE') < state.tx.findIndex((s) => s.startsWith('SELECT user_code FROM users')), 'kilit sırası: sites -> users');
    assert.equal(state.audits.length, 2);
    assert.ok(auditText().includes('visitor_entry.created') && !auditText().includes(SECRET) && !auditText().includes('Aras'));
  });

  it('POST: başka sitenin dairesi / olmayan daire 404 APARTMENT_NOT_FOUND (işlem geri alınır, kayıt yok); silinmiş hesap 401 ACCOUNT_DELETED', async () => {
    allowTx();
    for (const apartmentId of [APT_OTHER, 999]) {
      const res = await call('POST', url(), { user: users.staff, body: { kind: 'cargo', apartment_id: apartmentId, visitor_name: 'Aras' } });
      assert.deepEqual([res.status, res.body.code], [404, 'APARTMENT_NOT_FOUND']);
    }
    assert.ok(state.tx.includes('ROLLBACK') && state.entries.length === 0 && state.audits.length === 0);
    state.deletedUsers.add(20005);
    const gone = await call('POST', url(), { user: users.staff, body: { kind: 'cargo', visitor_name: 'Aras' } });
    assert.deepEqual([gone.status, gone.body.code], [401, 'ACCOUNT_DELETED']);
  });
});

describe('yönetim uçları: durum geçişleri (PATCH)', () => {
  it('bekliyor -> teslim_edildi (completed_at / completed_by_name); sonlanmış kayıt 409 INVALID_TRANSITION { from, to }; iceride -> teslim_edildi 409; iceride -> ayrildi 200', async () => {
    allowTx();
    const cargo = seed();
    const visitor = seed({ kind: 'visitor', status: 'iceride' });
    const delivered = await call('PATCH', url(`/${cargo.id}`), { user: users.staff, body: { status: 'teslim_edildi' } });
    assert.equal(delivered.status, 200);
    assert.deepEqual([delivered.body.status, delivered.body.next_statuses, delivered.body.completed_by_name, typeof delivered.body.completed_at], ['teslim_edildi', [], 'Görevli', 'string']);
    const reopened = await call('PATCH', url(`/${cargo.id}`), { user: users.manager, body: { status: 'iptal' } });
    assert.deepEqual([reopened.status, reopened.body.code, reopened.body.from, reopened.body.to], [409, 'INVALID_TRANSITION', 'teslim_edildi', 'iptal']);
    const wrong = await call('PATCH', url(`/${visitor.id}`), { user: users.manager, body: { status: 'teslim_edildi' } });
    assert.deepEqual([wrong.status, wrong.body.code, wrong.body.from, wrong.body.to], [409, 'INVALID_TRANSITION', 'iceride', 'teslim_edildi']);
    const left = await call('PATCH', url(`/${visitor.id}`), { user: users.manager, body: { status: 'ayrildi' } });
    assert.deepEqual([left.status, left.body.status, left.body.completed_by_name], [200, 'ayrildi', 'Yönetici']);
    assert.equal(state.updates.length, 2);
    assert.ok(state.tx.includes('ROLLBACK'), '409 işlemi geri alır');
  });

  it('aynı duruma istek değişiklik yapmaz (UPDATE / audit yok); not düzenlenir ve silinir; audit updated details from / to taşır, not metnini taşımaz', async () => {
    allowTx();
    const cargo = seed();
    const same = await call('PATCH', url(`/${cargo.id}`), { user: users.staff, body: { status: 'bekliyor' } });
    assert.deepEqual([same.status, same.body.status, state.updates.length, state.audits.length], [200, 'bekliyor', 0, 0]);
    const noted = await call('PATCH', url(`/${cargo.id}`), { user: users.staff, body: { note: SECRET } });
    assert.deepEqual([noted.status, noted.body.note, state.updates.length], [200, SECRET, 1]);
    const cleared = await call('PATCH', url(`/${cargo.id}`), { user: users.staff, body: { note: null, status: 'iptal' } });
    assert.deepEqual([cleared.status, cleared.body.note, cleared.body.status], [200, null, 'iptal']);
    assert.equal(state.audits.length, 2);
    assert.ok(auditText().includes('visitor_entry.updated') && auditText().includes('"from":"bekliyor"') && auditText().includes('"to":"iptal"') && !auditText().includes(SECRET));
  });

  it('başka sitenin kaydı / olmayan kayıt 404 VISITOR_ENTRY_NOT_FOUND (varlık sızmaz)', async () => {
    allowTx();
    const foreign = seed({ site_code: OTHER_SITE, apartment_id: APT_OTHER });
    for (const id of [foreign.id, 99999]) {
      const res = await call('PATCH', url(`/${id}`), { user: users.manager, body: { status: 'iptal' } });
      assert.deepEqual([res.status, res.body.code], [404, 'VISITOR_ENTRY_NOT_FOUND']);
    }
    assert.equal(state.updates.length, 0);
  });
});

describe('sakin uçları (/app): yalnız kendi dairesi, summary unread, seen idempotent', () => {
  it('liste: yalnız kendi dairesinin kayıtları; görevli adı YOK; site_code / site_name / unread; dairesiz kayıt kimseye gelmez; before_id sayfalama', async () => {
    const mine1 = seed();
    const mine2 = seed({ kind: 'visitor', status: 'iceride', resident_seen_at: new Date() });
    seed({ apartment_id: APT_B });
    seed({ apartment_id: null });
    const res = await call('GET', '/app/visitor-entries', { user: users.resident });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.items.map((item) => item.id), [mine2.id, mine1.id]);
    assert.equal(res.body.next_before_id, null);
    const item = res.body.items[1];
    assert.ok(!('recorded_by_name' in item) && !('completed_by_name' in item));
    assert.deepEqual([item.site_code, item.site_name, item.unread, item.next_statuses, res.body.items[0].unread], [SITE, 'Deneme Sitesi', true, [], false]);
    const page = await call('GET', '/app/visitor-entries?limit=1', { user: users.resident });
    assert.deepEqual([page.body.items.map((i) => i.id), page.body.next_before_id], [[mine2.id], mine2.id]);
    const next = await call('GET', `/app/visitor-entries?limit=1&before_id=${page.body.next_before_id}`, { user: users.resident });
    assert.deepEqual([next.body.items.map((i) => i.id), next.body.next_before_id], [[mine1.id], null]);
    assert.deepEqual((await call('GET', '/app/visitor-entries', { user: users.resident2 })).body.items.map((i) => i.apartment_id), [APT_B]);
    assert.deepEqual((await call('GET', '/app/visitor-entries', { user: users.outsider })).body.items, []);
  });

  it('summary: kendi dairesinde okunmamış sayısı; seen idempotent (ikinci çağrı yazmaz); başkasının dairesi / dairesiz / olmayan 404; geçersiz kimlik 404', async () => {
    const mine = seed();
    seed({ resident_seen_at: new Date() });
    const other = seed({ apartment_id: APT_B });
    const common = seed({ apartment_id: null });
    assert.deepEqual((await call('GET', '/app/visitor-entries/summary', { user: users.resident })).body, { unread: 1 });
    const seen = await call('POST', `/app/visitor-entries/${mine.id}/seen`, { user: users.resident });
    assert.deepEqual([seen.status, seen.body, state.seenWrites], [200, { ok: true }, 1]);
    const again = await call('POST', `/app/visitor-entries/${mine.id}/seen`, { user: users.resident });
    assert.deepEqual([again.status, again.body, state.seenWrites], [200, { ok: true }, 1]);
    assert.deepEqual((await call('GET', '/app/visitor-entries/summary', { user: users.resident })).body, { unread: 0 });
    for (const id of [other.id, common.id, 99999, 'abc']) {
      const res = await call('POST', `/app/visitor-entries/${id}/seen`, { user: users.resident });
      assert.deepEqual([res.status, res.body.code], [404, 'VISITOR_ENTRY_NOT_FOUND'], String(id));
    }
    assert.equal(state.seenWrites, 1);
    assert.deepEqual((await call('GET', '/app/visitor-entries/summary', { user: users.resident2 })).body, { unread: 1 });
  });

  it('site_code verilmiş ve modül kapalı -> 403 MODULE_DISABLED; site_code yoksa kapalı sitenin kayıtları gelmez; liste sorgusu geçersizse 400', async () => {
    seed();
    state.moduleEnabled = false;
    const withSite = await call('GET', `/app/visitor-entries?site_code=${SITE}`, { user: users.resident });
    assert.deepEqual([withSite.status, withSite.body.code, withSite.body.module], [403, 'MODULE_DISABLED', 'visitor_log']);
    assert.deepEqual((await call('GET', '/app/visitor-entries', { user: users.resident })).body.items, []);
    assert.deepEqual((await call('GET', '/app/visitor-entries/summary', { user: users.resident })).body, { unread: 0 });
    state.moduleEnabled = true;
    const bad = await call('GET', '/app/visitor-entries?limit=0', { user: users.resident });
    assert.deepEqual([bad.status, bad.body.code], [400, 'INVALID_QUERY']);
  });
});
