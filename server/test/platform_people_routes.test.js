// Kisi ve Daire Kayitlari (Faz 2a) uclari (DB'siz): yetki matrisi, hiz sinirlari, girdi dogrulama, yanit bicimleri, sabit sorgu sayisi.
// Kimlik katmani test icin sahte (x-test-user); pool.query / pool.connect bellek ici sahte veritabanina baglanir.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import { peopleReadLimiter, peopleRouter, peopleWriteLimiter } from '../src/modules/people_routes.js';

const SITE_1 = 1000000001;
const SITE_2 = 1000000002;
const T0 = new Date('2026-10-14T08:00:00.000Z');

const mk = (id, role, name) => ({ id, user_code: id, userCode: id, role, full_name: name, email: `u${id}@example.com` });
const users = {
  superUser: mk(1, 'super_user', 'Süper Kullanıcı'),
  mgrA: mk(20001, 'site_manager', 'Ayşe Yönetici'),
  mgrB: mk(20002, 'site_manager', 'Bora Yönetici'),
  ownerC: mk(20003, 'apartment_owner', 'Can Sahip'),
  resident: mk(20004, 'apartment_owner', 'Deniz Sakin'),
  staff: mk(20005, 'individual', 'Ece Görevli'),
  board: mk(20006, 'individual', 'Fatma Kurul'),
  boardB: mk(20007, 'individual', 'Gül Başka Kurul'),
  outsider: mk(20008, 'individual', 'Hakan İlgisiz'),
};

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

let state;
let overrides;

function makeState() {
  return {
    sites: new Set([SITE_1, SITE_2]),
    managerLinks: [
      { site_code: SITE_1, user_code: 20001 },
      { site_code: SITE_2, user_code: 20002 },
    ],
    memberships: [
      { site_code: SITE_1, user_code: 20003, role: 'SITE_OWNER', is_active: true },
      { site_code: SITE_1, user_code: 20005, role: 'STAFF', is_active: true },
      { site_code: SITE_1, user_code: 20004, role: 'RESIDENT', is_active: true },
      { site_code: SITE_1, user_code: 20006, role: 'BOARD_MEMBER', is_active: true },
      { site_code: SITE_2, user_code: 20007, role: 'BOARD_MEMBER', is_active: true },
    ],
    log: [],
    clientLog: [],
  };
}

function personRow(overrides = {}) {
  return {
    id: '5',
    user_code: 30001,
    is_active: true,
    note: 'not',
    created_at: T0,
    full_name: 'Ali Veli',
    phone: '+905551234567',
    email: 'ali@example.com',
    has_account: true,
    ...overrides,
  };
}

function handle(sql, params) {
  state.log.push({ sql, params });
  for (const [pattern, fn] of overrides) {
    if (pattern.test(sql)) return fn(sql, params);
  }

  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(state.managerLinks.filter((l) => l.site_code === Number(params[0]) && l.user_code === Number(params[1])).map(() => ({ x: 1 })));
  }
  if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) {
    return ok(
      state.memberships
        .filter((m) => m.site_code === Number(params[0]) && m.user_code === Number(params[1]) && ['SITE_OWNER', 'SITE_ADMIN'].includes(m.role) && m.is_active)
        .map(() => ({ x: 1 })),
    );
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
  // liste / kart varsayilanlari
  if (/^SELECT COUNT\(\*\)::INTEGER AS total FROM/.test(sql)) return ok([{ total: 0 }]);
  return ok();
}

function installFakeDb() {
  pool.query = async (text, params) => handle(norm(text), params ?? []);
  pool.connect = async () => ({
    async query(text, params) {
      const sql = norm(text);
      state.clientLog.push({ sql, params });
      return ok();
    },
    release() {},
  });
}

const ORIGINAL_ROUTES = peopleRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({
    path: layer.route.path,
    method: Object.keys(layer.route.methods)[0],
    handlers: layer.route.stack.map((entry) => entry.handle),
  }));

let server;
let baseUrl;

