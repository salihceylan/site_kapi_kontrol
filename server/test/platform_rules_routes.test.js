// Kurallar uçları (gerçek HTTP, sahte veritabanı): ara katman zinciri, yetki matrisi (süper / yönetici / başka site / kimliksiz), gövde şekli, 400/404
// gövdeleri, sızdırmama, önbellek başlığı, platformServicesRouter birleşimi. Gerçek PostgreSQL: scripts/qa_platform_pg.mjs "platform_rules".
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired, requireSiteManager, requireSuperUser } from '../src/middlewares/auth_middleware.js';
import { platformServicesRouter } from '../src/modules/platform_config_routes.js';
import { RULE_KEYS, invalidateRuleCache } from '../src/modules/platform_rules.js';
import { platformRulesRouter, rulesReadLimiter, rulesWriteLimiter } from '../src/modules/platform_rules_routes.js';

const SITE_1 = 1000000001;
const SITE_2 = 1000000002;
const users = {
  superUser: { id: 1, user_code: 1, userCode: 1, role: 'super_user', full_name: 'Süper Kişi', email: 'root@example.com' },
  mgrA: { id: 20001, user_code: 20001, userCode: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici', email: 'a@example.com' },
  resident: { id: 20004, user_code: 20004, userCode: 20004, role: 'apartment_owner', full_name: 'Deniz Sakin', email: 'd@example.com' },
  individual: { id: 48213, user_code: 48213, userCode: 48213, role: 'individual', full_name: 'Bora', email: 'b@example.com' },
};

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
const routeOf = (method, path) => platformRulesRouter.stack.find((l) => l.route?.path === path && l.route.methods[method.toLowerCase()]);
const ORIGINAL_CHAIN = {
  'GET /admin/rules': routeOf('GET', '/admin/rules').route.stack.map((e) => e.handle),
  'PUT /admin/rules': routeOf('PUT', '/admin/rules').route.stack.map((e) => e.handle),
  'GET /manager/sites/:siteCode/rules': routeOf('GET', '/manager/sites/:siteCode/rules').route.stack.map((e) => e.handle),
};

let state;
let server;
let baseUrl;

function installDb() {
  const handle = async (text, params = []) => {
    const sql = norm(text);
    state.log.push({ sql, params });
    if (state.failOn && state.failOn.test(sql)) throw Object.assign(new Error('SECRET_DB_DETAIL password=hunter2'), { code: 'XX000' });
    if (/^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT|ROLLBACK TO SAVEPOINT)\b/.test(sql)) return ok();
    if (/^SELECT pg_advisory_xact_lock/.test(sql)) return ok();
    if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL FOR KEY SHARE$/.test(sql)) return ok([{ user_code: params[0] }]);
    if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
      return ok(Number(params[0]) === SITE_1 && Number(params[1]) === 20001 ? [{ x: 1 }] : []);
    }
    if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) return ok();
    if (/^SELECT 1 FROM site_manager_sites WHERE manager_user_code = \$1 LIMIT 1$/.test(sql)) return ok(Number(params[0]) === 20001 ? [{ x: 1 }] : []);
    if (/^SELECT 1 FROM site_memberships WHERE user_code = \$1 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) return ok();
    if (/^SELECT site_code, name FROM sites WHERE site_code = \$1( FOR KEY SHARE)?$/.test(sql)) {
      return ok([SITE_1, SITE_2].includes(Number(params[0])) ? [{ site_code: String(params[0]), name: Number(params[0]) === SITE_1 ? 'Gül Sitesi' : 'Lale Sitesi' }] : []);
    }
    if (/FROM platform_rule_values v LEFT JOIN users u/.test(sql)) return ok(state.rows.filter((r) => params[0].includes(r.rule_key)));
    if (/^INSERT INTO platform_rule_values/.test(sql)) {
      const id = String(state.rows.length + 1);
      state.rows.push({ id, rule_key: params[0], site_code: params[1] === null ? null : String(params[1]), value: params[2] === null ? null : JSON.parse(params[2]), inherit: params[3], valid_from: params[4], note: params[5], created_at: new Date(), created_by_name: 'Süper Kişi' });
      return ok([{ id }]);
    }
    if (/^INSERT INTO audit_log/.test(sql)) return ok([], 1);
    throw new Error(`SAHTE VERITABANI: tanimsiz SQL: ${sql.slice(0, 160)}`);
  };
  pool.query = handle;
  pool.connect = async () => ({ query: handle, release() {} });
}

