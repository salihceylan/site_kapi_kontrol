// Platform modul sistemi uclari (DB'siz): yetki matrisi, onay zorunlulugu, denetim kaydi, sayfalama, ek roller.
// Kimlik katmani test icin sahte (x-test-user); pool.query / pool.connect bellek ici sahte veritabanina baglanir.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired, requireSiteManager, requireSuperUser } from '../src/middlewares/auth_middleware.js';
import { readFileSync } from 'node:fs';
import { moduleRouter, moduleToggleLimiter, staffRoleLimiter } from '../src/modules/module_routes.js';

const SITE_1 = 1000000001;
const SITE_2 = 1000000002;
const WARNING = 'Geçiş Kontrol kapatılırsa telefondan kapı açma, QR ve misafir geçişi durur. Onaylıyor musunuz?';

const users = {
  superUser: { id: 1, user_code: 1, userCode: 1, role: 'super_user', full_name: 'Süper Kullanıcı', email: 'root@example.com' },
  mgrA: { id: 20001, user_code: 20001, userCode: 20001, role: 'site_manager', full_name: 'Ayşe Yönetici', email: 'a@example.com' },
  mgrB: { id: 20002, user_code: 20002, userCode: 20002, role: 'site_manager', full_name: 'Bora Yönetici', email: 'b@example.com' },
  ownerC: { id: 20003, user_code: 20003, userCode: 20003, role: 'apartment_owner', full_name: 'Can Sahip', email: 'c@example.com' },
  resident: { id: 20004, user_code: 20004, userCode: 20004, role: 'apartment_owner', full_name: 'Deniz Sakin', email: 'd@example.com' },
  staff: { id: 20005, user_code: 20005, userCode: 20005, role: 'individual', full_name: 'Ece Görevli', email: 'e@example.com' },
};

// ---------------------------------------------------------------------------
// Bellek ici sahte veritabani
// ---------------------------------------------------------------------------

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const T0 = new Date('2026-10-14T08:00:00.000Z');

function makeUser(code, name, email, overrides = {}) {
  return {
    user_code: code,
    full_name: name,
    email,
    role: 'apartment_owner',
    is_active: true,
    email_verified: true,
    approval_status: 'approved',
    ...overrides,
  };
}

function makeState() {
  return {
    sites: new Map([
      [SITE_1, { name: 'Gül Sitesi', management_type: 'apartment_site' }],
      [SITE_2, { name: 'Lale Sitesi', management_type: 'apartment_site' }],
    ]),
    managerLinks: [
      { site_code: SITE_1, user_code: 20001 },
      { site_code: SITE_2, user_code: 20002 },
      { site_code: SITE_1, user_code: 30008 },
    ],
    memberships: [
      { site_code: SITE_1, user_code: 20003, role: 'SITE_OWNER', is_active: true, created_at: T0 },
      { site_code: SITE_1, user_code: 20005, role: 'STAFF', is_active: true, created_at: new Date(T0.getTime() + 1000) },
      { site_code: SITE_1, user_code: 30003, role: 'SITE_ADMIN', is_active: true, created_at: T0 },
      { site_code: SITE_1, user_code: 30004, role: 'RESIDENT', is_active: true, created_at: T0 },
    ],
    users: [
      makeUser(1, 'Süper Kullanıcı', 'root@example.com', { role: 'super_user' }),
      makeUser(20001, 'Ayşe Yönetici', 'a@example.com', { role: 'site_manager' }),
      makeUser(20002, 'Bora Yönetici', 'b@example.com', { role: 'site_manager' }),
      makeUser(20003, 'Can Sahip', 'c@example.com'),
      makeUser(20004, 'Deniz Sakin', 'd@example.com'),
      makeUser(20005, 'Ece Görevli', 'e@example.com', { role: 'individual' }),
      makeUser(30001, 'Fatma Kurul', 'fatma@example.com'),
      makeUser(30002, 'Gül Pasif', 'pasif@example.com', { is_active: false }),
      makeUser(30003, 'Hasan Yönetici', 'hasan@example.com', { role: 'site_manager' }),
      makeUser(30004, 'İpek Sakin', 'ipek@example.com'),
      makeUser(30005, 'Jale Doğrulanmamış', 'dogrulanmamis@example.com', { email_verified: false }),
      makeUser(30006, 'Kaan Bekleyen', 'bekleyen@example.com', { approval_status: 'pending' }),
      makeUser(30008, 'Leman Link', 'leman@example.com', { role: 'site_manager' }),
    ],
    siteModules: new Map(),
    audit: [],
    auditSeq: 0,
    myLinks: [],
    failAuditInsert: false,
    failModuleUpsert: false,
    // site -> cihaz idleri (yerel kontrol anahtari donmesi icin); rotations: UPDATE devices kayitlari
    moduleRequests: [],
    locks: [],
    siteDeviceIds: new Map([[SITE_1, [501, 502]]]),
    rotations: [],
    failDeviceQuery: false,
    // yaris benzetimi: ek rol upsert'inden hemen once calisir (baska bir isteğin commit'ini temsil eder)
    beforeUpsert: null,
    log: [],
  };
}

let state;

const ok = (rows = []) => ({ rows, rowCount: rows.length });

function siteHeader(code) {
  const site = state.sites.get(Number(code));
  return site ? { site_code: String(code), name: site.name, management_type: site.management_type } : null;
}

