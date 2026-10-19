// Karar Defteri uçları (DB'siz, KATI sahte veritabanı): rota zinciri + hız sınırları, yetki / modül kapısı sırası (biçim -> yetki -> site -> modül), kurul salt okur,
// görevli 403, doğrulama hatalarının (400 INVALID_FIELD { field }) işlem açmadan dönmesi, IDOR (başka site 403 / görünmeyen karar 404), gövde boyutu, kesinleştirme
// akışı (numara danışma kilidi altında; kesin karar idempotent, PATCH / DELETE 409 DECISION_FINAL + ROLLBACK), sakin uçları. Kimlik katmanı sahte (x-test-user).
// Gerçek PostgreSQL doğrulaması (değişmezlik tetikleyicisi, numara yarışı, site silme, görünürlük): scripts/qa_platform_pg.mjs "decision_book".
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import { decisionBookRouter, decisionReadLimiter, decisionWriteLimiter } from '../src/modules/decision_book_routes.js';

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
    residentSites: [SITE],
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
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 LIMIT 1$/.test(sql)) return ok(state.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(params[1] === 'decision_book' ? [{ enabled: state.moduleEnabled }] : []);
  }
  if (/^SELECT DISTINCT year FROM board_decisions WHERE site_code = \$1 ORDER BY year DESC$/.test(sql)) return ok([{ year: 2026 }, { year: 2025 }]);
  if (/^SELECT .* FROM board_decisions d .* WHERE d\.site_code = \$1/.test(sql)) {
    assert.ok([SITE, OTHER_SITE].includes(Number(params[0])), 'her yönetim sorgusu site_code taşır');
    return ok();
  }
  if (/^WITH my_sites AS MATERIALIZED/.test(sql)) {
    assert.equal(Number(params[0]), users.resident.user_code, 'sakin sorgusu çağıranın kullanıcı koduyla başlar');
    if (/SELECT EXISTS \(SELECT 1 FROM my_sites WHERE site_code = \$2\) AS related$/.test(sql)) return ok([{ related: state.residentSites.includes(Number(params[1])) }]);
    assert.match(sql, /d\.status = 'kesin' AND d\.visibility = 'sakinler' AND d\.site_code IN \(SELECT site_code FROM my_sites\)/, 'görünürlük süzgeci her sakin sorgusunda');
    return ok();
  }
  throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
}

const ORIGINAL_ROUTES = decisionBookRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({ path: layer.route.path, method: Object.keys(layer.route.methods)[0], handlers: layer.route.stack.map((entry) => entry.handle) }));

let server;
let baseUrl;

