// Anket ve Oylama uçları (DB'siz, KATI sahte veritabanı): rota zinciri + hız sınırları, yetki / modül kapısı sırası (biçim -> yetki -> site -> modül), kurul salt okur,
// voters kurul 403, doğrulama hatalarının veritabanına hiç gitmeden dönmesi, IDOR (başka site 403 / görünmeyen anket 404), gövde boyutu. Kimlik katmanı sahte (x-test-user).
// Gerçek PostgreSQL doğrulaması (oy kuralları, hedef, geçişler, 40P01 = 0): scripts/qa_platform_pg.mjs "survey".
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import { surveyReadLimiter, surveyRouter, surveyVoteLimiter, surveyWriteLimiter } from '../src/modules/survey_routes.js';

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
    surveys: [],
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
    return ok(params[1] === 'survey' ? [{ enabled: state.moduleEnabled }] : []);
  }
  // Okuma sorguları (yalnız site_code ile): anket yoksa boş
  if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM surveys s WHERE s\.site_code = \$1/.test(sql)) return ok([{ n: 0 }]);
  if (/^SELECT id, anonymous FROM surveys WHERE site_code = \$1 AND id = \$2 LIMIT 1$/.test(sql)) {
    return ok(state.surveys.filter((s) => s.site_code === Number(params[0]) && s.id === Number(params[1])));
  }
  if (/FROM surveys s/.test(sql) && /s\.site_code = \$1/.test(sql)) {
    assert.ok(params.length >= 1 && Number(params[0]) === SITE || Number(params[0]) === OTHER_SITE, 'her yönetim sorgusu site_code taşır');
    return ok();
  }
  if (/FROM surveys s/.test(sql) && /am\.user_code = \$1/.test(sql)) return ok(); // sakin: kitle süzgeci her sorguda
  throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 200)}`);
}

const ORIGINAL_ROUTES = surveyRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({ path: layer.route.path, method: Object.keys(layer.route.methods)[0], handlers: layer.route.stack.map((entry) => entry.handle) }));

let server;
let baseUrl;

before(async () => {
  for (const layer of surveyRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    layer.route.stack[1].handle = (_req, _res, next) => next(); // hız sınırlayıcılar ayrı testte sınanır
  }
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(surveyRouter);
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

const url = (suffix = '', site = SITE) => `/manager/sites/${site}/surveys${suffix}`;
const GOOD = { title: 'Aidat', question: 'Aidat artsın mı?', options: ['Evet', 'Hayır'], target: { type: 'site' } };

describe('rota zinciri ve hız sınırları', () => {
  it('sözleşmedeki 11 uç vardır; her biri authRequired ile BAŞLAR, ikinci halka hız sınırlayıcıdır (oy: ayrı sınır)', () => {
    const routes = ORIGINAL_ROUTES.map((route) => `${route.method.toUpperCase()} ${route.path}`);
    assert.deepEqual([...routes].sort(), [
      'DELETE /manager/sites/:siteCode/surveys/:id',
      'GET /app/surveys',
      'GET /app/surveys/:id',
      'GET /manager/sites/:siteCode/surveys',
      'GET /manager/sites/:siteCode/surveys/:id',
      'GET /manager/sites/:siteCode/surveys/:id/voters',
      'PATCH /manager/sites/:siteCode/surveys/:id',
      'POST /app/surveys/:id/vote',
      'POST /manager/sites/:siteCode/surveys',
      'POST /manager/sites/:siteCode/surveys/:id/close',
      'POST /manager/sites/:siteCode/surveys/:id/open',
    ].sort());
    for (const route of ORIGINAL_ROUTES) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}`);
      const expected = route.method === 'get' ? surveyReadLimiter : route.path.endsWith('/vote') ? surveyVoteLimiter : surveyWriteLimiter;
      assert.equal(route.handlers[1], expected, `${route.method} ${route.path}`);
    }
  });

  it('yazma 120/saat, oy 60/saat, okuma 1200/saat (429 + Retry-After)', () => {
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
    for (const [limiter, max, user] of [[surveyWriteLimiter, 120, 778001], [surveyVoteLimiter, 60, 778002], [surveyReadLimiter, 1200, 778003]]) {
      const statuses = fire(limiter, user, max + 1);
      assert.equal(statuses.slice(0, max).every(([code]) => code === 200), true);
      assert.equal(statuses[max][0], 429);
      assert.ok(Number(statuses[max][1]) > 0);
    }
  });
});