function handle(sql, params, tx) {
  const write = (fn) => (tx && tx.pending ? tx.pending.push(fn) : fn());
  state.log.push({ sql, params, inTx: Boolean(tx?.pending) });

  // --- transaction kontrolu ---
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
  if (/^SELECT pg_advisory_xact_lock/.test(sql)) {
    state.locks.push(params[0]);
    return ok();
  }

  // --- yetki sorgulari (requireSiteManager / hasSiteManagementAccess) ---
  if (/^SELECT 1 FROM site_manager_sites WHERE manager_user_code = \$1 LIMIT 1$/.test(sql)) {
    return ok(state.managerLinks.filter((l) => l.user_code === Number(params[0])).slice(0, 1).map(() => ({ '?column?': 1 })));
  }
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(
      state.managerLinks
        .filter((l) => l.site_code === Number(params[0]) && l.user_code === Number(params[1]))
        .map(() => ({ '?column?': 1 })),
    );
  }
  if (/^SELECT 1 FROM site_memberships WHERE user_code = \$1 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) {
    return ok(
      state.memberships
        .filter((m) => m.user_code === Number(params[0]) && ['SITE_OWNER', 'SITE_ADMIN'].includes(m.role) && m.is_active)
        .slice(0, 1)
        .map(() => ({ '?column?': 1 })),
    );
  }
  if (/^SELECT 1 FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) {
    return ok(
      state.memberships
        .filter(
          (m) =>
            m.site_code === Number(params[0]) &&
            m.user_code === Number(params[1]) &&
            ['SITE_OWNER', 'SITE_ADMIN'].includes(m.role) &&
            m.is_active,
        )
        .map(() => ({ '?column?': 1 })),
    );
  }

  // --- siteler ---
  if (/^SELECT site_code, name, management_type FROM sites WHERE site_code = \$1 LIMIT 1$/.test(sql)) {
    const header = siteHeader(params[0]);
    return ok(header ? [header] : []);
  }
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 (FOR SHARE|LIMIT 1)$/.test(sql)) {
    return ok(state.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  }

  // --- site modulleri ---
  if (/^SELECT sm\.module_code, sm\.enabled, sm\.updated_at, u\.full_name AS updated_by_name FROM site_modules sm/.test(sql)) {
    const rows = [];
    for (const row of state.siteModules.values()) {
      if (row.site_code !== Number(params[0])) continue;
      const updater = state.users.find((u) => u.user_code === row.updated_by);
      rows.push({
        module_code: row.module_code,
        enabled: row.enabled,
        updated_at: row.updated_at,
        updated_by_name: updater ? updater.full_name : null,
      });
    }
    return ok(rows);
  }
  if (/^SELECT module_code FROM module_requests WHERE site_code = \$1 AND status = 'pending'$/.test(sql)) {
    return ok(
      state.moduleRequests
        .filter((r) => r.site_code === Number(params[0]) && r.status === 'pending')
        .map((r) => ({ module_code: r.module_code })),
    );
  }
  if (/^UPDATE module_requests SET status = 'approved', decided_by = \$3, decided_by_name = \$4, decision_note = \$5, decided_at = NOW\(\) WHERE site_code = \$1 AND module_code = \$2 AND status = 'pending' RETURNING id$/.test(sql)) {
    const [siteCode, moduleCode, decidedBy, decidedByName, decisionNote] = params;
    const hits = state.moduleRequests.filter(
      (r) => r.site_code === Number(siteCode) && r.module_code === moduleCode && r.status === 'pending',
    );
    write(() => {
      for (const r of hits) {
        Object.assign(r, { status: 'approved', decided_by: decidedBy, decided_by_name: decidedByName, decision_note: decisionNote });
      }
    });
    return ok(hits.map((r) => ({ id: String(r.id) })));
  }
  if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) {
    const row = state.siteModules.get(`${params[0]}:${params[1]}`);
    return ok(row ? [{ enabled: row.enabled }] : []);
  }
  if (/^INSERT INTO site_modules /.test(sql)) {
    if (state.failModuleUpsert) {
      throw Object.assign(new Error('SECRET_DB_DETAIL upsert'), { code: 'XX000' });
    }
    const [siteCode, moduleCode, enabled, updatedBy] = params;
    write(() =>
      state.siteModules.set(`${siteCode}:${moduleCode}`, {
        site_code: Number(siteCode),
        module_code: moduleCode,
        enabled,
        updated_by: updatedBy,
        updated_at: new Date('2026-10-15T10:00:00.000Z'),
      }),
    );
    return ok();
  }
  if (/^WITH links AS /.test(sql)) {
    return ok(state.myLinks);
  }
  if (/^SELECT site_code, module_code, enabled FROM site_modules WHERE site_code = ANY\(\$1::BIGINT\[\]\)$/.test(sql)) {
    const wanted = new Set(params[0].map(Number));
    return ok([...state.siteModules.values()].filter((row) => wanted.has(row.site_code)));
  }

  // --- yerel kontrol anahtari donmesi (local_token_service -> device_service) ---
  if (/^SELECT DISTINCT devices\.id FROM devices LEFT JOIN site_doors door ON door\.assigned_device_id = devices\.id WHERE devices\.site_code = \$1 OR door\.site_code = \$1$/.test(sql)) {
    if (state.failDeviceQuery) {
      throw Object.assign(new Error('SECRET_DB_DETAIL cihaz sorgusu'), { code: 'XX000' });
    }
    return ok((state.siteDeviceIds.get(Number(params[0])) ?? []).map((id) => ({ id: String(id) })));
  }
  if (/^UPDATE devices SET local_control_token = \$1 WHERE id = \$2 RETURNING device_uid, local_control_token$/.test(sql)) {
    state.rotations.push({ deviceId: Number(params[1]), token: params[0] });
    return ok([{ device_uid: `DEV${params[1]}`, local_control_token: params[0] }]);
  }

  // --- denetim kaydi ---
  if (/^INSERT INTO audit_log /.test(sql)) {
    if (state.failAuditInsert) {
      throw Object.assign(new Error('audit tablo yok'), { code: '42P01' });
    }
    const [actorUserCode, actorName, actorRole, action, siteCode, targetType, targetId, details] = params;
    write(() => {
      state.auditSeq += 1;
      state.audit.push({
        id: state.auditSeq,
        created_at: new Date(T0.getTime() + state.auditSeq * 1000),
        actor_user_code: actorUserCode,
        actor_name: actorName,
        actor_role: actorRole,
        action,
        site_code: siteCode,
        target_type: targetType,
        target_id: targetId,
        details: JSON.parse(details),
      });
    });
    return ok();
  }
  if (/FROM audit_log a LEFT JOIN sites s ON s\.site_code = a\.site_code/.test(sql)) {
    const [siteCode, beforeId, limit, action] = params;
    const rows = state.audit
      .filter(
        (a) =>
          (siteCode === null || a.site_code === Number(siteCode)) &&
          (beforeId === null || a.id < Number(beforeId)) &&
          (action === null || a.action === action),
      )
      .sort((x, y) => y.id - x.id)
      .slice(0, limit)
      .map((a) => ({
        ...a,
        id: String(a.id), // BIGSERIAL pg'de metin doner
        site_code: a.site_code === null ? null : String(a.site_code),
        site_name: a.site_code === null ? null : (state.sites.get(a.site_code)?.name ?? null),
      }));
    return ok(rows);
  }

  // --- ek roller ---
  if (/^SELECT sm\.user_code, u\.full_name, u\.email, sm\.role, sm\.created_at FROM site_memberships sm INNER JOIN users u/.test(sql)) {
    const rows = state.memberships
      .filter((m) => m.site_code === Number(params[0]) && ['BOARD_MEMBER', 'STAFF'].includes(m.role) && m.is_active)
      .sort((a, b) => a.created_at - b.created_at || a.user_code - b.user_code)
      .map((m) => {
        const u = state.users.find((x) => x.user_code === m.user_code);
        return { user_code: m.user_code, full_name: u.full_name, email: u.email, role: m.role, created_at: m.created_at };
      });
    return ok(rows);
  }
  if (/^SELECT user_code, full_name, email, role, is_active, email_verified, approval_status FROM users WHERE LOWER\(email\) = \$1 AND deleted_at IS NULL LIMIT 1 FOR KEY SHARE$/.test(sql)) {
    const user = state.users.find((u) => u.email.toLowerCase() === params[0]);
    return ok(user ? [user] : []);
  }
  if (/^SELECT 1 AS present FROM site_manager_sites /.test(sql)) {
    const [siteCode, userCode] = params.map(Number);
    const linked = state.managerLinks.some((l) => l.site_code === siteCode && l.user_code === userCode);
    const member = state.memberships.some(
      (m) => m.site_code === siteCode && m.user_code === userCode && ['SITE_OWNER', 'SITE_ADMIN'].includes(m.role) && m.is_active,
    );
    return ok(linked || member ? [{ present: 1 }] : []);
  }
  if (/^SELECT role, is_active FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 LIMIT 1 FOR UPDATE$/.test(sql)) {
    const row = state.memberships.find((m) => m.site_code === Number(params[0]) && m.user_code === Number(params[1]));
    return ok(row ? [{ role: row.role, is_active: row.is_active }] : []);
  }
  if (/^INSERT INTO site_memberships \(site_code, user_code, role, is_active\) VALUES \(\$1, \$2, \$3, TRUE\) ON CONFLICT/.test(sql)) {
    const [siteCode, userCode, role] = params.map((p, i) => (i < 2 ? Number(p) : p));
    if (state.beforeUpsert) {
      const hook = state.beforeUpsert;
      state.beforeUpsert = null;
      hook();
    }
    const existing = state.memberships.find((m) => m.site_code === siteCode && m.user_code === userCode);
    // SQL'deki: WHERE site_memberships.role NOT IN ('SITE_OWNER','SITE_ADMIN') OR site_memberships.is_active = FALSE
    if (existing && ['SITE_OWNER', 'SITE_ADMIN'].includes(existing.role) && existing.is_active) {
      return ok([]);
    }
    const createdAt = existing ? existing.created_at : new Date('2026-10-15T09:00:00.000Z');
    write(() => {
      const current = state.memberships.find((m) => m.site_code === siteCode && m.user_code === userCode);
      if (current) {
        current.role = role;
        current.is_active = true;
      } else {
        state.memberships.push({ site_code: siteCode, user_code: userCode, role, is_active: true, created_at: createdAt });
      }
    });
    return ok([{ created_at: createdAt }]);
  }
  if (/^DELETE FROM site_memberships WHERE site_code = \$1 AND user_code = \$2 AND role IN \('BOARD_MEMBER', 'STAFF'\) RETURNING role$/.test(sql)) {
    const [siteCode, userCode] = params.map(Number);
    const row = state.memberships.find(
      (m) => m.site_code === siteCode && m.user_code === userCode && ['BOARD_MEMBER', 'STAFF'].includes(m.role),
    );
    if (!row) return ok();
    write(() => {
      state.memberships = state.memberships.filter((m) => m !== row);
    });
    return ok([{ role: row.role }]);
  }

  throw new Error(`sahte veritabani: beklenmeyen sorgu: ${sql}`);
}

function installFakeDb() {
  pool.query = async (text, params) => handle(norm(text), params ?? [], null);
  pool.connect = async () => {
    const tx = { pending: null };
    return {
      released: false,
      query: async (text, params) => handle(norm(text), params ?? [], tx),
      release() {
        this.released = true;
      },
    };
  };
}

// ---------------------------------------------------------------------------
// HTTP duzenegi
// ---------------------------------------------------------------------------

const ORIGINAL_FIRST_HANDLERS = moduleRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({
    path: layer.route.path,
    methods: Object.keys(layer.route.methods),
    handlers: layer.route.stack.map((entry) => entry.handle),
  }));

let server;
let baseUrl;