before(async () => {
  for (const layer of peopleRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    // hiz sinirlayicilar rota testlerinde atlanir (dogrudan ayri testte sinanir)
    if (layer.route.stack.length > 2 && layer.route.path.startsWith('/manager/')) {
      layer.route.stack[1].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json());
  app.use(peopleRouter);
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
  overrides = [];
  installFakeDb();
  mock.method(console, 'error', () => {});
  mock.method(console, 'log', () => {});
});

afterEach(() => {
  mock.restoreAll();
  peopleReadLimiter.reset();
  peopleWriteLimiter.reset();
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
    // govdesiz
  }
  return { status: response.status, body: json };
}

const base = (site = SITE_1) => `/manager/sites/${site}`;

// ---------------------------------------------------------------------------
// Rota zinciri
// ---------------------------------------------------------------------------

describe('people rotalari: zincir', () => {
  it('15 rota; hepsi authRequired ile baslar; /manager uclari hiz sinirli (okuma 600/saat, yazma 120/saat)', () => {
    const summary = ORIGINAL_ROUTES.map((r) => `${r.method.toUpperCase()} ${r.path}`).sort();
    assert.deepEqual(summary, [
      'DELETE /manager/sites/:siteCode/vehicles/:vehicleId',
      'GET /app/my-records',
      'GET /manager/sites/:siteCode/apartments',
      'GET /manager/sites/:siteCode/apartments/:apartmentId',
      'GET /manager/sites/:siteCode/history',
      'GET /manager/sites/:siteCode/people',
      'GET /manager/sites/:siteCode/people/:personId',
      'GET /manager/sites/:siteCode/vehicles',
      'PATCH /manager/sites/:siteCode/apartments/:apartmentId',
      'PATCH /manager/sites/:siteCode/people/:personId',
      'PATCH /manager/sites/:siteCode/residencies/:residencyId',
      'POST /manager/sites/:siteCode/people',
      'POST /manager/sites/:siteCode/people/:personId/residencies',
      'POST /manager/sites/:siteCode/residencies/:residencyId/end',
      'POST /manager/sites/:siteCode/vehicles',
    ]);
    for (const route of ORIGINAL_ROUTES) {
      assert.equal(route.handlers[0], authRequired, route.path);
      if (route.path.startsWith('/manager/')) {
        assert.equal(route.handlers[1], route.method === 'get' ? peopleReadLimiter : peopleWriteLimiter, `${route.method} ${route.path}`);
      }
    }
  });

  it('hiz sinirlari: yazma kullanici basina 120/saat, okuma 600/saat; 429 + Retry-After', () => {
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
    for (let i = 0; i < 120; i += 1) assert.equal(run(peopleWriteLimiter, 7).passed, true, String(i));
    const blockedWrite = run(peopleWriteLimiter, 7);
    assert.equal(blockedWrite.res.statusCode, 429);
    assert.ok(Number(blockedWrite.res.headers['Retry-After']) > 0);
    assert.ok(blockedWrite.res.body.retry_after_seconds > 0);
    assert.equal(run(peopleWriteLimiter, 8).passed, true);
    for (let i = 0; i < 600; i += 1) assert.equal(run(peopleReadLimiter, 7).passed, true, String(i));
    assert.equal(run(peopleReadLimiter, 7).res.statusCode, 429);
  });
});

// ---------------------------------------------------------------------------
// Yetki matrisi
// ---------------------------------------------------------------------------

const READS = [
  ['GET', '/people'],
  ['GET', '/people/5'],
  ['GET', '/apartments'],
  ['GET', '/apartments/9'],
  ['GET', '/vehicles'],
  ['GET', '/history'],
];
const WRITES = [
  ['POST', '/people', { full_name: 'Ali Veli' }],
  ['PATCH', '/people/5', { note: 'x' }],
  ['POST', '/people/5/residencies', { apartment_id: 9, relation: 'tenant' }],
  ['PATCH', '/residencies/3', { relation: 'owner' }],
  ['POST', '/residencies/3/end', {}],
  ['PATCH', '/apartments/9', { floor: 2 }],
  ['POST', '/vehicles', { person_id: 5, plate: '34 ABC 123' }],
  ['DELETE', '/vehicles/4'],
];

describe('people yetki matrisi (yonetici / kurul / gorevli / sakin / baska site / super)', () => {
  const forbiddenCodes = (res) => [res.status, res.body?.code];

  it('OKUMA: yonetici, SITE_OWNER, super ve o sitenin BOARD_MEMBER\'i gecer (403 degil)', async () => {
    for (const user of [users.mgrA, users.ownerC, users.superUser, users.board]) {
      for (const [method, path] of READS) {
        const res = await call(method, `${base()}${path}`, { user });
        assert.notEqual(res.status, 403, `${user.full_name} ${method} ${path}`);
        assert.notEqual(res.status, 401);
      }
    }
  });

  it('YAZMA: yonetici, SITE_OWNER ve super gecer', async () => {
    for (const user of [users.mgrA, users.ownerC, users.superUser]) {
      for (const [method, path, body] of WRITES) {
        const res = await call(method, `${base()}${path}`, { user, body });
        assert.notEqual(res.status, 403, `${user.full_name} ${method} ${path}`);
      }
    }
  });

  it('YAZMA: kurul uyesi salt okunur -> 403 FORBIDDEN_ROLE (tum yazma uclari)', async () => {
    for (const [method, path, body] of WRITES) {
      const res = await call(method, `${base()}${path}`, { user: users.board, body });
      assert.deepEqual(forbiddenCodes(res), [403, 'FORBIDDEN_ROLE'], `${method} ${path}`);
      assert.equal(res.body.error, 'Bu işlem için yetkiniz yok.');
    }
  });

  it('STAFF ve sakin ve ilgisiz kullanici: okuma ve yazma 403 FORBIDDEN_ROLE', async () => {
    for (const user of [users.staff, users.resident, users.outsider]) {
      for (const [method, path, body] of [...READS, ...WRITES]) {
        const res = await call(method, `${base()}${path}`, { user, body });
        assert.deepEqual(forbiddenCodes(res), [403, 'FORBIDDEN_ROLE'], `${user.full_name} ${method} ${path}`);
      }
    }
  });

  it('baska sitenin yoneticisi ve baska sitenin kurul uyesi: 403 FORBIDDEN_SITE (okuma ve yazma)', async () => {
    for (const user of [users.mgrB, users.boardB]) {
      for (const [method, path, body] of [...READS, ...WRITES]) {
        const res = await call(method, `${base()}${path}`, { user, body });
        assert.deepEqual(forbiddenCodes(res), [403, 'FORBIDDEN_SITE'], `${user.full_name} ${method} ${path}`);
      }
    }
  });

  it('reddedilen istek VERI/ESITLEME sorgusu CALISTIRMAZ (KVKK: baska sitenin bilgisi asla)', async () => {
    for (const user of [users.mgrB, users.staff, users.resident, users.board]) {
      state.log.length = 0;
      state.clientLog.length = 0;
      await call('POST', `${base()}/people`, { user, body: { full_name: 'Ali Veli' } });
      await call('GET', `${base()}/people`, { user: user === users.board ? users.mgrB : user });
      assert.equal(state.log.some((q) => /site_people|apartment_residencies|vehicles|audit_log/.test(q.sql)), false, user.full_name);
      assert.equal(state.clientLog.length, 0);
    }
  });

  it('gecersiz site kodu 400 INVALID_SITE_CODE; super + olmayan site 404 SITE_NOT_FOUND', async () => {
    for (const bad of ['abc', '0', '-3', '1.5']) {
      const res = await call('GET', `/manager/sites/${bad}/people`, { user: users.superUser });
      assert.equal(res.status, 400, bad);
      assert.equal(res.body.code, 'INVALID_SITE_CODE');
    }
    const missing = await call('GET', `${base(1999999999)}/people`, { user: users.superUser });
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'SITE_NOT_FOUND');
  });
});

