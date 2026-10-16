// Duyuru ve Bildirim (Faz 3a) uçları (DB'siz): rota zinciri, hız sınırları, yetki matrisi (yönetici / süper / kurul / görevli / sakin / başka site),
// kurul yanıtı temizliği, hata biçimleri, yayın sonrası e-posta tetiği (yanıtı BEKLETMEZ). Kimlik katmanı sahte (x-test-user);
// pool.query / pool.connect KATI sahte veritabanına bağlanır.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import {
  announcementReadLimiter,
  announcementRouteHooks,
  announcementRouter,
  announcementSummaryLimiter,
  announcementWriteLimiter,
} from '../src/modules/announcement_routes.js';
import { SYNC_STEPS } from '../src/modules/people_sync_sql.js';
import { resetPeopleSyncThrottle } from '../src/modules/people_sync.js';

process.env.PEOPLE_SYNC_MIN_INTERVAL_MS = '0';
process.env.JWT_SECRET ||= 'unit-test-secret-0123456789abcdef'; // e-posta adres özeti tuzu sırdan türetilir

const SITE_1 = 1000000001;
const SITE_2 = 1000000002;
const mk = (id, role, name) => ({ id, user_code: id, userCode: id, role, full_name: name, email: `u${id}@example.com` });
const users = {
  superUser: mk(1, 'super_user', 'Süper Kullanıcı'),
  mgrA: mk(20001, 'site_manager', 'Ayşe Yönetici'),
  mgrB: mk(20002, 'site_manager', 'Bora Yönetici'),
  resident: mk(20004, 'apartment_owner', 'Deniz Sakin'),
  staff: mk(20005, 'individual', 'Ece Görevli'),
  board: mk(20006, 'individual', 'Fatma Kurul'),
  boardB: mk(20007, 'individual', 'Gül Başka Kurul'),
  outsider: mk(20008, 'individual', 'Hakan İlgisiz'),
};

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });

let state;
let handlers;

function makeState() {
  return {
    sites: new Set([SITE_1, SITE_2]),
    managerLinks: [
      { site_code: SITE_1, user_code: 20001 },
      { site_code: SITE_2, user_code: 20002 },
    ],
    memberships: [
      { site_code: SITE_1, user_code: 20005, role: 'STAFF', is_active: true },
      { site_code: SITE_1, user_code: 20004, role: 'RESIDENT', is_active: true },
      { site_code: SITE_1, user_code: 20006, role: 'BOARD_MEMBER', is_active: true },
      { site_code: SITE_2, user_code: 20007, role: 'BOARD_MEMBER', is_active: true },
    ],
    log: [],
  };
}

function access(sql, params) {
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(state.managerLinks.filter((l) => l.site_code === Number(params[0]) && l.user_code === Number(params[1])).map(() => ({ x: 1 })));
  }
  if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) {
    return ok([]);
  }
  if (/^SELECT EXISTS \( SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'BOARD_MEMBER'/.test(sql)) {
    const [site, user] = params.map(Number);
    const here = state.memberships.filter((m) => m.site_code === site && m.user_code === user && m.is_active);
    const otherRole =
      state.managerLinks.some((l) => l.user_code === user) ||
      state.memberships.some((m) => m.user_code === user && m.is_active && ['SITE_OWNER', 'SITE_ADMIN', 'BOARD_MEMBER'].includes(m.role));
    return ok([{ is_board_here: here.some((m) => m.role === 'BOARD_MEMBER'), is_member_here: here.length > 0, has_other_role: otherRole }]);
  }
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/.test(sql)) {
    return ok(state.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  }
  return null;
}

const annRow = (overrides = {}) => ({
  id: '41',
  title: 'Su kesintisi',
  body: 'Yarın su yok.',
  body_head: 'Yarın su yok.',
  body_length: '13',
  importance: 'normal',
  status: 'published',
  target_type: 'site',
  target_block_ids: [],
  target_apartment_ids: [],
  send_email: false,
  publish_at: null,
  published_at: new Date('2026-10-16T08:00:00.000Z'),
  edited_at: null,
  recipient_count: 3,
  read_count: 1,
  created_at: new Date('2026-10-15T08:00:00.000Z'),
  created_by_name: 'Ayşe Yönetici',
  ...overrides,
});

const STEP_SQLS = new Set(SYNC_STEPS.map((step) => norm(step.sql)));

