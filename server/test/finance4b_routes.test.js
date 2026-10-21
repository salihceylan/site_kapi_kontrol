// Finans Faz 4b uçları (DB'siz, KATI sahte veritabanı): rota listesi (sözleşme), hız sınırlayıcı zinciri, yetki matrisi (yönetici / süper / kurul / görevli / sakin /
// ilgisiz / başka site), modül kapalı, 5xx yanıtında iç ayrıntı yok. Kimlik katmanı sahte (x-test-user). Gerçek PostgreSQL: scripts/qa_finance4b.mjs.
//
// Yetkili çağıran, veritabanında ilk veri sorgusuna (sahte DB katı: BEKLENMEYEN SQL -> 500) ya da doğrulama hatasına (4xx) ulaşır; yetkisiz çağıran 403 alır ve
// veri sorgusu HİÇ çalışmaz.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired, requireSuperUser } from '../src/middlewares/auth_middleware.js';
import { financeReadLimiter, financeResidentLimiter, financeWriteLimiter } from '../src/modules/finance_routes.js';
import {
  exportLimiter,
  expenseUploadLimiter,
  finance4bRouter,
  receiptVerifyLimiter,
  reminderSendLimiter,
  reportLimiter,
} from '../src/modules/finance_4b_routes.js';

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
    sites: new Set([SITE_1, SITE_2]),
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
    return ok(state.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  }
  if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) {
    return params[1] === 'finance' && state.financeEnabled.get(Number(params[0])) ? ok([{ enabled: true }]) : ok();
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

const ORIGINAL = finance4bRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({ path: layer.route.path, method: Object.keys(layer.route.methods)[0].toUpperCase(), handlers: layer.route.stack.map((entry) => entry.handle) }));

let server;
let baseUrl;

