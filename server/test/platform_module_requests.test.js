// Platform modul talebi akisi (Faz 1.1, DB'siz): yonetici TALEP eder, sistem yoneticisi (super kullanici) onaylar/reddeder.
// Kimlik katmani test icin sahte (x-test-user); pool.query / pool.connect bellek ici sahte veritabanina baglanir.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import nodemailer from 'nodemailer';
import { pool } from '../src/db.js';
import { authRequired, requireSiteManager, requireSuperUser } from '../src/middlewares/auth_middleware.js';
import { MODULE_REQUEST_EMAIL_SUBJECT } from '../src/mailer.js';
import { moduleRequestHooks, notifySuperUsersOfRequest, normalizeRequestNote } from '../src/modules/module_request_service.js';
import { moduleLockKey } from '../src/modules/module_service.js';
import { moduleRequestLimiter, moduleRequestRouter } from '../src/modules/module_request_routes.js';

const SITE_1 = 1000000001;
const SITE_2 = 1000000002;
const T0 = new Date('2026-10-15T08:00:00.000Z');

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
const ok = (rows = []) => ({ rows, rowCount: rows.length });

function makeState() {
  return {
    sites: new Map([
      [SITE_1, 'Gül Sitesi'],
      [SITE_2, 'Lale Sitesi'],
    ]),
    managerLinks: [
      { site_code: SITE_1, user_code: 20001 },
      { site_code: SITE_2, user_code: 20002 },
    ],
    memberships: [
      { site_code: SITE_1, user_code: 20003, role: 'SITE_OWNER', is_active: true },
      { site_code: SITE_1, user_code: 20005, role: 'STAFF', is_active: true },
    ],
    // door_control SITE_1'de KAPALI: talep edilebilir (varsayilan acik olsaydi MODULE_ALREADY_ENABLED olurdu)
    siteModules: new Map([[`${SITE_1}:door_control`, { enabled: false }]]),
    requests: [],
    requestSeq: 0,
    audit: [],
    auditSeq: 0,
    forceUniqueViolation: false,
    failUpdate: false,
    locks: [],
    log: [],
  };
}

let state;

function viewRow(request) {
  return {
    id: String(request.id),
    site_code: String(request.site_code),
    site_name: state.sites.get(request.site_code) ?? null,
    module_code: request.module_code,
    status: request.status,
    note: request.note,
    requested_by_name: request.requested_by_name,
    created_at: request.created_at,
    decided_by_name: request.decided_by_name,
    decided_at: request.decided_at,
    decision_note: request.decision_note,
  };
}

function seedRequest(overrides = {}) {
  state.requestSeq += 1;
  const request = {
    id: state.requestSeq,
    site_code: SITE_1,
    module_code: 'door_control',
    status: 'pending',
    requested_by: 20001,
    requested_by_name: 'Ayşe Yönetici',
    note: null,
    decided_by: null,
    decided_by_name: null,
    decision_note: null,
    created_at: new Date(T0.getTime() + state.requestSeq * 1000),
    decided_at: null,
    ...overrides,
  };
  state.requests.push(request);
  return request;
}