// ---------------------------------------------------------------------------
// Kisi listesi
// ---------------------------------------------------------------------------

describe('GET people: sorgu, sayfalama, sabit sorgu sayisi', () => {
  it('bos liste: { items: [], total: 0 }', async () => {
    const res = await call('GET', `${base()}/people`);
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { items: [], total: 0 });
  });

  it('PersonSummary bicimi; iliskiler sirali; araç sayisi; hesap rozeti', async () => {
    overrides.push(
      [/^SELECT COUNT\(\*\)::INTEGER AS total FROM site_people/, () => ok([{ total: 7 }])],
      [/^SELECT sp\.id, sp\.user_code, sp\.is_active, sp\.note/, () => ok([personRow(), personRow({ id: '6', user_code: null, has_account: false, full_name: 'Hesapsız Kişi', email: null, phone: null })])],
      [
        /FROM apartment_residencies r INNER JOIN apartments a ON a\.id = r\.apartment_id INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE r\.person_id = ANY/,
        () =>
          ok([
            { person_id: '5', apartment_id: '9', relation: 'resident', unit_label: 'Daire 2', block_name: 'A Blok' },
            { person_id: '5', apartment_id: '10', relation: 'owner', unit_label: 'Daire 3', block_name: 'A Blok' },
          ]),
      ],
      [/^SELECT person_id, COUNT\(\*\)::INTEGER AS vehicle_count FROM vehicles/, () => ok([{ person_id: '5', vehicle_count: 2 }])],
    );
    const res = await call('GET', `${base()}/people?status=all&limit=2&offset=4`);
    assert.equal(res.status, 200);
    assert.equal(res.body.total, 7);
    assert.deepEqual(res.body.items[0], {
      id: 5,
      full_name: 'Ali Veli',
      phone: '+905551234567',
      email: 'ali@example.com',
      has_account: true,
      is_active: true,
      relations: ['owner', 'resident'],
      apartments: [
        { apartment_id: 9, label: 'A Blok - Daire 2', block_name: 'A Blok', relation: 'resident' },
        { apartment_id: 10, label: 'A Blok - Daire 3', block_name: 'A Blok', relation: 'owner' },
      ],
      vehicle_count: 2,
    });
    assert.deepEqual(res.body.items[1], {
      id: 6,
      full_name: 'Hesapsız Kişi',
      phone: null,
      email: null,
      has_account: false,
      is_active: true,
      relations: [],
      apartments: [],
      vehicle_count: 0,
    });
    // limit/offset sayfa sorgusuna gider
    const page = state.log.find((q) => /^SELECT sp\.id, sp\.user_code/.test(q.sql));
    assert.deepEqual(page.params.slice(-2), [2, 4]);
  });

  it('SABIT sorgu sayisi (N+1 yok): erisim + sayim + sayfa + iliskiler + arac sayilari; esitleme ayri tek transaction', async () => {
    overrides.push(
      [/^SELECT sp\.id, sp\.user_code, sp\.is_active, sp\.note/, () => ok(Array.from({ length: 30 }, (_, i) => personRow({ id: String(100 + i) })))],
    );
    state.log.length = 0;
    await call('GET', `${base()}/people?limit=30`);
    const dataQueries = state.log.filter((q) => /site_people|apartment_residencies|vehicles/.test(q.sql));
    assert.equal(dataQueries.length, 4, dataQueries.map((q) => q.sql.slice(0, 50)).join(' | '));
    // esitleme: BEGIN + kilit + 5 adim + COMMIT = 8 (site basina sabit)
    assert.equal(state.clientLog.length, 8);
    assert.equal(state.clientLog.filter((q) => /^WITH desired AS/.test(q.sql)).length, 5);
    assert.deepEqual(state.clientLog[0].sql, 'BEGIN');
    assert.match(state.clientLog[1].sql, /^SELECT pg_advisory_xact_lock/);
    assert.equal(state.clientLog[1].params[0], `people_sync:${SITE_1}`);
  });

  it('esitleme hatasi okumayi ENGELLEMEZ (200, hata loglanir)', async () => {
    pool.connect = async () => {
      throw new Error('baglanti havuzu dolu');
    };
    const res = await call('GET', `${base()}/people`);
    assert.equal(res.status, 200);
    assert.ok(console.error.mock.calls.some((c) => String(c.arguments[0]).includes('[people] syncSitePeople')));
  });

  it('suzgecler SQL parametrelerine gider: q (Turkce katlanmis, joker kacirilmis), telefon rakamlari, iliski, daire', async () => {
    await call('GET', `${base()}/people?q=${encodeURIComponent('ÇAĞLAR_50%')}&relation=tenant&apartment_id=9&status=inactive`);
    const count = state.log.find((q) => /^SELECT COUNT\(\*\)::INTEGER AS total FROM site_people/.test(q.sql));
    assert.ok(count);
    assert.equal(count.params[0], SITE_1);
    assert.ok(count.params.includes('tenant'));
    assert.ok(count.params.includes(9));
    assert.ok(count.params.includes('%caglar\\_50\\%%'), JSON.stringify(count.params));
    assert.match(count.sql, /sp\.is_active = FALSE/);
    assert.match(count.sql, /ESCAPE '\\'/);

    state.log.length = 0;
    await call('GET', `${base()}/people?q=0555%20123`);
    const phoneQuery = state.log.find((q) => /^SELECT COUNT/.test(q.sql));
    assert.ok(phoneQuery.params.includes('%0555123%'), 'rakamlar telefon eslemesi icin ayrica gider');
    assert.match(phoneQuery.sql, /regexp_replace\(/);
  });

  it('varsayilan durum active; status=all hicbir is_active kosulu eklemez', async () => {
    await call('GET', `${base()}/people`);
    assert.match(state.log.find((q) => /^SELECT COUNT/.test(q.sql)).sql, /sp\.is_active = TRUE/);
    state.log.length = 0;
    await call('GET', `${base()}/people?status=all`);
    assert.equal(/sp\.is_active = (TRUE|FALSE)/.test(state.log.find((q) => /^SELECT COUNT/.test(q.sql)).sql), false);
  });

  it('gecersiz status / relation / apartment_id / offset 400 INVALID_QUERY', async () => {
    for (const query of ['status=zz', 'relation=malik', 'apartment_id=abc', 'offset=-1', 'status=a&status=b']) {
      const res = await call('GET', `${base()}/people?${query}`);
      assert.equal(res.status, 400, query);
      assert.equal(res.body.code, 'INVALID_QUERY');
    }
  });
});