describe('yönetim uçları: sıra biçim -> yetki -> site -> modül (yetki matrisi)', () => {
  it('geçersiz site kodu 400 INVALID_SITE_CODE (veritabanına gitmeden)', async () => {
    const res = await call('GET', '/manager/sites/abc/surveys', { user: users.manager });
    assert.equal(res.status, 400);
    assert.equal(res.body.code, 'INVALID_SITE_CODE');
    assert.equal(log.length, 0);
  });

  it('sakin / görevli / ilgisiz FORBIDDEN_ROLE; başka sitenin yöneticisi FORBIDDEN_SITE (IDOR); olmayan site (yetkili) 404 SITE_NOT_FOUND', async () => {
    for (const user of [users.resident, users.staff, users.outsider]) {
      const res = await call('GET', url(), { user });
      assert.deepEqual([res.status, res.body.code], [403, 'FORBIDDEN_ROLE'], user.full_name);
    }
    const other = await call('GET', url(), { user: users.otherManager });
    assert.deepEqual([other.status, other.body.code], [403, 'FORBIDDEN_SITE']);
    const otherWrite = await call('POST', url(), { user: users.otherManager, body: GOOD });
    assert.deepEqual([otherWrite.status, otherWrite.body.code], [403, 'FORBIDDEN_SITE']);
    const missing = await call('GET', '/manager/sites/1999999999/surveys', { user: users.superUser });
    assert.deepEqual([missing.status, missing.body.code], [404, 'SITE_NOT_FOUND']);
  });

  it('modül KAPALI: yetkili herkes 403 MODULE_DISABLED { module: survey }; yetki modülden ÖNCE denetlenir', async () => {
    state.moduleEnabled = false;
    for (const user of [users.superUser, users.manager, users.board]) {
      const res = await call('GET', url(), { user });
      assert.deepEqual([res.status, res.body.code, res.body.module], [403, 'MODULE_DISABLED', 'survey']);
    }
    assert.equal((await call('GET', url(), { user: users.outsider })).body.code, 'FORBIDDEN_ROLE');
    assert.equal((await call('POST', url(), { user: users.manager, body: GOOD })).body.code, 'MODULE_DISABLED');
  });

  it('yönetici / süper / kurul listeyi okur: { items, total }; her sorgu site_code taşır', async () => {
    for (const user of [users.manager, users.superUser, users.board]) {
      const res = await call('GET', url('?status=open'), { user });
      assert.equal(res.status, 200, user.full_name);
      assert.deepEqual(res.body, { items: [], total: 0 });
    }
  });

  it('kurul salt okur: POST / PATCH / DELETE / open / close / voters 403 FORBIDDEN_ROLE (iş mantığına hiç girmeden)', async () => {
    const attempts = [
      call('POST', url(), { user: users.board, body: GOOD }),
      call('PATCH', url('/5'), { user: users.board, body: { title: 'x' } }),
      call('DELETE', url('/5'), { user: users.board }),
      call('POST', url('/5/open'), { user: users.board, body: {} }),
      call('POST', url('/5/close'), { user: users.board, body: {} }),
      call('GET', url('/5/voters'), { user: users.board }),
    ];
    for (const res of await Promise.all(attempts)) assert.deepEqual([res.status, res.body.code], [403, 'FORBIDDEN_ROLE']);
  });

  it('voters: görünmeyen / başka sitenin anketi 404 SURVEY_NOT_FOUND; anonim ankette 409 INVALID_STATE', async () => {
    state.surveys = [{ id: 5, site_code: OTHER_SITE, anonymous: false }, { id: 6, site_code: SITE, anonymous: true }];
    const foreign = await call('GET', url('/5/voters'), { user: users.manager });
    assert.deepEqual([foreign.status, foreign.body.code], [404, 'SURVEY_NOT_FOUND']);
    const anonymous = await call('GET', url('/6/voters'), { user: users.manager });
    assert.deepEqual([anonymous.status, anonymous.body.code], [409, 'INVALID_STATE']);
    const badId = await call('GET', url('/abc/voters'), { user: users.superUser });
    assert.deepEqual([badId.status, badId.body.code], [404, 'SURVEY_NOT_FOUND']);
  });

  it('POST / PATCH doğrulama hataları (yetkili kullanıcı) işlem açmadan 400 INVALID_BODY; görünmez kimlik 404', async () => {
    for (const over of [{ title: '' }, { options: ['Tek'] }, { target: { type: 'blocks', block_ids: [] } }, { publish: 'yarın' }, { closes_at: '2000-01-01T00:00:00Z' }, { anonymous: 'evet' }]) {
      const res = await call('POST', url(), { user: users.manager, body: { ...GOOD, ...over } });
      assert.deepEqual([res.status, res.body.code], [400, 'INVALID_BODY'], JSON.stringify(over));
    }
    const empty = await call('PATCH', url('/5'), { user: users.manager, body: {} });
    assert.deepEqual([empty.status, empty.body.code], [400, 'INVALID_BODY']);
    for (const [method, path, body] of [['PATCH', url('/abc'), { title: 'x' }], ['DELETE', url('/abc')], ['POST', url('/abc/open'), {}], ['POST', url('/abc/close'), {}], ['GET', url('/abc')]]) {
      const res = await call(method, path, { user: users.manager, body });
      assert.deepEqual([res.status, res.body.code], [404, 'SURVEY_NOT_FOUND'], path);
    }
  });

  it('liste sorgusu geçersizse 400 INVALID_QUERY; 16 KB üstü gövde 413 BODY_TOO_LARGE', async () => {
    const res = await call('GET', url('?status=bogus'), { user: users.manager });
    assert.deepEqual([res.status, res.body.code], [400, 'INVALID_QUERY']);
    const big = await call('POST', url(), { user: users.manager, body: { ...GOOD, question: 'z'.repeat(20000) } });
    assert.deepEqual([big.status, big.body.code], [413, 'BODY_TOO_LARGE']);
  });

  it('open: closes_at geçmiş taslak 409 INVALID_STATE { from, to, closes_at_passed } (UPDATE / audit YOK, ROLLBACK, taslak kalır); NULL / gelecek closes_at açılır', async () => {
    const row = { id: 5, status: 'draft', closes_at: null, options: ['Evet', 'Hayır'], target_type: 'site', anonymous: true, one_vote_per_apartment: false };
    let tx = [];
    pool.connect = async () => ({
      release: () => tx.push('RELEASE'),
      query: async (text, params = []) => {
        const sql = norm(text);
        tx.push(sql);
        if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || /^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /.test(sql)) return ok();
        if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return ok([{ site_code: String(params[0]) }]);
        if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return ok([{ user_code: params[0] }]);
        if (/^SELECT id, status, closes_at, .* FROM surveys WHERE site_code = \$1 AND id = \$2 FOR UPDATE$/.test(sql)) {
          assert.deepEqual(params.map(Number), [SITE, 5]);
          return ok([{ ...row }]);
        }
        if (/^UPDATE surveys SET status = 'open', opened_at = NOW\(\)/.test(sql)) {
          row.status = 'open';
          return ok();
        }
        if (/^INSERT INTO audit_log /.test(sql)) return ok();
        throw new Error(`BEKLENMEYEN İŞLEM SQL: ${sql.slice(0, 200)}`);
      },
    });
    // Ayrıntı okuması (işlemden sonra, havuzdan): satır + oy sayımı
    pool.query = async (text, params) => {
      const sql = norm(text);
      if (/FROM surveys s LEFT JOIN users cu ON cu\.user_code = s\.created_by WHERE s\.site_code = \$1 AND s\.id = \$2 LIMIT 1$/.test(sql)) {
        const at = new Date();
        return ok([{ ...row, site_code: String(SITE), title: 'Aidat', question: 'Aidat artsın mı?', target_block_ids: [], target_apartment_ids: [], opened_at: at, closed_at: null, created_by: 20001, created_at: at, updated_at: at, created_by_name: 'Yönetici', total_votes: 0, eligible_count: 0 }]);
      }
      if (/^SELECT option_index, COUNT\(\*\)::INTEGER AS n FROM survey_votes WHERE survey_id = \$1 GROUP BY option_index$/.test(sql)) return ok();
      return fakeQuery(text, params);
    };

    row.closes_at = new Date(Date.now() - 60_000);
    const expired = await call('POST', url('/5/open'), { user: users.manager, body: {} });
    assert.deepEqual([expired.status, expired.body.code, expired.body.from, expired.body.to, expired.body.closes_at_passed], [409, 'INVALID_STATE', 'draft', 'open', true]);
    assert.match(expired.body.error, /Kapanış zamanı geçmiş/);
    assert.equal(row.status, 'draft', 'satır taslak kalır');
    assert.ok(!tx.some((sql) => /^UPDATE surveys/.test(sql)), 'UPDATE gitmez');
    assert.ok(!tx.some((sql) => /^INSERT INTO audit_log /.test(sql)), 'survey.opened audit yazılmaz');
    assert.ok(tx.includes('ROLLBACK') && !tx.includes('COMMIT') && tx.at(-1) === 'RELEASE', 'işlem geri alınır, bağlantı bırakılır');

    for (const closesAt of [new Date(Date.now() + 86_400_000), null]) {
      row.status = 'draft';
      row.closes_at = closesAt;
      tx = [];
      const opened = await call('POST', url('/5/open'), { user: users.manager, body: {} });
      assert.deepEqual([opened.status, opened.body.status, opened.body.effective_status], [200, 'open', 'open'], String(closesAt));
      assert.ok(tx.some((sql) => /^UPDATE surveys SET status = 'open'/.test(sql)) && tx.some((sql) => /^INSERT INTO audit_log /.test(sql)) && tx.includes('COMMIT') && !tx.includes('ROLLBACK'));
    }
  });
});