before(async () => {
  for (const layer of platformRulesRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, res, next) => {
      const key = req.headers['x-test-user'];
      if (!key) return res.status(401).json({ error: 'Yetkisiz erisim.' });
      req.authUser = { ...users[key] };
      return next();
    };
  }
  const app = express();
  app.use(express.json());
  app.use(platformRulesRouter);
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
  state = { rows: [], log: [], failOn: null };
  invalidateRuleCache();
  installDb();
  mock.method(console, 'error', () => {});
});

afterEach(() => {
  mock.restoreAll();
  rulesReadLimiter.reset();
  rulesWriteLimiter.reset();
});

const call = async (method, path, user, body) => {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: { 'content-type': 'application/json', ...(user ? { 'x-test-user': user } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch (_error) {
    // JSON değil
  }
  return { status: response.status, json, text, headers: response.headers };
};
const dataQueries = () => state.log.filter((entry) => /platform_rule_values|FROM sites/.test(entry.sql));

describe('kurallar: ara katman sırası ve birleşim', () => {
  it('admin uçları authRequired -> requireSuperUser -> hız sınırı; yönetici ucu authRequired -> requireSiteManager -> okuma sınırı', () => {
    assert.deepEqual(ORIGINAL_CHAIN['GET /admin/rules'].slice(0, 3), [authRequired, requireSuperUser, rulesReadLimiter]);
    assert.deepEqual(ORIGINAL_CHAIN['PUT /admin/rules'].slice(0, 3), [authRequired, requireSuperUser, rulesWriteLimiter]);
    assert.deepEqual(ORIGINAL_CHAIN['GET /manager/sites/:siteCode/rules'].slice(0, 3), [authRequired, requireSiteManager, rulesReadLimiter]);
    for (const chain of Object.values(ORIGINAL_CHAIN)) assert.equal(chain.length, 4);
  });

  it('platformServicesRouter kurallar uçlarını da taşır (server.js değişmeden bağlanır)', () => {
    const paths = new Set();
    const collect = (router) => {
      for (const layer of router.stack) {
        if (layer.route) for (const method of Object.keys(layer.route.methods)) paths.add(`${method.toUpperCase()} ${layer.route.path}`);
        else if (layer.handle?.stack) collect(layer.handle);
      }
    };
    collect(platformServicesRouter);
    for (const wanted of ['GET /admin/rules', 'PUT /admin/rules', 'GET /manager/sites/:siteCode/rules', 'GET /admin/platform-config']) assert.ok(paths.has(wanted), wanted);
  });
});

describe('kurallar: yetki matrisi', () => {
  it('kimliksiz 401; süper olmayan herkes admin uçlarında 403 ve veritabanına dokunulmaz', async () => {
    assert.equal((await call('GET', '/admin/rules', null)).status, 401);
    for (const user of ['mgrA', 'resident', 'individual']) {
      assert.equal((await call('GET', '/admin/rules', user)).status, 403, user);
      assert.equal((await call('PUT', '/admin/rules', user, { changes: [{ key: 'budget.objection_days', value: 9 }] })).status, 403, user);
    }
    assert.equal(dataQueries().length, 0);
    assert.equal(state.rows.length, 0);
  });

  it('yönetici: kendi sitesi 200 (salt okunur, ad yok); başka site 403 FORBIDDEN_SITE (IDOR); sakin / bireysel 403; biçimsiz site kodu 400', async () => {
    state.rows.push({ id: '1', rule_key: 'budget.objection_days', site_code: null, value: 10, inherit: false, valid_from: '2026-01-01', note: null, created_at: new Date('2026-01-01T08:00:00Z'), created_by_name: 'Süper Kişi' });
    const own = await call('GET', `/manager/sites/${SITE_1}/rules`, 'mgrA');
    assert.equal(own.status, 200, own.text);
    assert.equal(own.json.can_edit, false);
    assert.deepEqual(own.json.site, { site_code: SITE_1, site_name: 'Gül Sitesi' });
    assert.equal(own.json.items.length, RULE_KEYS.length);
    const objection = own.json.items.find((item) => item.key === 'budget.objection_days');
    assert.equal(objection.effective.value, 10);
    assert.equal(objection.platform.updated_by_name, null, 'yöneticiye değiştirenin adı gösterilmez');
    assert.equal(own.text.includes('Süper Kişi'), false);
    assert.equal(own.headers.get('cache-control'), 'no-store');
    const other = await call('GET', `/manager/sites/${SITE_2}/rules`, 'mgrA');
    assert.equal(other.status, 403);
    assert.equal(other.json.code, 'FORBIDDEN_SITE');
    for (const user of ['resident', 'individual']) assert.equal((await call('GET', `/manager/sites/${SITE_1}/rules`, user)).status, 403, user);
    assert.equal((await call('GET', '/manager/sites/abc/rules', 'mgrA')).status, 400);
  });

  it('süper kullanıcı yönetici ucunu da okur (salt okunur görünüm); var olmayan site 404', async () => {
    const res = await call('GET', `/manager/sites/${SITE_2}/rules`, 'superUser');
    assert.equal(res.status, 200);
    assert.equal(res.json.can_edit, false);
    assert.equal((await call('GET', '/manager/sites/1000000099/rules', 'superUser')).status, 404);
  });
});

describe('kurallar: süper kullanıcı uçları', () => {
  it('GET /admin/rules: platform görünümü (can_edit, gruplar, 16 kural); ?site_code= site görünümü; geçersiz site_code 400 INVALID_QUERY, yok 404', async () => {
    const res = await call('GET', '/admin/rules', 'superUser');
    assert.equal(res.status, 200, res.text);
    assert.equal(res.json.can_edit, true);
    assert.equal(res.json.site, null);
    assert.deepEqual(res.json.items.map((item) => item.key), [...RULE_KEYS]);
    assert.equal(res.headers.get('cache-control'), 'no-store');
    const site = await call('GET', `/admin/rules?site_code=${SITE_1}`, 'superUser');
    assert.equal(site.status, 200);
    assert.equal(site.json.site.site_code, SITE_1);
    const bad = await call('GET', '/admin/rules?site_code=x1', 'superUser');
    assert.equal(bad.status, 400);
    assert.equal(bad.json.code, 'INVALID_QUERY');
    assert.equal((await call('GET', '/admin/rules?site_code=1000000099', 'superUser')).status, 404);
  });

  it('PUT /admin/rules: 200 güncel görünüm + changed; doğrulama hatası 400 VALIDATION_FAILED { fields, rule_codes }; yapı hatası 400 INVALID_BODY', async () => {
    const res = await call('PUT', '/admin/rules', 'superUser', { changes: [{ key: 'finance.late_fee.monthly_bp_max', value: 450 }] });
    assert.equal(res.status, 200, res.text);
    assert.deepEqual(res.json.changed, ['finance.late_fee.monthly_bp_max']);
    assert.equal(res.json.items.find((item) => item.key === 'finance.late_fee.monthly_bp_max').effective.value, 450);
    const invalid = await call('PUT', '/admin/rules', 'superUser', { changes: [{ key: 'finance.late_fee.monthly_bp_max', value: 650 }] });
    assert.equal(invalid.status, 400);
    assert.equal(invalid.json.code, 'VALIDATION_FAILED');
    assert.equal(invalid.json.rule_codes['finance.late_fee.monthly_bp_max'], 'RULE_VALUE_INVALID');
    assert.match(invalid.json.fields['finance.late_fee.monthly_bp_max'], /0 ile 500/);
    const shape = await call('PUT', '/admin/rules', 'superUser', { changes: [] });
    assert.equal(shape.status, 400);
    assert.equal(shape.json.code, 'INVALID_BODY');
    const locked = await call('PUT', '/admin/rules', 'superUser', { changes: [{ key: 'retention.enforce', value: true }] });
    assert.equal(locked.json.rule_codes['retention.enforce'], 'RULE_LOCKED');
  });

  it('veritabanı hatası 500 + errorId; iç ayrıntı (SQL, parola) yanıtta YOK', async () => {
    state.failOn = /FROM platform_rule_values v/;
    const res = await call('GET', '/admin/rules', 'superUser');
    assert.equal(res.status, 500);
    assert.equal(typeof res.json.errorId, 'string');
    assert.equal(/SECRET|hunter2|SELECT/.test(res.text), false);
    const write = await call('PUT', '/admin/rules', 'superUser', { changes: [{ key: 'budget.objection_days', value: 9 }] });
    assert.equal(write.status, 500);
    assert.equal(/SECRET|hunter2/.test(write.text), false);
  });
});
