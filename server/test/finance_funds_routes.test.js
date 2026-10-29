// Kasa uçları (DB'siz, KATI sahte veritabanı): rota listesi (sözleşme), hız sınırlayıcı zinciri, yetki matrisi (yönetici / süper / kurul / görevli / sakin / ilgisiz / başka site),
// temel modül (Kural 25: satır kapalı olsa da MODULE_DISABLED yok). Kimlik katmanı sahte (x-test-user). Gerçek PostgreSQL: scripts/qa_finance_funds_section.mjs.
// Yetkili çağıran veritabanında ilk veri sorgusuna (sahte DB katı: BEKLENMEYEN SQL -> 500) ya da doğrulama hatasına (4xx) ulaşır; yetkisiz çağıran 403 alır ve veri sorgusu HİÇ çalışmaz.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { pool } = await import('../src/db.js');
const { authRequired } = await import('../src/middlewares/auth_middleware.js');
const { financeReadLimiter, financeWriteLimiter } = await import('../src/modules/finance_routes.js');
const { financeFundsRouter, fundsReportLimiter } = await import('../src/modules/finance_funds_routes.js');

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
let state;

function makeState() {
  return {
    managerLinks: [{ site_code: SITE_1, user_code: 20001 }, { site_code: SITE_2, user_code: 20002 }],
    memberships: [
      { site_code: SITE_1, user_code: 20005, role: 'STAFF', is_active: true },
      { site_code: SITE_1, user_code: 20004, role: 'RESIDENT', is_active: true },
      { site_code: SITE_1, user_code: 20006, role: 'BOARD_MEMBER', is_active: true },
    ],
    financeEnabled: new Map([[SITE_1, true], [SITE_2, true]]),
    dataLog: [],
  };
}

/** Yalnız yetki / modül sorguları cevaplanır; başka her şey "veri sorgusu" sayılır ve katı DB'de patlar. */
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
    return ok([{ site_code: String(params[0]) }]);
  }
  if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) {
    if (params[1] !== 'finance' || !state.financeEnabled.has(Number(params[0]))) return ok();
    return ok([{ enabled: state.financeEnabled.get(Number(params[0])) }]);
  }
  return null;
}

function installFakeDb() {
  const run = async (text, params) => {
    const sql = norm(text);
    const a = access(sql, params ?? []);
    if (a) return a;
    state.dataLog.push(sql);
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 160)}`);
  };
  pool.query = run;
  pool.connect = async () => ({ query: run, release() {} });
}

const ORIGINAL = financeFundsRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({ path: layer.route.path, method: Object.keys(layer.route.methods)[0].toUpperCase(), handlers: layer.route.stack.map((entry) => entry.handle) }));

let server;
let baseUrl;

before(async () => {
  for (const layer of financeFundsRouter.stack) {
    if (!layer.route) continue;
    const stack = layer.route.stack;
    stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    for (let i = 1; i < stack.length - 1; i += 1) {
      stack[i].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json());
  app.use(financeFundsRouter);
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
  installFakeDb();
  mock.method(console, 'error', () => {});
  mock.method(console, 'log', () => {});
});

afterEach(() => {
  mock.restoreAll();
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

const B = (site = SITE_1) => `/manager/sites/${site}/finance`;

// Sözleşmedeki uç listesi (docs/PLATFORM_FINANS_KASALAR.md 5); her satır [yöntem, yol, tür]. Tür: read (kurul okur), write (yalnız yönetici/süper).
const ROUTES = [
  ['GET', '/funds', 'read'],
  ['GET', '/funds/operating/movements', 'read'],
  ['GET', '/reports/period', 'read'],
  ['GET', '/fund-transfers', 'read'],
  ['POST', '/fund-transfers', 'write'],
  ['POST', '/fund-transfers/1/reverse', 'write'],
];

describe('kasa rota listesi ve zincir', () => {
  it('6 rota, sözleşmedeki listeyle birebir', () => {
    const expected = ROUTES.map(([method, path]) => `${method} /manager/sites/:siteCode/finance${path.replace('/operating/', '/:fund/').replace('/1/', '/:id/')}`).sort();
    const actual = ORIGINAL.map((route) => `${route.method} ${route.path}`).sort();
    assert.deepEqual(actual, expected);
  });

  it('hepsi authRequired ile başlar; okuma uçları okuma sınırlayıcı (+ rapor sınırlayıcı: özet ve döküm), yazma uçları yazma sınırlayıcı', () => {
    for (const route of ORIGINAL) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}`);
      assert.equal(route.handlers[1], route.method === 'POST' ? financeWriteLimiter : financeReadLimiter, `${route.method} ${route.path}: sınırlayıcı`);
    }
    for (const path of ['/manager/sites/:siteCode/finance/funds', '/manager/sites/:siteCode/finance/funds/:fund/movements', '/manager/sites/:siteCode/finance/reports/period']) {
      assert.ok(ORIGINAL.find((route) => route.path === path).handlers.includes(fundsReportLimiter), `${path}: ağır rapor sınırlayıcı`);
    }
  });
});