function installFakeDb() {
  const run = async (text, params, client) => {
    const sql = norm(text);
    state.log.push({ sql, params: params ?? [], client });
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return typeof fn === 'function' ? fn(sql, params ?? []) : fn;
    }
    const a = access(sql, params ?? []);
    if (a) return a;
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || /^SELECT pg_advisory_xact_lock/.test(sql) || /^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /.test(sql) || /^INSERT INTO audit_log/.test(sql)) return ok();
    if (STEP_SQLS.has(sql)) return ok();
    // kötüye kullanım sınırları ve çift POST koruması: varsayılan "izin verilir" (sınırları sınayan testler kendi işleyicisini ekler)
    if (/^SELECT COUNT\(\*\)::INTEGER AS total, COUNT\(\*\) FILTER \(WHERE importance = 'urgent' AND send_email\)/.test(sql)) return ok([{ total: 0, urgent_email: 0 }]);
    if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM announcements WHERE email_requested_by = \$1/.test(sql)) return ok([{ n: 0 }]);
    if (/^SELECT 1 FROM announcements WHERE site_code = \$1 AND created_by = \$2 AND status = 'published'/.test(sql)) return ok();
    if (/^WITH audience AS .* SELECT COUNT\(DISTINCT h\.email_hash\)/.test(sql)) return ok([{ n: 10 }]);
    if (/^SELECT importance, target_type, target_block_ids, target_apartment_ids, send_email FROM announcements WHERE id = \$1 AND site_code = \$2 AND status IN/.test(sql)) return ok();
    if (/^SELECT pg_try_advisory_xact_lock/.test(sql)) return ok([{ locked: true }]);
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 220)}`);
  };
  pool.query = async (text, params) => run(text, params, false);
  pool.connect = async () => ({ query: (text, params) => run(text, params, true), release() {} });
}

const ORIGINAL_ROUTES = announcementRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({
    path: layer.route.path,
    method: Object.keys(layer.route.methods)[0],
    handlers: layer.route.stack.map((entry) => entry.handle),
  }));

let server;
let baseUrl;

before(async () => {
  for (const layer of announcementRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    // hız sınırlayıcılar rota testlerinde atlanır (ayrı testte doğrudan sınanır)
    if (layer.route.stack.length > 2) {
      layer.route.stack[1].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json());
  app.use(announcementRouter);
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

let kickCalls;
let savedKick;

beforeEach(() => {
  state = makeState();
  handlers = [];
  installFakeDb();
  resetPeopleSyncThrottle();
  kickCalls = 0;
  savedKick = announcementRouteHooks.kickEmailQueue;
  announcementRouteHooks.kickEmailQueue = () => {
    kickCalls += 1;
  };
  mock.method(console, 'error', () => {});
  mock.method(console, 'log', () => {});
});

afterEach(() => {
  announcementRouteHooks.kickEmailQueue = savedKick;
  mock.restoreAll();
  announcementReadLimiter.reset();
  announcementWriteLimiter.reset();
  announcementSummaryLimiter.reset();
});

async function call(method, path, { user = users.mgrA, body } = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: { 'content-type': 'application/json', 'x-test-user': encodeURIComponent(JSON.stringify(user)) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await response.json();
  } catch (_e) {
    // gövdesiz
  }
  return { status: response.status, body: json };
}

const base = (site = SITE_1) => `/manager/sites/${site}/announcements`;

// --- yanıt işleyicileri -------------------------------------------------------------------------------------
const SITE_SHARE = /^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/;
const DETAIL = /^SELECT a\.id, a\.title, a\.body, a\.importance, a\.status, a\.target_type, a\.target_block_ids, a\.target_apartment_ids, a\.send_email, .* WHERE a\.id = \$1 AND a\.site_code = \$2 LIMIT 1$/;
const DETAIL_STATS = /^SELECT email_status, COUNT\(\*\)::INTEGER AS n, COUNT\(\*\) FILTER/;
const LIST_COUNT = /^SELECT COUNT\(\*\)::INTEGER AS total FROM announcements a/;
const LIST_PAGE = /^SELECT a\.id, a\.title, left\(a\.body, 1200\)/;
const INSERT_ANN = /^INSERT INTO announcements \(/;
const CLAIM = /^UPDATE announcements SET status = 'published'/;
const FINAL = /^UPDATE announcements SET recipient_count = \$2, published_at = clock_timestamp\(\)/;
const SNAPSHOT = /^WITH audience AS .* INSERT INTO announcement_recipients/;

function listHandlers() {
  return [
    [LIST_COUNT, () => ok([{ total: 1 }])],
    [LIST_PAGE, () => ok([annRow()])],
  ];
}

function publishFlow({ sendEmail = false, total = 3, pending = 0 } = {}) {
  return [
    [SITE_SHARE, () => ok([{ site_code: SITE_1 }])],
    [INSERT_ANN, () => ok([{ id: '41' }])],
    [CLAIM, () => ok([{ importance: 'normal', target_type: 'site', target_block_ids: [], target_apartment_ids: [], send_email: sendEmail }])],
    [/^SELECT COUNT\(\*\)::INTEGER AS used/, () => ok([{ used: 0 }])],
    [/FROM announcement_recipients r INNER JOIN announcements a ON a\.id = r\.announcement_id WHERE a\.site_code = \$1/, () => ok([{ used: 0 }])],
    [SNAPSHOT, () => ok([], total)],
    [/^SELECT email_status, COUNT\(\*\)::INTEGER AS n FROM announcement_recipients WHERE announcement_id = \$1 GROUP BY email_status$/, () => ok(pending > 0 ? [{ email_status: 'pending', n: pending }] : [])],
    [FINAL, () => ok([], 1)],
    [DETAIL, () => ok([annRow({ send_email: sendEmail })])],
    [DETAIL_STATS, () => ok(pending > 0 ? [{ email_status: 'pending', n: pending, read_n: 0 }] : [{ email_status: 'none', n: total, read_n: 0 }])],
  ];
}

// ---------------------------------------------------------------------------
// Rota zinciri ve hız sınırları
// ---------------------------------------------------------------------------

describe('duyuru rotaları: zincir', () => {
  it('16 rota; hepsi authRequired ile başlar; yazma uçları 120/saat, okuma 1200/saat, özet 600/saat sınırlayıcı ile', () => {
    const summary = ORIGINAL_ROUTES.map((r) => `${r.method.toUpperCase()} ${r.path}`).sort();
    assert.deepEqual(summary, [
      'DELETE /manager/sites/:siteCode/announcements/:id',
      'GET /app/announcements',
      'GET /app/announcements/:id',
      'GET /app/notification-preferences',
      'GET /app/notifications/summary',
      'GET /manager/sites/:siteCode/announcements',
      'GET /manager/sites/:siteCode/announcements/:id',
      'GET /manager/sites/:siteCode/announcements/:id/recipients',
      'PATCH /manager/sites/:siteCode/announcements/:id',
      'POST /app/announcements/:id/read',
      'POST /app/announcements/read-all',
      'POST /manager/sites/:siteCode/announcements',
      'POST /manager/sites/:siteCode/announcements/:id/publish',
      'POST /manager/sites/:siteCode/announcements/:id/withdraw',
      'POST /manager/sites/:siteCode/announcements/preview-audience',
      'PUT /app/notification-preferences',
    ]);
    const expectedLimiter = (route) => {
      if (route.path === '/app/notifications/summary') return announcementSummaryLimiter;
      if (route.method === 'get' || route.path.endsWith('/preview-audience')) return announcementReadLimiter;
      return announcementWriteLimiter;
    };
    for (const route of ORIGINAL_ROUTES) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}: authRequired ilk`);
      assert.equal(route.handlers[1], expectedLimiter(route), `${route.method} ${route.path}: hız sınırlayıcı`);
    }
  });

  it('hız sınırları: yazma 120/saat, okuma 1200/saat, özet 1500/saat (kullanıcı başına); 429 + Retry-After', () => {
    const run = (limiter, code) => {
      const res = {
        statusCode: 200,
        headers: {},
        setHeader(name, value) {
          this.headers[name] = value;
        },
        status(c) {
          this.statusCode = c;
          return this;
        },
        json(body) {
          this.body = body;
          return this;
        },
      };
      let passed = false;
      limiter({ authUser: { id: code }, ip: '1.2.3.4', path: '/x' }, res, () => {
        passed = true;
      });
      return { res, passed };
    };
    for (const [limiter, max] of [[announcementWriteLimiter, 120], [announcementSummaryLimiter, 1500], [announcementReadLimiter, 1200]]) {
      for (let i = 0; i < max; i += 1) assert.equal(run(limiter, 7).passed, true, `${max}/${i}`);
      const blocked = run(limiter, 7);
      assert.equal(blocked.res.statusCode, 429, `${max}`);
      assert.ok(Number(blocked.res.headers['Retry-After']) > 0);
      assert.ok(blocked.res.body.retry_after_seconds > 0);
      assert.equal(run(limiter, 8).passed, true, 'başka kullanıcı etkilenmez');
    }
  });

  it('D15 özet sınırı: kullanıcı başına 1500/saat (paylaşılan dahili daire hesabı: 4 cihaz x 180 + sekme yenilemeleri), IP başına 40000/saat (apartman / CGNAT NAT\'ı); eski 600 / 12000 değerleri aşılabilir', () => {
    const run = (limiter, code, ip = '1.2.3.4') => {
      const res = {
        statusCode: 200,
        headers: {},
        setHeader() {},
        status(c) {
          this.statusCode = c;
          return this;
        },
        json() {
          return this;
        },
      };
      let passed = false;
      limiter({ authUser: { id: code }, ip, path: '/x' }, res, () => {
        passed = true;
      });
      return { res, passed };
    };
    // eski sınırlar: tek hesap 601., IP başına 12001. istek artık 429 DEĞİL
    for (let i = 0; i < 1200; i += 1) assert.equal(run(announcementSummaryLimiter, 7).passed, true, `kullanıcı ${i}`);
    assert.equal(run(announcementSummaryLimiter, 7).passed, true, '1201. istek (eski sınır 600 aşıldı) geçer');
    announcementSummaryLimiter.reset();
    // 200 hesap x 180 istek = 36000 (aynı NAT arkasında): hiçbiri 429 almaz
    for (let user = 1; user <= 200; user += 1) {
      for (let i = 0; i < 180; i += 1) assert.equal(run(announcementSummaryLimiter, user, '9.9.9.9').passed, true, `hesap ${user}/${i}`);
    }
    // IP sınırı yine vardır: 40000. isteğe kadar geçer, sonrası 429
    let sent = 36000;
    let last = true;
    for (let user = 201; sent < 40000; user += 1) {
      for (let i = 0; i < 180 && sent < 40000; i += 1) {
        last = run(announcementSummaryLimiter, user, '9.9.9.9').passed;
        sent += 1;
      }
    }
    assert.equal(last, true, '40000. istek geçer');
    assert.equal(run(announcementSummaryLimiter, 9999, '9.9.9.9').res.statusCode, 429, '40001. istek IP sınırına takılır');
    assert.equal(run(announcementSummaryLimiter, 9999, '8.8.8.8').passed, true, 'başka IP etkilenmez');
  });
});