describe('sakin uçları', () => {
  it('oy: bozuk gövde 400 INVALID_BODY (hiçbir sorgu gitmez); görünmeyen / başka sitenin anketi 404 SURVEY_NOT_FOUND; bozuk kimlik 404', async () => {
    for (const body of [{}, { option_index: -1 }, { option_index: 'x' }]) {
      const res = await call('POST', '/app/surveys/5/vote', { user: users.resident, body });
      assert.deepEqual([res.status, res.body.code], [400, 'INVALID_BODY'], JSON.stringify(body));
    }
    assert.equal(log.length, 0);
    const invisible = await call('POST', '/app/surveys/5/vote', { user: users.resident, body: { option_index: 0 } });
    assert.deepEqual([invisible.status, invisible.body.code], [404, 'SURVEY_NOT_FOUND']);
    assert.ok(log.some((sql) => /am\.user_code = \$1/.test(sql) && /s\.status IN \('open', 'closed'\)/.test(sql)), 'görünürlük: kitle + open/closed');
    for (const [method, path] of [['GET', '/app/surveys/abc'], ['POST', '/app/surveys/abc/vote'], ['GET', '/app/surveys/7']]) {
      const res = await call(method, path, { user: users.resident, body: method === 'POST' ? { option_index: 0 } : undefined });
      assert.deepEqual([res.status, res.body.code], [404, 'SURVEY_NOT_FOUND'], path);
    }
  });

  it('liste: site_code verilmiş ve modül kapalıysa 403 MODULE_DISABLED; aksi hâlde { items, next_before_id }; bozuk sorgu 400', async () => {
    state.moduleEnabled = false;
    const closed = await call('GET', `/app/surveys?site_code=${SITE}`, { user: users.resident });
    assert.deepEqual([closed.status, closed.body.code, closed.body.module], [403, 'MODULE_DISABLED', 'survey']);
    state.moduleEnabled = true;
    const list = await call('GET', '/app/surveys', { user: users.resident });
    assert.deepEqual([list.status, list.body], [200, { items: [], next_before_id: null }]);
    const bad = await call('GET', '/app/surveys?limit=0', { user: users.resident });
    assert.deepEqual([bad.status, bad.body.code], [400, 'INVALID_QUERY']);
  });
});