before(async () => {
  for (const layer of moduleRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    // PUT uclari: hiz sinirlayicilar (ayri testlerde dogrudan sinanir)
    if (layer.route.methods.put && layer.route.path.endsWith('/staff-roles')) {
      assert.equal(layer.route.stack[2].handle, staffRoleLimiter);
      layer.route.stack[2].handle = (_req, _res, next) => next();
    }
    if (layer.route.methods.put && layer.route.path.endsWith('/modules/:moduleCode')) {
      assert.equal(layer.route.stack[2].handle, moduleToggleLimiter);
      layer.route.stack[2].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json());
  app.use(moduleRouter);
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
    // govdesiz
  }
  return { status: response.status, body: json };
}

const doorOf = (body) => body.modules.find((m) => m.code === 'door_control');
const moduleUrl = (site = SITE_1, code = 'door_control') => `/manager/sites/${site}/modules/${code}`;

// ---------------------------------------------------------------------------
// Katalog ve rota koruma zincirleri
// ---------------------------------------------------------------------------

describe('platform rotalari: kimlik zinciri', () => {
  it('her rota authRequired ile baslar; yonetici uclari requireSiteManager, denetim ucu requireSuperUser kullanir', () => {
    assert.equal(ORIGINAL_FIRST_HANDLERS.length, 8);
    for (const route of ORIGINAL_FIRST_HANDLERS) {
      assert.equal(route.handlers[0], authRequired, `${route.methods} ${route.path}`);
      if (route.path.startsWith('/manager/')) {
        assert.equal(route.handlers[1], requireSiteManager, route.path);
      }
      if (route.path === '/admin/audit-log') {
        assert.equal(route.handlers[1], requireSuperUser);
      }
      if (route.methods[0] === 'put' && route.path.endsWith('/staff-roles')) {
        assert.equal(route.handlers[2], staffRoleLimiter, 'staff-roles PUT hiz sinirli (yetkiden sonra)');
      }
      if (route.methods[0] === 'put' && route.path.endsWith('/modules/:moduleCode')) {
        assert.equal(route.handlers[2], moduleToggleLimiter, 'modul PUT hiz sinirli (yetkiden sonra)');
      }
    }
    const summary = ORIGINAL_FIRST_HANDLERS.map((r) => `${r.methods[0].toUpperCase()} ${r.path}`).sort();
    assert.deepEqual(summary, [
      'DELETE /manager/sites/:siteCode/staff-roles/:userCode',
      'GET /admin/audit-log',
      'GET /app/modules/catalog',
      'GET /app/my-modules',
      'GET /manager/sites/:siteCode/modules',
      'GET /manager/sites/:siteCode/staff-roles',
      'PUT /manager/sites/:siteCode/modules/:moduleCode',
      'PUT /manager/sites/:siteCode/staff-roles',
    ]);
  });
});

describe('GET /app/modules/catalog', () => {
  it('kimligi dogrulanmis herkese 10 modullu katalog doner', async () => {
    const res = await call('GET', '/app/modules/catalog', { user: users.resident });
    assert.equal(res.status, 200);
    assert.equal(res.body.modules.length, 10);
    assert.deepEqual(Object.keys(res.body.modules[0]), ['code', 'name', 'description', 'core', 'status']);
    assert.equal(res.body.modules[0].code, 'door_control');
    assert.equal(res.body.modules[1].core, true);
  });
});

// ---------------------------------------------------------------------------
// GET /manager/sites/:siteCode/modules
// ---------------------------------------------------------------------------

describe('GET /manager/sites/:siteCode/modules: yetki matrisi', () => {
  it('site yoneticisi kendi sitesi: 200 ve sozlesme govdesi (varsayilan door_control ACIK)', async () => {
    const res = await call('GET', `/manager/sites/${SITE_1}/modules`, { user: users.mgrA });
    assert.equal(res.status, 200);
    assert.equal(res.body.site_code, SITE_1);
    assert.equal(res.body.site_name, 'Gül Sitesi');
    assert.equal(res.body.management_type, 'apartment_site');
    assert.equal(res.body.management_type_label, 'Apartman ve Site');
    assert.equal(res.body.modules.length, 10);
    assert.deepEqual(doorOf(res.body), {
      code: 'door_control',
      name: 'Geçiş Kontrol (SmartKeyPass)',
      description: doorOf(res.body).description,
      core: false,
      status: 'available',
      enabled: true,
      toggleable: true,
      // Faz 1.1 (ekleyici alanlar): yonetici modul acip kapatamaz; bekleyen talep yok
      can_toggle: false,
      request_status: null,
      updated_at: null,
      updated_by: null,
    });
    const finance = res.body.modules.find((m) => m.code === 'finance');
    assert.equal(finance.status, 'available', 'Faz 4a: Aidat ve Finans kullanılabilir');
    assert.equal(finance.enabled, false, 'varsayılan KAPALI');
    assert.equal(finance.toggleable, true);
    assert.equal(finance.can_toggle, false, 'yönetici modül açıp kapatamaz (modül talep eder)');
    const reservation = res.body.modules.find((m) => m.code === 'reservation');
    assert.equal(reservation.status, 'available', 'Rezervasyon ve Konsiyerj kullanilabilir');
    assert.equal(reservation.enabled, false, 'varsayilan KAPALI');
    assert.equal(reservation.toggleable, true);
    assert.equal(reservation.can_toggle, false, 'yonetici modul acip kapatamaz (modul talep eder)');
    const metering = res.body.modules.find((m) => m.code === 'metering');
    assert.equal(metering.status, 'coming_soon');
    assert.equal(metering.enabled, false);
    assert.equal(metering.toggleable, false);
    assert.equal(metering.can_toggle, false);
  });

  it('can_toggle yalnizca SUPER kullanici ve toggleable modulde true; request_status bekleyen talebi gosterir', async () => {
    const asSuper = await call('GET', `/manager/sites/${SITE_1}/modules`, { user: users.superUser });
    assert.equal(asSuper.status, 200);
    assert.deepEqual(
      asSuper.body.modules.map((m) => [m.code, m.toggleable, m.can_toggle]),
      [
        ['door_control', true, true],
        ['people', false, false],
        ['announcements', false, false],
        ['finance', true, true],
        ['documents', true, true],
        ['reservation', true, true],
        ['work_tracking', true, true],
        ['metering', false, false],
        ['online_payment', false, false],
        ['visitor_log', true, true],
      ],
    );
    // bekleyen talep: yalnizca o sitenin o modulu 'pending' olur; baska site / sonuclanmis talep etkilemez
    state.moduleRequests = [
      { site_code: SITE_1, module_code: 'door_control', status: 'pending' },
      { site_code: SITE_1, module_code: 'finance', status: 'approved' },
      { site_code: SITE_2, module_code: 'finance', status: 'pending' },
    ];
    const asManager = await call('GET', `/manager/sites/${SITE_1}/modules`, { user: users.mgrA });
    assert.deepEqual(
      asManager.body.modules.filter((m) => m.request_status !== null).map((m) => [m.code, m.request_status]),
      [['door_control', 'pending']],
    );
    assert.ok(asManager.body.modules.every((m) => m.can_toggle === false));
    assert.ok(asManager.body.modules.every((m) => m.request_status === null || m.request_status === 'pending'));
  });

  it('super kullanici her siteye girer; SITE_OWNER uyeligi olan kisi de yonetici sayilir', async () => {
    assert.equal((await call('GET', `/manager/sites/${SITE_2}/modules`, { user: users.superUser })).status, 200);
    assert.equal((await call('GET', `/manager/sites/${SITE_1}/modules`, { user: users.ownerC })).status, 200);
  });

  it('baska sitenin yoneticisi 403 FORBIDDEN_SITE', async () => {
    const res = await call('GET', `/manager/sites/${SITE_1}/modules`, { user: users.mgrB });
    assert.equal(res.status, 403);
    assert.equal(res.body.code, 'FORBIDDEN_SITE');
    assert.equal(typeof res.body.error, 'string');
  });

  it('sakin ve ek rollu (STAFF/BOARD) kisi 403: yonetici sayilmaz', async () => {
    for (const user of [users.resident, users.staff]) {
      const res = await call('GET', `/manager/sites/${SITE_1}/modules`, { user });
      assert.equal(res.status, 403, user.full_name);
    }
  });

  it('super + olmayan site: 404 SITE_NOT_FOUND; baska yonetici + olmayan site: 403 (varlik sizdirilmaz)', async () => {
    const missing = await call('GET', '/manager/sites/1999999999/modules', { user: users.superUser });
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'SITE_NOT_FOUND');
    const forbidden = await call('GET', '/manager/sites/1999999999/modules', { user: users.mgrA });
    assert.equal(forbidden.status, 403);
  });

  it('gecersiz site kodu 400 INVALID_SITE_CODE', async () => {
    for (const bad of ['abc', '0', '-5', '12.5']) {
      const res = await call('GET', `/manager/sites/${bad}/modules`, { user: users.superUser });
      assert.equal(res.status, 400, bad);
      assert.equal(res.body.code, 'INVALID_SITE_CODE');
    }
  });

  it('beklenmeyen veritabani hatasi 500 + errorId; ic ayrinti sizmaz', async () => {
    pool.query = async () => {
      throw Object.assign(new Error('SECRET_DB_DETAIL baglanti'), { code: 'ECONNRESET' });
    };
    const res = await call('GET', `/manager/sites/${SITE_1}/modules`, { user: users.superUser });
    assert.equal(res.status, 500);
    assert.equal(typeof res.body.errorId, 'string');
    assert.equal(JSON.stringify(res.body).includes('SECRET_DB_DETAIL'), false);
  });
});

// ---------------------------------------------------------------------------
// PUT /manager/sites/:siteCode/modules/:moduleCode
// ---------------------------------------------------------------------------