// ---------------------------------------------------------------------------
// Yetki matrisi
// ---------------------------------------------------------------------------

describe('duyuru uçları: yetki matrisi', () => {
  const readPaths = [
    ['GET', base(), undefined],
    ['GET', `${base()}/41`, undefined],
  ];
  const writePaths = [
    ['POST', base(), { title: 'x', body: 'y', target: { type: 'site' } }],
    ['PATCH', `${base()}/41`, { title: 'x' }],
    ['POST', `${base()}/41/publish`, undefined],
    ['POST', `${base()}/41/withdraw`, undefined],
    ['DELETE', `${base()}/41`, undefined],
  ];
  const noBoardPaths = [
    ['GET', `${base()}/41/recipients`, undefined],
    ['POST', `${base()}/preview-audience`, { target: { type: 'site' } }],
  ];

  it('okuma (liste, ayrıntı): süper, yönetici ve KURUL 200', async () => {
    handlers.push(...listHandlers(), [DETAIL, () => ok([annRow()])], [DETAIL_STATS, () => ok()]);
    for (const user of [users.superUser, users.mgrA, users.board]) {
      for (const [method, path] of readPaths) {
        const res = await call(method, path, { user });
        assert.equal(res.status, 200, `${user.full_name} ${path}`);
      }
    }
  });

  it('yazma uçları: KURUL 403 FORBIDDEN_ROLE (yalnız okur); hiçbir yazma sorgusu çalışmaz', async () => {
    for (const [method, path, body] of writePaths) {
      const res = await call(method, path, { user: users.board, body });
      assert.equal(res.status, 403, `${method} ${path}`);
      assert.equal(res.body.code, 'FORBIDDEN_ROLE');
    }
    assert.equal(state.log.some((q) => /^(INSERT|UPDATE|DELETE|BEGIN)/.test(q.sql)), false);
  });

  it('alıcı listesi ve kitle önizlemesi: KURUL 403 FORBIDDEN_ROLE (alıcı adlarını göremez)', async () => {
    for (const [method, path, body] of noBoardPaths) {
      const res = await call(method, path, { user: users.board, body });
      assert.equal(res.status, 403, `${method} ${path}`);
      assert.equal(res.body.code, 'FORBIDDEN_ROLE');
    }
    assert.equal(state.log.some((q) => /announcement_recipients|site_people/.test(q.sql)), false, 'kurul için alıcı verisi okunmaz');
  });

  it('STAFF, sakin ve ilgisiz kullanıcı: tüm yönetici uçları 403 FORBIDDEN_ROLE', async () => {
    for (const user of [users.staff, users.resident, users.outsider]) {
      for (const [method, path, body] of [...readPaths, ...writePaths, ...noBoardPaths]) {
        const res = await call(method, path, { user, body });
        assert.equal(res.status, 403, `${user.full_name} ${method} ${path}`);
        assert.equal(res.body.code, 'FORBIDDEN_ROLE');
      }
    }
  });

  it('başka sitenin yöneticisi ve kurul üyesi: 403 FORBIDDEN_SITE', async () => {
    for (const user of [users.mgrB, users.boardB]) {
      for (const [method, path, body] of [...readPaths, ...writePaths, ...noBoardPaths]) {
        const res = await call(method, path, { user, body });
        assert.equal(res.status, 403, `${user.full_name} ${method} ${path}`);
        assert.equal(res.body.code, 'FORBIDDEN_SITE');
      }
    }
  });

  it('geçersiz site kodu 400 INVALID_SITE_CODE; olmayan site (süper) 404 SITE_NOT_FOUND', async () => {
    assert.equal((await call('GET', '/manager/sites/abc/announcements', { user: users.superUser })).body.code, 'INVALID_SITE_CODE');
    const missing = await call('GET', '/manager/sites/1999999998/announcements', { user: users.superUser });
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'SITE_NOT_FOUND');
  });
});

