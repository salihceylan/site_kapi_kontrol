// Firma ve Sözleşme Takibi uçları (DB'siz, KATI sahte veritabanı): rota zinciri + hız sınırları, yetki / modül kapısı sırası (biçim -> yetki -> site -> modül),
// yetki matrisi (yönetici / süper yazar; kurul ve görevli salt okur; sakin 403; başka site 403), doğrulama hatalarının veritabanına gitmeden dönmesi
// (400 INVALID_FIELD { field }), gövde boyutu, yanıt şekilleri ({ vendor }, { contract }, { items, next_cursor }, özet), kilit sırası ve kurallar
// (VENDOR_INACTIVE, LIMIT_REACHED, VENDOR_NAME_TAKEN, fesih). Kimlik katmanı sahte (x-test-user); gerçek HTTP, gerçek Express.
// Gerçek PostgreSQL doğrulaması (state SQL = JS, IDOR, eşzamanlı sınırlar, hatırlatma, hesap silme, 40P01 = 0): scripts/qa_platform_pg.mjs "contracts".
import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired } from '../src/middlewares/auth_middleware.js';
import { contractsReadLimiter, contractsRouter, contractsWriteLimiter } from '../src/modules/contracts_routes.js';
import { contractsHooks } from '../src/modules/contracts_service.js';
import { contractState, decodeCursor } from '../src/modules/contracts_common.js';

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
const NAMES = Object.fromEntries(Object.values(users).map((u) => [u.user_code, u.full_name]));
const SECRET = 'GIZLI-FIRMA-5521';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = []) => ({ rows, rowCount: rows.length });
let state;
let log;

function makeState() {
  return {
    sites: new Set([SITE, OTHER_SITE]),
    managerLinks: [{ site_code: SITE, user_code: 20001 }, { site_code: OTHER_SITE, user_code: 20002 }],
    memberships: [
      { site_code: SITE, user_code: 20004, role: 'RESIDENT', is_active: true },
      { site_code: SITE, user_code: 20005, role: 'STAFF', is_active: true },
      { site_code: SITE, user_code: 20006, role: 'BOARD_MEMBER', is_active: true },
    ],
    moduleEnabled: true,
    deletedUsers: new Set(),
    vendors: [],
    contracts: [],
    nextId: 100,
    audits: [],
    tx: [],
    locks: [],
    vendorCountOverride: null,
    contractCountOverride: null,
  };
}

function seedVendor(over = {}) {
  state.nextId += 1;
  const vendor = {
    id: state.nextId, site_code: SITE, name: 'Kuzey Asansör', category: 'asansor', contact_name: null, phone: '444 1 234', email: null, tax_no: null, note: null,
    is_active: true, created_by: 20001, created_at: new Date('2026-10-01T08:00:00Z'), updated_at: new Date('2026-10-01T08:00:00Z'), ...over,
  };
  state.vendors.push(vendor);
  return vendor;
}

function seedContract(over = {}) {
  state.nextId += 1;
  const contract = {
    id: state.nextId, site_code: SITE, vendor_id: state.vendors[0]?.id ?? 0, title: 'Bakım sözleşmesi', category: 'asansor', start_date: '2026-01-01', end_date: '2026-11-01',
    notice_days: 30, remind_before_days: 30, amount: '1250.00', currency: 'TRY', period: 'yillik', auto_renew: false, status: 'aktif', terminated_at: null, note: null,
    created_by: 20001, updated_by: 20001, created_at: new Date('2026-10-01T08:00:00Z'), updated_at: new Date('2026-10-01T08:00:00Z'), ...over,
  };
  state.contracts.push(contract);
  return contract;
}

const nameOf = (code) => (code === null || code === undefined || state.deletedUsers.has(code) ? null : NAMES[code] ?? null);
const vendorRow = (v) => ({ ...v, contract_count: state.contracts.filter((c) => c.site_code === v.site_code && c.vendor_id === v.id).length });
const contractRow = (c) => ({ ...c, vendor_name: state.vendors.find((v) => v.id === c.vendor_id)?.name ?? null, created_by_name: nameOf(c.created_by) });
const paramAt = (sql, pattern, params) => {
  const match = pattern.exec(sql);
  return match ? params[Number(match[1]) - 1] : undefined;
};
const byEnd = (a, b) => (a.end_date === b.end_date ? a.id - b.id : a.end_date === null ? 1 : b.end_date === null ? -1 : a.end_date < b.end_date ? -1 : 1);