describe('PUT modul: onay zorunlulugu ve denetim kaydi', () => {
  it('door_control kapatilirken confirm yoksa 409 MODULE_CONFIRM_REQUIRED + sozlesme metni; hicbir sey yazilmaz', async () => {
    const res = await call('PUT', moduleUrl(), { user: users.superUser, body: { enabled: false } });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'MODULE_CONFIRM_REQUIRED');
    assert.equal(res.body.error, WARNING);
    assert.equal(state.siteModules.size, 0);
    assert.equal(state.audit.length, 0);
    assert.equal(state.log.some((q) => q.sql === 'BEGIN'), false, 'dogrulama transaction acmadan reddeder');
  });

  it('confirm yalnizca boolean true kabul edilir ("true", 1, false reddedilir)', async () => {
    for (const confirm of ['true', 1, false, null, 'evet']) {
      const res = await call('PUT', moduleUrl(), { user: users.superUser, body: { enabled: false, confirm } });
      assert.equal(res.status, 409, String(confirm));
      assert.equal(res.body.code, 'MODULE_CONFIRM_REQUIRED');
    }
    assert.equal(state.audit.length, 0);
  });

  it('confirm:true ile kapatma: 200, GET ile ayni govde, satir + module.disabled audit (ayni transaction)', async () => {
    const res = await call('PUT', moduleUrl(), { user: users.superUser, body: { enabled: false, confirm: true } });
    assert.equal(res.status, 200);
    assert.equal(res.body.site_code, SITE_1);
    const door = doorOf(res.body);
    assert.equal(door.enabled, false);
    assert.equal(door.updated_by, 'Süper Kullanıcı');
    assert.equal(door.updated_at, '2026-10-15T10:00:00.000Z');
    // PUT yaniti da Faz 1.1 alanlarini tasir: super kullanici icin can_toggle true
    assert.equal(door.can_toggle, true);
    assert.equal(door.request_status, null);

    const row = state.siteModules.get(`${SITE_1}:door_control`);
    assert.equal(row.enabled, false);
    assert.equal(row.updated_by, 1);

    assert.equal(state.audit.length, 1);
    assert.deepEqual(
      {
        action: state.audit[0].action,
        site_code: state.audit[0].site_code,
        target_type: state.audit[0].target_type,
        target_id: state.audit[0].target_id,
        details: state.audit[0].details,
        actor_user_code: state.audit[0].actor_user_code,
        actor_name: state.audit[0].actor_name,
        actor_role: state.audit[0].actor_role,
      },
      {
        action: 'module.disabled',
        site_code: SITE_1,
        target_type: 'module',
        target_id: 'door_control',
        details: { enabled: false },
        actor_user_code: 1,
        actor_name: 'Süper Kullanıcı',
        actor_role: 'super_user',
      },
    );

    // degisiklik ve kayit AYNI transaction icinde: upsert + audit BEGIN ile COMMIT arasinda
    const sqls = state.log.map((q) => q.sql.split(' ').slice(0, 3).join(' '));
    const begin = sqls.indexOf('BEGIN');
    const commit = sqls.indexOf('COMMIT');
    const upsert = sqls.indexOf('INSERT INTO site_modules');
    const audit = sqls.indexOf('INSERT INTO audit_log');
    assert.ok(begin >= 0 && begin < upsert && upsert < audit && audit < commit, JSON.stringify(sqls));
  });

  it('kapaliyken acmak: onay gerekmez, module.enabled audit yazilir', async () => {
    await call('PUT', moduleUrl(), { user: users.superUser, body: { enabled: false, confirm: true } });
    const res = await call('PUT', moduleUrl(), { user: users.superUser, body: { enabled: true } });
    assert.equal(res.status, 200);
    assert.equal(doorOf(res.body).enabled, true);
    assert.deepEqual(state.audit.map((a) => a.action), ['module.disabled', 'module.enabled']);
    assert.deepEqual(state.audit[1].details, { enabled: true });
  });

  it('degisiklik yoksa audit YAZILMAZ ve site_modules satiri olusmaz (zaten acik modulu acmak)', async () => {
    const res = await call('PUT', moduleUrl(), { user: users.superUser, body: { enabled: true } });
    assert.equal(res.status, 200);
    assert.equal(doorOf(res.body).enabled, true);
    assert.equal(state.audit.length, 0);
    assert.equal(state.siteModules.size, 0);
  });

  it('degisiklik yoksa audit YAZILMAZ (zaten kapali modulu tekrar kapatmak)', async () => {
    await call('PUT', moduleUrl(), { user: users.superUser, body: { enabled: false, confirm: true } });
    state.rotations.length = 0;
    const res = await call('PUT', moduleUrl(), { user: users.superUser, body: { enabled: false, confirm: true } });
    assert.equal(res.status, 200);
    assert.equal(state.audit.length, 1);
    assert.ok(state.log.some((q) => q.sql === 'COMMIT'));
    assert.equal(state.rotations.length, 0, 'degisiklik yoksa anahtar donmez');
  });

  it('super kullanici ayni uc ile calisir; audit actor_role super_user', async () => {
    const res = await call('PUT', moduleUrl(SITE_2), { user: users.superUser, body: { enabled: false, confirm: true } });
    assert.equal(res.status, 200);
    assert.equal(state.audit[0].actor_role, 'super_user');
    assert.equal(state.audit[0].site_code, SITE_2);
  });

  it('Faz 1.1: site yoneticisi (kendi sitesi, baska sitenin yoneticisi, SITE_OWNER) 403 MODULE_ADMIN_ONLY; hicbir sey yazilmaz', async () => {
    for (const user of [users.mgrA, users.mgrB, users.ownerC]) {
      const res = await call('PUT', moduleUrl(), { user, body: { enabled: false, confirm: true } });
      assert.equal(res.status, 403, user.full_name);
      assert.deepEqual(res.body, {
        error: 'Modülleri yalnızca sistem yöneticisi açıp kapatabilir. Modül talebi gönderebilirsiniz.',
        code: 'MODULE_ADMIN_ONLY',
      });
    }
    // acma da yasak; gecersiz govde de yetki hatasindan once dogrulanmaz
    assert.equal((await call('PUT', moduleUrl(), { user: users.mgrA, body: { enabled: true } })).body.code, 'MODULE_ADMIN_ONLY');
    assert.equal((await call('PUT', moduleUrl(), { user: users.mgrA, body: {} })).body.code, 'MODULE_ADMIN_ONLY');
    assert.equal((await call('PUT', moduleUrl(SITE_1, 'nope'), { user: users.mgrA, body: { enabled: true } })).body.code, 'MODULE_ADMIN_ONLY');
    assert.equal(state.siteModules.size, 0);
    assert.equal(state.audit.length, 0);
    assert.equal(state.log.some((q) => q.sql === 'BEGIN'), false, 'transaction bile acilmaz');
    assert.equal(state.rotations.length, 0);
  });

  it('sakin ve STAFF: mevcut requireSiteManager 403\'u (code YOK); hicbir sey yazilmaz', async () => {
    for (const user of [users.resident, users.staff]) {
      const res = await call('PUT', moduleUrl(), { user, body: { enabled: false, confirm: true } });
      assert.equal(res.status, 403);
      assert.equal('code' in res.body, false);
    }
    assert.equal(state.siteModules.size, 0);
    assert.equal(state.audit.length, 0);
  });

  it('olmayan site (super): 404 SITE_NOT_FOUND ve transaction geri alinir', async () => {
    const res = await call('PUT', moduleUrl(1999999999), { user: users.superUser, body: { enabled: false, confirm: true } });
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'SITE_NOT_FOUND');
    assert.ok(state.log.some((q) => q.sql === 'ROLLBACK'));
    assert.equal(state.audit.length, 0);
  });

  it('bilinmeyen modul 404 MODULE_NOT_FOUND', async () => {
    for (const code of ['nope', 'DOOR_CONTROL', '__proto__']) {
      const res = await call('PUT', moduleUrl(SITE_1, code), { user: users.superUser, body: { enabled: true } });
      assert.equal(res.status, 404, code);
      assert.equal(res.body.code, 'MODULE_NOT_FOUND');
    }
  });

  it('enabled boolean degilse 400 INVALID_BODY', async () => {
    for (const body of [{}, { enabled: 'true' }, { enabled: 1 }, { enabled: null }, { confirm: true }]) {
      const res = await call('PUT', moduleUrl(), { user: users.superUser, body });
      assert.equal(res.status, 400, JSON.stringify(body));
      assert.equal(res.body.code, 'INVALID_BODY');
    }
    const noBody = await fetch(`${baseUrl}${moduleUrl()}`, { method: 'PUT', headers: { 'x-test-user': encodeURIComponent(JSON.stringify(users.superUser)) } });
    assert.equal(noBody.status, 400);
  });

  it('core modul (people/announcements) 400 MODULE_NOT_TOGGLEABLE (acma ve kapatma)', async () => {
    for (const code of ['people', 'announcements']) {
      for (const enabled of [true, false]) {
        const res = await call('PUT', moduleUrl(SITE_1, code), { user: users.superUser, body: { enabled, confirm: true } });
        assert.equal(res.status, 400, `${code} ${enabled}`);
        assert.equal(res.body.code, 'MODULE_NOT_TOGGLEABLE');
      }
    }
  });

  it('yakinda modul ACILAMAZ 409 MODULE_COMING_SOON; kapatmak 200 (degisiklik yok, audit yok)', async () => {
    for (const code of ['metering', 'online_payment']) {
      const open = await call('PUT', moduleUrl(SITE_1, code), { user: users.superUser, body: { enabled: true } });
      assert.equal(open.status, 409, code);
      assert.equal(open.body.code, 'MODULE_COMING_SOON');
      const close = await call('PUT', moduleUrl(SITE_1, code), { user: users.superUser, body: { enabled: false } });
      assert.equal(close.status, 200, code);
      assert.equal(close.body.modules.find((m) => m.code === code).enabled, false);
    }
    assert.equal(state.audit.length, 0);
    assert.equal(state.siteModules.size, 0);
  });

  it('finance (Faz 4a): super acar (200, onay GEREKMEZ, audit module.enabled) ve kapatir (onay gerekmez, audit module.disabled); yerel kontrol anahtari dondurulmez', async () => {
    const open = await call('PUT', moduleUrl(SITE_1, 'finance'), { user: users.superUser, body: { enabled: true } });
    assert.equal(open.status, 200, JSON.stringify(open.body));
    const financeOpen = open.body.modules.find((m) => m.code === 'finance');
    assert.equal(financeOpen.enabled, true);
    assert.equal(financeOpen.toggleable, true);
    assert.equal(state.siteModules.get(`${SITE_1}:finance`).enabled, true);
    const close = await call('PUT', moduleUrl(SITE_1, 'finance'), { user: users.superUser, body: { enabled: false } });
    assert.equal(close.status, 200, JSON.stringify(close.body));
    assert.equal(close.body.modules.find((m) => m.code === 'finance').enabled, false);
    assert.deepEqual(
      state.audit.map((a) => [a.action, a.target_id]),
      [['module.enabled', 'finance'], ['module.disabled', 'finance']],
    );
    assert.equal(state.rotations.length, 0, 'yalniz door_control kapaninca anahtar doner');
  });

  it('finance: yonetici (super olmayan) modulu DOGRUDAN acamaz: 403', async () => {
    const res = await call('PUT', moduleUrl(SITE_1, 'finance'), { user: users.mgrA, body: { enabled: true } });
    assert.equal(res.status, 403);
    assert.equal(state.siteModules.has(`${SITE_1}:finance`), false);
  });

  it('denetim kaydi yazilamazsa ana islem BOZULMAZ (savepoint ile yutulur ve loglanir)', async () => {
    state.failAuditInsert = true;
    const res = await call('PUT', moduleUrl(), { user: users.superUser, body: { enabled: false, confirm: true } });
    assert.equal(res.status, 200);
    assert.equal(doorOf(res.body).enabled, false);
    assert.equal(state.audit.length, 0);
    assert.ok(state.log.some((q) => q.sql === 'ROLLBACK TO SAVEPOINT audit_insert'));
    assert.ok(state.log.some((q) => q.sql === 'COMMIT'));
    assert.ok(console.error.mock.calls.some((c) => String(c.arguments[0]).includes('[audit]')));
  });

  it('modul satiri yazilamazsa transaction geri alinir: audit yok, 500 + errorId, ic ayrinti sizmaz', async () => {
    state.failModuleUpsert = true;
    const res = await call('PUT', moduleUrl(), { user: users.superUser, body: { enabled: false, confirm: true } });
    assert.equal(res.status, 500);
    assert.equal(typeof res.body.errorId, 'string');
    assert.equal(JSON.stringify(res.body).includes('SECRET_DB_DETAIL'), false);
    assert.ok(state.log.some((q) => q.sql === 'ROLLBACK'));
    assert.equal(state.log.some((q) => q.sql === 'COMMIT'), false);
    assert.equal(state.siteModules.size, 0);
    assert.equal(state.audit.length, 0);
  });

  it('istemci (client) her durumda serbest birakilir', async () => {
    const released = [];
    const original = pool.connect;
    pool.connect = async () => {
      const client = await original();
      const release = client.release.bind(client);
      client.release = () => {
        released.push(true);
        release();
      };
      return client;
    };
    await call('PUT', moduleUrl(), { user: users.superUser, body: { enabled: false, confirm: true } });
    await call('PUT', moduleUrl(1999999999), { user: users.superUser, body: { enabled: false, confirm: true } });
    state.failModuleUpsert = true;
    await call('PUT', moduleUrl(), { user: users.superUser, body: { enabled: true } }); // zaten acik: degisiklik yok
    await call('PUT', moduleUrl(SITE_1), { user: users.superUser, body: { enabled: true } }); // kapali -> acik (upsert patlar)
    assert.equal(released.length, 4);
  });
});

