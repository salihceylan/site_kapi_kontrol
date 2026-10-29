// Borç devri (089) ve alacak iadesi (088) uçları (DB'siz, KATI sahte veritabanı): rota listesi (sözleşme), sınırlayıcı zinciri, yetki matrisi (yönetici / süper / kurul / görevli / sakin /
// ilgisiz / başka site), doğrulama hataları veri sorgusuna ulaşmadan döner. Kimlik katmanı sahte (x-test-user). Gerçek PostgreSQL: scripts/qa_finance_devir_iade.mjs.
// Yetkili çağıran veritabanında ilk veri sorgusuna (sahte DB katı: BEKLENMEYEN SQL -> 500) ya da doğrulama hatasına (4xx) ulaşır; yetkisiz çağıran 403 alır ve veri sorgusu HİÇ çalışmaz.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';

process.env.JWT_SECRET ||= 'test-secret-test-secret-test-secret-123456';

const { pool } = await import('../src/db.js');
const { authRequired } = await import('../src/middlewares/auth_middleware.js');
const { financeReadLimiter, financeResidentLimiter, financeWriteLimiter } = await import('../src/modules/finance_routes.js');
const { financeLiabilityRouter } = await import('../src/modules/finance_liability_routes.js');
const { financeRefundRouter } = await import('../src/modules/finance_refund_routes.js');

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
    return params[1] === 'finance' ? ok([{ enabled: true }]) : ok();
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

const routesOf = (router) =>
  router.stack
    .filter((layer) => layer.route)
    .map((layer) => ({ path: layer.route.path, method: Object.keys(layer.route.methods)[0].toUpperCase(), handlers: layer.route.stack.map((entry) => entry.handle) }));
const ORIGINAL_LIABILITY = routesOf(financeLiabilityRouter);
const ORIGINAL_REFUND = routesOf(financeRefundRouter);

let server;
let baseUrl;