// ---------------------------------------------------------------------------
// Kisi karti
// ---------------------------------------------------------------------------

describe('GET people/:personId: PersonDetail', () => {
  function cardOverrides() {
    overrides.push(
      [/^SELECT sp\.id, sp\.user_code, sp\.is_active, sp\.note[\s\S]*WHERE sp\.site_code = \$1 AND sp\.id = \$2 LIMIT 1$/, () => ok([personRow()])],
      [
        /FROM apartment_residencies r INNER JOIN apartments a ON a\.id = r\.apartment_id INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE r\.person_id = \$1 ORDER BY/,
        () =>
          ok([
            { id: '31', apartment_id: '9', relation: 'owner', is_current: true, move_in_date: '2024-05-01', move_out_date: null, unit_label: 'Daire 2', block_name: 'A Blok' },
            { id: '12', apartment_id: '7', relation: 'tenant', is_current: false, move_in_date: '2022-01-01', move_out_date: '2024-04-30', unit_label: 'Daire 1', block_name: 'A Blok' },
          ]),
      ],
      [
        /FROM vehicles v LEFT JOIN site_people sp ON sp\.id = v\.person_id[\s\S]*WHERE v\.person_id = \$1 AND v\.is_active = TRUE ORDER BY v\.id$/,
        () => ok([{ id: '4', plate: '34ABC123', plate_display: '34 ABC 123', note: null, person_id: '5', is_active: true, person_name: 'Ali Veli', block_name: 'A Blok', unit_label: 'Daire 2' }]),
      ],
    );
  }

  it('Summary alanlari + note, created_at, residencies (gecmis dahil), vehicles, user_code (yonetici/super icin)', async () => {
    cardOverrides();
    const res = await call('GET', `${base()}/people/5`, { user: users.mgrA });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, {
      id: 5,
      full_name: 'Ali Veli',
      phone: '+905551234567',
      email: 'ali@example.com',
      has_account: true,
      is_active: true,
      relations: ['owner'],
      apartments: [{ apartment_id: 9, label: 'A Blok - Daire 2', block_name: 'A Blok', relation: 'owner' }],
      vehicle_count: 1,
      note: 'not',
      created_at: '2026-10-14T08:00:00.000Z',
      residencies: [
        { id: 31, apartment_id: 9, label: 'A Blok - Daire 2', block_name: 'A Blok', relation: 'owner', is_current: true, move_in_date: '2024-05-01', move_out_date: null },
        { id: 12, apartment_id: 7, label: 'A Blok - Daire 1', block_name: 'A Blok', relation: 'tenant', is_current: false, move_in_date: '2022-01-01', move_out_date: '2024-04-30' },
      ],
      vehicles: [{ id: 4, plate: '34ABC123', plate_display: '34 ABC 123', note: null, person_id: 5, person_name: 'Ali Veli', apartment_label: 'A Blok - Daire 2', is_active: true }],
      user_code: 30001,
    });
  });

  it('kurul uyesi kartı okur ama user_code DONMEZ', async () => {
    cardOverrides();
    const res = await call('GET', `${base()}/people/5`, { user: users.board });
    assert.equal(res.status, 200);
    assert.equal('user_code' in res.body, false);
    assert.equal(res.body.full_name, 'Ali Veli');
  });

  it('kisi yok / baska sitenin kisisi / gecersiz id -> 404 PERSON_NOT_FOUND (site kapsamli sorgu)', async () => {
    for (const id of ['999', 'abc', '0']) {
      const res = await call('GET', `${base()}/people/${id}`);
      assert.equal(res.status, 404, id);
      assert.equal(res.body.code, 'PERSON_NOT_FOUND');
    }
    const lookup = state.log.find((q) => /WHERE sp\.site_code = \$1 AND sp\.id = \$2/.test(q.sql));
    assert.deepEqual(lookup.params, [SITE_1, 999]);
  });

  it('hesapli kisinin e-postasi users\'tan, dahili (@ahbu.local) hesapta iletisim e-postasi CRM\'den okunur (SQL)', async () => {
    cardOverrides();
    await call('GET', `${base()}/people/5`);
    const sql = state.log.find((q) => /WHERE sp\.site_code = \$1 AND sp\.id = \$2/.test(q.sql)).sql;
    assert.match(sql, /COALESCE\(NULLIF\(u\.full_name, ''\), sp\.full_name\) AS full_name/);
    assert.match(sql, /COALESCE\(NULLIF\(u\.phone_number, ''\), sp\.phone\) AS phone/);
    assert.match(sql, /WHEN u\.user_code IS NOT NULL AND u\.email NOT LIKE '%@ahbu\.local' THEN u\.email ELSE sp\.email END AS email/);
  });
});

