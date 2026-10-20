// Aidat ve Finans (Faz 4a) uçları (DB'siz): rota zinciri, hız sınırları, yetki matrisi (yönetici / süper / kurul / görevli / sakin / başka site),
// modül kapalı, doğrulama (DB'ye dokunmadan 400), işlem sırası (kilit sırası), 40P01 tek yeniden deneme, kurul yanıtı temizliği, hata biçimleri.
// Kimlik katmanı sahte (x-test-user); pool.query / pool.connect KATI sahte veritabanına bağlanır. Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "finance".
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import { financeReadLimiter, financeResidentLimiter, financeRouter, financeWriteLimiter } from '../src/modules/finance_routes.js';
import { SYNC_STEPS } from '../src/modules/people_sync_sql.js';
import { resetPeopleSyncThrottle } from '../src/modules/people_sync.js';

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
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
const STEP_SQLS = new Set(SYNC_STEPS.map((step) => norm(step.sql)));

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
    ],
    financeEnabled: new Map([[SITE_1, true], [SITE_2, true]]),
    log: [],
    failAdvisory: 0,
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
  if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) {
    if (params[1] !== 'finance') return ok();
    return state.financeEnabled.has(Number(params[0])) && state.financeEnabled.get(Number(params[0])) ? ok([{ enabled: true }]) : ok();
  }
  return null;
}

function installFakeDb() {
  const run = async (text, params, client) => {
    const sql = norm(text);
    state.log.push({ sql, params: params ?? [], client });
    if (state.failAdvisory > 0 && /^SELECT pg_advisory_xact_lock/.test(sql)) {
      state.failAdvisory -= 1;
      throw Object.assign(new Error('deadlock detected'), { code: '40P01' });
    }
    for (const [pattern, fn] of handlers) {
      if (pattern.test(sql)) return typeof fn === 'function' ? fn(sql, params ?? []) : fn;
    }
    const a = access(sql, params ?? []);
    if (a) return a;
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql) || /^SELECT pg_advisory_xact_lock/.test(sql) || /^(SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT) /.test(sql) || /^INSERT INTO audit_log/.test(sql)) return ok();
    if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/.test(sql)) return ok(state.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
    if (STEP_SQLS.has(sql)) return ok();
    if (/^SELECT pg_try_advisory_xact_lock/.test(sql)) return ok([{ locked: true }]);
    if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return ok([{ user_code: params?.[0] }]);
    if (/^SELECT DISTINCT site_code FROM \(/.test(sql)) return ok();
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 220)}`);
  };
  pool.query = async (text, params) => run(text, params, false);
  pool.connect = async () => ({ query: (text, params) => run(text, params, true), release() {} });
}

const ORIGINAL_ROUTES = financeRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({
    path: layer.route.path,
    method: Object.keys(layer.route.methods)[0],
    handlers: layer.route.stack.map((entry) => entry.handle),
  }));

let server;
let baseUrl;

before(async () => {
  for (const layer of financeRouter.stack) {
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
  app.use(financeRouter);
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
  handlers = [];
  installFakeDb();
  resetPeopleSyncThrottle();
  mock.method(console, 'error', () => {});
  mock.method(console, 'log', () => {});
});

afterEach(() => {
  mock.restoreAll();
  financeReadLimiter.reset();
  financeWriteLimiter.reset();
  financeResidentLimiter.reset();
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

const base = (site = SITE_1) => `/manager/sites/${site}/finance`;
const writes = () => state.log.filter((e) => /^(INSERT INTO (ledger_entries|fee_runs|fee_definitions|finance_period_closures)|UPDATE |DELETE )/.test(e.sql));

// ---------------------------------------------------------------------------
// Rota zinciri ve hız sınırları
// ---------------------------------------------------------------------------

describe('finans rotaları: zincir', () => {
  it('17 rota; hepsi authRequired ile başlar; yazma uçları 120/saat, okuma + önizleme 1200/saat, sakin 600/saat sınırlayıcı ile', () => {
    const summary = ORIGINAL_ROUTES.map((r) => `${r.method.toUpperCase()} ${r.path}`).sort();
    assert.deepEqual(summary, [
      'GET /app/my-finance',
      'GET /manager/sites/:siteCode/finance/apartments/:apartmentId/account',
      'GET /manager/sites/:siteCode/finance/balances',
      'GET /manager/sites/:siteCode/finance/definitions',
      'GET /manager/sites/:siteCode/finance/periods',
      'GET /manager/sites/:siteCode/finance/summary',
      'PATCH /manager/sites/:siteCode/finance/definitions/:id',
      'POST /manager/sites/:siteCode/finance/charges',
      'POST /manager/sites/:siteCode/finance/charges/preview',
      'POST /manager/sites/:siteCode/finance/definitions',
      'POST /manager/sites/:siteCode/finance/definitions/:id/post',
      'POST /manager/sites/:siteCode/finance/definitions/:id/preview',
      'POST /manager/sites/:siteCode/finance/entries/:id/correct',
      'POST /manager/sites/:siteCode/finance/entries/:id/reverse',
      'POST /manager/sites/:siteCode/finance/payments',
      'POST /manager/sites/:siteCode/finance/periods/:period/close',
      'POST /manager/sites/:siteCode/finance/periods/:period/reopen',
    ]);
    const expectedLimiter = (route) => {
      if (route.path === '/app/my-finance') return financeResidentLimiter;
      if (route.method === 'get' || route.path.endsWith('/preview')) return financeReadLimiter;
      return financeWriteLimiter;
    };
    for (const route of ORIGINAL_ROUTES) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}: authRequired ilk`);
      assert.equal(route.handlers[1], expectedLimiter(route), `${route.method} ${route.path}: hız sınırlayıcı`);
    }
  });

  it('hız sınırları: yazma 120/saat, okuma 1200/saat, sakin 600/saat (kullanıcı başına); 429 + Retry-After; başka kullanıcı etkilenmez', () => {
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
    for (const [limiter, max] of [[financeWriteLimiter, 120], [financeResidentLimiter, 600], [financeReadLimiter, 1200]]) {
      for (let i = 0; i < max; i += 1) assert.equal(run(limiter, 7).passed, true, `${max}/${i}`);
      const blocked = run(limiter, 7);
      assert.equal(blocked.res.statusCode, 429, `${max}`);
      assert.ok(Number(blocked.res.headers['Retry-After']) > 0);
      assert.ok(blocked.res.body.retry_after_seconds > 0);
      assert.equal(run(limiter, 8).passed, true, 'başka kullanıcı etkilenmez');
    }
  });
});