describe('PUT modul: super kullanici modulu DOGRUDAN acarsa bekleyen talep onaylanir', () => {
  const open = (body = { enabled: true }, site = SITE_1, code = 'door_control') =>
    call('PUT', moduleUrl(site, code), { user: users.superUser, body });

  beforeEach(() => {
    state.siteModules.set(`${SITE_1}:door_control`, { site_code: SITE_1, module_code: 'door_control', enabled: false });
  });

  it('bekleyen talep ayni transaction\'da approved olur; karar veren super, gerekce "Modül doğrudan açıldı."; GET gorunumu temiz', async () => {
    state.moduleRequests = [{ id: 7, site_code: SITE_1, module_code: 'door_control', status: 'pending' }];
    const res = await open();
    assert.equal(res.status, 200);
    const door = doorOf(res.body);
    assert.equal(door.enabled, true);
    assert.equal(door.request_status, null, 'enabled:true + request_status:pending (sahipsiz rozet) OLMAZ');
    assert.deepEqual(
      { status: state.moduleRequests[0].status, by: state.moduleRequests[0].decided_by, name: state.moduleRequests[0].decided_by_name, note: state.moduleRequests[0].decision_note },
      { status: 'approved', by: 1, name: 'Süper Kullanıcı', note: 'Modül doğrudan açıldı.' },
    );
    assert.deepEqual(
      state.audit.map((a) => [a.action, a.target_type, a.target_id, a.details, a.site_code]),
      [
        ['module.enabled', 'module', 'door_control', { enabled: true }, SITE_1],
        ['module_request.approved', 'module_request', '7', { module_code: 'door_control', via: 'toggle' }, SITE_1],
      ],
    );
    // hepsi BEGIN..COMMIT arasinda
    const sqls = state.log.map((q) => q.sql);
    const begin = sqls.indexOf('BEGIN');
    const commit = sqls.indexOf('COMMIT');
    const update = sqls.findIndex((s) => s.startsWith('UPDATE module_requests'));
    assert.ok(begin >= 0 && begin < update && update < commit);
  });

  it('talep yoksa hicbir sey olmaz (module_requests UPDATE sonucu bos, ek audit yok)', async () => {
    const res = await open();
    assert.equal(res.status, 200);
    assert.deepEqual(state.audit.map((a) => a.action), ['module.enabled']);
  });

  it('baska modul / baska site / sonuclanmis talepler dokunulmaz', async () => {
    state.moduleRequests = [
      { id: 1, site_code: SITE_1, module_code: 'finance', status: 'pending' },
      { id: 2, site_code: SITE_2, module_code: 'door_control', status: 'pending' },
      { id: 3, site_code: SITE_1, module_code: 'door_control', status: 'rejected' },
    ];
    await open();
    assert.deepEqual(state.moduleRequests.map((r) => r.status), ['pending', 'pending', 'rejected']);
    assert.deepEqual(state.audit.map((a) => a.action), ['module.enabled']);
  });

  it('KAPATMA talepleri etkilemez; degisiklik olmayan acma da etkilemez', async () => {
    state.moduleRequests = [{ id: 5, site_code: SITE_1, module_code: 'door_control', status: 'pending' }];
    state.siteModules.set(`${SITE_1}:door_control`, { site_code: SITE_1, module_code: 'door_control', enabled: true });
    await open({ enabled: true }); // zaten acik: degisiklik yok
    assert.equal(state.moduleRequests[0].status, 'pending');
    assert.equal(state.audit.length, 0);
    await open({ enabled: false, confirm: true }); // kapatma
    assert.equal(state.moduleRequests[0].status, 'pending');
    assert.deepEqual(state.audit.map((a) => a.action), ['module.disabled']);
  });

  it('aç/kapa AYNI advisory anahtarini kullanir ve sites FOR SHARE ondan ONCE alinir', async () => {
    await open();
    assert.deepEqual(state.locks, [`site_module:${SITE_1}:door_control`]);
    const sqls = state.log.map((q) => q.sql);
    const siteLock = sqls.findIndex((s) => /^SELECT site_code FROM sites WHERE site_code = \$1 FOR SHARE$/.test(s));
    const advisory = sqls.findIndex((s) => s.startsWith('SELECT pg_advisory_xact_lock'));
    assert.ok(siteLock >= 0 && advisory > siteLock);
  });
});

describe('PUT modul: door_control kapaninca yerel kontrol anahtarlari dondurulur', () => {
  const close = (site = SITE_1, user = users.superUser) =>
    call('PUT', moduleUrl(site), { user, body: { enabled: false, confirm: true } });

  it('kapatinca sitedeki TUM cihazlarin anahtari yeni rastgele degerle degisir (COMMIT\'ten SONRA)', async () => {
    const res = await close();
    assert.equal(res.status, 200);
    assert.deepEqual(state.rotations.map((r) => r.deviceId), [501, 502]);
    for (const rotation of state.rotations) {
      assert.match(rotation.token, /^[A-Za-z0-9_-]{16,}$/);
    }
    assert.notEqual(state.rotations[0].token, state.rotations[1].token);
    const sqls = state.log.map((q) => q.sql);
    const commit = sqls.indexOf('COMMIT');
    const deviceQuery = sqls.findIndex((s) => s.startsWith('SELECT DISTINCT devices.id'));
    assert.ok(commit >= 0 && deviceQuery > commit, 'donme transaction tamamlandiktan sonra');
    // yalniz bu sitenin cihazlari sorgulanir
    assert.deepEqual(state.log.find((q) => q.sql.startsWith('SELECT DISTINCT devices.id')).params, [SITE_1]);
  });

  it('super kullanici kapatsa da donulur; baska sitenin cihazlarina dokunulmaz', async () => {
    state.siteDeviceIds.set(SITE_2, [601]);
    const res = await close(SITE_2, users.superUser);
    assert.equal(res.status, 200);
    assert.deepEqual(state.rotations.map((r) => r.deviceId), [601]);
  });

  it('YENIDEN ACMA anahtar dondurmez (/status yeni anahtari zaten dagitir)', async () => {
    await close();
    state.rotations.length = 0;
    const res = await call('PUT', moduleUrl(), { user: users.superUser, body: { enabled: true } });
    assert.equal(res.status, 200);
    assert.equal(state.rotations.length, 0);
  });

  it('degisiklik olmayan / reddedilen / diger modul istekleri anahtar dondurmez', async () => {
    // onaysiz kapatma (409), zaten acik modulu acma, yakinda modulu kapatma, yetkisiz, olmayan site
    await call('PUT', moduleUrl(), { user: users.superUser, body: { enabled: false } });
    await call('PUT', moduleUrl(), { user: users.superUser, body: { enabled: true } });
    await call('PUT', moduleUrl(SITE_1, 'metering'), { user: users.superUser, body: { enabled: false } });
    await call('PUT', moduleUrl(SITE_1, 'finance'), { user: users.superUser, body: { enabled: true } });
    await call('PUT', moduleUrl(SITE_1, 'finance'), { user: users.superUser, body: { enabled: false } });
    await call('PUT', moduleUrl(SITE_1), { user: users.mgrB, body: { enabled: false, confirm: true } });
    await call('PUT', moduleUrl(1999999999), { user: users.superUser, body: { enabled: false, confirm: true } });
    assert.equal(state.rotations.length, 0);
    assert.equal(state.log.some((q) => q.sql.startsWith('SELECT DISTINCT devices.id')), false);
  });

  it('cihazi olmayan sitede sorgu yapilir ama UPDATE yoktur', async () => {
    state.siteDeviceIds.set(SITE_1, []);
    const res = await close();
    assert.equal(res.status, 200);
    assert.equal(state.rotations.length, 0);
  });

  it('donme hatasi yaniti ve denetim kaydini BOZMAZ (200, modul kapali, audit yazili, hata loglanir)', async () => {
    state.failDeviceQuery = true;
    const res = await close();
    assert.equal(res.status, 200);
    assert.equal(doorOf(res.body).enabled, false);
    assert.equal(state.audit.length, 1);
    assert.equal(state.audit[0].action, 'module.disabled');
    assert.equal(JSON.stringify(res.body).includes('SECRET_DB_DETAIL'), false);
    assert.ok(console.error.mock.calls.some((c) => String(c.arguments[0]).includes('[LocalToken]')));
  });

  it('anahtar guncelleme sorgusu patlasa da yanit 200 kalir (hata yutulur)', async () => {
    // local_token_service zaten yutar; moduldeki ikinci savunma hatti: UPDATE patlarsa
    const original = pool.query;
    pool.query = async (text, params) => {
      if (/^UPDATE devices SET local_control_token/.test(norm(text))) {
        throw Object.assign(new Error('SECRET_DB_DETAIL update'), { code: 'XX000' });
      }
      return original(text, params);
    };
    const res = await close();
    assert.equal(res.status, 200);
    assert.equal(doorOf(res.body).enabled, false);
    assert.equal(state.audit.length, 1);
  });
});

// ---------------------------------------------------------------------------
// GET /admin/audit-log
// ---------------------------------------------------------------------------

function seedAudit(count, { siteCode = SITE_1 } = {}) {
  for (let i = 1; i <= count; i += 1) {
    state.auditSeq += 1;
    state.audit.push({
      id: state.auditSeq,
      created_at: new Date(T0.getTime() + state.auditSeq * 1000),
      actor_user_code: 20001,
      actor_name: 'Ayşe Yönetici',
      actor_role: 'site_manager',
      action: i % 2 ? 'module.disabled' : 'module.enabled',
      site_code: siteCode,
      target_type: 'module',
      target_id: 'door_control',
      details: { enabled: i % 2 === 0 },
    });
  }
}