function contractListRows(sql, params) {
  let rows = state.contracts.filter((c) => c.site_code === Number(params[0]));
  const vendor = paramAt(sql, /c\.vendor_id = \$(\d+)/, params);
  if (vendor !== undefined) rows = rows.filter((c) => c.vendor_id === Number(vendor));
  const category = paramAt(sql, /c\.category = \$(\d+)/, params);
  if (category !== undefined) rows = rows.filter((c) => c.category === category);
  const day = paramAt(sql, /c\.end_date - \$(\d+)::DATE/, params) ?? paramAt(sql, /c\.end_date < \$(\d+)::DATE/, params);
  for (const s of ['aktif', 'yaklasiyor', 'sona_erdi', 'feshedildi']) {
    const marker = { feshedildi: /^c\.status = 'feshedildi'$|AND c\.status = 'feshedildi'/, sona_erdi: /c\.end_date < \$\d+::DATE\)/, yaklasiyor: /c\.end_date - \$\d+::DATE <= c\.remind_before_days/, aktif: /c\.end_date - \$\d+::DATE > c\.remind_before_days/ }[s];
    if (marker.test(sql)) rows = rows.filter((c) => contractState({ status: c.status, endDate: c.end_date, remindBeforeDays: c.remind_before_days }, day ?? '2026-10-19') === s);
  }
  const cursorId = paramAt(sql, /c\.id > \$(\d+)/, params);
  if (cursorId !== undefined) {
    const end = paramAt(sql, /c\.end_date > \$(\d+)::DATE/, params);
    rows = rows.filter((c) => (end === undefined ? c.end_date === null && c.id > Number(cursorId) : c.end_date === null || c.end_date > end || (c.end_date === end && c.id > Number(cursorId))));
  }
  return rows.sort(byEnd);
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
    return ok(params[1] === 'contracts' ? [{ enabled: state.moduleEnabled }] : []);
  }
  if (/^SELECT v\.id, v\.name, .* FROM contract_vendors v WHERE v\.site_code = \$1 AND v\.id = \$2 LIMIT 1$/.test(sql)) {
    return ok(state.vendors.filter((v) => v.site_code === Number(params[0]) && v.id === Number(params[1])).map(vendorRow));
  }
  if (/^SELECT v\.id, v\.name, .* FROM contract_vendors v WHERE v\.site_code = \$1.* ORDER BY lower\(translate\(COALESCE\(v\.name, ''\).* v\.id LIMIT 500$/.test(sql)) {
    let rows = state.vendors.filter((v) => v.site_code === Number(params[0]));
    const active = paramAt(sql, /v\.is_active = \$(\d+)/, params);
    if (active !== undefined) rows = rows.filter((v) => v.is_active === active);
    return ok(rows.map(vendorRow));
  }
  if (/^SELECT c\.id, c\.vendor_id, v\.name AS vendor_name, .* FROM site_contracts c INNER JOIN contract_vendors v ON v\.id = c\.vendor_id LEFT JOIN users cu ON cu\.user_code = c\.created_by WHERE c\.site_code = \$1 AND c\.id = \$2 LIMIT 1$/.test(sql)) {
    return ok(state.contracts.filter((c) => c.site_code === Number(params[0]) && c.id === Number(params[1])).map(contractRow));
  }
  if (/^SELECT c\.id, c\.vendor_id, v\.name AS vendor_name, .* WHERE c\.site_code = \$1.* ORDER BY c\.end_date ASC NULLS LAST, c\.id ASC LIMIT \$(\d+)$/.test(sql)) {
    const limit = Number(params[params.length - 1]);
    return ok(contractListRows(sql, params).slice(0, limit).map(contractRow));
  }
  if (/^SELECT COUNT\(\*\) FILTER \(WHERE \(c\.status = 'aktif'.* FROM site_contracts c WHERE c\.site_code = \$1$/.test(sql)) {
    const counts = { aktif: 0, yaklasiyor: 0, sona_erdi: 0, feshedildi: 0 };
    for (const c of state.contracts.filter((x) => x.site_code === Number(params[0]))) counts[contractState({ status: c.status, endDate: c.end_date, remindBeforeDays: c.remind_before_days }, params[1])] += 1;
    return ok([{ active: counts.aktif, expiring_soon: counts.yaklasiyor, expired: counts.sona_erdi, terminated: counts.feshedildi }]);
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
  if (/^SELECT pg_advisory_xact_lock\(hashtext\(\$1\)\)$/.test(sql)) {
    state.locks.push(params[0]);
    return ok([{}]);
  }
  if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM contract_vendors WHERE site_code = \$1$/.test(sql)) {
    return ok([{ n: state.vendorCountOverride ?? state.vendors.filter((v) => v.site_code === Number(params[0])).length }]);
  }
  if (/^SELECT COUNT\(\*\)::INTEGER AS n FROM site_contracts WHERE site_code = \$1$/.test(sql)) {
    return ok([{ n: state.contractCountOverride ?? state.contracts.filter((c) => c.site_code === Number(params[0])).length }]);
  }
  if (/^SELECT 1 FROM contract_vendors WHERE site_code = \$1 AND lower\(name\) = lower\(\$2\)( AND id <> \$3)? LIMIT 1$/.test(sql)) {
    return ok(state.vendors.filter((v) => v.site_code === Number(params[0]) && v.name.toLowerCase() === String(params[1]).toLowerCase() && (params[2] === undefined || v.id !== Number(params[2]))).map(() => ({ x: 1 })));
  }
  if (/^INSERT INTO contract_vendors \(site_code, name, category, contact_name, phone, email, tax_no, note, created_by\) VALUES \(\$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9\) RETURNING id$/.test(sql)) {
    const [siteCode, name, category, contactName, phone, email, taxNo, note, createdBy] = params;
    const vendor = seedVendor({ site_code: Number(siteCode), name, category, contact_name: contactName, phone, email, tax_no: taxNo, note, created_by: createdBy });
    return ok([{ id: String(vendor.id) }]);
  }
  if (/^SELECT name, category, contact_name, phone, email, tax_no, note, is_active FROM contract_vendors WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/.test(sql)) {
    return ok(state.vendors.filter((v) => v.id === Number(params[0]) && v.site_code === Number(params[1])));
  }
  if (/^UPDATE contract_vendors SET .*, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2$/.test(sql)) {
    const vendor = state.vendors.find((v) => v.id === Number(params[0]) && v.site_code === Number(params[1]));
    for (const [, column, index] of sql.matchAll(/(\w+) = \$(\d+)/g)) if (!['id', 'site_code'].includes(column)) vendor[column] = params[Number(index) - 1];
    return ok();
  }
  if (/^SELECT id, category, is_active FROM contract_vendors WHERE id = \$1 AND site_code = \$2 FOR SHARE$/.test(sql)) {
    return ok(state.vendors.filter((v) => v.id === Number(params[0]) && v.site_code === Number(params[1])).map((v) => ({ id: v.id, category: v.category, is_active: v.is_active })));
  }
  if (/^INSERT INTO site_contracts \( site_code, vendor_id, title, category, start_date, end_date, notice_days, remind_before_days, amount, period, auto_renew, note, created_by, updated_by \) VALUES/.test(sql)) {
    const [siteCode, vendorId, title, category, startDate, endDate, noticeDays, remindBeforeDays, amount, period, autoRenew, note, createdBy] = params;
    const contract = seedContract({ site_code: Number(siteCode), vendor_id: Number(vendorId), title, category, start_date: startDate, end_date: endDate, notice_days: noticeDays,
      remind_before_days: remindBeforeDays, amount, period, auto_renew: autoRenew, note, created_by: createdBy, updated_by: createdBy });
    return ok([{ id: String(contract.id) }]);
  }
  if (/^SELECT c\.vendor_id, c\.title, c\.category, .* FROM site_contracts c WHERE c\.id = \$1 AND c\.site_code = \$2 FOR UPDATE OF c$/.test(sql)) {
    return ok(state.contracts.filter((c) => c.id === Number(params[0]) && c.site_code === Number(params[1])).map((c) => ({ ...c, vendor_id: String(c.vendor_id) })));
  }
  if (/^UPDATE site_contracts SET .* updated_by = \$\d+, updated_at = NOW\(\) WHERE id = \$1 AND site_code = \$2$/.test(sql)) {
    const contract = state.contracts.find((c) => c.id === Number(params[0]) && c.site_code === Number(params[1]));
    for (const [, column, index] of sql.matchAll(/(\w+) = \$(\d+)/g)) if (!['id', 'site_code'].includes(column)) contract[column] = params[Number(index) - 1];
    if (/terminated_at = NOW\(\)/.test(sql)) contract.terminated_at = new Date();
    if (/terminated_at = NULL/.test(sql)) contract.terminated_at = null;
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
const auditText = () => state.audits.map((params) => params.map((value) => (value === null || value === undefined ? '' : String(value))).join(' ')).join('\n');

const ORIGINAL_ROUTES = contractsRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({ path: layer.route.path, method: Object.keys(layer.route.methods)[0], handlers: layer.route.stack.map((entry) => entry.handle) }));

let server;
let baseUrl;

before(async () => {
  for (const layer of contractsRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    layer.route.stack[1].handle = (_req, _res, next) => next(); // hız sınırlayıcılar ayrı testte sınanır
  }
  contractsHooks.now = () => new Date('2026-10-19T09:00:00Z');
  const app = express();
  app.use(express.json({ limit: '1mb' }));
  app.use(contractsRouter);
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
  return { status: res.status, body: json };
}

const V = (suffix = '', site = SITE) => `/manager/sites/${site}/contract-vendors${suffix}`;
const C = (suffix = '', site = SITE) => `/manager/sites/${site}/contracts${suffix}`;

describe('rota zinciri ve hız sınırları', () => {
  it('sözleşmedeki 8 uç vardır; her biri authRequired ile BAŞLAR, ikinci halka hız sınırlayıcıdır (GET okuma, POST / PATCH yazma); /summary, /:id den ÖNCE; DELETE ve sakin ucu yok', () => {
    const routes = ORIGINAL_ROUTES.map((route) => `${route.method.toUpperCase()} ${route.path}`);
    assert.deepEqual([...routes].sort(), [
      'GET /manager/sites/:siteCode/contract-vendors',
      'GET /manager/sites/:siteCode/contracts',
      'GET /manager/sites/:siteCode/contracts/:id',
      'GET /manager/sites/:siteCode/contracts/summary',
      'PATCH /manager/sites/:siteCode/contract-vendors/:id',
      'PATCH /manager/sites/:siteCode/contracts/:id',
      'POST /manager/sites/:siteCode/contract-vendors',
      'POST /manager/sites/:siteCode/contracts',
    ]);
    assert.ok(routes.indexOf('GET /manager/sites/:siteCode/contracts/summary') < routes.indexOf('GET /manager/sites/:siteCode/contracts/:id'));
    for (const route of ORIGINAL_ROUTES) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}`);
      assert.equal(route.handlers[1], route.method === 'get' ? contractsReadLimiter : contractsWriteLimiter, `${route.method} ${route.path}`);
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
    for (const [limiter, max, user] of [[contractsWriteLimiter, 120, 779001], [contractsReadLimiter, 1200, 779002]]) {
      const statuses = fire(limiter, user, max + 1);
      assert.equal(statuses.slice(0, max).every(([code]) => code === 200), true);
      assert.equal(statuses[max][0], 429);
      assert.ok(Number(statuses[max][1]) > 0);
    }
  });
});

describe('yetki ve modül kapısı: sıra biçim -> yetki -> site -> modül', () => {
  it('geçersiz site kodu 400 INVALID_SITE_CODE (veritabanına gitmeden)', async () => {
    const res = await call('GET', '/manager/sites/abc/contracts', { user: users.manager });
    assert.deepEqual([res.status, res.body.code], [400, 'INVALID_SITE_CODE']);
    assert.equal(log.length, 0);
  });

  it('sakin / ilgisiz FORBIDDEN_ROLE; başka sitenin yöneticisi FORBIDDEN_SITE; olmayan site (süper) 404 SITE_NOT_FOUND', async () => {
    for (const [method, path] of [['GET', V()], ['GET', C()], ['GET', C('/summary')], ['POST', C()]]) {
      for (const user of [users.resident, users.outsider]) {
        const res = await call(method, path, { user, body: method === 'POST' ? {} : undefined });
        assert.deepEqual([res.status, res.body.code], [403, 'FORBIDDEN_ROLE'], `${method} ${path} ${user.full_name}`);
      }
      const other = await call(method, path, { user: users.otherManager, body: method === 'POST' ? {} : undefined });
      assert.deepEqual([other.status, other.body.code], [403, 'FORBIDDEN_SITE']);
    }
    const missing = await call('GET', C('', 1999999999), { user: users.superUser });
    assert.deepEqual([missing.status, missing.body.code], [404, 'SITE_NOT_FOUND']);
  });

  it('modül KAPALI: süper / yönetici / görevli / kurul 403 MODULE_DISABLED { module: contracts }; yetki modülden ÖNCE', async () => {
    state.moduleEnabled = false;
    for (const user of [users.superUser, users.manager, users.staff, users.board]) {
      const res = await call('GET', V(), { user });
      assert.deepEqual([res.status, res.body.code, res.body.module], [403, 'MODULE_DISABLED', 'contracts']);
    }
    assert.equal((await call('GET', V(), { user: users.resident })).body.code, 'FORBIDDEN_ROLE');
  });

  it('kurul ve görevli salt okur: GET 200 (telefon görünür); POST / PATCH 403 FORBIDDEN_ROLE, işlem açılmaz', async () => {
    const vendor = seedVendor();
    const contract = seedContract({ vendor_id: vendor.id });
    for (const user of [users.board, users.staff]) {
      const vendors = await call('GET', V(), { user });
      assert.equal(vendors.status, 200);
      assert.equal(vendors.body.items[0].phone, '444 1 234');
      assert.equal((await call('GET', C(), { user })).status, 200);
      assert.equal((await call('GET', C('/summary'), { user })).status, 200);
      assert.equal((await call('GET', C(`/${contract.id}`), { user })).status, 200);
      for (const [method, path, body] of [
        ['POST', V(), { name: 'x', category: 'diger' }],
        ['PATCH', V(`/${vendor.id}`), { is_active: false }],
        ['POST', C(), { vendor_id: vendor.id, title: 'x', start_date: '2026-01-01' }],
        ['PATCH', C(`/${contract.id}`), { status: 'feshedildi' }],
      ]) {
        const res = await call(method, path, { user, body });
        assert.deepEqual([res.status, res.body.code], [403, 'FORBIDDEN_ROLE'], `${method} ${path}`);
      }
    }
    assert.equal(state.tx.length, 0);
  });
});

describe('doğrulama (işlem açılmadan)', () => {
  it('hatalı gövde / sorgu 400 INVALID_FIELD { field }; görünmez kimlik 404', async () => {
    const cases = [
      ['POST', V(), { category: 'diger' }, 'name'],
      ['POST', V(), { name: 'x', category: 'boya' }, 'category'],
      ['POST', V(), [1, 2], 'body'],
      ['PATCH', V('/5'), {}, 'body'],
      ['PATCH', V('/5'), { is_active: 'false' }, 'is_active'],
      ['POST', C(), { title: 'x', start_date: '2026-01-01' }, 'vendor_id'],
      ['POST', C(), { vendor_id: 1, title: 'x', start_date: '2026-01-01', end_date: '2025-01-01' }, 'end_date'],
      ['POST', C(), { vendor_id: 1, title: 'x', start_date: '2026-01-01', amount: 'abc' }, 'amount'],
      ['PATCH', C('/5'), { status: 'iptal' }, 'status'],
      ['GET', C('?state=bogus'), undefined, 'state'],
      ['GET', C('?limit=0'), undefined, 'limit'],
      ['GET', C('?cursor=***'), undefined, 'cursor'],
      ['GET', V('?active=yes'), undefined, 'active'],
    ];
    for (const [method, path, body, field] of cases) {
      const res = await call(method, path, { user: users.manager, body });
      assert.deepEqual([res.status, res.body.code, res.body.field], [400, 'INVALID_FIELD', field], `${method} ${path} ${JSON.stringify(body)}`);
      assert.equal(typeof res.body.error, 'string');
    }
    const badVendor = await call('PATCH', V('/abc'), { user: users.manager, body: { name: 'x' } });
    const badContract = await call('GET', C('/abc'), { user: users.manager });
    assert.deepEqual([badVendor.status, badVendor.body.code], [404, 'VENDOR_NOT_FOUND']);
    assert.deepEqual([badContract.status, badContract.body.code], [404, 'CONTRACT_NOT_FOUND']);
    assert.equal(state.tx.length, 0);
  });

  it('16 KB üstü gövde 413 BODY_TOO_LARGE', async () => {
    const res = await call('POST', V(), { user: users.manager, body: { name: 'x', category: 'diger', note: 'z'.repeat(17000) } });
    assert.deepEqual([res.status, res.body.code], [413, 'BODY_TOO_LARGE']);
  });
});

describe('firmalar', () => {
  it('arama (q): ad, yetkili kişi VE telefon (Türkçe katlamalı); en az 3 rakamlı aramada telefon ayrıca YALNIZ rakamlarıyla karşılaştırılır', async () => {
    seedVendor();
    const seen = [];
    pool.query = async (text, params) => {
      seen.push([norm(text), params]);
      return fakeQuery(text, params);
    };
    const res = await call('GET', V(`?q=${encodeURIComponent('444 1-2')}`), { user: users.staff });
    assert.equal(res.status, 200);
    const [sql, params] = seen.find(([text]) => /FROM contract_vendors v WHERE v\.site_code = \$1 AND/.test(text));
    for (const column of ['v.name', 'v.contact_name', 'v.phone']) assert.ok(sql.includes(`lower(translate(COALESCE(${column}, '')`), column);
    assert.match(sql, /regexp_replace\(COALESCE\(v\.phone, ''\), '\[\^0-9\]', '', 'g'\) LIKE \$3/);
    assert.deepEqual(params.slice(1), ['%444 1-2%', '%44412%']);
    seen.length = 0;
    await call('GET', V('?q=ab1'), { user: users.staff });
    const [plain, plainParams] = seen.find(([text]) => /FROM contract_vendors v WHERE v\.site_code = \$1 AND/.test(text));
    assert.ok(!plain.includes('regexp_replace'), 'üç rakamdan az: yalnız metin araması');
    assert.equal(plainParams.length, 2);
  });

  it('POST 201 { vendor }: kilit sırası site -> kullanıcı -> site advisory; sayım + ad tekilliği; audit details yalnız kategori', async () => {
    allowTx();
    const res = await call('POST', V(), { user: users.manager, body: { name: SECRET, category: 'asansor', phone: '0212 555 11 22', email: 'A@B.COM', tax_no: '1234567890', note: 'gizli not' } });
    assert.equal(res.status, 201);
    assert.deepEqual(Object.keys(res.body), ['vendor']);
    assert.equal(res.body.vendor.name, SECRET);
    assert.equal(res.body.vendor.email, 'a@b.com');
    assert.equal(res.body.vendor.contract_count, 0);
    const order = state.tx.filter((sql) => !/^(BEGIN|COMMIT|SAVEPOINT|RELEASE)/.test(sql)).map((sql) => sql.slice(0, 40));
    assert.match(order[0], /^SELECT site_code FROM sites/);
    assert.match(order[1], /^SELECT user_code FROM users/);
    assert.match(order[2], /^SELECT pg_advisory_xact_lock/);
    assert.deepEqual(state.locks, [`contracts:${SITE}`]);
    const audit = auditText();
    assert.ok(audit.includes('contract_vendor.created'));
    for (const secret of [SECRET, '0212 555 11 22', 'a@b.com', '1234567890', 'gizli not']) assert.ok(!audit.includes(secret), secret);
  });

  it('aynı ad 409 VENDOR_NAME_TAKEN; 500 firmada 409 LIMIT_REACHED { limit: 500 }; silinmiş hesap 401 ACCOUNT_DELETED', async () => {
    allowTx();
    seedVendor({ name: 'Kuzey Asansör' });
    const dup = await call('POST', V(), { user: users.manager, body: { name: 'KUZEY ASANSÖR', category: 'asansor' } });
    assert.deepEqual([dup.status, dup.body.code], [409, 'VENDOR_NAME_TAKEN']);
    state.vendorCountOverride = 500;
    const full = await call('POST', V(), { user: users.manager, body: { name: 'Yeni', category: 'diger' } });
    assert.deepEqual([full.status, full.body.code, full.body.limit], [409, 'LIMIT_REACHED', 500]);
    state.vendorCountOverride = null;
    state.deletedUsers.add(20001);
    const gone = await call('POST', V(), { user: users.manager, body: { name: 'Yeni', category: 'diger' } });
    assert.deepEqual([gone.status, gone.body.code], [401, 'ACCOUNT_DELETED']);
  });

  it('PATCH: değişen alanlar yazılır, audit yalnız alan adları; değişiklik yoksa UPDATE / audit yok; liste active süzgeci', async () => {
    allowTx();
    const vendor = seedVendor();
    const res = await call('PATCH', V(`/${vendor.id}`), { user: users.superUser, body: { is_active: false, phone: '' } });
    assert.equal(res.status, 200);
    assert.equal(res.body.vendor.is_active, false);
    assert.equal(res.body.vendor.phone, null);
    assert.equal(state.audits.length, 1);
    assert.ok(auditText().includes('"fields":["phone","is_active"]'));
    assert.ok(!auditText().includes('444 1 234'));
    const again = await call('PATCH', V(`/${vendor.id}`), { user: users.superUser, body: { is_active: false } });
    assert.equal(again.status, 200);
    assert.equal(state.audits.length, 1);
    assert.equal(state.tx.filter((sql) => sql.startsWith('UPDATE')).length, 1);
    const active = await call('GET', V('?active=1'), { user: users.manager });
    const inactive = await call('GET', V('?active=0'), { user: users.manager });
    assert.deepEqual([active.body.items.length, inactive.body.items.length], [0, 1]);
    const foreign = seedVendor({ site_code: OTHER_SITE, name: 'Başka' });
    const cross = await call('PATCH', V(`/${foreign.id}`), { user: users.manager, body: { name: 'x' } });
    assert.deepEqual([cross.status, cross.body.code], [404, 'VENDOR_NOT_FOUND']);
  });
});

describe('sözleşmeler', () => {
  it('POST 201 { contract }: kategori firmadan, varsayılanlar, tutar metin, state / days_left / notice_deadline; audit tutar / başlık taşımaz', async () => {
    allowTx();
    const vendor = seedVendor();
    const res = await call('POST', C(), { user: users.manager, body: { vendor_id: vendor.id, title: SECRET, start_date: '2026-01-01', end_date: '2026-11-01', amount: 98765.43, auto_renew: true } });
    assert.equal(res.status, 201);
    assert.deepEqual(Object.keys(res.body), ['contract']);
    const contract = res.body.contract;
    assert.equal(contract.category, 'asansor');
    assert.equal(contract.amount, '98765.43');
    assert.equal(contract.notice_days, 30);
    assert.equal(contract.remind_before_days, 30);
    assert.equal(contract.state, 'yaklasiyor');
    assert.equal(contract.days_left, 13);
    assert.equal(contract.notice_deadline, '2026-10-02');
    assert.equal(contract.created_by_name, 'Yönetici');
    const audit = auditText();
    assert.ok(audit.includes('contract.created'));
    assert.ok(!audit.includes(SECRET) && !audit.includes('98765'));
    assert.ok(state.tx.some((sql) => /^SELECT id, category, is_active FROM contract_vendors .* FOR SHARE$/.test(sql)));
  });

  it('pasif firma 409 VENDOR_INACTIVE; başka sitenin firması 404 VENDOR_NOT_FOUND; 2000 sözleşmede 409 LIMIT_REACHED { limit: 2000 }', async () => {
    allowTx();
    const passive = seedVendor({ is_active: false });
    const foreign = seedVendor({ site_code: OTHER_SITE, name: 'Başka' });
    const active = seedVendor({ name: 'Etkin' });
    const r1 = await call('POST', C(), { user: users.manager, body: { vendor_id: passive.id, title: 'x', start_date: '2026-01-01' } });
    const r2 = await call('POST', C(), { user: users.manager, body: { vendor_id: foreign.id, title: 'x', start_date: '2026-01-01' } });
    state.contractCountOverride = 2000;
    const r3 = await call('POST', C(), { user: users.manager, body: { vendor_id: active.id, title: 'x', start_date: '2026-01-01' } });
    assert.deepEqual([r1.status, r1.body.code], [409, 'VENDOR_INACTIVE']);
    assert.deepEqual([r2.status, r2.body.code], [404, 'VENDOR_NOT_FOUND']);
    assert.deepEqual([r3.status, r3.body.code, r3.body.limit], [409, 'LIMIT_REACHED', 2000]);
    assert.equal(state.contracts.length, 0);
  });

  it('PATCH: feshedildi -> terminated_at; aynı durum değişiklik yok; birleşik tarih sırası 400 end_date; başka sitenin sözleşmesi 404', async () => {
    allowTx();
    const vendor = seedVendor();
    const contract = seedContract({ vendor_id: vendor.id });
    const term = await call('PATCH', C(`/${contract.id}`), { user: users.manager, body: { status: 'feshedildi' } });
    assert.equal(term.status, 200);
    assert.equal(term.body.contract.state, 'feshedildi');
    assert.equal(typeof term.body.contract.terminated_at, 'string');
    assert.ok(auditText().includes('"from":"aktif","to":"feshedildi"'));
    const audits = state.audits.length;
    const same = await call('PATCH', C(`/${contract.id}`), { user: users.manager, body: { status: 'feshedildi' } });
    assert.equal(same.status, 200);
    assert.equal(state.audits.length, audits);
    const back = await call('PATCH', C(`/${contract.id}`), { user: users.manager, body: { status: 'aktif' } });
    assert.equal(back.body.contract.terminated_at, null);
    const badOrder = await call('PATCH', C(`/${contract.id}`), { user: users.manager, body: { end_date: '2025-12-31' } });
    assert.deepEqual([badOrder.status, badOrder.body.code, badOrder.body.field], [400, 'INVALID_FIELD', 'end_date']);
    const foreign = seedContract({ site_code: OTHER_SITE });
    const cross = await call('PATCH', C(`/${foreign.id}`), { user: users.manager, body: { title: 'x' } });
    assert.deepEqual([cross.status, cross.body.code], [404, 'CONTRACT_NOT_FOUND']);
    const crossGet = await call('GET', C(`/${foreign.id}`), { user: users.manager });
    assert.deepEqual([crossGet.status, crossGet.body.code], [404, 'CONTRACT_NOT_FOUND']);
  });

  it('GET liste: { items, next_cursor }; sıra end_date artan (bitişsiz sonda); opak imleçle sonraki sayfa; özet sayıları ayrık', async () => {
    const vendor = seedVendor();
    seedContract({ vendor_id: vendor.id, end_date: null, title: 'Bitişsiz' });
    seedContract({ vendor_id: vendor.id, end_date: '2026-12-01', title: 'Aralık' });
    seedContract({ vendor_id: vendor.id, end_date: '2026-10-01', title: 'Ekim (geçti)' });
    seedContract({ vendor_id: vendor.id, end_date: '2026-11-01', title: 'Kasım', status: 'feshedildi', terminated_at: new Date() });
    const first = await call('GET', C('?limit=2'), { user: users.board });
    assert.deepEqual(Object.keys(first.body), ['items', 'next_cursor']);
    assert.deepEqual(first.body.items.map((i) => i.title), ['Ekim (geçti)', 'Kasım']);
    assert.deepEqual(decodeCursor(first.body.next_cursor), { endDate: '2026-11-01', id: first.body.items[1].id });
    const second = await call('GET', C(`?limit=2&cursor=${first.body.next_cursor}`), { user: users.board });
    assert.deepEqual(second.body.items.map((i) => i.title), ['Aralık', 'Bitişsiz']);
    assert.equal(second.body.next_cursor, null);
    const summary = await call('GET', C('/summary'), { user: users.staff });
    assert.deepEqual(summary.body, { active: 2, expiring_soon: 0, expired: 1, terminated: 1 });
    const expired = await call('GET', C('?state=sona_erdi'), { user: users.manager });
    assert.deepEqual(expired.body.items.map((i) => [i.title, i.state, i.days_left]), [['Ekim (geçti)', 'sona_erdi', -18]]);
    const listSql = log.find((sql) => /ORDER BY c\.end_date ASC NULLS LAST/.test(sql) && /c\.end_date < \$2::DATE/.test(sql));
    assert.ok(listSql, 'state süzgeci "bugün"ü parametre olarak alır');
  });
});