// ---------------------------------------------------------------------------
// Yetki matrisi ve modül
// ---------------------------------------------------------------------------

describe('finans: yetki matrisi ve modül kapalı', () => {
  const emptyDefinitions = () => [
    [/^SELECT COUNT\(\*\)::INTEGER AS total FROM fee_definitions d WHERE/, () => ok([{ total: 0 }])],
    [/^SELECT d\.id, d\.name, d\.kind/, () => ok()],
  ];

  it('GET definitions: yönetici / süper / kurul 200; görevli / sakin / ilgisiz 403 FORBIDDEN_ROLE; başka site yöneticisi 403 FORBIDDEN_SITE', async () => {
    handlers.push(...emptyDefinitions());
    for (const user of [users.mgrA, users.superUser, users.board]) {
      const res = await call('GET', `${base()}/definitions`, { user });
      assert.equal(res.status, 200, user.full_name);
      assert.deepEqual(res.body, { items: [], total: 0 });
    }
    for (const user of [users.staff, users.resident, users.outsider]) {
      const res = await call('GET', `${base()}/definitions`, { user });
      assert.equal(res.status, 403, user.full_name);
      assert.equal(res.body.code, 'FORBIDDEN_ROLE');
    }
    const other = await call('GET', `${base()}/definitions`, { user: users.mgrB });
    assert.equal(other.status, 403);
    assert.equal(other.body.code, 'FORBIDDEN_SITE');
  });

  it('kurul YALNIZ okur: tüm POST / PATCH uçları 403 FORBIDDEN_ROLE ve veritabanına HİÇ yazılmaz', async () => {
    const probes = [
      ['POST', '/definitions'], ['PATCH', '/definitions/1'], ['POST', '/definitions/1/preview'], ['POST', '/definitions/1/post'], ['POST', '/charges/preview'], ['POST', '/charges'],
      ['POST', '/payments'], ['POST', '/entries/1/reverse'], ['POST', '/entries/1/correct'], ['POST', `/periods/2026-10/close`], ['POST', `/periods/2026-10/reopen`],
    ];
    for (const [method, suffix] of probes) {
      const res = await call(method, `${base()}${suffix}`, { user: users.board, body: {} });
      assert.equal(res.status, 403, `${method} ${suffix}`);
      assert.equal(res.body.code, 'FORBIDDEN_ROLE', `${method} ${suffix}`);
    }
    assert.deepEqual(writes(), []);
    assert.equal(state.log.some((e) => e.sql === 'BEGIN'), false);
  });

  it('dönem yeniden açma YALNIZ süper kullanıcı: site yöneticisi 403 FORBIDDEN_ROLE', async () => {
    const res = await call('POST', `${base()}/periods/2026-10/reopen`, { user: users.mgrA, body: {} });
    assert.equal(res.status, 403);
    assert.equal(res.body.code, 'FORBIDDEN_ROLE');
    assert.equal(state.log.some((e) => e.sql === 'BEGIN'), false);
  });

  it('modül KAPALI: yönetici, süper ve kurul 403 MODULE_DISABLED { module: finance }; rol denetimi modülden ÖNCE (görevli FORBIDDEN_ROLE)', async () => {
    state.financeEnabled.set(SITE_1, false);
    const reads = ['/definitions', '/balances', '/periods', '/summary', '/apartments/5/account'];
    for (const user of [users.mgrA, users.superUser, users.board]) {
      for (const suffix of reads) {
        const res = await call('GET', `${base()}${suffix}`, { user });
        assert.equal(res.status, 403, `${user.full_name} ${suffix}`);
        assert.deepEqual(res.body, { error: 'Aidat ve Finans modülü kapalı.', code: 'MODULE_DISABLED', module: 'finance' });
      }
    }
    for (const user of [users.mgrA, users.superUser]) {
      const res = await call('POST', `${base()}/payments`, { user, body: {} });
      assert.equal(res.status, 403);
      assert.equal(res.body.code, 'MODULE_DISABLED');
      assert.equal(res.body.module, 'finance');
    }
    const staff = await call('GET', `${base()}/definitions`, { user: users.staff });
    assert.equal(staff.body.code, 'FORBIDDEN_ROLE');
    assert.deepEqual(writes(), []);
  });

  it('geçersiz site kodu 400; olmayan site 404 (süper)', async () => {
    const bad = await call('GET', '/manager/sites/abc/finance/definitions', { user: users.superUser });
    assert.equal(bad.status, 400);
    assert.equal(bad.body.code, 'INVALID_SITE_CODE');
    const missing = await call('GET', '/manager/sites/999999999/finance/definitions', { user: users.superUser });
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'SITE_NOT_FOUND');
  });
});