before(async () => {
  for (const layer of finance4bRouter.stack) {
    if (!layer.route) continue;
    const stack = layer.route.stack;
    stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    // ara katmanlar (hız sınırlayıcılar, süper kullanıcı denetimi hariç) atlanır; zincir yapısı ORIGINAL ile ayrıca sınanır
    for (let i = 1; i < stack.length - 1; i += 1) {
      if (stack[i].handle !== requireSuperUser) stack[i].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json());
  app.use(finance4bRouter);
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

// Sözleşmedeki uç listesi (docs/PLATFORM_FINANS_4B.md "Uç noktalar"); her satır [yöntem, yol, tür]. Tür: read (kurul okur), write (yalnız yönetici/süper).
const MANAGER_ROUTES = [
  ['GET', '/settings', 'read'], ['PUT', '/settings', 'write'],
  ['POST', '/entries/1/receipt', 'write'], ['GET', '/receipts', 'read'], ['POST', '/receipts/verify', 'read'], ['GET', '/receipts/1', 'read'], ['POST', '/receipts/1/cancel', 'write'], ['POST', '/receipts/1/print', 'write'],
  ['GET', '/accounts', 'read'], ['POST', '/accounts', 'write'], ['POST', '/accounts/assign-payments/preview', 'write'], ['POST', '/accounts/assign-payments/commit', 'write'], ['PATCH', '/accounts/1', 'write'],
  ['GET', '/accounts/1/movements', 'read'], ['POST', '/accounts/1/adjustments', 'write'], ['GET', '/accounts/1/reconciliations', 'read'], ['POST', '/accounts/1/reconciliations', 'write'],
  ['GET', '/transfers', 'read'], ['POST', '/transfers', 'write'], ['POST', '/transfers/1/void', 'write'],
  ['GET', '/expense-categories', 'read'], ['POST', '/expense-categories', 'write'], ['PATCH', '/expense-categories/1', 'write'],
  ['GET', '/suppliers', 'read'], ['POST', '/suppliers', 'write'], ['PATCH', '/suppliers/1', 'write'],
  ['POST', '/expenses', 'write'], ['GET', '/expenses', 'read'], ['GET', '/expenses/1', 'read'], ['POST', '/expenses/1/void', 'write'], ['POST', '/expenses/1/correct', 'write'],
  ['POST', '/expenses/1/documents', 'write'], ['PUT', '/expenses/1/documents/1/content', 'write'], ['GET', '/expenses/1/documents/1/download', 'read'], ['DELETE', '/expenses/1/documents/1', 'write'],
  ['POST', '/late-fee/preview', 'write'], ['POST', '/late-fee/post', 'write'], ['GET', '/late-fee/runs', 'read'], ['GET', '/late-fee/runs/1/lines', 'read'], ['POST', '/late-fee/runs/1/void', 'write'],
  ['GET', '/reminders/exclusions', 'read'], ['PUT', '/reminders/exclusions/1', 'write'], ['DELETE', '/reminders/exclusions/1', 'write'], ['POST', '/reminders/preview', 'write'], ['POST', '/reminders/send', 'write'],
  ['GET', '/reminders/runs', 'read'], ['GET', '/reminders/runs/1', 'read'], ['POST', '/reminders/runs/1/cancel', 'write'],
  ['GET', '/reports/aging', 'read'], ['GET', '/reports/income-expense', 'read'], ['GET', '/reports/cash-position', 'read'], ['GET', '/reports/board-summary', 'read'], ['GET', '/apartments/1/statement', 'read'],
  ['GET', '/exports/finance_aging', 'write'],
  ['GET', '/expenses/nature-suggestion', 'read'], ['PUT', '/expenses/1/nature', 'write'], ['GET', '/reports/expense-analysis', 'read'],
];
const OTHER_ROUTES = [
  'GET /app/my-finance/entries/:entryId/late-fee', 'GET /app/my-finance/apartments/:id/statement', 'GET /app/my-finance/receipts', 'GET /app/my-finance/receipts/:id',
  'GET /admin/finance-legal-gate', 'PUT /admin/finance-legal-gate',
];

const toTemplate = (path) =>
  `${B(':siteCode').replace(':siteCode', ':siteCode')}${path}`
    .replace(/\/entries\/1\//, '/entries/:id/')
    .replace(/\/receipts\/1/, '/receipts/:id')
    .replace(/\/accounts\/1/, '/accounts/:id')
    .replace(/\/transfers\/1/, '/transfers/:id')
    .replace(/\/expense-categories\/1/, '/expense-categories/:id')
    .replace(/\/suppliers\/1/, '/suppliers/:id')
    .replace(/\/expenses\/1\/documents\/1/, '/expenses/:id/documents/:docId')
    .replace(/\/expenses\/1/, '/expenses/:id')
    .replace(/\/runs\/1/, '/runs/:id')
    .replace(/\/exclusions\/1/, '/exclusions/:apartmentId')
    .replace(/\/apartments\/1\//, '/apartments/:id/')
    .replace(/\/exports\/finance_aging/, '/exports/:kind');

describe('4b rota listesi ve zincir', () => {
  it('63 rota, sözleşmedeki listeyle birebir (ne eksik ne fazla)', () => {
    const expected = [
      ...MANAGER_ROUTES.map(([method, path]) => `${method} /manager/sites/:siteCode/finance${toTemplate(path).slice('/manager/sites/:siteCode/finance'.length)}`),
      ...OTHER_ROUTES,
    ].sort();
    const actual = ORIGINAL.map((route) => `${route.method} ${route.path}`).sort();
    assert.deepEqual(actual, expected);
    assert.equal(actual.length, 63);
    assert.equal(new Set(actual).size, 63, 'yinelenen rota yok');
  });

  it('hepsi authRequired ile başlar; yönetim uçlarında hız sınırlayıcı var: yazma -> yazma sınırlayıcı, okuma/önizleme -> okuma sınırlayıcı; sakin uçları sakin sınırlayıcı', () => {
    const writeMethods = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);
    for (const route of ORIGINAL) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}: authRequired ilk`);
      if (route.path.startsWith('/app/my-finance')) {
        assert.equal(route.handlers[1], financeResidentLimiter, `${route.path}: sakin sınırlayıcı`);
      } else if (route.path.startsWith('/admin/')) {
        assert.equal(route.handlers[1], requireSuperUser, `${route.path}: yalnız süper`);
      } else if (route.path.endsWith('/content')) {
        assert.equal(route.handlers[1], expenseUploadLimiter, 'içerik yükleme: 30/saat kullanıcı + 300/saat IP');
      } else if (writeMethods.has(route.method) && !route.path.endsWith('/preview') && !route.path.endsWith('/receipts/verify')) {
        assert.equal(route.handlers[1], financeWriteLimiter, `${route.method} ${route.path}: yazma sınırlayıcı`);
      } else {
        assert.equal(route.handlers[1], financeReadLimiter, `${route.method} ${route.path}: okuma sınırlayıcı`);
      }
    }
    const chain = (method, path) => ORIGINAL.find((route) => route.method === method && route.path === `/manager/sites/:siteCode/finance${path}`).handlers;
    assert.ok(chain('POST', '/reminders/send').includes(reminderSendLimiter), 'hatırlatma gönderimi 5/saat');
    assert.ok(chain('POST', '/receipts/verify').includes(receiptVerifyLimiter), 'makbuz doğrulama 60/saat');
    assert.ok(chain('GET', '/exports/:kind').includes(exportLimiter), 'dışa aktarma 30/saat');
    for (const path of ['/reports/aging', '/reports/income-expense', '/reports/cash-position', '/reports/board-summary', '/reports/expense-analysis', '/apartments/:id/statement']) {
      assert.ok(chain('GET', path).includes(reportLimiter), `${path}: ağır rapor 120/saat`);
    }
  });
});

describe('4b yetki matrisi', () => {
  const reachedData = () => state.dataLog.length > 0;

  for (const [method, suffix, kind] of MANAGER_ROUTES) {
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

  it('modül KAPALI: tüm yönetim uçları (yönetici, süper, kurul okuma) 403 MODULE_DISABLED { module: finance } ve veri sorgusu çalışmaz; rol denetimi modülden ÖNCE', async () => {
    state.financeEnabled.set(SITE_1, false);
    for (const [method, suffix, kind] of MANAGER_ROUTES) {
      const body = method === 'GET' ? undefined : {};
      for (const user of [users.mgrA, users.superUser, ...(kind === 'read' ? [users.board] : [])]) {
        const res = await call(method, `${B()}${suffix}`, { user, body });
        assert.equal(res.status, 403, `${user.full_name} ${method} ${suffix}`);
        assert.equal(res.body.code, 'MODULE_DISABLED', `${method} ${suffix}`);
        assert.equal(res.body.module, 'finance');
      }
      const staff = await call(method, `${B()}${suffix}`, { user: users.staff, body });
      assert.equal(staff.body.code, 'FORBIDDEN_ROLE', `${method} ${suffix}: rol önce`);
    }
    assert.equal(state.dataLog.length, 0);
  });

  it('süper kullanıcı hukuk bayrağı ucu: yönetici / sakin 403 (süper denetimi), süper veri katmanına ulaşır', async () => {
    for (const user of [users.mgrA, users.resident, users.board]) {
      for (const method of ['GET', 'PUT']) {
        const res = await call(method, '/admin/finance-legal-gate', { user, body: method === 'GET' ? undefined : { legal_ok: true } });
        assert.equal(res.status, 403, `${user.full_name} ${method}`);
      }
    }
    assert.equal(state.dataLog.length, 0);
    const res = await call('GET', '/admin/finance-legal-gate', { user: users.superUser });
    assert.notEqual(res.status, 403);
    assert.ok(state.dataLog.length > 0, 'süper için bayrak sorgusu çalışır');
  });

  it('sakin uçları (/app/my-finance/...) kimliği doğrulanmış her kullanıcı için kendi verisine bakar: 403 değil; sorgu kullanıcı kodunu taşır', async () => {
    for (const suffix of ['/receipts', '/receipts/1', '/entries/1/late-fee', '/apartments/1/statement']) {
      const res = await call('GET', `/app/my-finance${suffix}`, { user: users.resident });
      assert.notEqual(res.status, 403, suffix);
      assert.notEqual(res.status, 401, suffix);
    }
    assert.ok(state.dataLog.length > 0);
  });
});

describe('4b hata biçimleri', () => {
  it('beklenmeyen hata: 500 + errorId + genel mesaj; SQL / iç ayrıntı yanıtta YOK; günlükte kişisel veri yok', async () => {
    const res = await call('GET', `${B()}/accounts`, { user: users.mgrA });
    assert.equal(res.status, 500);
    assert.equal(typeof res.body.errorId, 'string');
    assert.equal(res.body.error, 'Hesaplar yüklenemedi.');
    assert.equal(JSON.stringify(res.body).includes('BEKLENMEYEN'), false);
    assert.equal(/SELECT|FROM|finance_accounts/i.test(JSON.stringify(res.body)), false);
    const logged = console.error.mock.calls.map((callEntry) => callEntry.arguments.join(' ')).join('\n');
    assert.equal(logged.includes('u20001@example.com'), false, 'e-posta günlüğe yazılmaz');
    assert.equal(logged.includes('Ayşe'), false, 'ad günlüğe yazılmaz');
  });

  it('doğrulama hatası DB\'ye dokunmadan 400 { error, code }: hesap oluşturma, gider, makbuz iptali, tazminat, dışa aktarma türü', async () => {
    const cases = [
      ['POST', '/accounts', {}], ['POST', '/expenses', {}], ['POST', '/receipts/1/cancel', {}], ['POST', '/transfers', {}], ['PUT', '/settings', {}], ['POST', '/receipts/verify', {}],
      ['POST', '/accounts/1/adjustments', {}], ['POST', '/reminders/send', {}], ['POST', '/expense-categories', {}], ['POST', '/suppliers', {}],
    ];
    for (const [method, suffix, body] of cases) {
      state.dataLog.length = 0;
      const res = await call(method, `${B()}${suffix}`, { body });
      assert.equal(res.status, 400, `${method} ${suffix}`);
      assert.equal(res.body.code, 'INVALID_BODY', `${method} ${suffix}`);
      assert.equal(typeof res.body.error, 'string');
      assert.equal(state.dataLog.length, 0, `${method} ${suffix}: DB'ye dokunmadı`);
    }
    for (const suffix of ['/receipts?kind=x', '/expenses?status=x', '/accounts/1/movements?limit=0', '/reports/aging?status=x', '/reports/income-expense?from=2020-01&to=2026-10']) {
      state.dataLog.length = 0;
      const res = await call('GET', `${B()}${suffix}`);
      assert.equal(res.status, 400, suffix);
      assert.ok(['INVALID_QUERY', 'INVALID_BODY'].includes(res.body.code), `${suffix}: ${res.body.code}`);
    }
  });

  it('dışa aktarma: bilinmeyen tür 404 EXPORT_KIND_NOT_FOUND (veri sorgusu çalışmaz); kurul 403', async () => {
    state.dataLog.length = 0;
    const res = await call('GET', `${B()}/exports/finance_xyz`);
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'EXPORT_KIND_NOT_FOUND');
    const board = await call('GET', `${B()}/exports/finance_aging`, { user: users.board });
    assert.equal(board.status, 403);
  });

  it('geçersiz site kodu 400 INVALID_SITE_CODE', async () => {
    const res = await call('GET', '/manager/sites/abc/finance/accounts');
    assert.equal(res.status, 400);
    assert.equal(res.body.code, 'INVALID_SITE_CODE');
  });
});