// ---------------------------------------------------------------------------
// Dogrulama hatalari (veritabanina gitmeden)
// ---------------------------------------------------------------------------

describe('yazma uclari: girdi dogrulama (400, DB yazmasi yok)', () => {
  it('POST people: alan adiyla INVALID_BODY', async () => {
    const cases = [
      [{}, /full_name/],
      [{ full_name: 'A' }, /full_name/],
      [{ full_name: 'Ali', phone: '123' }, /phone/],
      [{ full_name: 'Ali', email: 'bozuk' }, /email/],
      [{ full_name: 'Ali', relation: 'x' }, /relation/],
      [{ full_name: 'Ali', apartment_id: 'abc' }, /apartment_id/],
      [{ full_name: 'Ali', move_in_date: '31.02.2026' }, /move_in_date/],
    ];
    for (const [body, pattern] of cases) {
      const res = await call('POST', `${base()}/people`, { body });
      assert.equal(res.status, 400, JSON.stringify(body));
      assert.equal(res.body.code, 'INVALID_BODY');
      assert.match(res.body.error, pattern);
    }
    assert.equal(state.clientLog.length, 0);
    assert.equal(state.log.some((q) => /^INSERT/.test(q.sql)), false);
  });

  it('PATCH apartments: gecersiz alan 400 INVALID_BODY (alan adiyla)', async () => {
    for (const [body, pattern] of [
      [{ floor: 1.5 }, /floor/],
      [{ gross_area_m2: 0 }, /gross_area_m2/],
      [{ land_share_denominator: 0 }, /land_share_denominator/],
      [{ category: 'x'.repeat(41) }, /category/],
      [{ responsible_party: 'z' }, /responsible_party/],
    ]) {
      const res = await call('PATCH', `${base()}/apartments/9`, { body });
      assert.equal(res.status, 400);
      assert.equal(res.body.code, 'INVALID_BODY');
      assert.match(res.body.error, pattern);
    }
  });

  it('POST vehicles: person_id eksik 400; plaka gecersiz 400 PLATE_INVALID', async () => {
    assert.equal((await call('POST', `${base()}/vehicles`, { body: { plate: '34ABC123' } })).body.code, 'INVALID_BODY');
    const res = await call('POST', `${base()}/vehicles`, { body: { person_id: 5, plate: '34' } });
    assert.equal(res.status, 400);
    assert.equal(res.body.code, 'PLATE_INVALID');
    assert.equal(res.body.error, 'Plaka biçimi geçersiz.');
  });

  it('PATCH people: is_active boolean olmali; yok kisi 404 PERSON_NOT_FOUND', async () => {
    const bad = await call('PATCH', `${base()}/people/5`, { body: { is_active: 'evet' } });
    assert.equal(bad.status, 400);
    assert.equal(bad.body.code, 'INVALID_BODY');
    const missing = await call('PATCH', `${base()}/people/5`, { body: { note: 'x' } });
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'PERSON_NOT_FOUND');
  });

  it('POST residencies: apartment_id zorunlu; relation gecersiz 400; yok kisi 404', async () => {
    assert.equal((await call('POST', `${base()}/people/5/residencies`, { body: {} })).body.code, 'INVALID_BODY');
    assert.equal((await call('POST', `${base()}/people/5/residencies`, { body: { apartment_id: 9, relation: 'x' } })).body.code, 'INVALID_BODY');
    const missing = await call('POST', `${base()}/people/5/residencies`, { body: { apartment_id: 9 } });
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'PERSON_NOT_FOUND');
  });

  it('PATCH/POST end residencies: yok kayit 404 RESIDENCY_NOT_FOUND; move_out_date gecersiz 400', async () => {
    const missing = await call('PATCH', `${base()}/residencies/3`, { body: { relation: 'owner' } });
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'RESIDENCY_NOT_FOUND');
    const badDate = await call('POST', `${base()}/residencies/3/end`, { body: { move_out_date: 'dün' } });
    assert.equal(badDate.status, 400);
    assert.equal(badDate.body.code, 'INVALID_BODY');
    assert.match(badDate.body.error, /move_out_date/);
  });

  it('DELETE vehicles: yok arac 404 VEHICLE_NOT_FOUND', async () => {
    const res = await call('DELETE', `${base()}/vehicles/4`);
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'VEHICLE_NOT_FOUND');
  });
});