// ---------------------------------------------------------------------------
// Doğrulama: DB'ye yazmadan 400
// ---------------------------------------------------------------------------

describe('finans: gövde doğrulaması veritabanına dokunmadan 400', () => {
  const cases = [
    ['POST', '/payments', { apartment_id: 5, amount_minor: 100.5, entry_date: '2026-10-01', method: 'cash', idempotency_key: 'k' }],
    ['POST', '/payments', { apartment_id: 5, amount_minor: '100', entry_date: '2026-10-01', method: 'cash', idempotency_key: 'k' }],
    ['POST', '/payments', { apartment_id: 5, amount_minor: 100, entry_date: '2999-01-01', method: 'cash', idempotency_key: 'k' }],
    ['POST', '/payments', { apartment_id: 5, amount_minor: 100, entry_date: '2026-10-01', method: 'cash' }],
    ['POST', '/payments', { apartment_id: 5, amount_minor: 1e21, entry_date: '2026-10-01', method: 'cash', idempotency_key: 'k' }],
    ['POST', '/definitions', { name: 'x', kind: 'recurring', distribution: 'fixed', amount_minor: 1.5, due_day: 5, start_period: '2026-01', target: { type: 'site' } }],
    ['POST', '/definitions', { name: 'x', kind: 'recurring', distribution: 'fixed', amount_minor: 100, due_day: 40, start_period: '2026-01', target: { type: 'site' } }],
    ['POST', '/charges', { name: 'x', distribution: 'equal', amount_minor: -5, target: { type: 'site' }, expected_total_minor: 1, expected_apartment_count: 1 }],
    ['POST', '/payments', { apartment_id: 5, amount_minor: 100, entry_date: '2002-10-01', method: 'cash', idempotency_key: 'k' }],
    ['POST', '/charges', { name: 'x', distribution: 'equal', amount_minor: 100, target: { type: 'site' }, expected_total_minor: 100, expected_apartment_count: 1, expected_hash: 'a'.repeat(64) }],
    ['POST', '/charges', { name: 'x', distribution: 'equal', amount_minor: 100, target: { type: 'site' }, expected_total_minor: 100, expected_apartment_count: 1, idempotency_key: 'k' }],
    ['POST', '/charges', { name: 'x', distribution: 'equal', amount_minor: 100, target: { type: 'site' }, due_date: '2002-01-01', expected_total_minor: 100, expected_apartment_count: 1, expected_hash: 'a'.repeat(64), idempotency_key: 'k' }],
    ['POST', '/entries/7/reverse', { reason: 'x'.repeat(201) }],
    ['POST', '/entries/7/correct', { amount_minor: 100, entry_date: '2026-10-01', method: 'kart', idempotency_key: 'k' }],
    ['POST', '/periods/abc/close', {}],
    ['PATCH', '/definitions/3', {}],
  ];

  it(`${cases.length} geçersiz gövde: 400 INVALID_BODY; işlem açılmaz (BEGIN yok), yazma yok`, async () => {
    handlers.push([/^SELECT d\.id/, () => ok([])]);
    for (const [method, suffix, body] of cases) {
      state.log.length = 0;
      const res = await call(method, `${base()}${suffix}`, { body });
      // tanım yok/kimlik geçersiz yolları: 400 ya da (gövde ayrıştırılmadan önce kimlik) 404 değil -> gövde ÖNCE doğrulanır
      assert.equal(res.status, 400, `${method} ${suffix}: ${JSON.stringify(res.body)}`);
      assert.equal(res.body.code, 'INVALID_BODY', `${method} ${suffix}`);
      assert.equal(state.log.some((e) => e.sql === 'BEGIN'), false, `${method} ${suffix}: BEGIN`);
      assert.deepEqual(writes(), [], `${method} ${suffix}`);
    }
  });

  it('gövde dizi / bozuk: yine 400 (sunucu hatası değil)', async () => {
    const res = await fetch(`${baseUrl}${base()}/payments`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-test-user': encodeURIComponent(JSON.stringify(users.mgrA)) },
      body: '[1,2,3]',
    });
    assert.equal(res.status, 400);
  });

  it('geçersiz sorgu parametreleri 400 INVALID_QUERY (bakiyeler, ekstre, tanımlar)', async () => {
    handlers.push([/^SELECT a\.id, a\.unit_label, b\.block_name, a\.responsible_party/, () => ok([{ id: '5', unit_label: 'D1', block_name: 'A', responsible_party: 'both' }])]);
    for (const suffix of ['/balances?status=x', '/balances?limit=0', '/balances?offset=-1', '/definitions?kind=x', '/definitions?active=maybe', '/apartments/5/account?limit=abc', '/apartments/5/account?from=2026-13-01', '/apartments/5/account?before_id=x']) {
      const res = await call('GET', `${base()}${suffix}`, { user: users.mgrA });
      assert.equal(res.status, 400, suffix);
      assert.equal(res.body.code, 'INVALID_QUERY', suffix);
    }
  });
});