before(async () => {
  for (const layer of decisionBookRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    layer.route.stack[1].handle = (_req, _res, next) => next(); // hız sınırlayıcılar ayrı testte sınanır
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(decisionBookRouter);
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

const url = (suffix = '', site = SITE) => `/manager/sites/${site}/decisions${suffix}`;
const GOOD = { meeting_type: 'genel_kurul', meeting_date: '2026-05-10', title: 'Asansör', body: 'Asansör bakım firması değiştirilecektir.', vote_result: 'kabul' };

describe('rota zinciri ve hız sınırları', () => {
  it('sözleşmedeki 8 uç vardır; her biri authRequired ile BAŞLAR, ikinci halka hız sınırlayıcıdır (GET okuma, diğerleri yazma)', () => {
    const routes = ORIGINAL_ROUTES.map((route) => `${route.method.toUpperCase()} ${route.path}`);
    assert.deepEqual([...routes].sort(), [
      'DELETE /manager/sites/:siteCode/decisions/:id',
      'GET /app/decisions',
      'GET /app/decisions/:id',
      'GET /manager/sites/:siteCode/decisions',
      'GET /manager/sites/:siteCode/decisions/:id',
      'PATCH /manager/sites/:siteCode/decisions/:id',
      'POST /manager/sites/:siteCode/decisions',
      'POST /manager/sites/:siteCode/decisions/:id/finalize',
    ].sort());
    for (const route of ORIGINAL_ROUTES) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}`);
      assert.equal(route.handlers[1], route.method === 'get' ? decisionReadLimiter : decisionWriteLimiter, `${route.method} ${route.path}`);
    }
  });

  it('yazma 120/saat, okuma 1200/saat (429 + Retry-After)', () => {
    const fire = (limiter, userCode, times) => {
      const statuses = [];
      for (let i = 0; i < times; i += 1) {
        const req = { authUser: { user_code: userCode }, ip: `10.0.3.${userCode % 200}`, headers: {}, socket: { remoteAddress: `10.0.3.${userCode % 200}` } };
        const headers = {};
        const res = {
          setHeader: (key, value) => { headers[key] = value; },
          status(code) { statuses.push([code, headers['Retry-After']]); return { json() {} }; },
        };
        limiter(req, res, () => statuses.push([200]));
      }
      return statuses;
    };
    for (const [limiter, max, user] of [[decisionWriteLimiter, 120, 779001], [decisionReadLimiter, 1200, 779003]]) {
      const statuses = fire(limiter, user, max + 1);
      assert.equal(statuses.slice(0, max).every(([code]) => code === 200), true);
      assert.equal(statuses[max][0], 429);
      assert.ok(Number(statuses[max][1]) > 0);
    }
  });
});

describe('yönetim uçları: sıra biçim -> yetki -> site -> modül (yetki matrisi)', () => {
  it('geçersiz site kodu 400 INVALID_SITE_CODE (veritabanına gitmeden)', async () => {
    const res = await call('GET', '/manager/sites/abc/decisions', { user: users.manager });
    assert.deepEqual([res.status, res.body.code], [400, 'INVALID_SITE_CODE']);
    assert.equal(log.length, 0);
  });

  it('sakin / görevli (STAFF) / ilgisiz 403 FORBIDDEN_ROLE (okuma dahil); başka sitenin yöneticisi 403 FORBIDDEN_SITE; olmayan site 404', async () => {
    for (const user of [users.resident, users.staff, users.outsider]) {
      for (const [method, path, body] of [['GET', url()], ['GET', url('/5')], ['POST', url(), GOOD], ['POST', url('/5/finalize'), {}]]) {
        const res = await call(method, path, { user, body });
        assert.deepEqual([res.status, res.body.code], [403, 'FORBIDDEN_ROLE'], `${user.full_name} ${method} ${path}`);
      }
    }
    const other = await call('GET', url(), { user: users.otherManager });
    assert.deepEqual([other.status, other.body.code], [403, 'FORBIDDEN_SITE']);
    const otherWrite = await call('POST', url('/5/finalize'), { user: users.otherManager, body: {} });
    assert.deepEqual([otherWrite.status, otherWrite.body.code], [403, 'FORBIDDEN_SITE']);
    const missing = await call('GET', '/manager/sites/1999999999/decisions', { user: users.superUser });
    assert.deepEqual([missing.status, missing.body.code], [404, 'SITE_NOT_FOUND']);
  });

  it('modül KAPALI: yetkili herkes 403 MODULE_DISABLED { module: decision_book }; yetki modülden ÖNCE denetlenir', async () => {
    state.moduleEnabled = false;
    for (const user of [users.superUser, users.manager, users.board]) {
      const res = await call('GET', url(), { user });
      assert.deepEqual([res.status, res.body.code, res.body.module], [403, 'MODULE_DISABLED', 'decision_book']);
    }
    assert.equal((await call('GET', url(), { user: users.staff })).body.code, 'FORBIDDEN_ROLE');
    assert.equal((await call('POST', url(), { user: users.manager, body: GOOD })).body.code, 'MODULE_DISABLED');
  });

  it('yönetici / süper / kurul listeyi okur: { items, next_before_id, next_cursor, years }', async () => {
    for (const user of [users.manager, users.superUser, users.board]) {
      const res = await call('GET', url('?status=taslak&year=2026&meeting_type=genel_kurul&q=asans%C3%B6r'), { user });
      assert.equal(res.status, 200, user.full_name);
      assert.deepEqual(res.body, { items: [], next_before_id: null, next_cursor: null, years: [2026, 2025] });
    }
  });

  it('kurul salt okur: POST / PATCH / DELETE / finalize 403 FORBIDDEN_ROLE (iş mantığına hiç girmeden)', async () => {
    const attempts = [
      call('POST', url(), { user: users.board, body: GOOD }),
      call('PATCH', url('/5'), { user: users.board, body: { title: 'x' } }),
      call('DELETE', url('/5'), { user: users.board }),
      call('POST', url('/5/finalize'), { user: users.board, body: {} }),
    ];
    for (const res of await Promise.all(attempts)) assert.deepEqual([res.status, res.body.code], [403, 'FORBIDDEN_ROLE']);
  });

  it('POST / PATCH doğrulama hataları işlem açmadan 400 INVALID_FIELD { field }; görünmez / bozuk kimlik 404 DECISION_NOT_FOUND', async () => {
    for (const [over, field] of [
      [{ title: '' }, 'title'],
      [{ meeting_type: 'kurul' }, 'meeting_type'],
      [{ meeting_date: '2026-02-30' }, 'meeting_date'],
      [{ vote_result: null }, 'vote_result'],
      [{ visibility: 'herkes' }, 'visibility'],
      [{ votes_for: -2 }, 'votes_for'],
      [{ supersedes_id: 'abc' }, 'supersedes_id'],
    ]) {
      const res = await call('POST', url(), { user: users.manager, body: { ...GOOD, ...over } });
      assert.deepEqual([res.status, res.body.code, res.body.field], [400, 'INVALID_FIELD', field], JSON.stringify(over));
    }
    const patchBad = await call('PATCH', url('/5'), { user: users.manager, body: { body: '' } });
    assert.deepEqual([patchBad.status, patchBad.body.code, patchBad.body.field], [400, 'INVALID_FIELD', 'body']);
    for (const [method, path, body] of [['PATCH', url('/abc'), { title: 'x' }], ['DELETE', url('/abc')], ['POST', url('/abc/finalize'), {}], ['GET', url('/abc')], ['GET', url('/77')]]) {
      const res = await call(method, path, { user: users.manager, body });
      assert.deepEqual([res.status, res.body.code], [404, 'DECISION_NOT_FOUND'], path);
    }
  });

  it('liste sorgusu geçersizse 400 INVALID_QUERY; 64 KB üstü gövde 413 BODY_TOO_LARGE', async () => {
    for (const query of ['?status=bogus', '?year=26', '?cursor=xyz', '?limit=0', '?meeting_type=x']) {
      const res = await call('GET', url(query), { user: users.manager });
      assert.deepEqual([res.status, res.body.code], [400, 'INVALID_QUERY'], query);
    }
    const big = await call('POST', url(), { user: users.manager, body: { ...GOOD, body: 'z'.repeat(70000) } });
    assert.deepEqual([big.status, big.body.code], [413, 'BODY_TOO_LARGE']);
  });
});

describe('yazma işlemleri (sahte işlem istemcisi)', () => {
  const at = new Date('2026-05-11T10:00:00Z');
  let row;
  let tx;

  function installTx() {
    tx = [];
    pool.connect = async () => ({
      release: () => tx.push('RELEASE'),
      query: async (text, params = []) => {
        const sql = norm(text);
        tx.push(sql);
        if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || /^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /.test(sql)) return ok();
        if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return ok([{ site_code: String(params[0]) }]);
        if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return ok([{ user_code: params[0] }]);
        if (/^SELECT id, status, year, .* FROM board_decisions WHERE site_code = \$1 AND id = \$2 FOR UPDATE$/.test(sql)) {
          assert.deepEqual(params.map(Number), [SITE, 5]);
          return ok([{ ...row }]);
        }
        if (/^SELECT pg_advisory_xact_lock\(hashtext\(\$1\)\)$/.test(sql)) {
          assert.equal(params[0], `board_decisions_no:${SITE}:2026`);
          return ok();
        }
        if (/^SELECT COALESCE\(MAX\(decision_no\), 0\) \+ 1 AS n FROM board_decisions WHERE site_code = \$1 AND year = \$2 AND decision_no IS NOT NULL$/.test(sql)) return ok([{ n: 4 }]);
        if (/^UPDATE board_decisions SET status = 'kesin', decision_no = \$3, finalized_at = NOW\(\), finalized_by = \$4, updated_at = NOW\(\) WHERE site_code = \$1 AND id = \$2$/.test(sql)) {
          Object.assign(row, { status: 'kesin', decision_no: params[2], finalized_by: params[3], finalized_at: at });
          return ok();
        }
        if (/^INSERT INTO audit_log /.test(sql)) return ok();
        throw new Error(`BEKLENMEYEN İŞLEM SQL: ${sql.slice(0, 200)}`);
      },
    });
    pool.query = async (text, params) => {
      const sql = norm(text);
      if (/FROM board_decisions d .* WHERE d\.site_code = \$1 AND d\.id = \$2 LIMIT 1$/.test(sql)) {
        return ok([{ ...row, site_code: String(SITE), title: 'Asansör', body: 'Metin', attendees: null, votes_for: null, votes_against: null, votes_abstain: null, supersedes_id: null, created_by: 20001, created_by_full_name: 'Yönetici', created_by_deleted: false, finalized_by_full_name: 'Yönetici', finalized_by_deleted: false, created_at: at, updated_at: at }]);
      }
      if (/^SELECT r\.supersedes_id, r\.id, r\.year, r\.decision_no FROM board_decisions r WHERE r\.site_code = ANY\(\$1::BIGINT\[\]\) AND r\.supersedes_id = ANY\(\$2::BIGINT\[\]\) AND r\.status = 'kesin' ORDER BY/.test(sql)) return ok();
      return fakeQuery(text, params);
    };
  }

  beforeEach(() => {
    row = { id: '5', status: 'taslak', year: 2026, decision_no: null, finalized_by: null, finalized_at: null, meeting_type: 'genel_kurul', meeting_date: '2026-05-10', vote_result: 'kabul', visibility: 'yonetim' };
    installTx();
  });

  it('finalize: taslak -> kesin; numara danışma kilidi (site, yıl) altında MAX + 1; audit yazılır; COMMIT', async () => {
    const res = await call('POST', url('/5/finalize'), { user: users.manager, body: {} });
    assert.equal(res.status, 200);
    assert.deepEqual([res.body.decision.status, res.body.decision.decision_no, res.body.decision.number_label, res.body.decision.finalized_by_name], ['kesin', 4, '2026/4', 'Yönetici']);
    const lockAt = tx.findIndex((sql) => /pg_advisory_xact_lock/.test(sql));
    const maxAt = tx.findIndex((sql) => /COALESCE\(MAX\(decision_no\)/.test(sql));
    const rowAt = tx.findIndex((sql) => /FOR UPDATE$/.test(sql));
    assert.ok(rowAt < lockAt && lockAt < maxAt, 'satır kilidi -> numara kilidi -> MAX');
    assert.ok(tx.some((sql) => /^INSERT INTO audit_log /.test(sql)) && tx.includes('COMMIT'));
  });

  it('finalize idempotent: zaten kesin karar AYNEN döner (200; UPDATE / numara kilidi / audit YOK)', async () => {
    Object.assign(row, { status: 'kesin', decision_no: 2, finalized_by: 20001, finalized_at: at });
    const res = await call('POST', url('/5/finalize'), { user: users.manager, body: {} });
    assert.deepEqual([res.status, res.body.decision.number_label], [200, '2026/2']);
    assert.ok(!tx.some((sql) => /^UPDATE |pg_advisory_xact_lock|^INSERT INTO audit_log /.test(sql)));
  });

  it('finalize: toplantı tarihi gelmemiş taslak 409 DECISION_MEETING_IN_FUTURE (Türkçe ileti); numara kilidi / MAX / UPDATE / audit YOK, ROLLBACK', async () => {
    const nextYear = new Date().getUTCFullYear() + 1;
    Object.assign(row, { meeting_date: `${nextYear}-01-15`, year: nextYear });
    const res = await call('POST', url('/5/finalize'), { user: users.manager, body: {} });
    assert.deepEqual([res.status, res.body.code, res.body.error], [409, 'DECISION_MEETING_IN_FUTURE', 'Toplantı tarihi gelmemiş karar kesinleştirilemez.']);
    assert.ok(!tx.some((sql) => /pg_advisory_xact_lock|COALESCE\(MAX|^UPDATE |^INSERT INTO audit_log /.test(sql)));
    assert.ok(tx.includes('ROLLBACK') && !tx.includes('COMMIT') && tx.at(-1) === 'RELEASE');
    assert.equal(row.status, 'taslak');
  });

  it('kesin karar PATCH / DELETE 409 DECISION_FINAL: UPDATE / DELETE / audit gitmez, ROLLBACK', async () => {
    Object.assign(row, { status: 'kesin', decision_no: 2, finalized_by: 20001, finalized_at: at });
    for (const [method, body] of [['PATCH', { title: 'Yeni' }], ['DELETE', undefined]]) {
      installTx();
      const res = await call(method, url('/5'), { user: users.manager, body });
      assert.deepEqual([res.status, res.body.code], [409, 'DECISION_FINAL'], method);
      assert.ok(!tx.some((sql) => /^(UPDATE|DELETE|INSERT INTO audit_log)/.test(sql)), method);
      assert.ok(tx.includes('ROLLBACK') && !tx.includes('COMMIT') && tx.at(-1) === 'RELEASE', method);
    }
  });
});

describe('sakin uçları', () => {
  it('bozuk / görünmeyen kimlik 404 DECISION_NOT_FOUND; her sorgu görünürlük süzgeci (kesin + sakinler + my_sites) taşır', async () => {
    for (const path of ['/app/decisions/abc', '/app/decisions/7']) {
      const res = await call('GET', path, { user: users.resident });
      assert.deepEqual([res.status, res.body.code], [404, 'DECISION_NOT_FOUND'], path);
    }
  });

  it('liste: sakini olmadığı site_code boş liste (modül durumu sızmaz); sakini olduğu sitede modül kapalıysa 403 MODULE_DISABLED; aksi { items, next_before_id, next_cursor, years }', async () => {
    const foreign = await call('GET', `/app/decisions?site_code=${OTHER_SITE}`, { user: users.resident });
    assert.deepEqual([foreign.status, foreign.body], [200, { items: [], next_before_id: null, next_cursor: null, years: [] }]);
    state.moduleEnabled = false;
    const off = await call('GET', `/app/decisions?site_code=${SITE}`, { user: users.resident });
    assert.deepEqual([off.status, off.body.code, off.body.module], [403, 'MODULE_DISABLED', 'decision_book']);
    state.moduleEnabled = true;
    const on = await call('GET', `/app/decisions?site_code=${SITE}&year=2026&limit=10`, { user: users.resident });
    assert.deepEqual([on.status, on.body], [200, { items: [], next_before_id: null, next_cursor: null, years: [] }]);
    const all = await call('GET', '/app/decisions', { user: users.resident });
    assert.equal(all.status, 200);
    const bad = await call('GET', '/app/decisions?year=abc', { user: users.resident });
    assert.deepEqual([bad.status, bad.body.code], [400, 'INVALID_QUERY']);
  });
});