describe('GET /admin/audit-log', () => {
  it('yalnizca super kullanici: yonetici, sakin ve STAFF 403', async () => {
    seedAudit(2);
    for (const user of [users.mgrA, users.ownerC, users.resident, users.staff]) {
      const res = await call('GET', '/admin/audit-log', { user });
      assert.equal(res.status, 403, user.full_name);
    }
    assert.equal((await call('GET', '/admin/audit-log', { user: users.superUser })).status, 200);
  });

  it('satir bicimi sozlesmeye uygun (id sayi, ISO tarih, site_name, details nesne)', async () => {
    seedAudit(1);
    const res = await call('GET', '/admin/audit-log', { user: users.superUser });
    assert.equal(res.status, 200);
    assert.equal(res.body.items.length, 1);
    const item = res.body.items[0];
    assert.deepEqual(Object.keys(item), [
      'id',
      'created_at',
      'actor_user_code',
      'actor_name',
      'actor_role',
      'action',
      'site_code',
      'site_name',
      'target_type',
      'target_id',
      'details',
    ]);
    assert.equal(item.id, 1);
    assert.equal(typeof item.id, 'number');
    assert.equal(item.created_at, '2026-10-14T08:00:01.000Z');
    assert.equal(item.site_code, SITE_1);
    assert.equal(item.site_name, 'Gül Sitesi');
    assert.deepEqual(item.details, { enabled: false });
    assert.equal(res.body.next_before_id, null);
  });

  it('silinmis site kaydi: site_name null, kayit yine listelenir', async () => {
    seedAudit(1, { siteCode: 1555555555 });
    const res = await call('GET', '/admin/audit-log', { user: users.superUser });
    assert.equal(res.body.items[0].site_name, null);
    assert.equal(res.body.items[0].site_code, 1555555555);
  });

  it('sayfalama: id DESC, next_before_id ile sonraki sayfa, son sayfada null', async () => {
    seedAudit(7);
    const get = (query) => call('GET', `/admin/audit-log${query}`, { user: users.superUser });

    const p1 = await get('?limit=3');
    assert.deepEqual(p1.body.items.map((i) => i.id), [7, 6, 5]);
    assert.equal(p1.body.next_before_id, 5);

    const p2 = await get(`?limit=3&before_id=${p1.body.next_before_id}`);
    assert.deepEqual(p2.body.items.map((i) => i.id), [4, 3, 2]);
    assert.equal(p2.body.next_before_id, 2);

    const p3 = await get(`?limit=3&before_id=${p2.body.next_before_id}`);
    assert.deepEqual(p3.body.items.map((i) => i.id), [1]);
    assert.equal(p3.body.next_before_id, null);
  });

  it('tam sinirda (kayit sayisi = limit) sonraki sayfa yoktur: next_before_id null', async () => {
    seedAudit(3);
    const res = await call('GET', '/admin/audit-log?limit=3', { user: users.superUser });
    assert.equal(res.body.items.length, 3);
    assert.equal(res.body.next_before_id, null);
  });

  it('limit 1-200 araliginda sinirlanir; bos/sayi olmayan deger varsayilan 50', async () => {
    seedAudit(60);
    const limitOf = async (query) => {
      state.log.length = 0;
      await call('GET', `/admin/audit-log${query}`, { user: users.superUser });
      const q = state.log.find((e) => /FROM audit_log a/.test(e.sql));
      return q.params[2] - 1; // sorgu limit + 1 ister
    };
    assert.equal(await limitOf(''), 50);
    assert.equal(await limitOf('?limit='), 50);
    assert.equal(await limitOf('?limit=abc'), 50);
    assert.equal(await limitOf('?limit=0'), 1);
    assert.equal(await limitOf('?limit=-4'), 1);
    assert.equal(await limitOf('?limit=999'), 200);
    assert.equal(await limitOf('?limit=200'), 200);
    assert.equal(await limitOf('?limit=7.9'), 7);
    const res = await call('GET', '/admin/audit-log', { user: users.superUser });
    assert.equal(res.body.items.length, 50);
    assert.equal(res.body.next_before_id, 11);
  });

  it('site_code suzgeci yalnizca o sitenin kayitlarini dondurur', async () => {
    seedAudit(2, { siteCode: SITE_1 });
    seedAudit(3, { siteCode: SITE_2 });
    const res = await call('GET', `/admin/audit-log?site_code=${SITE_2}`, { user: users.superUser });
    assert.equal(res.body.items.length, 3);
    assert.ok(res.body.items.every((i) => i.site_code === SITE_2));
  });

  it('action suzgeci (istege bagli, tam eslesme) yalnizca o eylemin kayitlarini dondurur', async () => {
    seedAudit(5); // tek sayili sira module.disabled, cift sayili module.enabled
    const disabled = await call('GET', '/admin/audit-log?action=module.disabled', { user: users.superUser });
    assert.equal(disabled.status, 200);
    assert.deepEqual(disabled.body.items.map((i) => i.id), [5, 3, 1]);
    assert.ok(disabled.body.items.every((i) => i.action === 'module.disabled'));
    const none = await call('GET', '/admin/audit-log?action=staff_role.removed', { user: users.superUser });
    assert.deepEqual(none.body, { items: [], next_before_id: null });
    const combined = await call('GET', `/admin/audit-log?action=module.enabled&site_code=${SITE_1}&limit=1`, { user: users.superUser });
    assert.deepEqual(combined.body.items.map((i) => i.id), [4]);
    assert.equal(combined.body.next_before_id, 4);
    const empty = await call('GET', '/admin/audit-log?action=', { user: users.superUser });
    assert.equal(empty.body.items.length, 5, 'bos action suzgec sayilmaz');
  });

  it('Faz 1.1: action suzgeci module_request.created/approved/rejected/cancelled eylemlerini de suzer', async () => {
    const actions = ['module_request.created', 'module_request.approved', 'module_request.rejected', 'module_request.cancelled', 'module.enabled'];
    for (const action of actions) {
      state.auditSeq += 1;
      state.audit.push({
        id: state.auditSeq,
        created_at: new Date(T0.getTime() + state.auditSeq * 1000),
        actor_user_code: 1,
        actor_name: 'Süper Kullanıcı',
        actor_role: 'super_user',
        action,
        site_code: SITE_1,
        target_type: action.startsWith('module_request') ? 'module_request' : 'module',
        target_id: String(state.auditSeq),
        details: { module_code: 'door_control' },
      });
    }
    for (const action of actions) {
      const res = await call('GET', `/admin/audit-log?action=${action}`, { user: users.superUser });
      assert.equal(res.status, 200, action);
      assert.equal(res.body.items.length, 1, action);
      assert.equal(res.body.items[0].action, action);
    }
    const all = await call('GET', '/admin/audit-log', { user: users.superUser });
    assert.equal(all.body.items.length, actions.length);
  });

  it('gecersiz site_code / before_id / action 400 INVALID_QUERY', async () => {
    for (const query of [
      '?site_code=abc',
      '?before_id=abc',
      '?before_id=0',
      '?site_code=-1',
      '?before_id=1.5',
      '?action=Module.Disabled',
      '?action=module%20disabled',
      '?action=%27%3B--',
      `?action=${'a'.repeat(101)}`,
      '?action=a&action=b',
    ]) {
      const res = await call('GET', `/admin/audit-log${query}`, { user: users.superUser });
      assert.equal(res.status, 400, query);
      assert.equal(res.body.code, 'INVALID_QUERY');
    }
  });

  it('API\'de denetim kaydini degistiren/silen uc yoktur', () => {
    const mutating = ORIGINAL_FIRST_HANDLERS.filter((r) => r.path.includes('audit'));
    assert.deepEqual(mutating.map((r) => r.methods), [['get']]);
  });
});

// ---------------------------------------------------------------------------
// Ek roller
// ---------------------------------------------------------------------------

const staffUrl = (site = SITE_1) => `/manager/sites/${site}/staff-roles`;
const assign = (body, user = users.mgrA, site = SITE_1) => call('PUT', staffUrl(site), { user, body });

describe('ek roller: GET', () => {
  it('yalnizca aktif kurul/gorevli uyeleri listeler (yonetici, sakin ve pasif satirlar hariç)', async () => {
    state.memberships.push({ site_code: SITE_1, user_code: 30001, role: 'BOARD_MEMBER', is_active: false, created_at: T0 });
    const res = await call('GET', staffUrl(), { user: users.mgrA });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, {
      items: [
        {
          user_code: 20005,
          full_name: 'Ece Görevli',
          email: 'e@example.com',
          role: 'STAFF',
          created_at: '2026-10-14T08:00:01.000Z',
        },
      ],
    });
  });

  it('yetki: baska sitenin yoneticisi 403 FORBIDDEN_SITE, sakin/STAFF 403, super ve SITE_OWNER 200', async () => {
    assert.equal((await call('GET', staffUrl(), { user: users.mgrB })).body.code, 'FORBIDDEN_SITE');
    assert.equal((await call('GET', staffUrl(), { user: users.resident })).status, 403);
    assert.equal((await call('GET', staffUrl(), { user: users.staff })).status, 403);
    assert.equal((await call('GET', staffUrl(), { user: users.superUser })).status, 200);
    assert.equal((await call('GET', staffUrl(), { user: users.ownerC })).status, 200);
  });

  it('super + olmayan site: 404 SITE_NOT_FOUND', async () => {
    const res = await call('GET', staffUrl(1999999999), { user: users.superUser });
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'SITE_NOT_FOUND');
  });
});

describe('ek roller: PUT (rol ata)', () => {
  it('yeni kisiye BOARD_MEMBER: 200 { item }, uyelik eklenir, staff_role.assigned audit', async () => {
    const res = await assign({ email: 'fatma@example.com', role: 'BOARD_MEMBER' });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.item, {
      user_code: 30001,
      full_name: 'Fatma Kurul',
      email: 'fatma@example.com',
      role: 'BOARD_MEMBER',
      created_at: '2026-10-15T09:00:00.000Z',
    });
    assert.ok(state.memberships.some((m) => m.user_code === 30001 && m.role === 'BOARD_MEMBER' && m.is_active));
    assert.equal(state.audit.length, 1);
    assert.deepEqual(
      [state.audit[0].action, state.audit[0].target_type, state.audit[0].target_id, state.audit[0].details, state.audit[0].site_code],
      ['staff_role.assigned', 'user', '30001', { role: 'BOARD_MEMBER' }, SITE_1],
    );
  });

  it('e-posta buyuk/kucuk harf ve bosluk duyarsiz', async () => {
    const res = await assign({ email: '  FATMA@Example.COM ', role: 'STAFF' });
    assert.equal(res.status, 200);
    assert.equal(res.body.item.user_code, 30001);
  });

  it('rol gecersizse 400 ROLE_INVALID (RESIDENT/SITE_ADMIN/kucuk harf/eksik dahil)', async () => {
    for (const role of ['RESIDENT', 'SITE_ADMIN', 'SITE_OWNER', 'staff', 'x', '', null, undefined, 5]) {
      const res = await assign({ email: 'fatma@example.com', role });
      assert.equal(res.status, 400, String(role));
      assert.equal(res.body.code, 'ROLE_INVALID');
    }
    assert.equal(state.audit.length, 0);
  });

  it('e-posta eksik/gecersizse 400 INVALID_BODY', async () => {
    for (const email of [undefined, null, '', 'bozuk', 'a@b', 42]) {
      const res = await assign({ email, role: 'STAFF' });
      assert.equal(res.status, 400, String(email));
      assert.equal(res.body.code, 'INVALID_BODY');
    }
  });

  it('kayitli hesap yoksa 404 USER_NOT_FOUND ve sozlesme metni', async () => {
    const res = await assign({ email: 'yok@example.com', role: 'STAFF' });
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'USER_NOT_FOUND');
    assert.equal(res.body.error, 'Bu e-posta ile kayıtlı hesap yok. Kişi kayıtları sonraki aşamada gelecek.');
  });

  it('hesap pasif / e-postasi dogrulanmamis / onay bekliyorsa 409 USER_NOT_ACTIVE', async () => {
    for (const email of ['pasif@example.com', 'dogrulanmamis@example.com', 'bekleyen@example.com']) {
      const res = await assign({ email, role: 'STAFF' });
      assert.equal(res.status, 409, email);
      assert.equal(res.body.code, 'USER_NOT_ACTIVE');
    }
    assert.equal(state.audit.length, 0);
  });

  it('kisi zaten site yoneticisi/sahibiyse 409 ALREADY_SITE_MANAGER (site_manager_sites, SITE_OWNER, SITE_ADMIN, super)', async () => {
    for (const email of ['leman@example.com', 'c@example.com', 'hasan@example.com', 'root@example.com']) {
      const res = await assign({ email, role: 'BOARD_MEMBER' });
      assert.equal(res.status, 409, email);
      assert.equal(res.body.code, 'ALREADY_SITE_MANAGER');
    }
    assert.equal(state.audit.length, 0);
  });

  it('baska sitenin yoneticisi olmak ALREADY_SITE_MANAGER degildir (yonetici bu sitede degil)', async () => {
    const res = await assign({ email: 'b@example.com', role: 'STAFF' }, users.mgrA);
    assert.equal(res.status, 200);
    assert.equal(res.body.item.user_code, 20002);
  });

  it('RESIDENT yukseltilir: tek satir kalir, rol guncellenir', async () => {
    const res = await assign({ email: 'ipek@example.com', role: 'STAFF' });
    assert.equal(res.status, 200);
    assert.equal(res.body.item.role, 'STAFF');
    const rows = state.memberships.filter((m) => m.user_code === 30004);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].role, 'STAFF');
  });

  it('mevcut kurul/gorevli rolu GUNCELLENIR (tek satir); ayni rolu tekrar vermek audit yazmaz', async () => {
    const first = await assign({ email: 'e@example.com', role: 'BOARD_MEMBER' });
    assert.equal(first.status, 200);
    assert.equal(first.body.item.role, 'BOARD_MEMBER');
    assert.equal(state.memberships.filter((m) => m.user_code === 20005).length, 1);
    assert.equal(state.audit.length, 1);

    const again = await assign({ email: 'e@example.com', role: 'BOARD_MEMBER' });
    assert.equal(again.status, 200);
    assert.equal(state.audit.length, 1, 'degisiklik yok: ikinci audit yok');
  });

  it('YARIS: kontrol ile yazma arasinda kisi yonetici yapilirsa satir dusurulmez, 409 ALREADY_SITE_MANAGER, audit yok', async () => {
    // 30004 (RESIDENT) kontrol sirasinda yonetici degil; upsert aninda baska bir istek onu SITE_ADMIN yapmis
    state.beforeUpsert = () => {
      const row = state.memberships.find((m) => m.user_code === 30004);
      row.role = 'SITE_ADMIN';
      row.is_active = true;
    };
    const res = await assign({ email: 'ipek@example.com', role: 'STAFF' });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'ALREADY_SITE_MANAGER');
    assert.equal(res.body.error, 'Bu kişi zaten site yöneticisi.');
    const row = state.memberships.find((m) => m.user_code === 30004);
    assert.equal(row.role, 'SITE_ADMIN', 'yonetici satiri STAFF/BOARD_MEMBER\'a dusurulmedi');
    assert.equal(state.audit.length, 0);
    assert.ok(state.log.some((q) => q.sql === 'ROLLBACK'));
    assert.equal(state.log.some((q) => q.sql === 'COMMIT'), false);
  });

  it('upsert SQL\'i yonetici satirini koruyan WHERE kosulunu icerir (yalniz aktif SITE_OWNER/SITE_ADMIN korunur)', async () => {
    await assign({ email: 'fatma@example.com', role: 'STAFF' });
    const upsert = state.log.find((q) => q.sql.startsWith('INSERT INTO site_memberships'));
    assert.match(
      upsert.sql,
      /DO UPDATE SET role = EXCLUDED\.role, is_active = TRUE, updated_at = NOW\(\) WHERE site_memberships\.role NOT IN \('SITE_OWNER', 'SITE_ADMIN'\) OR site_memberships\.is_active = FALSE RETURNING created_at/,
    );
  });

  it('yetki: baska yonetici 403, sakin/STAFF 403; hicbir sey yazilmaz', async () => {
    const body = { email: 'fatma@example.com', role: 'STAFF' };
    assert.equal((await assign(body, users.mgrB)).body.code, 'FORBIDDEN_SITE');
    assert.equal((await assign(body, users.resident)).status, 403);
    assert.equal((await assign(body, users.staff)).status, 403);
    assert.equal(state.audit.length, 0);
    assert.equal(state.memberships.some((m) => m.user_code === 30001), false);
  });

  it('super kullanici da atayabilir; olmayan sitede 404 SITE_NOT_FOUND', async () => {
    assert.equal((await assign({ email: 'fatma@example.com', role: 'STAFF' }, users.superUser)).status, 200);
    const missing = await assign({ email: 'fatma@example.com', role: 'STAFF' }, users.superUser, 1999999999);
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'SITE_NOT_FOUND');
  });
});