function handle(sql, params, tx) {
  const write = (fn) => (tx && tx.pending ? tx.pending.push(fn) : fn());
  state.log.push({ sql, params });

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

  // --- yetki ---
  if (/^SELECT 1 FROM site_manager_sites WHERE manager_user_code = \$1 LIMIT 1$/.test(sql)) {
    return ok(state.managerLinks.filter((l) => l.user_code === Number(params[0])).slice(0, 1).map(() => ({ x: 1 })));
  }
  if (/^SELECT 1 FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2 LIMIT 1$/.test(sql)) {
    return ok(
      state.managerLinks.filter((l) => l.site_code === Number(params[0]) && l.user_code === Number(params[1])).map(() => ({ x: 1 })),
    );
  }
  if (/^SELECT 1 FROM site_memberships WHERE user_code = \$1 AND role IN \('SITE_OWNER', 'SITE_ADMIN'\) AND is_active = TRUE LIMIT 1$/.test(sql)) {
    return ok(
      state.memberships
        .filter((m) => m.user_code === Number(params[0]) && ['SITE_OWNER', 'SITE_ADMIN'].includes(m.role) && m.is_active)
        .slice(0, 1)
        .map(() => ({ x: 1 })),
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
        .map(() => ({ x: 1 })),
    );
  }

  // --- site / modul ---
  if (/^SELECT site_code FROM sites WHERE site_code = \$1 (FOR SHARE|LIMIT 1)$/.test(sql)) {
    return ok(state.sites.has(Number(params[0])) ? [{ site_code: String(params[0]) }] : []);
  }
  if (/^SELECT enabled FROM site_modules WHERE site_code = \$1 AND module_code = \$2 LIMIT 1$/.test(sql)) {
    const row = state.siteModules.get(`${params[0]}:${params[1]}`);
    return ok(row ? [{ enabled: row.enabled }] : []);
  }
  if (/^INSERT INTO site_modules /.test(sql)) {
    const [siteCode, moduleCode, updatedBy] = params;
    write(() => state.siteModules.set(`${siteCode}:${moduleCode}`, { enabled: true, updated_by: updatedBy }));
    return ok();
  }

  // --- talepler ---
  if (/^SELECT id FROM module_requests WHERE site_code = \$1 AND module_code = \$2 AND status = 'pending' LIMIT 1$/.test(sql)) {
    return ok(
      state.requests
        .filter((r) => r.site_code === Number(params[0]) && r.module_code === params[1] && r.status === 'pending')
        .slice(0, 1)
        .map((r) => ({ id: String(r.id) })),
    );
  }
  if (/^INSERT INTO module_requests /.test(sql)) {
    const [siteCode, moduleCode, requestedBy, requestedByName, note] = params;
    const duplicate = state.requests.some(
      (r) => r.site_code === Number(siteCode) && r.module_code === moduleCode && r.status === 'pending',
    );
    if (state.forceUniqueViolation || duplicate) {
      throw Object.assign(new Error('duplicate key value violates unique constraint "uq_module_requests_pending"'), { code: '23505' });
    }
    state.requestSeq += 1;
    const id = state.requestSeq;
    write(() =>
      state.requests.push({
        id,
        site_code: Number(siteCode),
        module_code: moduleCode,
        status: 'pending',
        requested_by: requestedBy,
        requested_by_name: requestedByName,
        note,
        decided_by: null,
        decided_by_name: null,
        decision_note: null,
        created_at: new Date(T0.getTime() + id * 1000),
        decided_at: null,
      }),
    );
    return ok([{ id: String(id) }]);
  }
  if (/^SELECT id, site_code, module_code, status FROM module_requests WHERE id = \$1 AND site_code = \$2 FOR UPDATE$/.test(sql)) {
    const row = state.requests.find((r) => r.id === Number(params[0]) && r.site_code === Number(params[1]));
    return ok(row ? [{ id: String(row.id), site_code: String(row.site_code), module_code: row.module_code, status: row.status }] : []);
  }
  if (/^SELECT site_code, module_code FROM module_requests WHERE id = \$1$/.test(sql)) {
    const row = state.requests.find((r) => r.id === Number(params[0]));
    return ok(row ? [{ site_code: String(row.site_code), module_code: row.module_code }] : []);
  }
  if (/^SELECT id, site_code, module_code, status FROM module_requests WHERE id = \$1 FOR UPDATE$/.test(sql)) {
    const row = state.requests.find((r) => r.id === Number(params[0]));
    return ok(row ? [{ id: String(row.id), site_code: String(row.site_code), module_code: row.module_code, status: row.status }] : []);
  }
  if (/^UPDATE module_requests SET status = 'cancelled', decided_by = \$2, decided_by_name = \$3, decided_at = NOW\(\) WHERE id = \$1$/.test(sql)) {
    if (state.failUpdate) throw Object.assign(new Error('SECRET_DB_DETAIL update'), { code: 'XX000' });
    const [id, decidedBy, decidedByName] = params;
    write(() => {
      const row = state.requests.find((r) => r.id === Number(id));
      Object.assign(row, { status: 'cancelled', decided_by: decidedBy, decided_by_name: decidedByName, decided_at: new Date('2026-10-15T12:00:00.000Z') });
    });
    return ok();
  }
  if (/^UPDATE module_requests SET status = \$2, decided_by = \$3, decided_by_name = \$4, decision_note = \$5, decided_at = NOW\(\) WHERE id = \$1$/.test(sql)) {
    if (state.failUpdate) throw Object.assign(new Error('SECRET_DB_DETAIL update'), { code: 'XX000' });
    const [id, status, decidedBy, decidedByName, decisionNote] = params;
    write(() => {
      const row = state.requests.find((r) => r.id === Number(id));
      Object.assign(row, {
        status,
        decided_by: decidedBy,
        decided_by_name: decidedByName,
        decision_note: decisionNote,
        decided_at: new Date('2026-10-15T12:00:00.000Z'),
      });
    });
    return ok();
  }

  // talep gorunumleri (REQUEST_SELECT)
  if (/^SELECT r\.id, r\.site_code, s\.name AS site_name, .* FROM module_requests r LEFT JOIN sites s ON s\.site_code = r\.site_code WHERE r\.id = \$1 LIMIT 1$/.test(sql)) {
    const row = state.requests.find((r) => r.id === Number(params[0]));
    return ok(row ? [viewRow(row)] : []);
  }
  if (/FROM module_requests r LEFT JOIN sites s ON s\.site_code = r\.site_code WHERE r\.site_code = \$1 ORDER BY r\.id DESC LIMIT 50$/.test(sql)) {
    return ok(
      state.requests
        .filter((r) => r.site_code === Number(params[0]))
        .sort((a, b) => b.id - a.id)
        .slice(0, 50)
        .map(viewRow),
    );
  }
  if (/FROM module_requests r LEFT JOIN sites s ON s\.site_code = r\.site_code WHERE \(\$1::TEXT IS NULL OR r\.status = \$1::TEXT\) AND \(\$2::BIGINT IS NULL OR r\.id < \$2::BIGINT\) ORDER BY r\.id DESC LIMIT \$3$/.test(sql)) {
    const [status, beforeId, limit] = params;
    return ok(
      state.requests
        .filter((r) => (status === null || r.status === status) && (beforeId === null || r.id < Number(beforeId)))
        .sort((a, b) => b.id - a.id)
        .slice(0, limit)
        .map(viewRow),
    );
  }
  if (/^SELECT COUNT\(\*\)::INTEGER AS pending_count FROM module_requests WHERE status = 'pending'$/.test(sql)) {
    return ok([{ pending_count: state.requests.filter((r) => r.status === 'pending').length }]);
  }

  // --- denetim ---
  if (/^INSERT INTO audit_log /.test(sql)) {
    const [actorUserCode, actorName, actorRole, action, siteCode, targetType, targetId, details] = params;
    write(() => {
      state.auditSeq += 1;
      state.audit.push({
        id: state.auditSeq,
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

  // --- bildirim alicilari ---
  if (/^SELECT full_name, email FROM users WHERE role = 'super_user' AND is_active = TRUE AND email IS NOT NULL AND email <> ''$/.test(sql)) {
    return ok(state.superUsers ?? []);
  }

  throw new Error(`sahte veritabani: beklenmeyen sorgu: ${sql}`);
}

function installFakeDb() {
  pool.query = async (text, params) => handle(norm(text), params ?? [], null);
  pool.connect = async () => {
    const tx = { pending: null };
    return {
      query: async (text, params) => handle(norm(text), params ?? [], tx),
      release() {},
    };
  };
}

// ---------------------------------------------------------------------------
// HTTP duzenegi
// ---------------------------------------------------------------------------

const ORIGINAL_ROUTES = moduleRequestRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({
    path: layer.route.path,
    method: Object.keys(layer.route.methods)[0],
    handlers: layer.route.stack.map((entry) => entry.handle),
  }));

let server;
let baseUrl;
let notifications;
const originalNotify = moduleRequestHooks.notifyCreated;

before(async () => {
  for (const layer of moduleRequestRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    if (layer.route.methods.post && layer.route.path.endsWith('/module-requests')) {
      assert.equal(layer.route.stack[2].handle, moduleRequestLimiter);
      layer.route.stack[2].handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json());
  app.use(moduleRequestRouter);
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
  moduleRequestHooks.notifyCreated = originalNotify;
});

beforeEach(() => {
  state = makeState();
  installFakeDb();
  notifications = [];
  moduleRequestHooks.notifyCreated = async (request) => {
    notifications.push(request);
  };
  mock.method(console, 'error', () => {});
  mock.method(console, 'log', () => {});
});

afterEach(() => {
  mock.restoreAll();
  moduleRequestLimiter.reset();
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

const flush = () => new Promise((resolve) => setImmediate(resolve));
const requestsUrl = (site = SITE_1) => `/manager/sites/${site}/module-requests`;
const post = (body, user = users.mgrA, site = SITE_1) => call('POST', requestsUrl(site), { user, body });

const REQUEST_KEYS = [
  'id',
  'site_code',
  'site_name',
  'module_code',
  'module_name',
  'status',
  'note',
  'requested_by_name',
  'created_at',
  'decided_by_name',
  'decided_at',
  'decision_note',
];

// ---------------------------------------------------------------------------
// Kimlik zinciri
// ---------------------------------------------------------------------------

describe('modul talebi rotalari: kimlik zinciri', () => {
  it('5 rota; yonetici uclari requireSiteManager, admin uclari requireSuperUser; POST hiz sinirli', () => {
    const summary = ORIGINAL_ROUTES.map((r) => `${r.method.toUpperCase()} ${r.path}`).sort();
    assert.deepEqual(summary, [
      'DELETE /manager/sites/:siteCode/module-requests/:id',
      'GET /admin/module-requests',
      'GET /manager/sites/:siteCode/module-requests',
      'POST /manager/sites/:siteCode/module-requests',
      'PUT /admin/module-requests/:id',
    ]);
    for (const route of ORIGINAL_ROUTES) {
      assert.equal(route.handlers[0], authRequired, route.path);
      if (route.path.startsWith('/manager/')) assert.equal(route.handlers[1], requireSiteManager, route.path);
      if (route.path.startsWith('/admin/')) assert.equal(route.handlers[1], requireSuperUser, route.path);
      if (route.method === 'post') assert.equal(route.handlers[2], moduleRequestLimiter);
    }
  });
});

// ---------------------------------------------------------------------------
// POST /manager/sites/:siteCode/module-requests
// ---------------------------------------------------------------------------

describe('POST module-requests', () => {
  it('yonetici talep eder: 201 { request } sozlesme alanlariyla; status pending, isteyen adi, tarih ISO', async () => {
    const res = await post({ module_code: 'door_control', note: '  Kapıları uygulamadan açmak istiyoruz.  ' });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.deepEqual(Object.keys(res.body), ['request']);
    assert.deepEqual(Object.keys(res.body.request), REQUEST_KEYS);
    assert.deepEqual(res.body.request, {
      id: 1,
      site_code: SITE_1,
      site_name: 'Gül Sitesi',
      module_code: 'door_control',
      module_name: 'Geçiş Kontrol (SmartKeyPass)',
      status: 'pending',
      note: 'Kapıları uygulamadan açmak istiyoruz.',
      requested_by_name: 'Ayşe Yönetici',
      created_at: '2026-10-15T08:00:01.000Z',
      decided_by_name: null,
      decided_at: null,
      decision_note: null,
    });
    assert.equal(state.requests.length, 1);
    assert.equal(state.requests[0].requested_by, 20001);
  });

  it('audit module_request.created: target_type module_request, target_id talep id, details { module_code }; ayni transaction', async () => {
    await post({ module_code: 'door_control' });
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
        action: 'module_request.created',
        site_code: SITE_1,
        target_type: 'module_request',
        target_id: '1',
        details: { module_code: 'door_control' },
        actor_user_code: 20001,
        actor_name: 'Ayşe Yönetici',
        actor_role: 'site_manager',
      },
    );
    const sqls = state.log.map((q) => q.sql.split(' ').slice(0, 3).join(' '));
    const begin = sqls.indexOf('BEGIN');
    const insert = sqls.indexOf('INSERT INTO module_requests');
    const audit = sqls.indexOf('INSERT INTO audit_log');
    const commit = sqls.indexOf('COMMIT');
    assert.ok(begin >= 0 && begin < insert && insert < audit && audit < commit, JSON.stringify(sqls));
  });

  it('bildirim: COMMIT sonrasi fire-and-forget; talep nesnesiyle cagrilir', async () => {
    await post({ module_code: 'door_control', note: 'not' });
    await flush();
    assert.equal(notifications.length, 1);
    assert.equal(notifications[0].id, 1);
    assert.equal(notifications[0].site_name, 'Gül Sitesi');
    assert.equal(notifications[0].module_name, 'Geçiş Kontrol (SmartKeyPass)');
    assert.equal(notifications[0].requested_by_name, 'Ayşe Yönetici');
    assert.equal(notifications[0].note, 'not');
  });

  it('bildirim HATASI talebi bozmaz (201, kayit var, hata loglanir); bildirim yanit icin BEKLENMEZ', async () => {
    let release;
    const gate = new Promise((resolve) => {
      release = resolve;
    });
    moduleRequestHooks.notifyCreated = async () => {
      await gate; // asla beklenmemeli
      throw new Error('SMTP kapali');
    };
    const res = await post({ module_code: 'door_control' });
    assert.equal(res.status, 201);
    assert.equal(state.requests.length, 1);
    release();
    await flush();
    await flush();
    assert.ok(console.error.mock.calls.some((c) => String(c.arguments[0]).includes('[module_request]')));
  });

  it('baska hata kodlari: bilinmeyen modul 404, core 400, yakinda 409, zaten acik 409', async () => {
    const unknown = await post({ module_code: 'nope' });
    assert.equal(unknown.status, 404);
    assert.equal(unknown.body.code, 'MODULE_NOT_FOUND');

    for (const code of ['people', 'announcements']) {
      const core = await post({ module_code: code });
      assert.equal(core.status, 400, code);
      assert.equal(core.body.code, 'MODULE_NOT_TOGGLEABLE');
    }
    for (const code of ['metering', 'online_payment']) {
      const soon = await post({ module_code: code });
      assert.equal(soon.status, 409, code);
      assert.equal(soon.body.code, 'MODULE_COMING_SOON');
    }
    // SITE_2'de door_control satiri yok -> varsayilan ACIK -> zaten acik
    const open = await post({ module_code: 'door_control' }, users.mgrB, SITE_2);
    assert.equal(open.status, 409);
    assert.equal(open.body.code, 'MODULE_ALREADY_ENABLED');
    assert.equal(state.requests.length, 0);
    assert.equal(state.audit.length, 0);
    assert.equal(notifications.length, 0);
  });

  it('finance (Faz 4a) artik "available": yonetici modul talep edebilir (201, bekleyen, "Aidat ve Finans"); varsayilan KAPALI oldugundan ALREADY_ENABLED degil', async () => {
    const res = await post({ module_code: 'finance', note: 'Aidat takibi için.' });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    assert.equal(res.body.request.module_code, 'finance');
    assert.equal(res.body.request.module_name, 'Aidat ve Finans');
    assert.equal(res.body.request.status, 'pending');
    assert.equal(state.requests.length, 1);
    // ayni (site, modul) icin ikinci bekleyen talep yine engellenir
    const again = await post({ module_code: 'finance' });
    assert.equal(again.status, 409);
    assert.equal(again.body.code, 'MODULE_REQUEST_PENDING');
  });

  it('gecersiz govde 400 INVALID_BODY: module_code eksik/metin degil, not metin degil veya 500 karakterden uzun', async () => {
    for (const body of [{}, { module_code: '' }, { module_code: '   ' }, { module_code: 5 }, { module_code: null }, { note: 'x' }]) {
      const res = await post(body);
      assert.equal(res.status, 400, JSON.stringify(body));
      assert.equal(res.body.code, 'INVALID_BODY');
    }
    const badNote = await post({ module_code: 'door_control', note: 42 });
    assert.equal(badNote.status, 400);
    assert.equal(badNote.body.code, 'INVALID_BODY');
    const longNote = await post({ module_code: 'door_control', note: 'x'.repeat(501) });
    assert.equal(longNote.status, 400);
    assert.equal(longNote.body.code, 'INVALID_BODY');
    const exact = await post({ module_code: 'door_control', note: 'y'.repeat(500) });
    assert.equal(exact.status, 201, '500 karakter sinirdadir ve kabul edilir');
    assert.equal(state.requests.length, 1);
  });

  it('not normallestirme: bos/bosluk -> null; kontrol karakterleri atilir; satir sonu korunur; 500 KARAKTER (emoji dahil kod noktasi)', () => {
    assert.equal(normalizeRequestNote(undefined), null);
    assert.equal(normalizeRequestNote(null), null);
    assert.equal(normalizeRequestNote('   '), null);
    const nul = String.fromCharCode(0);
    const bell = String.fromCharCode(7);
    assert.equal(normalizeRequestNote(` a${nul}b${bell}c `), 'abc');
    assert.equal(normalizeRequestNote('satir1\r\nsatir2'), 'satir1\nsatir2');
    assert.equal(normalizeRequestNote('😀'.repeat(500)).length, 1000, '500 kod noktasi kabul edilir');
    assert.throws(() => normalizeRequestNote('😀'.repeat(501)), (e) => e.code === 'INVALID_BODY');
  });

  it('TEK bekleyen talep: ayni modul icin ikinci talep 409 MODULE_REQUEST_PENDING; baska sitenin talebi engellemez', async () => {
    assert.equal((await post({ module_code: 'door_control' })).status, 201);
    const again = await post({ module_code: 'door_control' });
    assert.equal(again.status, 409);
    assert.equal(again.body.code, 'MODULE_REQUEST_PENDING');
    assert.equal(again.body.error, 'Bu modül için bekleyen bir talebiniz var.');
    assert.equal(state.requests.length, 1);
    // baska sitede kapali door_control icin talep serbest
    state.siteModules.set(`${SITE_2}:door_control`, { enabled: false });
    assert.equal((await post({ module_code: 'door_control' }, users.mgrB, SITE_2)).status, 201);
    assert.equal(state.requests.length, 2);
  });

  it('YARIS: kontrol atlansa bile kismi tekil indeks ihlali (23505) 409 MODULE_REQUEST_PENDING olur, kayit ve audit yok', async () => {
    state.forceUniqueViolation = true;
    const res = await post({ module_code: 'door_control' });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'MODULE_REQUEST_PENDING');
    assert.equal(state.requests.length, 0);
    assert.equal(state.audit.length, 0);
    assert.ok(state.log.some((q) => q.sql === 'ROLLBACK'));
    assert.equal(notifications.length, 0);
  });

  it('geri cekildikten sonra yeniden talep edilebilir', async () => {
    const first = await post({ module_code: 'door_control' });
    assert.equal((await call('DELETE', `${requestsUrl()}/${first.body.request.id}`)).status, 200);
    const second = await post({ module_code: 'door_control' });
    assert.equal(second.status, 201);
    assert.equal(second.body.request.id, 2);
  });

  it('yetki: kendi sitesinin yoneticisi ve SITE_OWNER 201; super 201; baska sitenin yoneticisi 403 FORBIDDEN_SITE; sakin/STAFF 403', async () => {
    assert.equal((await post({ module_code: 'door_control' }, users.ownerC)).status, 201);
    state.requests.length = 0;
    assert.equal((await post({ module_code: 'door_control' }, users.superUser)).status, 201);
    state.requests.length = 0;
    const other = await post({ module_code: 'door_control' }, users.mgrB);
    assert.equal(other.status, 403);
    assert.equal(other.body.code, 'FORBIDDEN_SITE');
    for (const user of [users.resident, users.staff]) {
      assert.equal((await post({ module_code: 'door_control' }, user)).status, 403, user.full_name);
    }
    assert.equal(state.requests.length, 0);
  });

  it('gecersiz site kodu 400 INVALID_SITE_CODE; super + olmayan site 404 SITE_NOT_FOUND', async () => {
    const bad = await call('POST', '/manager/sites/abc/module-requests', { user: users.superUser, body: { module_code: 'door_control' } });
    assert.equal(bad.status, 400);
    assert.equal(bad.body.code, 'INVALID_SITE_CODE');
    const missing = await post({ module_code: 'door_control' }, users.superUser, 1999999999);
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'SITE_NOT_FOUND');
  });

  it('beklenmeyen veritabani hatasi 500 + errorId; ic ayrinti sizmaz', async () => {
    state.failUpdate = true;
    const original = pool.connect;
    pool.connect = async () => {
      const client = await original();
      const query = client.query;
      client.query = async (text, params) => {
        if (/^INSERT INTO module_requests/.test(norm(text))) {
          throw Object.assign(new Error('SECRET_DB_DETAIL insert'), { code: 'XX000' });
        }
        return query(text, params);
      };
      return client;
    };
    const res = await post({ module_code: 'door_control' });
    assert.equal(res.status, 500);
    assert.equal(typeof res.body.errorId, 'string');
    assert.equal(JSON.stringify(res.body).includes('SECRET_DB_DETAIL'), false);
    assert.equal(state.requests.length, 0);
  });
});

describe('advisory kilit anahtari ve kilit sirasi (site -> advisory -> talep satiri)', () => {
  const indexOfSql = (matcher) => state.log.findIndex((q) => matcher.test(q.sql));

  it('talep olusturma modul ac/kapa ile AYNI anahtari kullanir: site_module:<site>:<modul>', async () => {
    await post({ module_code: 'door_control' });
    assert.deepEqual(state.locks, [`site_module:${SITE_1}:door_control`]);
    assert.equal(state.locks[0], moduleLockKey(SITE_1, 'door_control'));
    assert.equal(moduleLockKey(SITE_1, 'door_control'), 'site_module:1000000001:door_control');
  });

  it('onay (approve) ve ret (reject) de AYNI anahtari alir', async () => {
    const first = seedRequest();
    await call('PUT', `/admin/module-requests/${first.id}`, { user: users.superUser, body: { decision: 'approve' } });
    assert.deepEqual(state.locks, [moduleLockKey(SITE_1, 'door_control')]);
    state.locks.length = 0;
    state.siteModules.set(`${SITE_1}:door_control`, { enabled: false });
    const second = seedRequest();
    await call('PUT', `/admin/module-requests/${second.id}`, { user: users.superUser, body: { decision: 'reject' } });
    assert.deepEqual(state.locks, [moduleLockKey(SITE_1, 'door_control')]);
  });

  it('create: sites FOR SHARE ONCE, sonra advisory kilit (deadlock onleme sirasi)', async () => {
    await post({ module_code: 'door_control' });
    const siteLock = indexOfSql(/^SELECT site_code FROM sites WHERE site_code = \$1 FOR SHARE$/);
    const advisory = indexOfSql(/^SELECT pg_advisory_xact_lock/);
    assert.ok(siteLock >= 0 && advisory > siteLock, JSON.stringify(state.log.map((q) => q.sql.slice(0, 40))));
  });

  it('onay: talep satiri kilitsiz okunur -> sites FOR SHARE -> advisory -> talep FOR UPDATE (site silme ile ters sira yok)', async () => {
    const created = seedRequest();
    await call('PUT', `/admin/module-requests/${created.id}`, { user: users.superUser, body: { decision: 'approve' } });
    const peek = indexOfSql(/^SELECT site_code, module_code FROM module_requests WHERE id = \$1$/);
    const siteLock = indexOfSql(/^SELECT site_code FROM sites WHERE site_code = \$1 FOR SHARE$/);
    const advisory = indexOfSql(/^SELECT pg_advisory_xact_lock/);
    const rowLock = indexOfSql(/FROM module_requests WHERE id = \$1 FOR UPDATE$/);
    const upsert = indexOfSql(/^INSERT INTO site_modules/);
    assert.ok(peek >= 0 && peek < siteLock && siteLock < advisory && advisory < rowLock && rowLock < upsert, JSON.stringify([peek, siteLock, advisory, rowLock, upsert]));
    // peek kilitsizdir
    assert.equal(/FOR (UPDATE|SHARE)/.test(state.log[peek].sql), false);
  });

  it('onay sirasinda site artik yoksa (silindi) 404 REQUEST_NOT_FOUND; talep satiri kilitlenmez', async () => {
    const created = seedRequest();
    state.sites.delete(SITE_1);
    const res = await call('PUT', `/admin/module-requests/${created.id}`, { user: users.superUser, body: { decision: 'approve' } });
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'REQUEST_NOT_FOUND');
    assert.equal(indexOfSql(/FROM module_requests WHERE id = \$1 FOR UPDATE$/), -1);
    assert.equal(state.locks.length, 0);
    assert.ok(state.log.some((q) => q.sql === 'ROLLBACK'));
  });
});

describe('POST module-requests: hiz siniri', () => {
  const run = (code, ip = '1.2.3.4') => {
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
    moduleRequestLimiter({ authUser: { id: code }, ip, path: '/x' }, res, () => {
      passed = true;
    });
    return { res, passed };
  };

  it('kullanici basina 10/saat: 11. istek 429 + Retry-After + retry_after_seconds; baska kullanici etkilenmez', () => {
    for (let i = 0; i < 10; i += 1) {
      assert.equal(run(111).passed, true, String(i));
    }
    const blocked = run(111);
    assert.equal(blocked.passed, false);
    assert.equal(blocked.res.statusCode, 429);
    assert.ok(Number(blocked.res.headers['Retry-After']) > 0 && Number(blocked.res.headers['Retry-After']) <= 3600);
    assert.ok(blocked.res.body.retry_after_seconds > 0);
    assert.equal(blocked.res.body.error, 'Çok fazla modül talebi. Biraz sonra tekrar deneyin.');
    assert.equal(run(222).passed, true);
  });

  it('IP basina 100/saat (NAT arkasi toplu kilitlenmesin)', () => {
    for (let i = 0; i < 100; i += 1) {
      assert.equal(run(1000 + i, '9.9.9.9').passed, true, String(i));
    }
    assert.equal(run(5000, '9.9.9.9').res.statusCode, 429);
    assert.equal(run(5001, '8.8.8.8').passed, true);
  });
});

// ---------------------------------------------------------------------------
// GET /manager/sites/:siteCode/module-requests
// ---------------------------------------------------------------------------

describe('GET module-requests (site yoneticisi)', () => {
  it('yalnizca o sitenin son 50 talebi, id DESC; sozlesme alanlari', async () => {
    for (let i = 0; i < 55; i += 1) {
      seedRequest({ status: i === 54 ? 'pending' : 'cancelled', module_code: 'door_control' });
    }
    seedRequest({ site_code: SITE_2 });
    const res = await call('GET', requestsUrl(), { user: users.mgrA });
    assert.equal(res.status, 200);
    assert.deepEqual(Object.keys(res.body), ['items']);
    assert.equal(res.body.items.length, 50);
    assert.deepEqual(res.body.items.slice(0, 2).map((r) => r.id), [55, 54]);
    assert.ok(res.body.items.every((r) => r.site_code === SITE_1));
    assert.deepEqual(Object.keys(res.body.items[0]), REQUEST_KEYS);
    assert.equal(res.body.items[0].created_at, '2026-10-15T08:00:55.000Z');
  });

  it('bos liste; yetki matrisi; olmayan site', async () => {
    assert.deepEqual((await call('GET', requestsUrl(), { user: users.mgrA })).body, { items: [] });
    assert.equal((await call('GET', requestsUrl(), { user: users.superUser })).status, 200);
    assert.equal((await call('GET', requestsUrl(), { user: users.ownerC })).status, 200);
    const other = await call('GET', requestsUrl(), { user: users.mgrB });
    assert.equal(other.status, 403);
    assert.equal(other.body.code, 'FORBIDDEN_SITE');
    assert.equal((await call('GET', requestsUrl(), { user: users.resident })).status, 403);
    assert.equal((await call('GET', requestsUrl(), { user: users.staff })).status, 403);
    const missing = await call('GET', requestsUrl(1999999999), { user: users.superUser });
    assert.equal(missing.status, 404);
    assert.equal(missing.body.code, 'SITE_NOT_FOUND');
  });
});

// ---------------------------------------------------------------------------
// DELETE /manager/sites/:siteCode/module-requests/:id
// ---------------------------------------------------------------------------

describe('DELETE module-requests/:id (geri cek)', () => {
  const del = (id, user = users.mgrA, site = SITE_1) => call('DELETE', `${requestsUrl(site)}/${id}`, { user });

  it('bekleyen talep cancelled olur; { request } doner; geri ceken ve zaman yazilir; audit module_request.cancelled', async () => {
    const created = seedRequest({ note: 'lütfen' });
    const res = await del(created.id);
    assert.equal(res.status, 200);
    assert.deepEqual(Object.keys(res.body), ['request']);
    assert.equal(res.body.request.status, 'cancelled');
    assert.equal(res.body.request.decided_by_name, 'Ayşe Yönetici');
    assert.equal(res.body.request.decided_at, '2026-10-15T12:00:00.000Z');
    assert.equal(res.body.request.note, 'lütfen');
    assert.equal(state.requests[0].status, 'cancelled');
    assert.deepEqual(
      [state.audit[0].action, state.audit[0].target_type, state.audit[0].target_id, state.audit[0].details, state.audit[0].site_code],
      ['module_request.cancelled', 'module_request', String(created.id), { module_code: 'door_control' }, SITE_1],
    );
    assert.ok(state.log.some((q) => /FOR UPDATE$/.test(q.sql) && q.sql.includes('FROM module_requests')), 'satir kilitlenir');
  });

  it('bekleyen olmayan talep 409 REQUEST_NOT_PENDING (approved/rejected/cancelled)', async () => {
    for (const status of ['approved', 'rejected', 'cancelled']) {
      const created = seedRequest({ status, module_code: 'door_control' });
      const res = await del(created.id);
      assert.equal(res.status, 409, status);
      assert.equal(res.body.code, 'REQUEST_NOT_PENDING');
      assert.equal(res.body.error, 'Bu talep artık bekleyen durumda değil.');
    }
    assert.equal(state.audit.length, 0);
  });

  it('BASKA sitenin talebi 404 REQUEST_NOT_FOUND (varlik sizmaz); yok ve gecersiz id de 404', async () => {
    const otherSite = seedRequest({ site_code: SITE_2 });
    const res = await del(otherSite.id, users.mgrA, SITE_1);
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'REQUEST_NOT_FOUND');
    assert.equal(state.requests[0].status, 'pending');
    for (const id of [9999, 'abc', 0, -1, '1.5']) {
      const r = await del(id);
      assert.equal(r.status, 404, String(id));
      assert.equal(r.body.code, 'REQUEST_NOT_FOUND');
    }
  });

  it('yetki: baska sitenin yoneticisi 403 FORBIDDEN_SITE, sakin/STAFF 403; super ve SITE_OWNER geri cekebilir', async () => {
    const created = seedRequest();
    const other = await del(created.id, users.mgrB);
    assert.equal(other.status, 403);
    assert.equal(other.body.code, 'FORBIDDEN_SITE');
    assert.equal((await del(created.id, users.resident)).status, 403);
    assert.equal((await del(created.id, users.staff)).status, 403);
    assert.equal(state.requests[0].status, 'pending');
    assert.equal((await del(created.id, users.ownerC)).status, 200);
    const second = seedRequest();
    assert.equal((await del(second.id, users.superUser)).status, 200);
  });

  it('guncelleme patlarsa ROLLBACK, 500 + errorId, talep bekleyen kalir', async () => {
    const created = seedRequest();
    state.failUpdate = true;
    const res = await del(created.id);
    assert.equal(res.status, 500);
    assert.equal(JSON.stringify(res.body).includes('SECRET_DB_DETAIL'), false);
    assert.equal(state.requests[0].status, 'pending');
    assert.ok(state.log.some((q) => q.sql === 'ROLLBACK'));
  });
});

// ---------------------------------------------------------------------------
// GET /admin/module-requests
// ---------------------------------------------------------------------------

describe('GET /admin/module-requests', () => {
  const list = (query = '', user = users.superUser) => call('GET', `/admin/module-requests${query}`, { user });

  function seedMixed() {
    seedRequest({ status: 'pending', module_code: 'door_control', site_code: SITE_1 }); // 1
    seedRequest({ status: 'approved', module_code: 'door_control', site_code: SITE_2 }); // 2
    seedRequest({ status: 'rejected', module_code: 'door_control', site_code: SITE_2 }); // 3
    seedRequest({ status: 'cancelled', module_code: 'door_control', site_code: SITE_1 }); // 4
    seedRequest({ status: 'pending', module_code: 'finance', site_code: SITE_2 }); // 5
  }

  it('yalnizca super kullanici; yonetici, SITE_OWNER, sakin ve STAFF 403', async () => {
    seedMixed();
    for (const user of [users.mgrA, users.mgrB, users.ownerC, users.resident, users.staff]) {
      assert.equal((await list('', user)).status, 403, user.full_name);
    }
    assert.equal((await list()).status, 200);
  });

  it('varsayilan durum pending; { items, next_before_id, pending_count }; id DESC', async () => {
    seedMixed();
    const res = await list();
    assert.equal(res.status, 200);
    assert.deepEqual(Object.keys(res.body), ['items', 'next_before_id', 'pending_count']);
    assert.deepEqual(res.body.items.map((r) => r.id), [5, 1]);
    assert.equal(res.body.next_before_id, null);
    assert.equal(res.body.pending_count, 2);
    assert.deepEqual(Object.keys(res.body.items[0]), REQUEST_KEYS);
    assert.equal(res.body.items[0].site_name, 'Lale Sitesi');
    assert.equal(res.body.items[0].module_name, 'Aidat ve Finans');
  });

  it('durum suzgecleri: approved / rejected / cancelled / pending / all; pending_count suzgecten BAGIMSIZ', async () => {
    seedMixed();
    const expectations = {
      approved: [2],
      rejected: [3],
      cancelled: [4],
      pending: [5, 1],
      all: [5, 4, 3, 2, 1],
    };
    for (const [status, ids] of Object.entries(expectations)) {
      const res = await list(`?status=${status}`);
      assert.equal(res.status, 200, status);
      assert.deepEqual(res.body.items.map((r) => r.id), ids, status);
      assert.equal(res.body.pending_count, 2, `${status}: toplam bekleyen`);
    }
    assert.equal((await list('?status=')).body.items.length, 2, 'bos status = pending');
  });

  it('gecersiz status / before_id 400 INVALID_QUERY', async () => {
    seedMixed();
    for (const query of ['?status=bilinmeyen', '?status=PENDING', '?status=a&status=b', '?before_id=abc', '?before_id=0', '?before_id=1.5']) {
      const res = await list(query);
      assert.equal(res.status, 400, query);
      assert.equal(res.body.code, 'INVALID_QUERY');
    }
  });

  it('sayfalama: limit + before_id + next_before_id; limit 1-200 araliginda sinirlanir', async () => {
    seedMixed();
    const p1 = await list('?status=all&limit=2');
    assert.deepEqual(p1.body.items.map((r) => r.id), [5, 4]);
    assert.equal(p1.body.next_before_id, 4);
    const p2 = await list(`?status=all&limit=2&before_id=${p1.body.next_before_id}`);
    assert.deepEqual(p2.body.items.map((r) => r.id), [3, 2]);
    assert.equal(p2.body.next_before_id, 2);
    const p3 = await list(`?status=all&limit=2&before_id=${p2.body.next_before_id}`);
    assert.deepEqual(p3.body.items.map((r) => r.id), [1]);
    assert.equal(p3.body.next_before_id, null);
    assert.equal((await list('?status=all&limit=0')).body.items.length, 1, 'limit alt siniri 1');
    assert.equal((await list('?status=all&limit=abc')).body.items.length, 5, 'sayi olmayan limit varsayilan 50');
  });

  it('bos liste: items [], pending_count 0', async () => {
    assert.deepEqual((await list()).body, { items: [], next_before_id: null, pending_count: 0 });
  });
});

// ---------------------------------------------------------------------------
// PUT /admin/module-requests/:id
// ---------------------------------------------------------------------------

describe('PUT /admin/module-requests/:id', () => {
  const decide = (id, body, user = users.superUser) => call('PUT', `/admin/module-requests/${id}`, { user, body });

  it('onay: talep approved; site_modules door_control AÇILIR; audit module.enabled (via request) + module_request.approved; hepsi ayni transaction', async () => {
    const created = seedRequest({ note: 'lütfen' });
    const res = await decide(created.id, { decision: 'approve', note: 'Onaylandı' });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.deepEqual(Object.keys(res.body), ['request']);
    assert.deepEqual(res.body.request, {
      id: created.id,
      site_code: SITE_1,
      site_name: 'Gül Sitesi',
      module_code: 'door_control',
      module_name: 'Geçiş Kontrol (SmartKeyPass)',
      status: 'approved',
      note: 'lütfen',
      requested_by_name: 'Ayşe Yönetici',
      created_at: res.body.request.created_at,
      decided_by_name: 'Süper Kullanıcı',
      decided_at: '2026-10-15T12:00:00.000Z',
      decision_note: 'Onaylandı',
    });

    // modul GERCEKTEN acildi
    const row = state.siteModules.get(`${SITE_1}:door_control`);
    assert.equal(row.enabled, true);
    assert.equal(row.updated_by, 1);

    assert.deepEqual(
      state.audit.map((a) => [a.action, a.target_type, a.target_id, a.details, a.site_code, a.actor_role]),
      [
        ['module.enabled', 'module', 'door_control', { via: 'request', request_id: created.id }, SITE_1, 'super_user'],
        ['module_request.approved', 'module_request', String(created.id), { module_code: 'door_control' }, SITE_1, 'super_user'],
      ],
    );

    const sqls = state.log.map((q) => q.sql.split(' ').slice(0, 3).join(' '));
    const begin = sqls.indexOf('BEGIN');
    const lock = state.log.findIndex((q) => /FROM module_requests WHERE id = \$1 FOR UPDATE$/.test(q.sql));
    const upsert = sqls.indexOf('INSERT INTO site_modules');
    const update = sqls.indexOf('UPDATE module_requests SET');
    const commit = sqls.indexOf('COMMIT');
    assert.ok(begin >= 0 && begin < lock && lock < upsert && upsert < update && update < commit, JSON.stringify(sqls));
    assert.equal(sqls.filter((s) => s === 'COMMIT').length, 1);
  });

  it('onaydan sonra eski istemciler/yonetici icin modul acik gorunur: bekleyen talep kalmaz, ikinci onay 409', async () => {
    const created = seedRequest();
    assert.equal((await decide(created.id, { decision: 'approve' })).status, 200);
    const again = await decide(created.id, { decision: 'approve' });
    assert.equal(again.status, 409);
    assert.equal(again.body.code, 'REQUEST_NOT_PENDING');
    const asReject = await decide(created.id, { decision: 'reject' });
    assert.equal(asReject.status, 409);
    assert.equal(asReject.body.code, 'REQUEST_NOT_PENDING');
    assert.equal(state.audit.length, 2, 'ikinci denemeler audit yazmaz');
  });

  it('ret: talep rejected + gerekce; site_modules DEGISMEZ; audit yalniz module_request.rejected', async () => {
    const created = seedRequest();
    const res = await decide(created.id, { decision: 'reject', note: 'Şu an uygun değil' });
    assert.equal(res.status, 200);
    assert.equal(res.body.request.status, 'rejected');
    assert.equal(res.body.request.decision_note, 'Şu an uygun değil');
    assert.equal(res.body.request.decided_by_name, 'Süper Kullanıcı');
    assert.equal(state.siteModules.get(`${SITE_1}:door_control`).enabled, false);
    assert.equal(state.log.some((q) => q.sql.startsWith('INSERT INTO site_modules')), false);
    assert.deepEqual(
      state.audit.map((a) => [a.action, a.target_id, a.details]),
      [['module_request.rejected', String(created.id), { module_code: 'door_control' }]],
    );
    // reddedilen modul icin yeniden talep edilebilir (bekleyen kalmadi)
    assert.equal((await post({ module_code: 'door_control' })).status, 201);
  });

  it('gerekce istege bagli (null); 500 karakterden uzun 400 INVALID_BODY ve hicbir sey degismez', async () => {
    const created = seedRequest();
    const long = await decide(created.id, { decision: 'reject', note: 'x'.repeat(501) });
    assert.equal(long.status, 400);
    assert.equal(long.body.code, 'INVALID_BODY');
    assert.equal(state.requests[0].status, 'pending');
    const noNote = await decide(created.id, { decision: 'reject' });
    assert.equal(noNote.status, 200);
    assert.equal(noNote.body.request.decision_note, null);
  });

  it('gecersiz decision / govde 400 INVALID_BODY', async () => {
    const created = seedRequest();
    for (const body of [{}, { decision: 'maybe' }, { decision: 'APPROVE' }, { decision: true }, { note: 'x' }, { decision: 'approve', note: 5 }]) {
      const res = await decide(created.id, body);
      assert.equal(res.status, 400, JSON.stringify(body));
      assert.equal(res.body.code, 'INVALID_BODY');
    }
    assert.equal(state.requests[0].status, 'pending');
    assert.equal(state.audit.length, 0);
  });

  it('yok / gecersiz id 404 REQUEST_NOT_FOUND', async () => {
    for (const id of [9999, 'abc', 0, -3, '1.5']) {
      const res = await decide(id, { decision: 'approve' });
      assert.equal(res.status, 404, String(id));
      assert.equal(res.body.code, 'REQUEST_NOT_FOUND');
    }
  });

  it('bekleyen olmayan talep (approved/rejected/cancelled) 409 REQUEST_NOT_PENDING; yazma yok', async () => {
    for (const status of ['approved', 'rejected', 'cancelled']) {
      const created = seedRequest({ status });
      for (const decision of ['approve', 'reject']) {
        const res = await decide(created.id, { decision });
        assert.equal(res.status, 409, `${status}/${decision}`);
        assert.equal(res.body.code, 'REQUEST_NOT_PENDING');
      }
    }
    assert.equal(state.audit.length, 0);
    assert.equal(state.log.some((q) => q.sql.startsWith('INSERT INTO site_modules')), false);
  });

  it('onay aninda modul ZATEN ACIK: 409 MODULE_ALREADY_ENABLED, talep BEKLEYEN kalir, hicbir sey yazilmaz', async () => {
    const created = seedRequest();
    state.siteModules.set(`${SITE_1}:door_control`, { enabled: true }); // talep ile onay arasinda baska yoldan acildi
    const res = await decide(created.id, { decision: 'approve' });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'MODULE_ALREADY_ENABLED');
    assert.equal(state.requests[0].status, 'pending');
    assert.equal(state.audit.length, 0);
    assert.ok(state.log.some((q) => q.sql === 'ROLLBACK'));
    // yine de reddedilebilir
    assert.equal((await decide(created.id, { decision: 'reject' })).status, 200);
  });

  it('finance (Faz 4a) talebi onaylaninca modul ACILIR (site_modules finance enabled) ve audit module.enabled yazilir', async () => {
    const created = seedRequest({ module_code: 'finance', site_code: SITE_2 });
    const res = await decide(created.id, { decision: 'approve' });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.request.status, 'approved');
    assert.equal(res.body.request.module_name, 'Aidat ve Finans');
    assert.equal(state.siteModules.get(`${SITE_2}:finance`).enabled, true);
    assert.deepEqual(
      state.audit.map((a) => [a.action, a.target_id]),
      [['module.enabled', 'finance'], ['module_request.approved', String(created.id)]],
    );
  });

  it('onay aninda modul "yakinda" (metering): 409 MODULE_COMING_SOON, talep bekleyen kalir; ret yine mumkun', async () => {
    const created = seedRequest({ module_code: 'metering', site_code: SITE_2 });
    const res = await decide(created.id, { decision: 'approve' });
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'MODULE_COMING_SOON');
    assert.equal(state.requests[0].status, 'pending');
    assert.equal(state.siteModules.has(`${SITE_2}:metering`), false);
    assert.equal(state.audit.length, 0);
    assert.equal((await decide(created.id, { decision: 'reject' })).status, 200);
  });

  it('katalogda artik olmayan modul icin onay 404 MODULE_NOT_FOUND (talep bekleyen kalir)', async () => {
    const created = seedRequest({ module_code: 'eski_modul' });
    const res = await decide(created.id, { decision: 'approve' });
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'MODULE_NOT_FOUND');
    assert.equal(state.requests[0].status, 'pending');
  });

  it('YARIS: talep satiri FOR UPDATE ile kilitlenir; ikinci es zamanli karar kilitten sonra bekleyen degil gorur', async () => {
    const created = seedRequest();
    const [a, b] = await Promise.all([
      decide(created.id, { decision: 'approve' }),
      decide(created.id, { decision: 'reject' }),
    ]);
    const statuses = [a.status, b.status].sort();
    assert.deepEqual(statuses, [200, 409]);
    const locks = state.log.filter((q) => /FROM module_requests WHERE id = \$1 FOR UPDATE$/.test(q.sql));
    assert.equal(locks.length, 2);
  });

  it('yetki: yalnizca super; yonetici (talep sahibi dahil), SITE_OWNER, sakin ve STAFF 403; hicbir sey yazilmaz', async () => {
    const created = seedRequest();
    for (const user of [users.mgrA, users.mgrB, users.ownerC, users.resident, users.staff]) {
      const res = await decide(created.id, { decision: 'approve' }, user);
      assert.equal(res.status, 403, user.full_name);
    }
    assert.equal(state.requests[0].status, 'pending');
    assert.equal(state.siteModules.get(`${SITE_1}:door_control`).enabled, false);
    assert.equal(state.audit.length, 0);
  });

  it('guncelleme patlarsa: ROLLBACK, 500 + errorId; site_modules ve audit DEGISMEZ (atomik)', async () => {
    const created = seedRequest();
    state.failUpdate = true;
    const res = await decide(created.id, { decision: 'approve' });
    assert.equal(res.status, 500);
    assert.equal(JSON.stringify(res.body).includes('SECRET_DB_DETAIL'), false);
    assert.equal(state.siteModules.get(`${SITE_1}:door_control`).enabled, false);
    assert.equal(state.audit.length, 0);
    assert.equal(state.requests[0].status, 'pending');
    assert.ok(state.log.some((q) => q.sql === 'ROLLBACK'));
  });

  it('onay yerel anahtar dondurmez (modul ACILIYOR); mevcut PUT modules davranisi ayridir', async () => {
    const created = seedRequest();
    await decide(created.id, { decision: 'approve' });
    assert.equal(state.log.some((q) => /devices/.test(q.sql)), false);
  });
});

