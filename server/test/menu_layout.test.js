// Site menu yerlesimi (K8, P1-16): YETENEK (modul acik/kapali) ile MENU YERLESIMI (kompakt menu kumesi) ayri katman.
// Saf mantik + sema/migration birebirligi + uc davranisi (DB'siz: bellek ici sahte veritabani, sahte kimlik katmani).
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired, requireSiteManager } from '../src/middlewares/auth_middleware.js';
import { MODULE_CATALOG, MODULE_STATUS_AVAILABLE, computeEnabledMap } from '../src/modules/catalog.js';
import { coreModuleDefinitions } from '../src/modules/core_modules.js';
import {
  MENU_ESSENTIAL_MODULES,
  MENU_MODULE_CODES,
  deriveDefaultCompactModules,
  normalizeCompactModules,
  publicMenuLayout,
  resolveMenuLayout,
  sameModuleSet,
  sanitizeStoredModules,
} from '../src/modules/menu_layout_common.js';
import { MENU_LAYOUT_DDL } from '../src/modules/menu_layout_schema.js';
import { menuLayoutLimiter, menuLayoutRouter } from '../src/modules/menu_layout_routes.js';
import { setSiteModuleEnabled } from '../src/modules/module_service.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const norm = (s) => String(s).replace(/--.*$/gm, '').replace(/\s+/g, ' ').replace(/ ?\( ?/g, '(').replace(/ ?\) ?/g, ')').replace(/ ?, ?/g, ',').trim();

const SITE_1 = 1000000001;
const SITE_2 = 1000000002;
const CORE_CODES = coreModuleDefinitions().map((d) => d.code);

const enabledAllCore = (extra = []) => {
  const rows = [...CORE_CODES, ...extra].map((code) => ({ module_code: code, enabled: true }));
  return computeEnabledMap(rows);
};

// ---------------------------------------------------------------------------
// Saf mantik
// ---------------------------------------------------------------------------

describe('menu yerlesimi: varsayilan kume (yonetim turu onerilerinden turetilir)', () => {
  it('menu kodlari: katalogdaki kullanilabilir moduller, katalog sirasiyla ("yakinda" olanlar yok)', () => {
    const expected = MODULE_CATALOG.filter((d) => d.status === MODULE_STATUS_AVAILABLE).map((d) => d.code);
    assert.deepEqual([...MENU_MODULE_CODES], expected);
    assert.ok(!MENU_MODULE_CODES.includes('online_payment'));
    assert.ok(!MENU_MODULE_CODES.includes('hgs_access'));
  });

  it('apartman/site: gunluk isler + onerilenler; her sitede acik diger temel moduller (anket, panolar ...) kumede degil', () => {
    const enabled = enabledAllCore(['door_control']);
    assert.deepEqual(deriveDefaultCompactModules({ managementType: 'apartment_site', enabled }), [
      'door_control',
      'people',
      'announcements',
      'finance',
      'drive_storage',
    ]);
  });

  it('tur onerileri kumeyi degistirir (kooperatif: anket de onerilir; is merkezi: is takibi/ziyaretci ACIKSA girer)', () => {
    const coop = deriveDefaultCompactModules({ managementType: 'cooperative', enabled: enabledAllCore() });
    assert.ok(coop.includes('survey'), 'kooperatif anketi onerir');
    assert.ok(!coop.includes('neighbor_board'));
    const business = deriveDefaultCompactModules({
      managementType: 'business_center',
      enabled: enabledAllCore(['work_tracking', 'visitor_log']),
    });
    assert.deepEqual(business, ['people', 'announcements', 'finance', 'work_tracking', 'visitor_log', 'drive_storage']);
    const businessClosed = deriveDefaultCompactModules({ managementType: 'business_center', enabled: enabledAllCore() });
    assert.ok(!businessClosed.includes('work_tracking'), 'onerilen ama KAPALI modul kumede olmaz');
    assert.ok(!businessClosed.includes('visitor_log'));
  });

  it('isteyerek acilan (temel olmayan) modul onerilmese de kumeye girer; kapali modul girmez', () => {
    const open = deriveDefaultCompactModules({ managementType: 'apartment_site', enabled: enabledAllCore(['contracts', 'budget']) });
    assert.ok(open.includes('contracts') && open.includes('budget'));
    const closed = deriveDefaultCompactModules({ managementType: 'apartment_site', enabled: enabledAllCore() });
    assert.ok(!closed.includes('contracts') && !closed.includes('door_control'));
  });

  it('bilinmeyen tur / eksik veri: apartman/site onerileri; sonuc daima katalog sirasinda ve tekrarsiz', () => {
    const a = deriveDefaultCompactModules({ managementType: 'garip_tur', enabled: enabledAllCore(['door_control']) });
    const b = deriveDefaultCompactModules({ managementType: 'apartment_site', enabled: enabledAllCore(['door_control']) });
    assert.deepEqual(a, b);
    assert.deepEqual(deriveDefaultCompactModules(), []);
    for (const list of [a, b]) {
      assert.deepEqual(list, MENU_MODULE_CODES.filter((c) => list.includes(c)));
      assert.equal(new Set(list).size, list.length);
    }
  });

  it('gunluk isler sabit listedir', () => {
    assert.deepEqual([...MENU_ESSENTIAL_MODULES], ['people', 'announcements', 'finance', 'door_control']);
  });
});