// Hiz sinirlayicilari dogrudan sinar (rota testlerinde atlanir).
function runLimiter(limiter, userCode, ip = '1.2.3.4') {
  const res = {
    statusCode: 200,
    headers: {},
    setHeader(name, value) {
      this.headers[name] = value;
    },
    status(code2) {
      this.statusCode = code2;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
  let passed = false;
  limiter({ authUser: { id: userCode }, ip, path: '/x' }, res, () => {
    passed = true;
  });
  return { res, passed };
}

describe('hiz sinirlari: PUT staff-roles (hesap taramasina karsi) ve PUT modules (audit buyumesine karsi)', () => {
  afterEach(() => {
    staffRoleLimiter.reset();
    moduleToggleLimiter.reset();
  });

  it('staff-roles: kullanici basina 20/saat (davet limitleyicisi duzeyi); 21. istek 429 + Retry-After + retry_after_seconds', () => {
    for (let i = 0; i < 20; i += 1) {
      assert.equal(runLimiter(staffRoleLimiter, 111).passed, true, String(i));
    }
    const blocked = runLimiter(staffRoleLimiter, 111);
    assert.equal(blocked.passed, false);
    assert.equal(blocked.res.statusCode, 429);
    assert.ok(Number(blocked.res.headers['Retry-After']) > 0);
    assert.ok(Number(blocked.res.headers['Retry-After']) <= 3600);
    assert.ok(blocked.res.body.retry_after_seconds > 0);
    assert.equal(blocked.res.body.error, 'Çok fazla rol atama denemesi. Biraz sonra tekrar deneyin.');
    assert.equal(runLimiter(staffRoleLimiter, 222).passed, true, 'baska kullanici etkilenmez');
  });

  it('staff-roles: IP basina 60/saat (farkli kullanicilar toplami); 61. istek 429', () => {
    for (let i = 0; i < 60; i += 1) {
      assert.equal(runLimiter(staffRoleLimiter, 1000 + i, '9.9.9.9').passed, true, String(i));
    }
    assert.equal(runLimiter(staffRoleLimiter, 5000, '9.9.9.9').res.statusCode, 429);
    assert.equal(runLimiter(staffRoleLimiter, 5001, '8.8.8.8').passed, true, 'baska IP etkilenmez');
  });

  it('modules PUT: kullanici basina 60/saat; 61. istek 429; sayaclar staff-roles ile paylasilmaz', () => {
    for (let i = 0; i < 60; i += 1) {
      assert.equal(runLimiter(moduleToggleLimiter, 111).passed, true, String(i));
    }
    const blocked = runLimiter(moduleToggleLimiter, 111);
    assert.equal(blocked.passed, false);
    assert.equal(blocked.res.statusCode, 429);
    assert.equal(blocked.res.body.error, 'Çok fazla modül değişikliği. Biraz sonra tekrar deneyin.');
    assert.ok(blocked.res.body.retry_after_seconds > 0);
    assert.equal(runLimiter(moduleToggleLimiter, 222).passed, true);
    assert.equal(runLimiter(staffRoleLimiter, 111).passed, true, 'staff-roles sayaci ayri');
  });

  it('modules PUT: IP basina 300/saat (NAT arkasi toplu kilitlenmesin)', () => {
    for (let i = 0; i < 300; i += 1) {
      assert.equal(runLimiter(moduleToggleLimiter, 10000 + i, '7.7.7.7').passed, true, String(i));
    }
    assert.equal(runLimiter(moduleToggleLimiter, 99999, '7.7.7.7').res.statusCode, 429);
  });

  it('limitler kaynak kodda belgelenmis degerlerdedir (20/60 saat, 60/300 saat)', () => {
    const source = readFileSync(new URL('../src/modules/module_routes.js', import.meta.url), 'utf8');
    assert.match(source, /export const staffRoleLimiter = createRuleLimiter\(\{\s*rules: \[\s*\{ windowMs: HOUR_MS, max: 20, key: userKey \},\s*\{ windowMs: HOUR_MS, max: 60, key: ipKey \},/);
    assert.match(source, /export const moduleToggleLimiter = createRuleLimiter\(\{\s*rules: \[\s*\{ windowMs: HOUR_MS, max: 60, key: userKey \},\s*\{ windowMs: HOUR_MS, max: 300, key: ipKey \},/);
  });
});

describe('ek roller: DELETE', () => {
  const remove = (userCode, user = users.mgrA, site = SITE_1) =>
    call('DELETE', `${staffUrl(site)}/${userCode}`, { user });

  it('kurul/gorevli satiri silinir, { ok: true } ve staff_role.removed audit', async () => {
    const res = await remove(20005);
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { ok: true });
    assert.equal(state.memberships.some((m) => m.user_code === 20005), false);
    assert.equal(state.audit.length, 1);
    assert.deepEqual(
      [state.audit[0].action, state.audit[0].target_type, state.audit[0].target_id, state.audit[0].details],
      ['staff_role.removed', 'user', '20005', { role: 'STAFF' }],
    );
  });

  it('RESIDENT satiri silinmez (rol yok sayilir): 404 ROLE_NOT_FOUND ve uyelik yerinde kalir', async () => {
    const res = await remove(30004);
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'ROLE_NOT_FOUND');
    assert.equal(res.body.error, 'Bu kişide kurul veya görevli rolü yok.');
    assert.ok(state.memberships.some((m) => m.user_code === 30004 && m.role === 'RESIDENT'));
  });

  it('yonetici satiri silinemez (SITE_ADMIN/SITE_OWNER): 404 ROLE_NOT_FOUND', async () => {
    for (const code of [30003, 20003]) {
      const res = await remove(code);
      assert.equal(res.status, 404, String(code));
      assert.equal(res.body.code, 'ROLE_NOT_FOUND');
    }
    assert.ok(state.memberships.some((m) => m.user_code === 30003));
    assert.ok(state.memberships.some((m) => m.user_code === 20003));
  });

  it('olmayan kisi / gecersiz kod: 404 ROLE_NOT_FOUND; ikinci silme de 404', async () => {
    assert.equal((await remove(99999)).body.code, 'ROLE_NOT_FOUND');
    assert.equal((await remove('abc')).body.code, 'ROLE_NOT_FOUND');
    // users.user_code INTEGER: int4 disi deger veritabanina HIC gitmez (tasma hatasi/500 olmaz)
    state.log.length = 0;
    const huge = await remove('99999999999');
    assert.equal(huge.status, 404);
    assert.equal(huge.body.code, 'ROLE_NOT_FOUND');
    assert.equal(state.log.some((q) => q.sql.startsWith('DELETE FROM')), false);
    assert.equal((await remove(20005)).status, 200);
    assert.equal((await remove(20005)).status, 404);
    assert.equal(state.audit.length, 1);
  });

  it('yetki: baska yonetici 403 FORBIDDEN_SITE, sakin/STAFF 403 (kendi rolunu bile silemez)', async () => {
    assert.equal((await remove(20005, users.mgrB)).body.code, 'FORBIDDEN_SITE');
    assert.equal((await remove(20005, users.resident)).status, 403);
    assert.equal((await remove(20005, users.staff)).status, 403);
    assert.ok(state.memberships.some((m) => m.user_code === 20005));
  });
});

// ---------------------------------------------------------------------------
// GET /app/my-modules
// ---------------------------------------------------------------------------

describe('GET /app/my-modules', () => {
  it('super kullanici: { scope: "all", sites: [] } ve veritabani sorgulanmaz', async () => {
    const res = await call('GET', '/app/my-modules', { user: users.superUser });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { scope: 'all', sites: [] });
    assert.equal(state.log.length, 0);
  });

  it('bagli site yoksa { scope: "sites", sites: [] }', async () => {
    const res = await call('GET', '/app/my-modules', { user: users.resident });
    assert.deepEqual(res.body, { scope: 'sites', sites: [] });
  });

  it('en yetkili rol adlari, katalogdaki TUM modul kodlari ve hesaplanmis enabled', async () => {
    state.myLinks = [
      { site_code: String(SITE_1), site_name: 'Gül Sitesi', management_type: 'apartment_site', rank: 4, door_access: true },
      { site_code: String(SITE_2), site_name: 'Lale Sitesi', management_type: 'apartment_site', rank: 1, door_access: true },
      { site_code: '1000000003', site_name: 'Papatya', management_type: 'apartment_site', rank: 3, door_access: false },
      { site_code: '1000000004', site_name: 'Zambak', management_type: 'apartment_site', rank: 2, door_access: false },
    ];
    state.siteModules.set(`${SITE_2}:door_control`, { site_code: SITE_2, module_code: 'door_control', enabled: false });
    // katalogda olmayan ve "yakinda" modul satirlari sonucu degistirmez; finance (Faz 4a, available) satiri enabled: true ise ACIK
    state.siteModules.set(`${SITE_1}:metering`, { site_code: SITE_1, module_code: 'metering', enabled: true });
    state.siteModules.set(`${SITE_1}:finance`, { site_code: SITE_1, module_code: 'finance', enabled: true });
    state.siteModules.set(`${SITE_1}:baska`, { site_code: SITE_1, module_code: 'baska', enabled: true });

    const res = await call('GET', '/app/my-modules', { user: users.resident });
    assert.equal(res.status, 200);
    assert.equal(res.body.scope, 'sites');
    assert.deepEqual(
      res.body.sites.map((s) => [s.site_code, s.site_name, s.role]),
      [
        [SITE_1, 'Gül Sitesi', 'manager'],
        [SITE_2, 'Lale Sitesi', 'resident'],
        [1000000003, 'Papatya', 'board_member'],
        [1000000004, 'Zambak', 'staff'],
      ],
    );
    for (const site of res.body.sites) {
      assert.equal(typeof site.site_code, 'number');
      assert.equal(site.management_type, 'apartment_site');
      assert.deepEqual(Object.keys(site.modules), [
        'door_control',
        'people',
        'announcements',
        'finance',
        'documents',
        'reservation',
        'work_tracking',
        'metering',
        'online_payment',
        'visitor_log',
      ]);
    }
    assert.equal(res.body.sites[0].modules.door_control, true);
    assert.equal(res.body.sites[0].modules.metering, false, 'yakinda modul satiri olsa bile false');
    assert.equal(res.body.sites[0].modules.reservation, false, 'rezervasyon satiri yoksa varsayilan KAPALI');
    assert.equal(res.body.sites[0].modules.finance, true, 'Faz 4a: finance satiri enabled ise acik');
    assert.equal(res.body.sites[1].modules.finance, false, 'satir yoksa varsayilan KAPALI');
    assert.equal(res.body.sites[1].modules.door_control, false);
  });

  it('baglanti sorgusu: yalniz onayli siteler; yonetici/sakin/kurul/gorevli baglari ve en yetkili rol (MAX rank)', async () => {
    await call('GET', '/app/my-modules', { user: users.resident });
    const query = state.log.find((e) => /^WITH links AS/.test(e.sql));
    assert.ok(query, 'baglanti sorgusu calismadi');
    const sql = query.sql;
    assert.match(sql, /WHERE s\.approval_status = 'approved'/);
    assert.match(sql, /FROM site_manager_sites sms WHERE sms\.manager_user_code = \$1/);
    assert.match(sql, /role IN \('SITE_OWNER', 'SITE_ADMIN'\)/);
    assert.match(sql, /sm\.role = 'BOARD_MEMBER'/);
    assert.match(sql, /sm\.role = 'STAFF'/);
    assert.match(sql, /FROM apartment_memberships am INNER JOIN apartments a ON a\.id = am\.apartment_id WHERE am\.user_code = \$1 AND am\.is_active = TRUE/);
    assert.match(sql, /FROM apartments a WHERE a\.resident_user_code = \$1/);
    assert.match(sql, /sm\.role = 'RESIDENT'/);
    assert.match(sql, /MAX\(l\.rank\) AS rank/);
    assert.deepEqual(query.params, [20004]);
  });

  it('door_access: gercek kapi erisim yolu olan sitelerde true; yalniz BOARD_MEMBER/STAFF (veya yalniz RESIDENT site uyeligi) bagi olanlarda false', async () => {
    state.myLinks = [
      { site_code: String(SITE_1), site_name: 'Yonetilen', management_type: 'apartment_site', rank: 4, door_access: true },
      { site_code: String(SITE_2), site_name: 'Yalniz Kurul', management_type: 'apartment_site', rank: 3, door_access: false },
      { site_code: '1000000003', site_name: 'Yalniz Gorevli', management_type: 'apartment_site', rank: 2, door_access: false },
      // gorevli ama ayni sitede kapi izni (override) de var: bag rolu staff, kapi erisimi VAR
      { site_code: '1000000004', site_name: 'Gorevli Ve Izinli', management_type: 'apartment_site', rank: 2, door_access: true },
      // eski/eksik satir (alan hic yok): guvenli taraf false
      { site_code: '1000000005', site_name: 'Alansiz', management_type: 'apartment_site', rank: 1 },
    ];
    const res = await call('GET', '/app/my-modules', { user: users.resident });
    assert.equal(res.status, 200);
    assert.deepEqual(
      res.body.sites.map((s) => [s.site_name, s.role, s.door_access]),
      [
        ['Yonetilen', 'manager', true],
        ['Yalniz Kurul', 'board_member', false],
        ['Yalniz Gorevli', 'staff', false],
        ['Gorevli Ve Izinli', 'staff', true],
        ['Alansiz', 'resident', false],
      ],
    );
    for (const site of res.body.sites) {
      assert.equal(typeof site.door_access, 'boolean');
      assert.deepEqual(Object.keys(site), ['site_code', 'site_name', 'management_type', 'role', 'door_access', 'modules']);
    }
  });

  it('door_access, modules.door_control degerinden BAGIMSIZDIR (kapali modul + kapi erisimi; acik modul + erisim yok)', async () => {
    state.myLinks = [
      { site_code: String(SITE_1), site_name: 'A', management_type: 'apartment_site', rank: 3, door_access: false },
      { site_code: String(SITE_2), site_name: 'B', management_type: 'apartment_site', rank: 1, door_access: true },
    ];
    state.siteModules.set(`${SITE_2}:door_control`, { site_code: SITE_2, module_code: 'door_control', enabled: false });
    const res = await call('GET', '/app/my-modules', { user: users.resident });
    assert.deepEqual(
      res.body.sites.map((s) => [s.site_name, s.door_access, s.modules.door_control]),
      [
        ['A', false, true],
        ['B', true, false],
      ],
    );
  });

  describe('baglanti sorgusu (MY_SITES_SQL) kapi erisim mantigi', () => {
    const normalize = (text) =>
      String(text)
        .replace(/--.*$/gm, ' ')
        .replace(/\s+/g, ' ')
        .trim();
    const moduleSource = normalize(readFileSync(new URL('../src/modules/module_service.js', import.meta.url), 'utf8'));
    const doorSource = normalize(readFileSync(new URL('../src/services/door_service.js', import.meta.url), 'utf8'));

    it('door_access: yonetici ve aktif daire bagi TRUE; kurul, gorevli ve yalniz RESIDENT site uyeligi FALSE', () => {
      assert.match(moduleSource, /SELECT sms\.site_code, 4 AS rank, TRUE AS door_access FROM site_manager_sites sms/);
      assert.match(moduleSource, /SELECT sm\.site_code, 4, TRUE FROM site_memberships sm WHERE sm\.user_code = \$1 AND sm\.is_active = TRUE AND sm\.role IN \('SITE_OWNER', 'SITE_ADMIN'\)/);
      assert.match(moduleSource, /SELECT sm\.site_code, 3, FALSE FROM site_memberships sm WHERE [^)]*sm\.role = 'BOARD_MEMBER'/);
      assert.match(moduleSource, /SELECT sm\.site_code, 2, FALSE FROM site_memberships sm WHERE [^)]*sm\.role = 'STAFF'/);
      assert.match(moduleSource, /SELECT sm\.site_code, 1, FALSE FROM site_memberships sm WHERE [^)]*sm\.role = 'RESIDENT'/);
      assert.match(moduleSource, /BOOL_OR\(l\.door_access\) AS door_access/);
    });

    it('askiya alinmis/pasif bagler artik "bagli" sayilmaz: aktif daire + aktif uyelik; eski sakin icin aktif daire', () => {
      assert.match(
        moduleSource,
        /SELECT a\.site_code, 1, TRUE FROM apartment_memberships am INNER JOIN apartments a ON a\.id = am\.apartment_id WHERE am\.user_code = \$1 AND am\.is_active = TRUE AND a\.is_active = TRUE/,
      );
      assert.match(
        moduleSource,
        /SELECT a\.site_code, 1, TRUE FROM apartments a WHERE a\.resident_user_code = \$1 AND a\.is_active = TRUE/,
      );
    });

    it('yalniz kapi izniyle (door_access_overrides is_allowed=TRUE, aktif kapi) bagli siteler de gelir, rol resident, door_access TRUE', () => {
      assert.match(
        moduleSource,
        /SELECT d\.site_code, 1, TRUE FROM door_access_overrides dao INNER JOIN site_doors d ON d\.id = dao\.door_id WHERE dao\.user_code = \$1 AND dao\.is_allowed = TRUE AND d\.is_active = TRUE/,
      );
    });

    it('override askiya kosulu door_service.listAccessibleDoorsForUser ile BIREBIR ayni (kod tekrari kaymasin)', () => {
      const block = /NOT \( EXISTS \( SELECT 1 FROM apartment_memberships am_any[\s\S]*?a_on_res\.resident_user_code = \$1 \)/;
      const inModule = block.exec(moduleSource)?.[0];
      const inDoorService = block.exec(doorSource)?.[0];
      assert.ok(inModule, 'module_service askiya kosulu bulunamadi');
      assert.ok(inDoorService, 'door_service askiya kosulu bulunamadi');
      assert.equal(inModule, inDoorService);
    });
  });
});