// ---------------------------------------------------------------------------
// Kurul yanıtı temizliği
// ---------------------------------------------------------------------------

describe('kurul üyesi yanıtları', () => {
  it('liste ve ayrıntı: created_by_name null, kullanıcı kodu alanları (created_by, user_code, actor_user_code) YOK; yöneticiye ad görünür', async () => {
    handlers.push(...listHandlers(), [DETAIL, () => ok([{ ...annRow(), created_by: 20001 }])], [DETAIL_STATS, () => ok([{ email_status: 'none', n: 3, read_n: 1 }])]);
    for (const path of [base(), `${base()}/41`]) {
      const asBoard = await call('GET', path, { user: users.board });
      const asManager = await call('GET', path, { user: users.mgrA });
      const dump = JSON.stringify(asBoard.body);
      assert.doesNotMatch(dump, /"(created_by|user_code|actor_user_code)"/);
      assert.ok(!dump.includes('Ayşe Yönetici'), 'yönetici adı kurula sızmaz');
      assert.ok(JSON.stringify(asManager.body).includes('Ayşe Yönetici'));
      const board = path.endsWith('/41') ? asBoard.body : asBoard.body.items[0];
      assert.equal(board.created_by_name, null, 'anahtar kalır (istemci modeli bozulmaz), değer null');
      assert.equal(board.title, 'Su kesintisi');
      assert.equal(board.recipient_count, 3);
    }
  });

  it('D6 küçük hedef (1-4 alıcı): kurul için okunma / okunmamış / e-posta sayıları NULL (anahtarlar kalır), recipients sayısı kalır; yönetici gerçek sayıları görür; 5+ alıcıda kurul da görür', async () => {
    const stats = [{ email_status: 'sent', n: 1, read_n: 1 }, { email_status: 'no_address', n: 1, read_n: 0 }];
    handlers.push(...listHandlers(), [DETAIL, () => ok([annRow({ recipient_count: 2 })])], [DETAIL_STATS, () => ok(stats)]);
    handlers.unshift([LIST_PAGE, () => ok([annRow({ recipient_count: 2, read_count: 1 })])]);
    const asBoard = await call('GET', `${base()}/41`, { user: users.board });
    const asManager = await call('GET', `${base()}/41`, { user: users.mgrA });
    assert.equal(asBoard.status, 200);
    assert.equal(asBoard.body.stats.recipients, 2);
    assert.equal(asBoard.body.stats.read, null);
    assert.equal(asBoard.body.stats.unread, null);
    assert.deepEqual(Object.keys(asBoard.body.stats.email).sort(), Object.keys(asManager.body.stats.email).sort(), 'anahtarlar kalır');
    assert.ok(Object.values(asBoard.body.stats.email).every((value) => value === null));
    assert.equal(asBoard.body.read_count, null);
    assert.equal(asManager.body.stats.read, 1);
    assert.equal(asManager.body.stats.email.sent, 1);
    const listBoard = await call('GET', base(), { user: users.board });
    assert.equal(listBoard.body.items[0].read_count, null);
    assert.equal(listBoard.body.items[0].recipient_count, 2);
    assert.equal((await call('GET', base(), { user: users.mgrA })).body.items[0].read_count, 1);
    handlers.length = 0;
    const fiveStats = [{ email_status: 'sent', n: 3, read_n: 1 }, { email_status: 'no_address', n: 2, read_n: 0 }];
    handlers.push([DETAIL, () => ok([annRow({ recipient_count: 5 })])], [DETAIL_STATS, () => ok(fiveStats)]);
    assert.equal((await call('GET', `${base()}/41`, { user: users.board })).body.stats.read, 1);
  });

  it('E7 küçük hedef kararı CANLI alıcı satırı sayısıyla da verilir: yayın anında 6 alıcı, kişi silinince 3 satır kaldıysa kurul sayıları NULL görür (ayrıntı ve liste); canlı sayı 0 ise sayılar sıfırdır, null değil; yanıta canlı sayı alanı GİRMEZ', async () => {
    const threeStats = [{ email_status: 'sent', n: 2, read_n: 1 }, { email_status: 'no_address', n: 1, read_n: 0 }];
    handlers.push(
      [DETAIL, () => ok([annRow({ recipient_count: 6 })])],
      [DETAIL_STATS, () => ok(threeStats)],
      [LIST_COUNT, () => ok([{ total: 2 }])],
      [LIST_PAGE, () => ok([annRow({ id: '41', recipient_count: 6, read_count: 1, live_count: 3 }), annRow({ id: '42', recipient_count: 6, read_count: 4, live_count: 6 })])],
    );
    const detailBoard = (await call('GET', `${base()}/41`, { user: users.board })).body;
    assert.equal(detailBoard.recipient_count, 6, 'yayın anındaki sayı aynen');
    assert.equal(detailBoard.stats.recipients, 3);
    assert.equal(detailBoard.stats.read, null);
    assert.equal(detailBoard.stats.unread, null);
    assert.equal(detailBoard.read_count, null);
    assert.ok(Object.values(detailBoard.stats.email).every((value) => value === null));
    const detailManager = (await call('GET', `${base()}/41`, { user: users.mgrA })).body;
    assert.equal(detailManager.stats.read, 1);
    assert.equal(Object.hasOwn(detailManager, 'live_recipient_count'), false, 'canlı sayı yanıta girmez');
    assert.equal(JSON.stringify(detailManager).includes('live_'), false);
    const list = (await call('GET', base(), { user: users.board })).body.items;
    assert.equal(list[0].read_count, null, 'canlı 3: küçük hedef');
    assert.equal(list[1].read_count, 4, 'canlı 6: kurul görür');
    assert.equal(JSON.stringify(list).includes('live_'), false);
    // tüm alıcı satırları silinmiş: kişisel veri kalmadı, sayılar sıfır
    handlers.unshift([DETAIL_STATS, () => ok([])]);
    const empty = (await call('GET', `${base()}/41`, { user: users.board })).body;
    assert.equal(empty.stats.recipients, 0);
    assert.equal(empty.stats.read, 0);
  });
});