describe('menu yerlesimi: dogrulama ve cozumleme', () => {
  const throwsCode = (fn, code) => assert.throws(fn, (e) => e.code === code && e.statusCode === 400);

  it('normalizeCompactModules: katalog sirasi, tekrar atilir, eski documents kodu Dosya Deposu olur, bos dizi gecerli', () => {
    assert.deepEqual(normalizeCompactModules(['finance', 'people', 'finance']), ['people', 'finance']);
    assert.deepEqual(normalizeCompactModules(['documents']), ['drive_storage']);
    assert.deepEqual(normalizeCompactModules([' survey ']), ['survey']);
    assert.deepEqual(normalizeCompactModules([]), []);
  });

  it('normalizeCompactModules: dizi degil / bilinmeyen / yakinda / metin olmayan kod / cok uzun liste reddedilir (girdi yansitilmaz)', () => {
    throwsCode(() => normalizeCompactModules(undefined), 'INVALID_BODY');
    throwsCode(() => normalizeCompactModules('finance'), 'INVALID_BODY');
    throwsCode(() => normalizeCompactModules({ 0: 'finance' }), 'INVALID_BODY');
    throwsCode(() => normalizeCompactModules(['bilinmeyen']), 'INVALID_MENU_MODULE');
    throwsCode(() => normalizeCompactModules(['online_payment']), 'INVALID_MENU_MODULE');
    throwsCode(() => normalizeCompactModules(['hgs_access']), 'INVALID_MENU_MODULE');
    throwsCode(() => normalizeCompactModules(['card_payments']), 'INVALID_MENU_MODULE');
    throwsCode(() => normalizeCompactModules([5]), 'INVALID_MENU_MODULE');
    throwsCode(() => normalizeCompactModules([null]), 'INVALID_MENU_MODULE');
    throwsCode(() => normalizeCompactModules(Array.from({ length: 65 }, () => 'finance')), 'INVALID_MENU_MODULE');
    try {
      normalizeCompactModules(['<script>alert(1)</script>']);
      assert.fail('reddedilmeliydi');
    } catch (error) {
      assert.ok(!error.message.includes('script'), 'kullanici girdisi hata metnine yansimaz');
    }
  });

  it('sanitizeStoredModules: bozuk / kalkmis kod sessizce atilir, okuma fırlatmaz', () => {
    assert.deepEqual(sanitizeStoredModules(['survey', 'x', 5, null, 'finance', 'documents']), ['finance', 'survey', 'drive_storage']);
    assert.deepEqual(sanitizeStoredModules(null), []);
    assert.deepEqual(sanitizeStoredModules('finance'), []);
  });

  it('resolveMenuLayout: kayit yoksa varsayilan, varsa yoneticinin secimi (customized); default listesi hep dolu', () => {
    const enabled = enabledAllCore(['door_control']);
    const auto = resolveMenuLayout({ managementType: 'apartment_site', enabled });
    assert.equal(auto.customized, false);
    assert.deepEqual(auto.compact_modules, auto.default_compact_modules);
    const custom = resolveMenuLayout({ managementType: 'apartment_site', enabled, stored: ['finance'] });
    assert.equal(custom.customized, true);
    assert.deepEqual(custom.compact_modules, ['finance']);
    assert.deepEqual(custom.default_compact_modules, auto.default_compact_modules);
    const empty = resolveMenuLayout({ managementType: 'apartment_site', enabled, stored: [] });
    assert.deepEqual([empty.customized, empty.compact_modules], [true, []]);
  });

  it('publicMenuLayout: my-modules icin kucuk govde (varsayilan liste tasinmaz)', () => {
    const layout = resolveMenuLayout({ managementType: 'apartment_site', enabled: enabledAllCore() });
    assert.deepEqual(Object.keys(publicMenuLayout(layout)), ['compact_modules', 'customized']);
  });

  it('sameModuleSet: sira onemsiz, uzunluk ve uyelik onemli', () => {
    assert.equal(sameModuleSet(['a', 'b'], ['b', 'a']), true);
    assert.equal(sameModuleSet(['a'], ['a', 'b']), false);
    assert.equal(sameModuleSet([], []), true);
  });
});