// ---------------------------------------------------------------------------
// İşlem sırası (kilit sırası) ve yeniden deneme
// ---------------------------------------------------------------------------

// 40 gün önce: 5 yıllık geri sınırın içinde, gelecek değil ve aynı yıl içinde kapalı dönem yok (testin yaşı ne olursa olsun geçerli)
const PAY_DATE = new Date(Date.now() - 40 * 86400000).toISOString().slice(0, 10);
const PAY_PERIOD = `${PAY_DATE.slice(0, 7)}-01`;
const PAYMENT_BODY = { apartment_id: 5, amount_minor: 50000, entry_date: PAY_DATE, method: 'cash', description: 'Nakit', idempotency_key: 'test-key-1' };

function paymentFlow({ balance = '-50000' } = {}) {
  const entryRow = {
    id: '77', apartment_id: '5', kind: 'payment', amount_minor: '-50000', period: PAY_PERIOD, entry_date: PAY_DATE, due_date: null, description: 'Nakit', method: 'cash', payer_party: 'both',
    definition_name: null, reverses_entry_id: null, reversed_by_entry_id: null, reversal_reason: null, created_by_name: 'Ayşe Yönetici', created_at: new Date(`${PAY_DATE}T09:00:00Z`), definition_id: null, run_id: null, idempotency_key: 'test-key-1',
  };
  return [
    [/^SELECT id, responsible_party FROM apartments WHERE id = \$1 AND site_code = \$2 FOR KEY SHARE$/, () => ok([{ id: '5', responsible_party: 'both' }])],
    [/WHERE l\.site_code = \$1 AND l\.idempotency_key = \$2 LIMIT 1$/, () => ok()],
    [/^SELECT 1 FROM finance_period_closures WHERE site_code = \$1 AND period >= \$2::DATE LIMIT 1$/, () => ok()],
    // Faz 4b: hesap gereksinimi (hesap yok) ve ayarlar (makbuz otomatik düzenleme KAPALI: bu test makbuz yolunu sınamaz; makbuz / hesap akışı finance4b_* testleri ve QA)
    [/^SELECT bool_or\(is_active\) AS has_active FROM finance_accounts WHERE site_code = \$1 AND opening_date <= \$2::DATE HAVING COUNT\(\*\) > 0$/, () => ok()],
    [/^SELECT receipts_auto_issue, .* FROM finance_settings WHERE site_code = \$1$/, () => ok([{ receipts_auto_issue: false, late_fee_enabled: false, late_fee_rate_bp: 500, late_fee_method: 'daily_30', late_fee_grace_days: 0, late_fee_start_period: null, reminders_enabled: false, reminder_min_overdue_minor: '5000', reminder_min_days_overdue: 5, reminder_min_interval_days: 14, reminder_max_consecutive: 3, settings_version: 1 }])],
    // İki hesap (İP-1A): hesap verilmedi -> varsayılan (açık borç yok -> oturanın hesabı; kiracı yok -> ev sahibi); tahsilat hesabının bakiyesi
    [/FROM ledger_entries l WHERE l\.site_code = \$1 AND l\.apartment_id = \$2 ORDER BY l\.id$/, () => ok()],
    [/^SELECT a\.responsible_party, EXISTS/, () => ok([{ responsible_party: 'both', has_tenant: false }])],
    [/^SELECT COALESCE\(SUM\(l\.amount_minor\), 0\)::TEXT AS balance FROM ledger_entries l WHERE l\.site_code = \$1 AND l\.apartment_id = \$2 AND COALESCE/, () => ok([{ balance }])],
    [/^INSERT INTO ledger_entries \(/, () => ok([{ id: '77' }])],
    [/WHERE l\.id = \$1 AND l\.site_code = \$2 LIMIT 1$/, () => ok([entryRow])],
    [/^SELECT COALESCE\(SUM\(amount_minor\), 0\)::TEXT AS balance FROM ledger_entries WHERE site_code = \$1 AND apartment_id = \$2$/, () => ok([{ balance }])],
  ];
}

describe('finans: işlem sırası ve yeniden deneme', () => {
  it('tahsilat: BEGIN -> sites FOR KEY SHARE -> finance_post advisory kilidi -> modül denetimi -> daire FOR KEY SHARE -> işlemi yapan kullanıcı FOR KEY SHARE -> INSERT -> audit -> COMMIT; 201 { entry, balance_minor }', async () => {
    handlers.push(...paymentFlow());
    const res = await call('POST', `${base()}/payments`, { body: PAYMENT_BODY });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.deepEqual(Object.keys(res.body), ['entry', 'balance_minor', 'account_balance_minor', 'receipt', 'movement_id']);
    assert.equal(res.body.account_balance_minor, -50000);
    assert.equal(res.body.receipt, null, 'makbuz otomatik düzenleme kapalı');
    assert.equal(res.body.movement_id, null, 'hesap yok: 4a davranışı');
    assert.equal(res.body.entry.kind, 'payment');
    assert.equal(res.body.entry.amount_minor, -50000);
    assert.equal(res.body.entry.period, PAY_PERIOD.slice(0, 7));
    assert.equal(res.body.balance_minor, -50000);
    const txLog = state.log.filter((e) => e.client);
    const order = txLog.map((e) => e.sql);
    const idx = (pattern) => order.findIndex((s) => pattern.test(s));
    const begin = idx(/^BEGIN$/);
    const siteLock = idx(/^SELECT site_code FROM sites WHERE site_code = \$1 FOR KEY SHARE$/);
    const advisory = idx(/^SELECT pg_advisory_xact_lock/);
    const moduleCheck = idx(/^SELECT enabled FROM site_modules/);
    const apartment = idx(/FROM apartments WHERE id = \$1 AND site_code = \$2 FOR KEY SHARE/);
    const actorLock = idx(/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/);
    const insert = idx(/^INSERT INTO ledger_entries/);
    const audit = idx(/^INSERT INTO audit_log/);
    const commit = idx(/^COMMIT$/);
    assert.ok(begin === 0 && siteLock > begin && advisory > siteLock && moduleCheck > advisory && apartment > moduleCheck && actorLock > apartment && insert > actorLock && audit > insert && commit > audit, JSON.stringify(order));
    assert.equal(txLog[advisory].params[0], `finance_post:${SITE_1}`);
    assert.equal(order.filter((s) => s === 'COMMIT').length, 1);
    // kayıt: tutar defterde NEGATİF kuruş (metin), dönem ayın ilk günü, ödeyen taraf dairenin değeri, işlem anahtarı
    const insertParams = txLog[insert].params;
    assert.deepEqual(insertParams.slice(0, 9), [SITE_1, 5, '-50000', PAY_PERIOD, PAY_DATE, 'both', 'cash', 'Nakit', 'test-key-1']);
    // İP-1A: hesap (gövdede yok -> varsayılan ev sahibi) ve kaynak izi (yönetici tahsilatı = manual)
    assert.deepEqual(insertParams.slice(10), ['owner', 'manual', null]);
  });

  it('İP-1A: gövdedeki account_party tahsilatın hesabıdır (varsayılan sorgusu çalışmaz); geçersiz hesap 400 ve işlem açılmaz', async () => {
    handlers.push(...paymentFlow());
    const res = await call('POST', `${base()}/payments`, { body: { ...PAYMENT_BODY, account_party: 'tenant' } });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    const txLog = state.log.filter((e) => e.client);
    const insert = txLog.find((e) => /^INSERT INTO ledger_entries/.test(e.sql));
    assert.deepEqual(insert.params.slice(10), ['tenant', 'manual', null]);
    assert.equal(txLog.some((e) => /ORDER BY l\.id$/.test(e.sql)), false, 'varsayılan hesap sorgusu yok');
    state.log.length = 0;
    const bad = await call('POST', `${base()}/payments`, { body: { ...PAYMENT_BODY, account_party: 'both' } });
    assert.equal(bad.status, 400);
    assert.equal(bad.body.code, 'INVALID_BODY');
    assert.equal(state.log.some((e) => e.sql === 'BEGIN'), false);
  });

  it('kilit çıkmazı (40P01): işlem TEK SEFER baştan denenir -> 201; ilk deneme ROLLBACK', async () => {
    handlers.push(...paymentFlow());
    state.failAdvisory = 1;
    const res = await call('POST', `${base()}/payments`, { body: PAYMENT_BODY });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    const sqls = state.log.filter((e) => e.client).map((e) => e.sql);
    assert.equal(sqls.filter((s) => s === 'BEGIN').length, 2);
    assert.equal(sqls.filter((s) => s === 'ROLLBACK').length, 1);
    assert.equal(sqls.filter((s) => s === 'COMMIT').length, 1);
    assert.equal(sqls.filter((s) => s.startsWith('INSERT INTO ledger_entries')).length, 1, 'tek kayıt');
  });

  it('40P01 ikinci kez de olursa daha fazla denenmez: 500 + errorId, iç ayrıntı sızmaz', async () => {
    handlers.push(...paymentFlow());
    state.failAdvisory = 2;
    const res = await call('POST', `${base()}/payments`, { body: PAYMENT_BODY });
    assert.equal(res.status, 500);
    assert.equal(typeof res.body.errorId, 'string');
    assert.equal(res.body.error, 'Tahsilat kaydedilemedi.');
    assert.equal(JSON.stringify(res.body).includes('deadlock'), false);
    assert.equal(state.log.filter((e) => e.sql === 'BEGIN').length, 2);
    assert.deepEqual(writes(), []);
  });

  it('beklenmeyen veritabanı hatası: 500 + errorId, ayrıntı sızmaz; işlem geri alınır', async () => {
    handlers.push(...paymentFlow());
    handlers.unshift([/^INSERT INTO ledger_entries \(/, () => {
      throw Object.assign(new Error('SECRET_DB_DETAIL'), { code: 'XX000' });
    }]);
    const res = await call('POST', `${base()}/payments`, { body: PAYMENT_BODY });
    assert.equal(res.status, 500);
    assert.equal(JSON.stringify(res.body).includes('SECRET_DB_DETAIL'), false);
    assert.ok(state.log.some((e) => e.sql === 'ROLLBACK'));
    assert.equal(state.log.some((e) => e.sql === 'COMMIT'), false);
  });

  it('kapalı dönem: 409 PERIOD_CLOSED, INSERT yok, ROLLBACK', async () => {
    handlers.push(...paymentFlow());
    handlers.unshift([/^SELECT 1 FROM finance_period_closures WHERE site_code = \$1 AND period >= \$2::DATE LIMIT 1$/, () => ok([{ x: 1 }])]);
    const res = await call('POST', `${base()}/payments`, { body: PAYMENT_BODY });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'PERIOD_CLOSED');
    assert.equal(state.log.some((e) => e.sql.startsWith('INSERT INTO ledger_entries')), false);
    assert.ok(state.log.some((e) => e.sql === 'ROLLBACK'));
  });

  it('IDOR: başka sitenin dairesi 404 APARTMENT_NOT_FOUND (daire sorgusu site_code ile)', async () => {
    handlers.push(...paymentFlow());
    handlers.unshift([/^SELECT id, responsible_party FROM apartments WHERE id = \$1 AND site_code = \$2 FOR KEY SHARE$/, () => ok()]);
    const res = await call('POST', `${base()}/payments`, { body: PAYMENT_BODY });
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'APARTMENT_NOT_FOUND');
    const lookup = state.log.find((e) => e.sql.includes('FROM apartments WHERE id = $1 AND site_code = $2'));
    assert.deepEqual(lookup.params, [5, SITE_1]);
  });

  it('modül işlem içinde yeniden denetlenir: yazma sırasında kapatılmışsa 403 MODULE_DISABLED ve ROLLBACK', async () => {
    handlers.push(...paymentFlow());
    let calls = 0;
    handlers.unshift([/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/, () => {
      calls += 1;
      return calls === 1 ? ok([{ enabled: true }]) : ok();
    }]);
    const res = await call('POST', `${base()}/payments`, { body: PAYMENT_BODY });
    assert.equal(res.status, 403);
    assert.equal(res.body.code, 'MODULE_DISABLED');
    assert.ok(state.log.some((e) => e.sql === 'ROLLBACK'));
  });
});