// ---------------------------------------------------------------------------
// Bildirim e-postasi (varsayilan kanca)
// ---------------------------------------------------------------------------

describe('yeni talep bildirimi: tum AKTIF super kullanicilara e-posta', () => {
  const saved = {};
  const originalCreateTransport = nodemailer.createTransport;
  let sent;

  beforeEach(() => {
    sent = [];
    for (const name of ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASSWORD', 'SMTP_FROM', 'SMTP_PORT']) {
      saved[name] = process.env[name];
    }
    process.env.SMTP_HOST = 'smtp.invalid';
    process.env.SMTP_USER = 'user@example.invalid';
    process.env.SMTP_PASSWORD = 'test-only';
    process.env.SMTP_FROM = 'Sistem <noreply@example.invalid>';
    delete process.env.SMTP_PORT;
    nodemailer.createTransport = () => ({
      sendMail: async (message) => {
        if (String(message.to).startsWith('bozuk')) {
          throw new Error('SMTP reddetti');
        }
        sent.push(message);
      },
    });
  });

  afterEach(() => {
    nodemailer.createTransport = originalCreateTransport;
    for (const [name, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  });

  const request = {
    id: 7,
    site_name: 'Gül Sitesi',
    module_name: 'Geçiş Kontrol (SmartKeyPass)',
    requested_by_name: 'Ayşe Yönetici',
    note: 'Lütfen açın <b>acil</b>',
  };

  it('aktif super kullanici sorgusu is_active=TRUE ile yapilir; her aliciya ayri e-posta, sabit konu', async () => {
    state.superUsers = [
      { full_name: 'Süper Bir', email: 'bir@example.com' },
      { full_name: 'Süper İki', email: 'iki@example.com' },
    ];
    const count = await notifySuperUsersOfRequest(request);
    assert.equal(count, 2);
    assert.deepEqual(sent.map((m) => m.to), ['bir@example.com', 'iki@example.com']);
    for (const message of sent) {
      assert.equal(message.subject, 'Site ve Toplu Yaşam Yönetim Sistemi - Yeni Modül Talebi');
      assert.equal(message.subject, MODULE_REQUEST_EMAIL_SUBJECT);
    }
    const query = state.log.find((q) => q.sql.includes("role = 'super_user'"));
    assert.match(query.sql, /is_active = TRUE/);
  });

  it('bir alicinin hatasi digerlerini ve cagiranı bozmaz (hata loglanir)', async () => {
    state.superUsers = [
      { full_name: 'Bozuk', email: 'bozuk@example.com' },
      { full_name: 'Saglam', email: 'saglam@example.com' },
    ];
    const count = await notifySuperUsersOfRequest(request);
    assert.equal(count, 1);
    assert.deepEqual(sent.map((m) => m.to), ['saglam@example.com']);
    assert.ok(console.error.mock.calls.some((c) => String(c.arguments[0]).includes('[module_request]')));
  });

  it('super kullanici yoksa e-posta gitmez', async () => {
    state.superUsers = [];
    assert.equal(await notifySuperUsersOfRequest(request), 0);
    assert.equal(sent.length, 0);
  });

  it('tum akis: POST varsayilan kancayla super kullanicilara e-posta yollar (fire-and-forget)', async () => {
    moduleRequestHooks.notifyCreated = originalNotify;
    state.superUsers = [{ full_name: 'Süper Bir', email: 'bir@example.com' }];
    const res = await post({ module_code: 'door_control', note: 'acil' });
    assert.equal(res.status, 201);
    for (let i = 0; i < 5 && sent.length === 0; i += 1) {
      await flush();
    }
    assert.equal(sent.length, 1);
    assert.equal(sent[0].to, 'bir@example.com');
    assert.match(sent[0].text, /Gül Sitesi/);
    assert.match(sent[0].text, /Geçiş Kontrol \(SmartKeyPass\)/);
    assert.match(sent[0].text, /Ayşe Yönetici/);
    assert.match(sent[0].text, /acil/);
  });

  it('SMTP ayari yoksa bile talep olusur (e-posta hatasi talebi bozmaz)', async () => {
    moduleRequestHooks.notifyCreated = originalNotify;
    delete process.env.SMTP_FROM;
    delete process.env.SMTP_USER;
    state.superUsers = [{ full_name: 'Süper Bir', email: 'bir@example.com' }];
    const res = await post({ module_code: 'door_control' });
    assert.equal(res.status, 201);
    await flush();
    await flush();
    assert.equal(sent.length, 0);
    assert.equal(state.requests.length, 1);
  });
});