// ---------------------------------------------------------------------------
// Daireler, araclar, gecmis, kendi kayitlarim
// ---------------------------------------------------------------------------

describe('GET apartments / vehicles / history / my-records', () => {
  it('daire listesi: ApartmentSummary (owner/tenant/resident_count/land_share/sayilar); blok ve arama suzgeci', async () => {
    overrides.push(
      [/^SELECT COUNT\(\*\)::INTEGER AS total FROM apartments a/, () => ok([{ total: 12 }])],
      [
        /^SELECT a\.id, a\.unit_label, a\.block_id, b\.block_name, a\.floor/,
        () =>
          ok([
            { id: '9', unit_label: 'Daire 2', block_id: '3', block_name: 'A Blok', floor: 1, category: '3+1', gross_area_m2: '120.50', net_area_m2: '100.00', land_share_numerator: 35, land_share_denominator: 1000, responsible_party: 'tenant' },
            { id: '10', unit_label: 'Daire 3', block_id: '3', block_name: 'A Blok', floor: null, category: null, gross_area_m2: null, net_area_m2: null, land_share_numerator: null, land_share_denominator: null, responsible_party: 'both' },
          ]),
      ],
      [
        /FROM apartment_residencies r INNER JOIN site_people sp ON sp\.id = r\.person_id LEFT JOIN users u ON u\.user_code = sp\.user_code WHERE r\.apartment_id = ANY\(\$1::BIGINT\[\]\) AND r\.is_current = TRUE/,
        () =>
          ok([
            { residency_id: '1', apartment_id: '9', person_id: '5', relation: 'owner', is_current: true, move_in_date: '2024-01-01', move_out_date: null, full_name: 'Ali Veli', has_account: true },
            { residency_id: '2', apartment_id: '9', person_id: '6', relation: 'tenant', is_current: true, move_in_date: null, move_out_date: null, full_name: 'Veli Kaya', has_account: false },
            { residency_id: '3', apartment_id: '9', person_id: '7', relation: 'family_member', is_current: true, move_in_date: null, move_out_date: null, full_name: 'Can', has_account: false },
          ]),
      ],
    );
    const res = await call('GET', `${base()}/apartments?block_id=3&q=${encodeURIComponent('Daire')}&limit=2`);
    assert.equal(res.status, 200);
    assert.equal(res.body.total, 12);
    assert.deepEqual(res.body.items[0], {
      id: 9,
      label: 'A Blok - Daire 2',
      block_id: 3,
      block_name: 'A Blok',
      floor: 1,
      category: '3+1',
      gross_area_m2: 120.5,
      net_area_m2: 100,
      land_share: { numerator: 35, denominator: 1000 },
      responsible_party: 'tenant',
      owner: { person_id: 5, full_name: 'Ali Veli' },
      tenant: { person_id: 6, full_name: 'Veli Kaya' },
      resident_count: 3,
    });
    assert.deepEqual(res.body.items[1], {
      id: 10,
      label: 'A Blok - Daire 3',
      block_id: 3,
      block_name: 'A Blok',
      floor: null,
      category: null,
      gross_area_m2: null,
      net_area_m2: null,
      land_share: null,
      responsible_party: 'both',
      owner: null,
      tenant: null,
      resident_count: 0,
    });
    const count = state.log.find((q) => /^SELECT COUNT\(\*\)::INTEGER AS total FROM apartments/.test(q.sql));
    assert.equal(count.params[0], SITE_1);
    assert.ok(count.params.includes(3));
    assert.ok(count.params.includes('%daire%'));
  });

  it('daire karti: sakinler guncel/gecmis ayrilir; yok / baska sitenin dairesi 404 APARTMENT_NOT_FOUND', async () => {
    overrides.push(
      [
        /^SELECT a\.id, a\.unit_label, a\.block_id, b\.block_name[\s\S]*WHERE a\.id = \$1 AND a\.site_code = \$2 LIMIT 1$/,
        (sql, params) =>
          params[0] === 9
            ? ok([{ id: '9', unit_label: 'Daire 2', block_id: '3', block_name: 'A Blok', floor: 2, category: null, gross_area_m2: null, net_area_m2: null, land_share_numerator: null, land_share_denominator: null, responsible_party: 'both' }])
            : ok(),
      ],
      [
        /WHERE r\.apartment_id = ANY\(\$1::BIGINT\[\]\) ORDER BY/,
        () =>
          ok([
            { residency_id: '1', apartment_id: '9', person_id: '5', relation: 'owner', is_current: true, move_in_date: '2024-01-01', move_out_date: null, full_name: 'Ali Veli', has_account: true },
            { residency_id: '2', apartment_id: '9', person_id: '6', relation: 'tenant', is_current: false, move_in_date: '2022-01-01', move_out_date: '2023-12-31', full_name: 'Eski Kiracı', has_account: false },
          ]),
      ],
    );
    const res = await call('GET', `${base()}/apartments/9`);
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.current_residents, [
      { residency_id: 1, person_id: 5, full_name: 'Ali Veli', relation: 'owner', move_in_date: '2024-01-01', has_account: true },
    ]);
    assert.deepEqual(res.body.past_residents, [
      { residency_id: 2, person_id: 6, full_name: 'Eski Kiracı', relation: 'tenant', move_in_date: '2022-01-01', has_account: false, move_out_date: '2023-12-31' },
    ]);
    assert.equal(res.body.owner.full_name, 'Ali Veli');
    assert.equal(res.body.tenant, null, 'gecmis kiraci "guncel kiraci" sayilmaz');
    assert.equal(res.body.resident_count, 1);

    const missing = await call('GET', `${base()}/apartments/77`);
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'APARTMENT_NOT_FOUND');
    const lookup = state.log.filter((q) => /WHERE a\.id = \$1 AND a\.site_code = \$2/.test(q.sql)).pop();
    assert.deepEqual(lookup.params, [77, SITE_1]);
  });

  it('arac listesi: { items, total }; Vehicle bicimi; q plaka+kisi adi, person_id suzgeci', async () => {
    overrides.push(
      [/^SELECT COUNT\(\*\)::INTEGER AS total FROM vehicles v/, () => ok([{ total: 3 }])],
      [
        /^SELECT v\.id, v\.plate, v\.plate_display, v\.note, v\.person_id, v\.is_active/,
        () => ok([{ id: '4', plate: '34ABC123', plate_display: '34 ABC 123', note: 'beyaz', person_id: '5', is_active: true, person_name: 'Ali Veli', block_name: 'A Blok', unit_label: 'Daire 2' }]),
      ],
    );
    const res = await call('GET', `${base()}/vehicles?q=${encodeURIComponent('34 abc')}&person_id=5`);
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, {
      items: [{ id: 4, plate: '34ABC123', plate_display: '34 ABC 123', note: 'beyaz', person_id: 5, person_name: 'Ali Veli', apartment_label: 'A Blok - Daire 2', is_active: true }],
      total: 3,
    });
    const count = state.log.find((q) => /^SELECT COUNT\(\*\)::INTEGER AS total FROM vehicles/.test(q.sql));
    assert.ok(count.params.includes(5));
    assert.ok(count.params.includes('%34ABC%'), JSON.stringify(count.params));
    assert.match(count.sql, /v\.is_active = TRUE/);
  });

  it('gecmis: yalniz bu sitenin kayitlari; hedef suzgeci; gecersiz parametre 400', async () => {
    overrides.push([
      /^SELECT a\.id, a\.created_at, a\.actor_user_code[\s\S]*FROM audit_log a/,
      () =>
        ok([
          { id: '12', created_at: T0, actor_user_code: 1, actor_name: 'Süper', actor_role: 'super_user', action: 'person.updated', site_code: String(SITE_1), site_name: 'Gül', target_type: 'person', target_id: '5', details: { changes: [{ field: 'phone', from: null, to: '+905551234567' }] } },
          { id: '11', created_at: T0, actor_user_code: 1, actor_name: 'Süper', actor_role: 'super_user', action: 'person.created', site_code: String(SITE_1), site_name: 'Gül', target_type: 'person', target_id: '5', details: {} },
        ]),
    ]);
    const res = await call('GET', `${base()}/history?target_type=person&target_id=5&limit=1`, { user: users.board });
    assert.equal(res.status, 200);
    assert.equal(res.body.items.length, 1);
    assert.equal(res.body.items[0].id, 12);
    assert.equal(res.body.items[0].details.changes[0].field, 'phone');
    assert.equal(res.body.next_before_id, 12, 'fazladan satir var -> sonraki sayfa');
    const query = state.log.find((q) => /FROM audit_log a/.test(q.sql));
    assert.equal(query.params[0], SITE_1, 'her zaman site kapsamli');
    assert.match(query.sql, /a\.site_code = \$1/);
    assert.ok(query.params.includes('person') && query.params.includes('5'));

    for (const q of ['target_type=zz', 'target_id=abc', 'before_id=0']) {
      const bad = await call('GET', `${base()}/history?${q}`);
      assert.equal(bad.status, 400, q);
      assert.equal(bad.body.code, 'INVALID_QUERY');
    }
  });

  it('gecmis (daire): residency olaylari details.apartment_id ile eslenir', async () => {
    await call('GET', `${base()}/history?target_type=apartment&target_id=9`);
    const query = state.log.find((q) => /FROM audit_log a/.test(q.sql));
    assert.match(query.sql, /a\.action LIKE 'residency\.%' AND a\.details->>'apartment_id' = \$\d+/);
    assert.ok(query.params.includes('9'));
  });

  it('/app/my-records: authRequired, yalnizca CAGIRANIN kayitlari (sorgu user_code ile), arac listesi dahil', async () => {
    overrides.push(
      [
        /FROM site_people sp INNER JOIN apartment_residencies r ON r\.person_id = sp\.id AND r\.is_current = TRUE/,
        (sql, params) => {
          assert.deepEqual(params, [20004]);
          return ok([{ site_code: String(SITE_1), site_name: 'Gül Sitesi', apartment_id: '9', unit_label: 'Daire 2', block_name: 'A Blok', relation: 'resident', move_in_date: '2025-01-02', person_id: '5' }]);
        },
      ],
      [
        /WHERE v\.person_id = ANY\(\$1::BIGINT\[\]\) AND v\.is_active = TRUE ORDER BY v\.id$/,
        () => ok([{ id: '4', plate: '34ABC123', plate_display: '34 ABC 123', note: null, person_id: '5', is_active: true, person_name: 'Deniz Sakin', block_name: 'A Blok', unit_label: 'Daire 2' }]),
      ],
    );
    const res = await call('GET', '/app/my-records', { user: users.resident });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, {
      records: [
        {
          site_code: SITE_1,
          site_name: 'Gül Sitesi',
          apartment_id: 9,
          label: 'A Blok - Daire 2',
          block_name: 'A Blok',
          relation: 'resident',
          move_in_date: '2025-01-02',
          vehicles: [{ id: 4, plate: '34ABC123', plate_display: '34 ABC 123', note: null, person_id: 5, person_name: 'Deniz Sakin', apartment_label: 'A Blok - Daire 2', is_active: true }],
        },
      ],
    });
    // kullanici bazli esitleme (siteler arasi), baska kullanicinin verisi sorgulanmaz
    assert.deepEqual(state.clientLog.find((q) => /^WITH desired AS/.test(q.sql)).params, [null, 20004]);
    assert.equal(state.clientLog[1].params[0], 'people_sync_user:20004');
  });

  it('/app/my-records: kaydi olmayan kullanici -> { records: [] }; STAFF/kurul dahil herkes yalniz kendisini gorur', async () => {
    const res = await call('GET', '/app/my-records', { user: users.staff });
    assert.deepEqual(res.body, { records: [] });
  });
});