function stubAuth(router) {
  for (const layer of router.stack) {
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
}

before(async () => {
  stubAuth(financeLiabilityRouter);
  stubAuth(financeRefundRouter);
  const app = express();
  app.use(express.json());
  app.use(financeLiabilityRouter);
  app.use(financeRefundRouter);
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

// Sözleşmedeki yönetici uçları; her satır [yöntem, yol, tür]. Tür: read (kurul okur), write (yalnız yönetici / süper).
const ROUTES = [
  ['GET', '/liability-transfer/candidates', 'read'],
  ['GET', '/apartments/1/liability-transfer/preview', 'read'],
  ['POST', '/apartments/1/liability-transfer', 'write'],
  ['GET', '/apartments/1/liability-transfers', 'read'],
  ['POST', '/liability-transfers/1/reverse', 'write'],
  ['GET', '/refunds', 'read'],
  ['GET', '/refunds/1', 'read'],
  ['POST', '/refunds', 'write'],
  ['POST', '/refunds/1/approve', 'write'],
  ['POST', '/refunds/1/reject', 'write'],
  ['POST', '/refunds/1/reverse', 'write'],
];

describe('devir / iade rota listesi ve zincir', () => {
  it('yönetici uçları sözleşmedeki listeyle birebir; sakin iade uçları /app/my-finance/refund-requests altında', () => {
    const expected = ROUTES.map(([method, path]) => `${method} /manager/sites/:siteCode/finance${path.replace('/apartments/1/', '/apartments/:apartmentId/').replace(/\/1(\/|$)/, '/:id$1')}`).sort();
    const actual = [...ORIGINAL_LIABILITY, ...ORIGINAL_REFUND].filter((route) => route.path.startsWith('/manager/')).map((route) => `${route.method} ${route.path}`).sort();
    assert.deepEqual(actual, expected);
    const resident = ORIGINAL_REFUND.filter((route) => route.path.startsWith('/app/')).map((route) => `${route.method} ${route.path}`).sort();
    assert.deepEqual(resident, ['GET /app/my-finance/refund-requests', 'POST /app/my-finance/refund-requests', 'POST /app/my-finance/refund-requests/:id/cancel']);
  });

  it('hepsi authRequired ile başlar; yönetici okuma uçları okuma, yazma uçları yazma sınırlayıcı; sakin uçları sakin sınırlayıcı', () => {
    for (const route of [...ORIGINAL_LIABILITY, ...ORIGINAL_REFUND]) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}`);
      const expected = route.path.startsWith('/app/') ? financeResidentLimiter : route.method === 'POST' ? financeWriteLimiter : financeReadLimiter;
      assert.equal(route.handlers[1], expected, `${route.method} ${route.path}: sınırlayıcı`);
    }
  });
});

describe('devir / iade yetki matrisi', () => {
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

  it('doğrulama hataları veri sorgusuna ulaşmadan 400 döner: devir gövdesi (özet / neden / anahtar), geri alma nedeni, iade talebi, onay hesabı, ret nedeni', async () => {
    const cases = [
      ['POST', '/apartments/1/liability-transfer', {}],
      ['POST', '/apartments/1/liability-transfer', { expected_total_minor: 1500, expected_hash: 'zz', reason: 'x', idempotency_key: 'k' }],
      ['POST', '/apartments/1/liability-transfer', { expected_total_minor: 1500, expected_hash: 'a'.repeat(64), idempotency_key: 'k' }],
      ['POST', '/apartments/1/liability-transfer', { expected_total_minor: 0, expected_hash: 'a'.repeat(64), reason: 'x', idempotency_key: 'k' }],
      ['POST', '/liability-transfers/1/reverse', { idempotency_key: 'k' }],
      ['POST', '/refunds', { apartment_id: 1, amount_minor: 100, idempotency_key: 'k' }],
      ['POST', '/refunds', { apartment_id: 1, account_party: 'owner', amount_minor: -5, idempotency_key: 'k' }],
      ['POST', '/refunds', { apartment_id: 1, account_party: 'baska', amount_minor: 5, idempotency_key: 'k' }],
      ['POST', '/refunds/1/approve', { idempotency_key: 'k' }],
      ['POST', '/refunds/1/approve', { pay_account_id: 'abc', idempotency_key: 'k' }],
      ['POST', '/refunds/1/reject', { idempotency_key: 'k' }],
      ['POST', '/refunds/1/reverse', { reason: 'x' }],
    ];
    for (const [method, suffix, body] of cases) {
      state.dataLog.length = 0;
      const res = await call(method, `${B()}${suffix}`, { body });
      assert.equal(res.status, 400, `${suffix} ${JSON.stringify(body)}`);
      assert.equal(res.body.code, 'INVALID_BODY');
      assert.equal(state.dataLog.length, 0, 'doğrulama hataları veritabanına gitmeden döner');
    }
  });

  it('geçersiz kimlik (path) 404 ve veri sorgusuna ulaşmaz: devir / iade kimliği sayı değilse', async () => {
    for (const [method, suffix] of [['GET', '/refunds/abc'], ['POST', '/refunds/abc/reject'], ['POST', '/liability-transfers/abc/reverse'], ['GET', '/apartments/abc/liability-transfers']]) {
      state.dataLog.length = 0;
      const res = await call(method, `${B()}${suffix}`, { body: method === 'GET' ? undefined : { reason: 'x', idempotency_key: 'k' } });
      assert.ok([404, 400].includes(res.status), `${method} ${suffix}: ${res.status}`);
      assert.equal(state.dataLog.length, 0, `${suffix}: veri sorgusu çalışmamalı`);
    }
  });

  it('5xx yanıtında iç ayrıntı sızmaz: errorId + genel mesaj', async () => {
    const res = await call('GET', `${B()}/refunds`);
    assert.equal(res.status, 500);
    assert.ok(res.body.errorId);
    assert.doesNotMatch(JSON.stringify(res.body), /BEKLENMEYEN|SELECT|finance_refunds/);
  });
});