describe('kasa yetki matrisi', () => {
  const reachedData = () => state.dataLog.length > 0;

  for (const [method, suffix, kind] of ROUTES) {
    it(`${method} ${suffix}: yönetici ve süper geçer; ${kind === 'read' ? 'kurul okur' : 'kurul 403'}; görevli / sakin / ilgisiz / başka site yöneticisi 403 ve veri sorgusu HİÇ çalışmaz`, async () => {
      const send = (user, site = SITE_1) => call(method, `${B(site)}${suffix}`, { user, body: method === 'GET' ? undefined : {} });
      for (const user of [users.mgrA, users.superUser]) {
        const res = await send(user);
        assert.notEqual(res.status, 403, `${user.full_name}: yetkili`);
        assert.notEqual(res.status, 401, `${user.full_name}: yetkili`);
      }
      state.dataLog.length = 0;
      const board = await send(users.board);
      if (kind === 'read') {
        assert.notEqual(board.status, 403, 'kurul okur');
      } else {
        assert.equal(board.status, 403, 'kurul yazamaz');
        assert.equal(board.body.code, 'FORBIDDEN_ROLE');
        assert.equal(reachedData(), false, 'kurul için veri sorgusu çalışmamalı');
      }
      for (const user of [users.staff, users.resident, users.outsider]) {
        state.dataLog.length = 0;
        const res = await send(user);
        assert.equal(res.status, 403, user.full_name);
        assert.equal(res.body.code, 'FORBIDDEN_ROLE', user.full_name);
        assert.equal(reachedData(), false, `${user.full_name}: veri sorgusu çalışmamalı`);
      }
      state.dataLog.length = 0;
      const other = await send(users.mgrB);
      assert.equal(other.status, 403);
      assert.equal(other.body.code, 'FORBIDDEN_SITE');
      assert.equal(reachedData(), false);
    });
  }

  it('finans temel modül (Kural 25): site_modules finans satırı kapalı (ya da hiç yok) olsa bile MODULE_DISABLED YOK; rol denetimi aynen sürer', async () => {
    for (const row of [false, undefined]) {
      if (row === undefined) state.financeEnabled.delete(SITE_1);
      else state.financeEnabled.set(SITE_1, row);
      for (const [method, suffix, kind] of ROUTES) {
        const body = method === 'GET' ? undefined : {};
        for (const user of [users.mgrA, users.superUser, ...(kind === 'read' ? [users.board] : [])]) {
          const res = await call(method, `${B()}${suffix}`, { user, body });
          assert.notEqual(res.status, 403, `${user.full_name} ${method} ${suffix}`);
          assert.notEqual(res.body?.code, 'MODULE_DISABLED', `${user.full_name} ${method} ${suffix}`);
        }
        state.dataLog.length = 0;
        for (const user of [...(kind === 'read' ? [] : [users.board]), users.staff, users.resident, users.outsider]) {
          const res = await call(method, `${B()}${suffix}`, { user, body });
          assert.equal(res.status, 403);
          assert.equal(res.body.code, 'FORBIDDEN_ROLE');
        }
        assert.equal(state.dataLog.length, 0, 'yetkisizler için veri sorgusu çalışmamalı');
      }
    }
  });

  it('geçersiz kasa adı (path) 404 FUND_NOT_FOUND; geçersiz sorgu 400 INVALID_QUERY; geçersiz aktarım gövdesi 400 INVALID_BODY (veri sorgusuna ulaşmadan)', async () => {
    const notFound = await call('GET', `${B()}/funds/fon/movements`);
    assert.equal(notFound.status, 404);
    assert.equal(notFound.body.code, 'FUND_NOT_FOUND');
    assert.equal(state.dataLog.length, 0);
    const badQuery = await call('GET', `${B()}/funds/operating/movements?from=2026-10-02&to=2026-10-01`);
    assert.equal(badQuery.status, 400);
    assert.equal(badQuery.body.code, 'INVALID_QUERY');
    const badBody = await call('POST', `${B()}/fund-transfers`, { body: { from_fund: 'operating', to_fund: 'operating', amount_minor: 1, transfer_date: '2026-10-01', idempotency_key: 'k' } });
    assert.equal(badBody.status, 400);
    assert.equal(badBody.body.code, 'INVALID_BODY');
    assert.equal(state.dataLog.length, 0, 'doğrulama hataları veritabanına gitmeden döner');
  });

  it('5xx yanıtında iç ayrıntı sızmaz: errorId + genel mesaj', async () => {
    const res = await call('GET', `${B()}/funds`);
    assert.equal(res.status, 500);
    assert.ok(res.body.errorId);
    assert.doesNotMatch(JSON.stringify(res.body), /BEKLENMEYEN|SELECT|ledger_entries/);
  });
});