describe('102 site_menu_layouts: sema', () => {
  const migration = readFileSync(path.join(here, '..', 'migrations', '102_site_menu_layout.sql'), 'utf8');

  it('db.js DDL migration ile birebir ve idempotent', () => {
    const all = norm(migration);
    for (const [name, sql] of Object.entries(MENU_LAYOUT_DDL)) {
      assert.match(sql, /IF NOT EXISTS/, name);
      assert.ok(all.includes(norm(sql)), `${name} migration ile ayni degil`);
    }
  });

  it('tablo: site silinince satir da gider; kume bos olabilir; hicbir sutun modul durumu tutmaz', () => {
    const sql = MENU_LAYOUT_DDL.table.replace(/\s+/g, ' ');
    assert.match(sql, /site_code BIGINT PRIMARY KEY REFERENCES sites\(site_code\) ON DELETE CASCADE/);
    assert.match(sql, /compact_modules TEXT\[\] NOT NULL DEFAULT '\{\}'/);
    assert.match(sql, /cardinality\(compact_modules\) <= 64/);
    assert.ok(!/enabled/i.test(sql), 'yetenek (acik/kapali) bu tabloda tutulmaz');
  });

  it('db.js acilista ensureMenuLayoutSchema cagirir; sunucu rotayi baglar', () => {
    const db = readFileSync(path.join(here, '..', 'src', 'db.js'), 'utf8');
    assert.match(db, /import \{ ensureMenuLayoutSchema \} from '\.\/modules\/menu_layout_schema\.js'/);
    assert.match(db, /await ensureMenuLayoutSchema\(client\)/);
    const server = readFileSync(path.join(here, '..', 'src', 'server.js'), 'utf8');
    assert.match(server, /app\.use\(menuLayoutRouter\)/);
  });
});

// ---------------------------------------------------------------------------
// Bellek ici sahte veritabani
// ---------------------------------------------------------------------------