// ---------------------------------------------------------------------------
// Kurul yanıtı temizliği ve okuma şekli
// ---------------------------------------------------------------------------

describe('finans: okuma uçları ve kurul yanıtı temizliği', () => {
  const accountRow = (overrides = {}) => ({
    id: '9', apartment_id: '5', kind: 'charge', amount_minor: '150000', period: '2026-10-01', entry_date: '2026-10-01', due_date: '2026-10-05', description: null, method: null, payer_party: 'both',
    definition_name: 'Aidat', reverses_entry_id: null, reversed_by_entry_id: null, reversal_reason: null, created_by_name: 'Ayşe Yönetici', created_at: new Date('2026-10-01T09:00:00Z'), ...overrides,
  });

  function accountHandlers() {
    return [
      [/^SELECT a\.id, a\.unit_label, b\.block_name, a\.responsible_party FROM apartments a INNER JOIN site_blocks b ON b\.id = a\.block_id WHERE a\.id = \$1 AND a\.site_code = \$2 LIMIT 1$/, (_sql, params) => (Number(params[1]) === SITE_1 && Number(params[0]) === 5 ? ok([{ id: '5', unit_label: 'Daire 1', block_name: 'A Blok', responsible_party: 'both' }]) : ok())],
      [/^SELECT COALESCE\(SUM\(amount_minor\), 0\)::TEXT AS balance, COALESCE\(SUM\(amount_minor\) FILTER/, () => ok([{ balance: '150000', not_due: '0' }])],
      [/ORDER BY l\.entry_date DESC, l\.id DESC LIMIT/, () => ok([accountRow(), accountRow({ id: '8', created_by_name: 'Bora' })])],
    ];
  }

  it('ekstre: yönetici oluşturan adını görür; KURUL created_by_name NULL görür; tutarlar tamsayı kuruş; dönem YYYY-MM', async () => {
    handlers.push(...accountHandlers());
    const manager = await call('GET', `${base()}/apartments/5/account`, { user: users.mgrA });
    assert.equal(manager.status, 200, JSON.stringify(manager.body));
    assert.equal(manager.body.balance_minor, 150000);
    assert.equal(manager.body.overdue_minor, 150000);
    assert.deepEqual(manager.body.apartment, { id: 5, label: 'A Blok - Daire 1', block_name: 'A Blok', responsible_party: 'both' });
    assert.equal(manager.body.items[0].created_by_name, 'Ayşe Yönetici');
    assert.equal(manager.body.items[0].amount_minor, 150000);
    assert.equal(manager.body.items[0].period, '2026-10');
    assert.equal(manager.body.next_before_id, null);
    const board = await call('GET', `${base()}/apartments/5/account`, { user: users.board });
    assert.equal(board.status, 200);
    assert.ok(board.body.items.every((e) => e.created_by_name === null));
    assert.equal(board.body.balance_minor, 150000);
  });

  it('ekstre sayfalama: limit 1 -> bir fazla satır okunur, next_before_id son satırın kimliği', async () => {
    handlers.push(...accountHandlers());
    const res = await call('GET', `${base()}/apartments/5/account?limit=1`, { user: users.mgrA });
    assert.equal(res.status, 200);
    assert.equal(res.body.items.length, 1);
    assert.equal(res.body.next_before_id, 9);
    const entrySql = state.log.find((e) => /ORDER BY l\.entry_date DESC, l\.id DESC LIMIT/.test(e.sql));
    assert.equal(entrySql.params[entrySql.params.length - 1], 2, 'limit + 1');
    assert.ok(entrySql.sql.includes('l.site_code = $1') && entrySql.sql.includes('l.apartment_id = $2'), 'her sorguda site_code');
  });

  it('IDOR: başka sitenin dairesi (ya da olmayan) 404 APARTMENT_NOT_FOUND; kimlik metin 404', async () => {
    handlers.push(...accountHandlers());
    assert.equal((await call('GET', `${base()}/apartments/99/account`)).body.code, 'APARTMENT_NOT_FOUND');
    assert.equal((await call('GET', `${base()}/apartments/abc/account`)).status, 404);
    assert.equal((await call('GET', `${base(SITE_2)}/apartments/5/account`, { user: users.mgrB })).status, 404, 'daire SITE_2\'ye ait değil');
  });

  it('dönemler: kurul kapatan adını göremez; open_period; closed_through', async () => {
    handlers.push([/^SELECT to_char\(c\.period, 'YYYY-MM-DD'\) AS period, c\.closed_at, u\.full_name AS closed_by_name FROM finance_period_closures c/, () => ok([
      { period: '2026-08-01', closed_at: new Date('2026-09-02T09:00:00Z'), closed_by_name: 'Ayşe Yönetici' },
      { period: '2026-09-01', closed_at: new Date('2026-10-02T09:00:00Z'), closed_by_name: 'Ayşe Yönetici' },
    ])]);
    const manager = await call('GET', `${base()}/periods`, { user: users.mgrA });
    assert.equal(manager.status, 200);
    assert.equal(manager.body.closed_through, '2026-09');
    assert.deepEqual(manager.body.closable, ['2026-10'], 'closed_through + 1 (bu ay ya da öncesi) tek kapatılabilir ay');
    assert.deepEqual(manager.body.items.map((i) => i.period), ['2026-09', '2026-08']);
    assert.equal(manager.body.items[0].closed_by_name, 'Ayşe Yönetici');
    assert.match(manager.body.open_period, /^\d{4}-\d{2}$/);
    const board = await call('GET', `${base()}/periods`, { user: users.board });
    assert.ok(board.body.items.every((i) => i.closed_by_name === null));
    assert.equal(board.body.closed_through, '2026-09');
  });

  it('sakin ucu /app/my-finance: hiç dairesi olmayan kullanıcı 200 { items: [] }', async () => {
    handlers.push([/FROM site_people sp INNER JOIN apartment_residencies r ON r\.person_id = sp\.id AND r\.is_current = TRUE/, () => ok()]);
    const res = await call('GET', '/app/my-finance', { user: users.resident });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { items: [] });
  });

  it('sakin ucu sorgusu çağıranın user_code\'una bağlanır (başkasının dairesi parametreyle seçilemez) ve family_member\'ı dışlar', async () => {
    handlers.push([/FROM site_people sp INNER JOIN apartment_residencies r ON r\.person_id = sp\.id AND r\.is_current = TRUE/, () => ok()]);
    await call('GET', '/app/my-finance?user_code=999&apartment_id=5', { user: users.resident });
    const query = state.log.find((e) => /FROM site_people sp INNER JOIN apartment_residencies r/.test(e.sql) && /family_member/.test(e.sql));
    assert.ok(query, 'görünürlük sorgusu çalışmadı');
    assert.deepEqual(query.params, [users.resident.id]);
    assert.match(query.sql, /r\.relation <> 'family_member'/);
    assert.match(query.sql, /s\.approval_status = 'approved'/);
    assert.match(query.sql, /sp\.user_code = \$1 AND sp\.is_active = TRUE/);
  });
});