// ---------------------------------------------------------------------------
// Hata biçimleri ve durum kodları
// ---------------------------------------------------------------------------

describe('hata biçimleri', () => {
  it('geçersiz gövde 400 INVALID_BODY ({error, code}); mesaj Türkçe etiketli; DB\'ye dokunulmaz', async () => {
    const res = await call('POST', base(), { body: { title: '', body: 'x', target: { type: 'site' } } });
    assert.equal(res.status, 400);
    assert.equal(res.body.code, 'INVALID_BODY');
    assert.match(res.body.error, /Başlık/);
    assert.doesNotMatch(res.body.error, /title|_/);
    assert.equal(state.log.some((q) => /^BEGIN/.test(q.sql)), false);
  });

  it('olmayan / başka sitenin duyurusu 404 ANNOUNCEMENT_NOT_FOUND; geçersiz kimlik de 404', async () => {
    handlers.push([DETAIL, () => ok()]);
    const missing = await call('GET', `${base()}/41`);
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'ANNOUNCEMENT_NOT_FOUND');
    assert.deepEqual(state.log.find((q) => DETAIL.test(q.sql)).params, [41, SITE_1], 'sorgu site kapsamlı');
    assert.equal((await call('GET', `${base()}/abc`)).body.code, 'ANNOUNCEMENT_NOT_FOUND');
  });

  it('INVALID_STATE 409 ve NO_RECIPIENTS 409 hata kodlarıyla döner', async () => {
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE_1 }])], [CLAIM, () => ok()], [/^SELECT status FROM announcements/, () => ok([{ status: 'published' }])]);
    const res = await call('POST', `${base()}/41/publish`);
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'INVALID_STATE');
    handlers.length = 0;
    handlers.push(...publishFlow({ total: 0 }));
    const empty = await call('POST', base(), { body: { title: 'x', body: 'y', target: { type: 'site' }, publish: 'now' } });
    assert.equal(empty.status, 409);
    assert.equal(empty.body.code, 'NO_RECIPIENTS');
  });

  it('yeni kötüye kullanım hata kodları: DUPLICATE_ANNOUNCEMENT / ANNOUNCEMENT_DAILY_LIMIT / ANNOUNCEMENT_HOURLY_LIMIT 409, ANNOUNCEMENT_EMAIL_LIMIT 400 ({error, code}, Türkçe mesaj, errorId YOK)', async () => {
    const create = (extra = {}) => call('POST', base(), { body: { title: 'x', body: 'y', target: { type: 'site' }, publish: 'now', ...extra } });
    handlers.push(...publishFlow(), [/^SELECT 1 FROM announcements WHERE site_code = \$1 AND created_by = \$2 AND status = 'published'/, () => ok([{ x: 1 }])]);
    const duplicate = await create();
    assert.deepEqual([duplicate.status, duplicate.body.code], [409, 'DUPLICATE_ANNOUNCEMENT']);
    assert.match(duplicate.body.error, /az önce/);
    handlers.length = 0;
    handlers.push(...publishFlow(), [/^SELECT COUNT\(\*\)::INTEGER AS total, COUNT\(\*\) FILTER/, () => ok([{ total: 30, urgent_email: 0 }])]);
    const daily = await create();
    assert.deepEqual([daily.status, daily.body.code], [409, 'ANNOUNCEMENT_DAILY_LIMIT']);
    assert.match(daily.body.error, /günlük/);
    handlers.length = 0;
    handlers.push(...publishFlow({ sendEmail: true, pending: 2 }), [/^SELECT COUNT\(\*\)::INTEGER AS n FROM announcements WHERE email_requested_by = \$1/, () => ok([{ n: 10 }])]);
    const hourly = await create({ send_email: true });
    assert.deepEqual([hourly.status, hourly.body.code], [409, 'ANNOUNCEMENT_HOURLY_LIMIT']);
    handlers.length = 0;
    handlers.push(...publishFlow({ sendEmail: true }), [/^WITH audience AS .* SELECT COUNT\(DISTINCT h\.email_hash\)/, () => ok([{ n: 1001 }])]);
    const tooMany = await create({ send_email: true });
    assert.deepEqual([tooMany.status, tooMany.body.code], [400, 'ANNOUNCEMENT_EMAIL_LIMIT']);
    for (const res of [duplicate, daily, hourly, tooMany]) {
      assert.equal(res.body.errorId, undefined);
      assert.doesNotMatch(res.body.error, /[a-z]+_[a-z_]+/);
    }
  });

  it('beklenmeyen DB hatası 500: genel mesaj + errorId; DB ayrıntısı istemciye SIZMAZ', async () => {
    handlers.push([LIST_COUNT, () => {
      throw new Error('relation "announcements" does not exist: secret-detail');
    }]);
    const res = await call('GET', base());
    assert.equal(res.status, 500);
    assert.match(res.body.errorId, /^[0-9a-f]+$/);
    assert.equal(res.body.error, 'Duyurular yüklenemedi.');
    assert.ok(!JSON.stringify(res.body).includes('secret-detail'));
  });

  it('oluşturma 201; PATCH 200; sil { ok: true }', async () => {
    handlers.push(...publishFlow());
    const created = await call('POST', base(), { body: { title: 'x', body: 'y', target: { type: 'site' } } });
    assert.equal(created.status, 201);
    assert.equal(created.body.id, 41);
    handlers.length = 0;
    handlers.push([SITE_SHARE, () => ok([{ site_code: SITE_1 }])], [/^DELETE FROM announcements/, () => ok([{ status: 'draft' }])]);
    const removed = await call('DELETE', `${base()}/41`);
    assert.deepEqual([removed.status, removed.body], [200, { ok: true }]);
  });
});