const users = {
  superUser: { id: 1, user_code: 1, userCode: 1, role: 'super_user', full_name: 'Süper Kullanıcı', email: 'root@example.com' },
  mgrA: { id: 20001, user_code: 20001, userCode: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici', email: 'a@example.com' },
  mgrB: { id: 20002, user_code: 20002, userCode: 20002, role: 'site_manager', full_name: 'Bora Yönetici', email: 'b@example.com' },
  resident: { id: 20004, user_code: 20004, userCode: 20004, role: 'apartment_owner', full_name: 'Deniz Sakin', email: 'd@example.com' },
};

let state;

function makeState() {
  return {
    sites: new Map([
      [SITE_1, { name: 'Gül Sitesi', management_type: 'apartment_site' }],
      [SITE_2, { name: 'İş Merkezi', management_type: 'business_center' }],
    ]),
    managerLinks: [
      { site_code: SITE_1, user_code: 20001 },
      { site_code: SITE_2, user_code: 20002 },
    ],
    siteModules: new Map(),
    layouts: new Map(),
    audit: [],
    failLayoutWrite: false,
    log: [],
  };
}

const ok = (rows = []) => ({ rows, rowCount: rows.length });

function handle(sql, params, tx) {
  const write = (fn) => (tx && tx.pending ? tx.pending.push(fn) : fn());
  state.log.push({ sql, params, inTx: Boolean(tx?.pending) });

  if (sql === 'BEGIN') {
    tx.pending = [];
    return ok();
  }
  if (sql === 'COMMIT') {
    for (const fn of tx.pending) fn();
    tx.pending = null;
    return ok();
  }
  if (sql === 'ROLLBACK') {
    tx.pending = null;
    return ok();
  }
  if (/^(SAVEPOINT|ROLLBACK TO SAVEPOINT|RELEASE SAVEPOINT) /.test(sql)) return ok();

  // yetki
  if (/^SELECT 1 FROM site_manager_sites WHERE manager_user_code = \$1 LIMIT 1$/.test(sql)) {
    return ok(state.managerLinks.filter((l) => l.user_code === Number(params[0])).slice(0, 1).map(() => ({ '?column?': 1 })));
  }
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(
      state.managerLinks.filter((l) => l.site_code === Number(params[0]) && l.user_code === Number(params[1])).map(() => ({ '?column?': 1 })),
    );
  }
  if (/^SELECT 1 FROM site_memberships /.test(sql)) return ok();

  // site
  if (/^SELECT site_code, name, management_type FROM sites WHERE site_code = \$1 (LIMIT 1|FOR SHARE)$/.test(sql)) {
    const site = state.sites.get(Number(params[0]));
    return ok(site ? [{ site_code: String(params[0]), name: site.name, management_type: site.management_type }] : []);
  }
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 FOR SHARE$/.test(sql)) {
    return ok(state.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  }

  // yetenek (yalniz okunur: bu uclar site_modules'a ASLA yazmaz)
  if (/^SELECT module_code, enabled FROM site_modules WHERE site_code = \$1$/.test(sql)) {
    return ok([...state.siteModules.values()].filter((r) => r.site_code === Number(params[0])).map((r) => ({ module_code: r.module_code, enabled: r.enabled })));
  }
  if (/^(INSERT INTO|UPDATE|DELETE FROM) site_modules/.test(sql)) {
    throw new Error(`menu yerlesimi site_modules'a yazmamali: ${sql}`);
  }

  // yerlesim
  if (/^SELECT compact_modules FROM site_menu_layouts WHERE site_code = \$1 (LIMIT 1|FOR UPDATE)$/.test(sql)) {
    const row = state.layouts.get(Number(params[0]));
    return ok(row ? [{ compact_modules: row.compact_modules }] : []);
  }
  if (/^INSERT INTO site_menu_layouts /.test(sql)) {
    if (state.failLayoutWrite) throw Object.assign(new Error('SECRET_DB_DETAIL yaz'), { code: 'XX000' });
    const [siteCode, modules, updatedBy] = params;
    write(() => state.layouts.set(Number(siteCode), { compact_modules: [...modules], updated_by: updatedBy }));
    return ok();
  }
  if (/^DELETE FROM site_menu_layouts WHERE site_code = \$1 RETURNING site_code$/.test(sql)) {
    const had = state.layouts.has(Number(params[0]));
    write(() => state.layouts.delete(Number(params[0])));
    return ok(had ? [{ site_code: String(params[0]) }] : []);
  }

  // denetim
  if (/^INSERT INTO audit_log /.test(sql)) {
    const [actorUserCode, actorName, actorRole, action, siteCode, targetType, targetId, details] = params;
    write(() =>
      state.audit.push({
        actor_user_code: actorUserCode,
        actor_name: actorName,
        actor_role: actorRole,
        action,
        site_code: siteCode,
        target_type: targetType,
        target_id: targetId,
        details: JSON.parse(details),
      }),
    );
    return ok();
  }

  throw new Error(`sahte veritabani: beklenmeyen sorgu: ${sql}`);
}

function installFakeDb() {
  pool.query = async (text, params) => handle(norm2(text), params ?? [], null);
  pool.connect = async () => {
    const tx = { pending: null };
    return {
      query: async (text, params) => handle(norm2(text), params ?? [], tx),
      release() {},
    };
  };
}

// Sahte veritabani sorgu metnini tek bosluga indirger (modul testleriyle ayni kural).
const norm2 = (text) => String(text).replace(/\s+/g, ' ').trim();

// ---------------------------------------------------------------------------
// HTTP duzenegi
// ---------------------------------------------------------------------------

