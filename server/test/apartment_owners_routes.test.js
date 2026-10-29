// Coklu malik (104) uclari (DB'siz): yetki matrisi (yonetici / super yazar; kurul okur; sakin, gorevli, ilgisiz 403; baska sitenin yoneticisi 403 FORBIDDEN_SITE),
// girdi dogrulama (DB'ye gitmeden 400), yanit bicimi, rota zinciri (kimlik dogrulama + hiz siniri). Gercek SQL / eszamanlilik: scripts/qa_coklu_malik.mjs.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { peopleReadLimiter, peopleRouter, peopleWriteLimiter } from '../src/modules/people_routes.js';
import { SYNC_STEPS } from '../src/modules/people_sync_sql.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';

process.env.PEOPLE_SYNC_MIN_INTERVAL_MS = '0';

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
  outsider: mk(20008, 'individual', 'Hakan İlgisiz'),
};

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });

let state;
let overrides;

function makeState() {
  return {
    managerLinks: [
      { site_code: SITE_1, user_code: 20001 },
      { site_code: SITE_2, user_code: 20002 },
    ],
    memberships: [
      { site_code: SITE_1, user_code: 20005, role: 'STAFF', is_active: true },
      { site_code: SITE_1, user_code: 20004, role: 'RESIDENT', is_active: true },
      { site_code: SITE_1, user_code: 20006, role: 'BOARD_MEMBER', is_active: true },
    ],
    log: [],
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
    return ok([]);
  }
  if (/^SELECT EXISTS \( SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role = 'BOARD_MEMBER'/.test(sql)) {
    const [site, user] = params.map(Number);
    const here = state.memberships.filter((m) => m.site_code === site && m.user_code === user && m.is_active);
    const otherRole = state.managerLinks.some((l) => l.user_code === user) || state.memberships.some((m) => m.user_code === user && m.is_active && m.role === 'BOARD_MEMBER');
    return ok([{ is_board_here: here.some((m) => m.role === 'BOARD_MEMBER'), is_member_here: here.length > 0, has_other_role: otherRole }]);
  }
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/.test(sql)) {
    return ok([SITE_1, SITE_2].includes(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  }
  if (/^(INSERT|UPDATE|DELETE)\b/.test(sql)) throw new Error(`BEKLENMEYEN yazma SQL (sahte DB kati): ${sql.slice(0, 200)}`);
  return ok();
}

const STEP_SQLS = new Set(SYNC_STEPS.map((step) => norm(step.sql)));
const CLIENT_INFRA = [/^BEGIN$/, /^COMMIT$/, /^ROLLBACK$/, /^SELECT pg_advisory_xact_lock/];

function installFakeDb() {
  pool.query = async (text, params) => handle(norm(text), params ?? []);
  pool.connect = async () => ({
    async query(text) {
      const sql = norm(text);
      if (/^SELECT pg_try_advisory_xact_lock/.test(sql)) return ok([{ locked: true }]);
      if (CLIENT_INFRA.some((pattern) => pattern.test(sql)) || STEP_SQLS.has(sql)) return ok();
      if (/^SELECT DISTINCT site_code FROM \(/.test(sql)) return ok();
      throw new Error(`BEKLENMEYEN transaction SQL (sahte DB kati): ${sql.slice(0, 200)}`);
    },
    release() {},
  });
}

const OWNER_ROUTES = peopleRouter.stack
  .filter((layer) => layer.route && /\/owners/.test(layer.route.path))
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
    if (layer.route.stack.length > 2) {
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

const owners = (site = SITE_1, apt = 301) => `/manager/sites/${site}/apartments/${apt}/owners`;

/** Sahte daire + malik satirlari (listApartmentOwners). */
function seedOwners(rows) {
  overrides.push(
    [/^SELECT a\.id, a\.site_code, a\.unit_label, a\.resident_user_code, b\.block_name FROM apartments a/, (sql, params) => (Number(params[0]) === 301 && Number(params[1]) === SITE_1 ? ok([{ id: '301', site_code: String(SITE_1), unit_label: 'Daire 5', resident_user_code: null, block_name: 'A Blok' }]) : ok())],
    [/^SELECT r\.id AS residency_id, r\.person_id, r\.relation, r\.is_account_holder/, () => ok(rows)],
  );
}

const ROWS = [
  { residency_id: '11', person_id: '1', relation: 'owner', is_account_holder: true, move_in_date: '2024-01-15', user_code: 30001, full_name: 'Ayşe Yılmaz', has_account: true },
  { residency_id: '12', person_id: '2', relation: 'owner', is_account_holder: false, move_in_date: null, user_code: null, full_name: 'Ali Yılmaz', has_account: false },
];

describe('coklu malik rotalari: zincir', () => {
  it('4 rota; hepsi authRequired ile baslar; yazma ucları yazma, okuma ucu okuma hiz siniriyla', () => {
    const summary = OWNER_ROUTES.map((r) => `${r.method.toUpperCase()} ${r.path}`).sort();
    assert.deepEqual(summary, [
      'GET /manager/sites/:siteCode/apartments/:apartmentId/owners',
      'POST /manager/sites/:siteCode/apartments/:apartmentId/owners',
      'POST /manager/sites/:siteCode/apartments/:apartmentId/owners/:residencyId/remove',
      'PUT /manager/sites/:siteCode/apartments/:apartmentId/owners/account-holder',
    ]);
    for (const route of OWNER_ROUTES) {
      // ORIGINAL zincir: before() ilk iki eleman degistirdi; yine de sayi ve sira korunur
      assert.equal(route.handlers.length, 3, `${route.method} ${route.path}: kimlik + hiz siniri + isleyici`);
    }
  });

  it('kaynakta: okuma ucu peopleReadLimiter, yazma uclari peopleWriteLimiter kullanir', async () => {
    const { readFileSync } = await import('node:fs');
    const source = readFileSync(new URL('../src/modules/people_routes.js', import.meta.url), 'utf8').replace(/\r\n/g, '\n');
    const block = source.slice(source.indexOf('// --- Malikler'), source.indexOf('// --- Araçlar'));
    assert.match(block, /peopleRouter\.get\(\s*'\/manager\/sites\/:siteCode\/apartments\/:apartmentId\/owners',\s*authRequired,\s*peopleReadLimiter,/);
    assert.equal((block.match(/authRequired,\s*peopleWriteLimiter,/g) ?? []).length, 3);
    assert.equal((block.match(/write: true/g) ?? []).length, 3, 'uc yazma ucu write:true ile yetki cozer');
    assert.equal(typeof authRequired, 'function');
  });
});

describe('coklu malik rotalari: yetki matrisi', () => {
  it('GET owners: yonetici, super ve kurul okur; sakin / gorevli / ilgisiz 403 FORBIDDEN_ROLE; baska sitenin yoneticisi 403 FORBIDDEN_SITE', async () => {
    seedOwners(ROWS);
    for (const user of [users.mgrA, users.superUser, users.board]) {
      const res = await call('GET', owners(), { user });
      assert.equal(res.status, 200, user.full_name);
    }
    for (const user of [users.resident, users.staff, users.outsider]) {
      const res = await call('GET', owners(), { user });
      assert.equal(res.status, 403, user.full_name);
      assert.equal(res.body.code, 'FORBIDDEN_ROLE', user.full_name);
    }
    const other = await call('GET', owners(), { user: users.mgrB });
    assert.equal(other.status, 403);
    assert.equal(other.body.code, 'FORBIDDEN_SITE');
  });

  it('yazma uclari: kurul, sakin, gorevli, ilgisiz 403 FORBIDDEN_ROLE; baska sitenin yoneticisi 403 FORBIDDEN_SITE; hicbiri DB yazmaz', async () => {
    const requests = [
      ['POST', owners(), { person_id: 5 }],
      ['PUT', `${owners()}/account-holder`, { residency_id: 11 }],
      ['POST', `${owners()}/12/remove`, {}],
    ];
    for (const [method, path, body] of requests) {
      for (const user of [users.board, users.resident, users.staff, users.outsider]) {
        const res = await call(method, path, { user, body });
        assert.equal(res.status, 403, `${method} ${path} ${user.full_name}`);
        assert.equal(res.body.code, 'FORBIDDEN_ROLE', `${method} ${path} ${user.full_name}`);
      }
      const other = await call(method, path, { user: users.mgrB, body });
      assert.equal(other.status, 403);
      assert.equal(other.body.code, 'FORBIDDEN_SITE');
    }
    assert.equal(state.log.some((q) => /^(INSERT|UPDATE|DELETE)\b/.test(q.sql)), false);
  });
});

describe('coklu malik rotalari: girdi dogrulama (DB yazmadan 400)', () => {
  it('POST owners: bos govde, hem person_id hem person, gecersiz kimlik / ad / telefon / e-posta / bayrak', async () => {
    const bad = [
      {},
      { person_id: 5, person: { full_name: 'Ali Veli' } },
      { person_id: 'x' },
      { person_id: -3 },
      { person: 'Ali Veli' },
      { person: { full_name: 'A' } },
      { person: { full_name: 'Ali Veli', phone: '123' } },
      { person: { full_name: 'Ali Veli', email: 'gecersiz' } },
      { person_id: 5, make_account_holder: 'evet' },
      { person_id: 5, move_in_date: '31.02.2024' },
    ];
    for (const body of bad) {
      const res = await call('POST', owners(), { body });
      assert.equal(res.status, 400, JSON.stringify(body));
      assert.equal(res.body.code, 'INVALID_BODY', JSON.stringify(body));
    }
    assert.equal(state.log.some((q) => /^(INSERT|UPDATE|DELETE)\b/.test(q.sql)), false);
  });

  it('PUT account-holder ve remove: gecersiz govde / kimlik 400 ya da 404', async () => {
    for (const body of [{}, { residency_id: 'x' }, { residency_id: 0 }]) {
      const res = await call('PUT', `${owners()}/account-holder`, { body });
      assert.equal(res.status, 400, JSON.stringify(body));
      assert.equal(res.body.code, 'INVALID_BODY');
    }
    const badRemove = await call('POST', `${owners()}/12/remove`, { body: { new_account_holder_residency_id: 'abc' } });
    assert.equal(badRemove.status, 400);
    assert.equal(badRemove.body.code, 'INVALID_BODY');
    const badId = await call('POST', `${owners()}/abc/remove`, { body: {} });
    assert.equal(badId.status, 404);
    assert.equal(badId.body.code, 'OWNER_NOT_FOUND');
  });
});

describe('coklu malik rotalari: GET yanit bicimi', () => {
  it('owners: muhatap basta, hesap muhatabi kimligi, sinir; kullanici kodu / telefon / e-posta YOK', async () => {
    seedOwners([...ROWS].reverse());
    const res = await call('GET', owners(), { user: users.board });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, {
      apartment_id: 301,
      label: 'A Blok - Daire 5',
      owners: [
        { residency_id: 11, person_id: 1, full_name: 'Ayşe Yılmaz', has_account: true, is_account_holder: true, move_in_date: '2024-01-15' },
        { residency_id: 12, person_id: 2, full_name: 'Ali Yılmaz', has_account: false, is_account_holder: false, move_in_date: null },
      ],
      account_holder_residency_id: 11,
      owner_limit: 10,
    });
    assert.doesNotMatch(JSON.stringify(res.body), /user_code|phone|email|30001/);
  });

  it('dairede malik yoksa owners [] ve muhatap null; olmayan / baska sitenin dairesi 404 APARTMENT_NOT_FOUND', async () => {
    seedOwners([]);
    const empty = await call('GET', owners());
    assert.equal(empty.status, 200);
    assert.deepEqual(empty.body.owners, []);
    assert.equal(empty.body.account_holder_residency_id, null);
    const missing = await call('GET', owners(SITE_1, 999));
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'APARTMENT_NOT_FOUND');
    const bad = await call('GET', owners(SITE_1, 'abc'));
    assert.equal(bad.status, 404);
    assert.equal(bad.body.code, 'APARTMENT_NOT_FOUND');
  });

  it('sorgular site kapsamli: daire sorgusu (daire kimligi, site kodu) ikilisiyle gider', async () => {
    seedOwners(ROWS);
    await call('GET', owners());
    const lookup = state.log.find((q) => /FROM apartments a INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.id = \$1 AND a\.site_code = \$2/.test(q.sql));
    assert.ok(lookup, 'daire sorgusu bulundu');
    assert.deepEqual(lookup.params, [301, SITE_1]);
  });
});