// ---------------------------------------------------------------------------
// Yayın sonrası e-posta tetiği
// ---------------------------------------------------------------------------

describe('yayın sonrası e-posta kuyruğu tetiği', () => {
  const body = (extra = {}) => ({ title: 'x', body: 'y', target: { type: 'site' }, publish: 'now', send_email: true, ...extra });

  it('yayınlanmış + e-posta istenmiş + bekleyen adres varsa kuyruk TETİKLENİR (bir kez)', async () => {
    handlers.push(...publishFlow({ sendEmail: true, total: 5, pending: 3 }));
    const res = await call('POST', base(), { body: body() });
    assert.equal(res.status, 201);
    assert.equal(res.body.stats.email.pending, 3);
    assert.equal(kickCalls, 1);
  });

  it('e-posta istenmediyse ya da bekleyen adres yoksa TETİKLENMEZ', async () => {
    handlers.push(...publishFlow({ sendEmail: false, total: 5 }));
    await call('POST', base(), { body: body({ send_email: false }) });
    assert.equal(kickCalls, 0);
    handlers.length = 0;
    handlers.push(...publishFlow({ sendEmail: true, total: 5, pending: 0 }));
    await call('POST', base(), { body: body() });
    assert.equal(kickCalls, 0);
  });

  it('tetik hata fırlatsa / reddetse bile yanıt 201; asla bitmeyen tetik yanıtı BEKLETMEZ', async () => {
    handlers.push(...publishFlow({ sendEmail: true, total: 5, pending: 2 }));
    announcementRouteHooks.kickEmailQueue = () => {
      throw new Error('tetik hatası');
    };
    assert.equal((await call('POST', base(), { body: body() })).status, 201);
    announcementRouteHooks.kickEmailQueue = () => Promise.reject(new Error('tetik reddedildi'));
    assert.equal((await call('POST', base(), { body: body() })).status, 201);
    announcementRouteHooks.kickEmailQueue = () => new Promise(() => {});
    const started = Date.now();
    assert.equal((await call('POST', base(), { body: body() })).status, 201);
    assert.ok(Date.now() - started < 1500, 'yanıt kuyruğu beklemedi');
  });

  it('taslak oluşturma kuyruğu tetiklemez', async () => {
    handlers.push(...publishFlow({ sendEmail: true, total: 5, pending: 2 }));
    handlers.unshift([DETAIL, () => ok([annRow({ status: 'draft', send_email: true })])]);
    await call('POST', base(), { body: body({ publish: 'draft' }) });
    assert.equal(kickCalls, 0);
  });
});