const ORIGINAL = menuLayoutRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({
    path: layer.route.path,
    method: Object.keys(layer.route.methods)[0],
    handlers: layer.route.stack.map((entry) => entry.handle),
  }));

let server;
let baseUrl;

before(async () => {
  for (const layer of menuLayoutRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    // degistiren uclar: hiz sinirlayici (ayri testte dogrudan sinanir)
    const idx = layer.route.stack.findIndex((entry) => entry.handle === menuLayoutLimiter);
    if (idx >= 0) layer.route.stack[idx].handle = (_req, _res, next) => next();
  }
  const app = express();
  app.use(express.json());
  app.use(menuLayoutRouter);
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

async function call(method, urlPath, { user = users.mgrA, body } = {}) {
  const response = await fetch(`${baseUrl}${urlPath}`, {
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

const url = (site = SITE_1) => `/manager/sites/${site}/menu-layout`;
const openModule = (site, code) => state.siteModules.set(`${site}:${code}`, { site_code: site, module_code: code, enabled: true });

describe('menu yerlesimi uclari: kimlik zinciri', () => {
  it('3 rota: authRequired + requireSiteManager; degistiren uclar hiz sinirli (yetkiden sonra)', () => {
    assert.deepEqual(
      ORIGINAL.map((r) => `${r.method.toUpperCase()} ${r.path}`).sort(),
      ['DELETE /manager/sites/:siteCode/menu-layout', 'GET /manager/sites/:siteCode/menu-layout', 'PUT /manager/sites/:siteCode/menu-layout'],
    );
    for (const route of ORIGINAL) {
      assert.equal(route.handlers[0], authRequired, `${route.method} ${route.path}`);
      assert.equal(route.handlers[1], requireSiteManager, `${route.method} ${route.path}`);
      if (route.method !== 'get') assert.equal(route.handlers[2], menuLayoutLimiter, `${route.method} sinirli`);
    }
  });
});

describe('GET /manager/sites/:siteCode/menu-layout', () => {
  it('yonetici kendi sitesi: varsayilan kume, secim listesi (yetenek enabled + compact + recommended)', async () => {
    openModule(SITE_1, 'door_control');
    const res = await call('GET', url());
    assert.equal(res.status, 200);
    assert.deepEqual(Object.keys(res.body), [
      'site_code',
      'site_name',
      'management_type',
      'management_type_label',
      'customized',
      'compact_modules',
      'default_compact_modules',
      'modules',
    ]);
    assert.equal(res.body.site_code, SITE_1);
    assert.equal(res.body.management_type, 'apartment_site');
    assert.equal(res.body.customized, false);
    assert.deepEqual(res.body.compact_modules, ['door_control', 'people', 'announcements', 'finance', 'drive_storage']);
    assert.deepEqual(res.body.compact_modules, res.body.default_compact_modules);
    assert.equal(res.body.modules.length, MENU_MODULE_CODES.length);
    assert.deepEqual(Object.keys(res.body.modules[0]), ['code', 'name', 'description', 'core', 'enabled', 'compact', 'recommended']);
    const byCode = Object.fromEntries(res.body.modules.map((m) => [m.code, m]));
    assert.equal(byCode.survey.core, true);
    assert.equal(byCode.survey.enabled, true, 'temel modul acik');
    assert.equal(byCode.survey.compact, false, 'ama varsayilan kumede degil');
    assert.equal(byCode.door_control.recommended, true);
    assert.equal(byCode.reservation.enabled, false);
  });

  it('kayitli kume: customized true ve secim aynen doner', async () => {
    state.layouts.set(SITE_1, { compact_modules: ['finance', 'survey'] });
    const res = await call('GET', url());
    assert.equal(res.body.customized, true);
    assert.deepEqual(res.body.compact_modules, ['finance', 'survey']);
    assert.ok(res.body.default_compact_modules.includes('people'));
  });

  it('yetki: baska sitenin yoneticisi 403 FORBIDDEN_SITE, sakin 403, super kullanici her site; olmayan site 404', async () => {
    assert.equal((await call('GET', url(SITE_1), { user: users.mgrB })).body.code, 'FORBIDDEN_SITE');
    assert.equal((await call('GET', url(SITE_1), { user: users.resident })).status, 403);
    assert.equal((await call('GET', url(SITE_2), { user: users.superUser })).status, 200);
    state.sites.delete(SITE_2);
    const missing = await call('GET', url(SITE_2), { user: users.superUser });
    assert.deepEqual([missing.status, missing.body.code], [404, 'SITE_NOT_FOUND']);
  });

  it('gecersiz site kodu 400', async () => {
    const res = await call('GET', '/manager/sites/abc/menu-layout');
    assert.deepEqual([res.status, res.body.code], [400, 'INVALID_SITE_CODE']);
  });
});

describe('PUT /manager/sites/:siteCode/menu-layout', () => {
  it('ozel kume kaydedilir (katalog sirasi), yanit guncel gorunumdur, denetim kaydi yazilir', async () => {
    openModule(SITE_1, 'door_control');
    const res = await call('PUT', url(), { body: { compact_modules: ['survey', 'finance', 'finance'] } });
    assert.equal(res.status, 200);
    assert.equal(res.body.customized, true);
    assert.deepEqual(res.body.compact_modules, ['finance', 'survey']);
    assert.deepEqual(state.layouts.get(SITE_1).compact_modules, ['finance', 'survey']);
    assert.equal(state.layouts.get(SITE_1).updated_by, users.mgrA.user_code);
    assert.equal(state.audit.length, 1);
    assert.equal(state.audit[0].action, 'menu_layout.updated');
    assert.equal(state.audit[0].site_code, SITE_1);
    assert.deepEqual(state.audit[0].details, { compact_modules: ['finance', 'survey'] });
  });

  it('YETENEK degismez: temel moduller kumede olmasa da acik kalir, site_modules\'a hic yazilmaz', async () => {
    const res = await call('PUT', url(), { body: { compact_modules: [] } });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.compact_modules, []);
    const byCode = Object.fromEntries(res.body.modules.map((m) => [m.code, m]));
    for (const code of CORE_CODES) {
      assert.equal(byCode[code].enabled, true, `${code} (temel) acik kalir`);
      assert.equal(byCode[code].compact, false);
    }
    assert.ok(!state.log.some((e) => /site_modules/.test(e.sql) && /^(INSERT|UPDATE|DELETE)/.test(e.sql)));
    assert.equal(state.siteModules.size, 0);
  });

  it('temel modul KAPATILAMAZ: katman ayrimi bu kurali degistirmez (MODULE_NOT_TOGGLEABLE)', async () => {
    for (const code of CORE_CODES) {
      await assert.rejects(
        () => setSiteModuleEnabled({ siteCode: SITE_1, moduleCode: code, enabled: false, actor: users.superUser }),
        (e) => e.code === 'MODULE_NOT_TOGGLEABLE' && e.statusCode === 400,
        code,
      );
    }
    assert.equal(state.siteModules.size, 0);
  });

  it('varsayilanla ayni kume ozellestirme sayilmaz: satir silinir (sonradan acilan moduller varsayilani izler)', async () => {
    openModule(SITE_1, 'door_control');
    await call('PUT', url(), { body: { compact_modules: ['finance'] } });
    assert.equal(state.layouts.has(SITE_1), true);
    const back = await call('PUT', url(), { body: { compact_modules: ['drive_storage', 'finance', 'people', 'announcements', 'door_control'] } });
    assert.equal(back.status, 200);
    assert.equal(back.body.customized, false);
    assert.equal(state.layouts.has(SITE_1), false);
    assert.deepEqual(state.audit.map((a) => a.action), ['menu_layout.updated', 'menu_layout.reset']);
    // Satir yokken varsayilani yeniden kaydetmek hicbir sey yazmaz.
    const before = state.audit.length;
    await call('PUT', url(), { body: { compact_modules: ['drive_storage', 'finance', 'people', 'announcements', 'door_control'] } });
    assert.equal(state.audit.length, before);
  });

  it('ayni ozel kumeyi tekrar kaydetmek degisiklik sayilmaz (ikinci denetim satiri yok)', async () => {
    await call('PUT', url(), { body: { compact_modules: ['finance'] } });
    await call('PUT', url(), { body: { compact_modules: ['finance'] } });
    assert.equal(state.audit.length, 1);
  });

  it('gecersiz govde: dizi degil 400 INVALID_BODY; bilinmeyen / yakinda kod 400 INVALID_MENU_MODULE; hicbir sey yazilmaz', async () => {
    const cases = [
      [undefined, 'INVALID_BODY'],
      ['finance', 'INVALID_BODY'],
      [['finance', 'yok'], 'INVALID_MENU_MODULE'],
      [['online_payment'], 'INVALID_MENU_MODULE'],
      [[1], 'INVALID_MENU_MODULE'],
    ];
    for (const [value, code] of cases) {
      const res = await call('PUT', url(), { body: { compact_modules: value } });
      assert.deepEqual([res.status, res.body.code], [400, code], JSON.stringify(value));
    }
    assert.equal(state.layouts.size, 0);
    assert.equal(state.audit.length, 0);
  });

  it('yetki: baska yonetici 403, sakin 403, olmayan site 404', async () => {
    assert.equal((await call('PUT', url(), { user: users.mgrB, body: { compact_modules: [] } })).body.code, 'FORBIDDEN_SITE');
    assert.equal((await call('PUT', url(), { user: users.resident, body: { compact_modules: [] } })).status, 403);
    state.sites.delete(SITE_1);
    const missing = await call('PUT', url(), { user: users.superUser, body: { compact_modules: [] } });
    assert.deepEqual([missing.status, missing.body.code], [404, 'SITE_NOT_FOUND']);
    assert.equal(state.layouts.size, 0);
  });

  it('yazma hatasi: ayrinti sizmaz (500 genel mesaj), islem geri alinir', async () => {
    state.failLayoutWrite = true;
    const res = await call('PUT', url(), { body: { compact_modules: ['finance'] } });
    assert.equal(res.status, 500);
    assert.ok(!JSON.stringify(res.body).includes('SECRET_DB_DETAIL'));
    assert.equal(state.layouts.size, 0);
    assert.equal(state.audit.length, 0);
  });

  it('site kimligi gecerliyse is merkezi icin tur onerileri ayri turetilir', async () => {
    openModule(SITE_2, 'work_tracking');
    const res = await call('GET', url(SITE_2), { user: users.mgrB });
    assert.equal(res.status, 200);
    assert.ok(res.body.compact_modules.includes('work_tracking'));
    assert.ok(!res.body.compact_modules.includes('visitor_log'), 'kapali oneri yok');
  });
});

describe('DELETE /manager/sites/:siteCode/menu-layout', () => {
  it('ozel kume silinir ve varsayilana donulur (denetim: menu_layout.reset)', async () => {
    state.layouts.set(SITE_1, { compact_modules: ['survey'] });
    const res = await call('DELETE', url());
    assert.equal(res.status, 200);
    assert.equal(res.body.customized, false);
    assert.equal(state.layouts.has(SITE_1), false);
    assert.deepEqual(state.audit.map((a) => a.action), ['menu_layout.reset']);
  });

  it('kayit yoksa sessiz basari (denetim satiri yok); yetki ve site denetimi', async () => {
    const res = await call('DELETE', url());
    assert.equal(res.status, 200);
    assert.equal(state.audit.length, 0);
    assert.equal((await call('DELETE', url(), { user: users.mgrB })).body.code, 'FORBIDDEN_SITE');
    state.sites.delete(SITE_2);
    assert.equal((await call('DELETE', url(SITE_2), { user: users.superUser })).body.code, 'SITE_NOT_FOUND');
  });
});

describe('hiz sinirlayici', () => {
  it('menuLayoutLimiter: kullanici basina saatte 60 degisiklik, asilinca 429 + Retry-After', () => {
    menuLayoutLimiter.reset();
    const req = { authUser: { user_code: 9 }, ip: '10.0.0.1', headers: {}, socket: { remoteAddress: '10.0.0.1' } };
    let blocked = 0;
    for (let i = 0; i < 70; i += 1) {
      const res = {
        headers: {},
        setHeader(k, v) { this.headers[k] = v; },
        status(code) { this.code = code; return this; },
        json(body) { this.body = body; return this; },
      };
      let passed = false;
      menuLayoutLimiter(req, res, () => { passed = true; });
      if (!passed) {
        blocked += 1;
        assert.equal(res.code, 429);
        assert.ok(res.headers['Retry-After']);
      }
    }
    assert.ok(blocked >= 1, 'sinir asilinca engellenir');
    menuLayoutLimiter.reset();
  });
});