// ---------------------------------------------------------------------------
// Sakin uçları
// ---------------------------------------------------------------------------

describe('sakin uçları (kimliği doğrulanmış her kullanıcı)', () => {
  it('liste / ayrıntı / okundu / hepsini okundu / özet / tercihler: çağıranın user_code\'u ile çalışır (rol kısıtı yok)', async () => {
    handlers.push(
      [/^SELECT a\.id, a\.site_code, s\.name AS site_name, a\.title, left/, () => ok([{ id: '2', site_code: String(SITE_1), site_name: 'Gül', title: 'T', body_head: 'B', body_length: '1', importance: 'normal', published_at: new Date('2026-10-16T08:00:00.000Z'), edited_at: null, read_at: null }])],
      [/^SELECT a\.id, a\.site_code, s\.name AS site_name, a\.title, a\.body,/, () => ok([{ id: '2', site_code: String(SITE_1), site_name: 'Gül', title: 'T', body: 'B', importance: 'normal', published_at: new Date('2026-10-16T08:00:00.000Z'), edited_at: null, read_at: null }])],
      [/^UPDATE announcement_recipients r SET read_at = NOW\(\) FROM site_people sp, announcements a, sites s WHERE r\.announcement_id = \$1/, () => ok([{ read_at: new Date('2026-10-16T10:00:00.000Z') }])],
      [/^UPDATE announcement_recipients r SET read_at = NOW\(\) FROM site_people sp, announcements a, sites s WHERE sp\.id = r\.person_id/, () => ok([], 2)],
      [/^WITH mine AS/, () => ok([{ unread: 2, unread_urgent: 0, latest_id: '2', latest_published_at: new Date('2026-10-16T08:00:00.000Z'), server_time: new Date('2026-10-16T09:00:00.000Z') }])],
      [/^SELECT email_announcements, push_announcements FROM notification_preferences/, () => ok()],
      [/^INSERT INTO notification_preferences/, () => ok([{ email_announcements: false, push_announcements: true }])],
      [/^SELECT EXISTS \( SELECT 1 FROM \( SELECT translate\(btrim\(u\.email\)/, () => ok([{ suppressed: false }])],
    );
    const as = { user: users.resident };
    const list = await call('GET', '/app/announcements?limit=5', as);
    assert.equal(list.status, 200);
    assert.equal(list.body.items[0].id, 2);
    assert.equal(list.body.next_before_id, null);
    assert.equal((await call('GET', '/app/announcements/2', as)).body.body, 'B');
    assert.deepEqual((await call('POST', '/app/announcements/2/read', as)).body, { ok: true, read_at: '2026-10-16T10:00:00.000Z' });
    assert.deepEqual((await call('POST', '/app/announcements/read-all', { ...as, body: {} })).body, { ok: true, marked: 2 });
    const summary = await call('GET', '/app/notifications/summary', as);
    assert.equal(summary.body.unread_announcements, 2);
    assert.equal(summary.body.latest_announcement_id, 2);
    assert.deepEqual((await call('GET', '/app/notification-preferences', as)).body, { email_announcements: true, push_announcements: true, push_available: false, email_suppressed: false });
    assert.deepEqual((await call('PUT', '/app/notification-preferences', { ...as, body: { email_announcements: false } })).body, { email_announcements: false, push_announcements: true, push_available: false, email_suppressed: false });
    // tüm sakin sorguları çağıranın kullanıcı kodunu (20004) parametre olarak taşır; istekten gelen kimlik kullanılmaz
    const userParams = state.log.filter((q) => /site_people|notification_preferences/.test(q.sql)).map((q) => q.params);
    assert.ok(userParams.length >= 6);
    assert.ok(userParams.every((params) => params.includes(20004)), JSON.stringify(userParams));
  });

  it('sakin hataları: 404 ANNOUNCEMENT_NOT_FOUND, 400 INVALID_QUERY / INVALID_BODY, mesajlar Türkçe', async () => {
    handlers.push([/^SELECT a\.id, a\.site_code, s\.name AS site_name, a\.title, a\.body,/, () => ok()], [/^UPDATE announcement_recipients r SET read_at/, () => ok()], [/^SELECT r\.read_at FROM site_people sp/, () => ok()]);
    const as = { user: users.resident };
    assert.equal((await call('GET', '/app/announcements/9', as)).body.code, 'ANNOUNCEMENT_NOT_FOUND');
    assert.equal((await call('POST', '/app/announcements/9/read', as)).status, 404);
    const badQuery = await call('GET', '/app/announcements?before_id=abc', as);
    assert.deepEqual([badQuery.status, badQuery.body.code], [400, 'INVALID_QUERY']);
    const badPref = await call('PUT', '/app/notification-preferences', { ...as, body: { email_announcements: 'x' } });
    assert.deepEqual([badPref.status, badPref.body.code], [400, 'INVALID_BODY']);
    assert.match(badPref.body.error, /tercihi/);
  });
});
