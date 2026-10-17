// Telefon bildirimi (Faz 3b-B) uçları (DB'siz, KATI sahte veritabanı): cihaz kaydı (kilit + devir + UPSERT + 10 cihaz sınırı + 23505 tek yeniden deneme),
// silinmiş hesaba yazmama, IDOR (başkasının install_id'si), jeton HİÇBİR yanıtta yok, doğrulama mesajları, test bildirimi (503 / gönderim), yönetici durumu
// (yalnız süper), hız sınırları (60/saat, 5/gün). Kimlik katmanı sahte (x-test-user); gerçek PG davranışı qa "push" bölümünde.
import { describe, it, before, after, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { authRequired, requireSuperUser } from '../src/middlewares/auth_middleware.js';
import { setPushRuntimeForTests } from '../src/modules/push_credentials.js';
import { pushDeviceHooks, resetDeadTokenGuard } from '../src/modules/push_devices.js';
import { PUSH_DEVICE_LOCK_CLASS } from '../src/modules/push_common.js';
import { resetPushQueueState } from '../src/modules/push_worker.js';
import {
  pushDeviceReadLimiter,
  pushRegisterLimiter,
  pushRouter,
  pushStatusLimiter,
  pushTestLimiter,
} from '../src/modules/push_routes.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const ok = (rows = [], rowCount = rows.length) => ({ rows, rowCount });
const TOKEN = 'fcm-kayit-jetonu-GIZLI-0123456789-abcdefghijklmnop';
const INSTALL = '3f2b8c1e-9a7d-4e21-b1aa-0c9d8e7f6a5b';
const users = {
  resident: { id: 20004, user_code: 20004, userCode: 20004, role: 'apartment_owner' },
  other: { id: 20005, user_code: 20005, userCode: 20005, role: 'apartment_owner' },
  superUser: { id: 1, user_code: 1, userCode: 1, role: 'super_user' },
  manager: { id: 20001, user_code: 20001, userCode: 20001, role: 'site_manager' },
};

let db;
let server;
let baseUrl;
let savedHooks;
let consoleErrors;

function installFakeDb() {
  db = { log: [], liveUsers: new Set([20004, 20005, 1, 20001]), insertFailures: [], devices: [], nextId: 900, extra: [] };
  const run = async (text, params = []) => {
    const sql = norm(text);
    db.log.push({ sql, params });
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return ok();
    if (/^SELECT user_code FROM users WHERE user_code = \$1 AND deleted_at IS NULL AND is_active = TRUE FOR KEY SHARE$/.test(sql)) {
      return ok(db.liveUsers.has(params[0]) ? [{ user_code: params[0] }] : []);
    }
    if (/^DELETE FROM push_devices WHERE fcm_token = \$1 AND NOT \(user_code = \$2 AND install_id = \$3\)$/.test(sql)) return ok([], 0);
    if (/^INSERT INTO push_devices \(user_code, install_id, platform, fcm_token, app_version, notifications_enabled\)/.test(sql)) {
      const failure = db.insertFailures.shift();
      if (failure) throw Object.assign(new Error(`duplicate key value violates unique constraint "uq_push_devices_token"`), { code: failure, detail: `Key (fcm_token)=(${params[3]}) already exists.` });
      db.nextId += 1;
      return ok([{ id: String(db.nextId) }]);
    }
    if (/^SELECT pg_advisory_xact_lock\(\$1::int, \$2::int\)$/.test(sql)) return ok([{ pg_advisory_xact_lock: '' }]);
    if (/^DELETE FROM push_devices WHERE id IN \( SELECT id FROM push_devices WHERE id = ANY\(ARRAY\(SELECT id FROM push_devices WHERE user_code = \$1 ORDER BY last_seen_at DESC, id DESC OFFSET \$2\)\) ORDER BY id FOR UPDATE \)$/.test(sql)) return ok([], 0);
    if (/^DELETE FROM push_devices WHERE user_code = \$1 AND install_id = \$2$/.test(sql)) return ok([], params[0] === 20004 && params[1] === INSTALL ? 1 : 0);
    if (/^SELECT install_id, platform, app_version, last_seen_at FROM push_devices WHERE user_code = \$1 ORDER BY last_seen_at DESC, id DESC$/.test(sql)) {
      return ok([{ install_id: INSTALL, platform: 'android', app_version: '1.0.0', last_seen_at: new Date('2026-10-17T08:00:00Z'), fcm_token: TOKEN }]);
    }
    if (/^SELECT id, fcm_token FROM push_devices WHERE user_code = \$1 AND notifications_enabled/.test(sql)) return ok(db.devices);
    if (/^(UPDATE|DELETE FROM) push_devices/.test(sql)) return ok([], 1);
    for (const [pattern, answer] of db.extra) if (pattern.test(sql)) return typeof answer === 'function' ? answer(sql, params) : answer;
    throw new Error(`BEKLENMEYEN SQL (sahte DB katı): ${sql.slice(0, 160)}`);
  };
  pool.query = async (text, params) => run(text, params);
  pool.connect = async () => ({ query: run, release() {} });
}

const LIMITERS = new Set([pushRegisterLimiter, pushDeviceReadLimiter, pushTestLimiter, pushStatusLimiter]);
const ORIGINAL_CHAINS = pushRouter.stack
  .filter((layer) => layer.route)
  .map((layer) => ({ path: layer.route.path, method: Object.keys(layer.route.methods)[0], handles: layer.route.stack.map((entry) => entry.handle) }));

describe('rota zinciri', () => {
  it('her uç authRequired ile başlar; süper ucu requireSuperUser; hız sınırlayıcıları sözleşmedeki gibi', () => {
    const byKey = Object.fromEntries(ORIGINAL_CHAINS.map((chain) => [`${chain.method.toUpperCase()} ${chain.path}`, chain.handles]));
    assert.deepEqual(Object.keys(byKey).sort(), [
      'DELETE /app/push/devices/:installId',
      'GET /admin/push/status',
      'GET /app/push/devices',
      'POST /app/push/test',
      'PUT /app/push/devices',
    ]);
    for (const handles of Object.values(byKey)) assert.equal(handles[0], authRequired);
    assert.equal(byKey['PUT /app/push/devices'][1], pushRegisterLimiter);
    assert.equal(byKey['POST /app/push/test'][1], pushTestLimiter);
    assert.deepEqual(byKey['GET /admin/push/status'].slice(0, 3), [authRequired, requireSuperUser, pushStatusLimiter]);
  });
});

before(async () => {
  for (const layer of pushRouter.stack) {
    if (!layer.route) continue;
    layer.route.stack[0].handle = (req, _res, next) => {
      req.authUser = JSON.parse(decodeURIComponent(req.headers['x-test-user']));
      next();
    };
    for (const entry of layer.route.stack) {
      if (LIMITERS.has(entry.handle)) entry.handle = (_req, _res, next) => next();
    }
  }
  const app = express();
  app.use(express.json());
  app.use(pushRouter);
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.closeAllConnections?.();
  await new Promise((resolve) => server.close(resolve));
});

beforeEach(() => {
  installFakeDb();
  savedHooks = { ...pushDeviceHooks };
  resetDeadTokenGuard();
  resetPushQueueState();
  consoleErrors = [];
  mock.method(console, 'error', (...args) => consoleErrors.push(args.map((a) => (a instanceof Error ? `${a.message} ${a.stack} ${a.detail ?? ''}` : String(a))).join(' ')));
});

afterEach(() => {
  Object.assign(pushDeviceHooks, savedHooks);
  setPushRuntimeForTests(null);
  delete pool.query;
  delete pool.connect;
  mock.restoreAll();
});

async function call(method, path, user, body) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: { 'content-type': 'application/json', 'x-test-user': encodeURIComponent(JSON.stringify(user)) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null, text, cache: response.headers.get('cache-control') };
}

const register = (user = users.resident, extra = {}) =>
  call('PUT', '/app/push/devices', user, { install_id: INSTALL, platform: 'android', token: TOKEN, app_version: '1.0.0', notifications_enabled: true, ...extra });

describe('PUT /app/push/devices', () => {
  it('kayıt: kullanıcı KEY SHARE kilidi -> kullanıcı cihaz kilidi (advisory "PUSH", user_code) -> devir silmesi -> UPSERT -> 10 cihaz sınırı (id sıralı kilit), tek işlem; yanıt { ok, device_id, push_available } (jeton YOK)', async () => {
    const response = await register();
    assert.equal(response.status, 200);
    assert.deepEqual(response.body, { ok: true, device_id: 901, push_available: false });
    assert.ok(!response.text.includes(TOKEN));
    assert.equal(response.cache, 'no-store');
    const steps = db.log.map((q) => q.sql.slice(0, 40));
    assert.deepEqual(
      db.log.map((q) => q.sql.split(' ')[0]),
      ['BEGIN', 'SELECT', 'SELECT', 'DELETE', 'INSERT', 'DELETE', 'COMMIT'],
      steps.join(' | '),
    );
    assert.deepEqual(db.log[1].params, [20004]);
    assert.equal(db.log[2].sql, 'SELECT pg_advisory_xact_lock($1::int, $2::int)');
    assert.deepEqual(db.log[2].params, [PUSH_DEVICE_LOCK_CLASS, 20004], 'aynı kullanıcının eşzamanlı kayıtları sıraya girer (10 cihaz yarışı)');
    assert.equal(PUSH_DEVICE_LOCK_CLASS, 0x50555348, 'sınıf "PUSH" (duyuru kilitlerinin "ANNC" sınıfından ayrı)');
    assert.ok(PUSH_DEVICE_LOCK_CLASS > 0 && PUSH_DEVICE_LOCK_CLASS < 2 ** 31);
    assert.deepEqual(db.log[3].params, [TOKEN, 20004, INSTALL], 'aynı jeton BAŞKA kullanıcı / kurulumdaysa o satır silinir (cihaz devri)');
    const upsert = db.log[4];
    assert.deepEqual(upsert.params, [20004, INSTALL, 'android', TOKEN, '1.0.0', true]);
    for (const fragment of ['ON CONFLICT (user_code, install_id) DO UPDATE SET', 'fcm_token = EXCLUDED.fcm_token', 'last_seen_at = NOW()', 'failure_count = 0', 'COALESCE($6::BOOLEAN, push_devices.notifications_enabled)']) {
      assert.ok(upsert.sql.includes(fragment), fragment);
    }
    assert.deepEqual(db.log[5].params, [20004, 10], 'kullanıcı başına en çok 10 cihaz (en eski last_seen_at düşer)');
    assert.match(db.log[5].sql, /ORDER BY id FOR UPDATE \)$/, 'kırpılacak satırlar id sırasıyla kilitlenir');
  });

  it('push açık ve yapılandırılmışsa push_available: true; kapalıyken de KAYDEDER', async () => {
    pushDeviceHooks.available = () => true;
    assert.equal((await register()).body.push_available, true);
    pushDeviceHooks.available = () => false;
    const off = await register();
    assert.equal(off.status, 200);
    assert.equal(off.body.push_available, false);
  });

  it('silinmiş / pasif hesap (kilit satır döndürmez) -> 401 ACCOUNT_DELETED; jeton YAZILMAZ', async () => {
    db.liveUsers.delete(20004);
    const response = await register();
    assert.deepEqual([response.status, response.body.code], [401, 'ACCOUNT_DELETED']);
    assert.ok(!db.log.some((q) => /^INSERT/.test(q.sql)));
    assert.ok(db.log.some((q) => q.sql === 'ROLLBACK'));
  });

  it('23505 yarışı (aynı jeton eşzamanlı başka kullanıcıda): TEK yeniden deneme; ikinci kez de olursa 500 errorId, günlükte jeton YOK', async () => {
    db.insertFailures.push('23505');
    const retried = await register();
    assert.equal(retried.status, 200);
    assert.equal(db.log.filter((q) => q.sql === 'BEGIN').length, 2);
    db.log.length = 0;
    db.insertFailures.push('23505', '23505');
    const failed = await register();
    assert.equal(failed.status, 500);
    assert.ok(failed.body.errorId);
    assert.ok(!failed.text.includes(TOKEN));
    assert.equal(db.log.filter((q) => q.sql === 'BEGIN').length, 2, 'en çok bir yeniden deneme');
    assert.ok(consoleErrors.length > 0);
    assert.ok(consoleErrors.every((line) => !line.includes(TOKEN)), 'günlükte kayıt jetonu yok');
  });

  it('54000 (dizin satır sınırını aşan çok uzun jeton) -> 400 INVALID_BODY', async () => {
    db.insertFailures.push('54000');
    const response = await register();
    assert.deepEqual([response.status, response.body.code], [400, 'INVALID_BODY']);
  });

  it('doğrulama: 400 INVALID_BODY, Türkçe mesaj, alan adı / jeton yok; DB\'ye hiç gidilmez', async () => {
    for (const extra of [{ install_id: 'kisa' }, { platform: 'windows' }, { token: 'kisa' }, { token: `${TOKEN} bosluk` }, { app_version: 'x'.repeat(40) }, { notifications_enabled: 'evet' }]) {
      const response = await register(users.resident, extra);
      assert.equal(response.status, 400, JSON.stringify(extra));
      assert.equal(response.body.code, 'INVALID_BODY');
      assert.doesNotMatch(response.body.error, /_|token|install/);
      assert.ok(!response.text.includes(TOKEN));
    }
    assert.equal(db.log.length, 0);
  });
});

describe('DELETE / GET /app/push/devices', () => {
  it('DELETE yalnız ÇAĞIRANIN satırı (IDOR yok: başkasının install_id\'si 0 satır) ve idempotent { ok: true }', async () => {
    assert.deepEqual((await call('DELETE', `/app/push/devices/${INSTALL}`, users.resident)).body, { ok: true });
    assert.deepEqual(db.log.at(-1).params, [20004, INSTALL]);
    const other = await call('DELETE', `/app/push/devices/${INSTALL}`, users.other);
    assert.deepEqual([other.status, other.body], [200, { ok: true }]);
    assert.deepEqual(db.log.at(-1).params, [20005, INSTALL], 'sorgu çağıranın kodunu taşır; başkasının satırına dokunamaz');
    assert.deepEqual((await call('DELETE', `/app/push/devices/${INSTALL}`, users.resident)).body, { ok: true }, 'ikinci silme de ok');
    const bad = await call('DELETE', '/app/push/devices/kisa', users.resident);
    assert.deepEqual([bad.status, bad.body.code], [400, 'INVALID_BODY']);
  });

  it('GET: { items: [{ install_id, platform, app_version, last_seen_at }] }; jeton SEÇİLMEZ ve dönmez', async () => {
    const response = await call('GET', '/app/push/devices', users.resident);
    assert.deepEqual(response.body, { items: [{ install_id: INSTALL, platform: 'android', app_version: '1.0.0', last_seen_at: '2026-10-17T08:00:00.000Z' }] });
    assert.ok(!response.text.includes(TOKEN));
    assert.doesNotMatch(db.log.at(-1).sql, /fcm_token/);
    assert.deepEqual(db.log.at(-1).params, [20004]);
  });
});

describe('POST /app/push/test', () => {
  it('push hazır değil -> 503 PUSH_UNAVAILABLE ("Telefon bildirimi şu an kullanılamıyor."); DB / FCM yok', async () => {
    const response = await call('POST', '/app/push/test', users.resident, {});
    assert.deepEqual([response.status, response.body.code, response.body.error], [503, 'PUSH_UNAVAILABLE', 'Telefon bildirimi şu an kullanılamıyor.']);
    assert.equal(db.log.length, 0);
  });

  it('hazır: çağıranın izinli cihazlarına doğrudan (outbox dışı) GENEL test bildirimi; ölü jeton silinir; { ok, sent, failed }', async () => {
    const sent = [];
    pushDeviceHooks.available = () => true;
    pushDeviceHooks.client = () => ({
      send: async (message) => {
        sent.push(message);
        return message.token.endsWith('ölü') ? { kind: 'dead', code: 'UNREGISTERED' } : { kind: 'ok' };
      },
    });
    db.devices = [{ id: '7', fcm_token: TOKEN }, { id: '8', fcm_token: `${TOKEN}-ölü` }];
    const response = await call('POST', '/app/push/test', users.resident, {});
    assert.deepEqual(response.body, { ok: true, sent: 1, failed: 1 });
    assert.ok(!response.text.includes(TOKEN));
    assert.deepEqual(sent.map((m) => m.notification.title), ['Test bildirimi', 'Test bildirimi']);
    assert.ok(sent.every((m) => JSON.stringify(m.data) === '{"type":"test"}'));
    const del = db.log.find((q) => /^DELETE FROM push_devices d USING unnest/.test(q.sql));
    assert.deepEqual(del.params, [[8], [`${TOKEN}-ölü`]]);
    assert.ok(!db.log.some((q) => /push_outbox/.test(q.sql)), 'outbox dışı');
    assert.ok(consoleErrors.every((line) => !line.includes(TOKEN)));
  });

  it('2. tur Y1: bu hizmet hesabıyla henüz BAŞARI görülmemişken (canlıya almadaki ilk test yanlış projenin hesabıyla) ölü sonuç cihaz SİLDİRMEZ; failure_count artmaz; sonra başarı görülünce silinir', async () => {
    pushDeviceHooks.available = () => true;
    pushDeviceHooks.account = () => null;
    pushDeviceHooks.client = () => ({ send: async () => ({ kind: 'dead', code: 'SENDER_ID_MISMATCH' }) });
    db.devices = [{ id: '7', fcm_token: TOKEN }, { id: '8', fcm_token: `${TOKEN}-2` }];
    const response = await call('POST', '/app/push/test', users.resident, {});
    assert.deepEqual(response.body, { ok: false, sent: 0, failed: 2 });
    assert.equal(db.log.some((q) => /^DELETE FROM push_devices/.test(q.sql)), false, 'silme yok');
    assert.equal(db.log.some((q) => /failure_count = LEAST/.test(q.sql)), false, 'failure_count artmaz');
    const note = db.log.find((q) => /^UPDATE push_devices d SET last_error_code = v\.code/.test(q.sql));
    assert.deepEqual(note.params, [[7, 8], ['SENDER_ID_MISMATCH', 'SENDER_ID_MISMATCH']]);
    // aynı hizmet hesabıyla bir başarı görüldükten sonra ölü jeton silinir
    pushDeviceHooks.client = () => ({ send: async (message) => (message.token === TOKEN ? { kind: 'ok' } : { kind: 'dead', code: 'UNREGISTERED' }) });
    db.log.length = 0;
    assert.deepEqual((await call('POST', '/app/push/test', users.resident, {})).body, { ok: true, sent: 1, failed: 1 });
    assert.deepEqual(db.log.find((q) => /^DELETE FROM push_devices d USING unnest/.test(q.sql)).params, [[8], [`${TOKEN}-2`]]);
  });

  it('cihaz yoksa { ok: false, sent: 0, failed: 0 }', async () => {
    pushDeviceHooks.available = () => true;
    pushDeviceHooks.client = () => ({ send: async () => ({ kind: 'ok' }) });
    assert.deepEqual((await call('POST', '/app/push/test', users.resident, {})).body, { ok: false, sent: 0, failed: 0 });
  });
});

describe('GET /admin/push/status', () => {
  it('yalnız süper kullanıcı (yönetici / sakin 403); gövde sözleşme alanları, sır / jeton yok', async () => {
    for (const user of [users.resident, users.manager]) {
      assert.equal((await call('GET', '/admin/push/status', user)).status, 403);
    }
    db.extra.push([/^SELECT \(SELECT COUNT\(\*\)::INTEGER FROM push_devices\) AS devices_total/, ok([{ devices_total: 4, pending: 2, sent_24h: 9, failed_24h: 1, last_outbox_error: 'UNAVAILABLE', last_success_at: new Date('2026-10-17T07:00:00Z') }])]);
    setPushRuntimeForTests({ enabled: false, configured: true, account: { projectId: 'siteyonetim-f6aca' } });
    const response = await call('GET', '/admin/push/status', users.superUser);
    assert.deepEqual(response.body, {
      enabled: false,
      configured: true,
      project_id: 'siteyonetim-f6aca',
      devices_total: 4,
      pending: 2,
      sent_24h: 9,
      failed_24h: 1,
      last_error_code: 'UNAVAILABLE',
      last_success_at: '2026-10-17T07:00:00.000Z',
    });
    assert.equal(response.cache, 'no-store');
  });
});

describe('hız sınırları (bellek içi limiter, doğrudan)', () => {
  function hit(limiter, user, times) {
    let last = null;
    for (let i = 0; i < times; i += 1) {
      const res = {
        statusCode: 200,
        headers: {},
        setHeader(name, value) {
          this.headers[name] = value;
        },
        status(code) {
          this.statusCode = code;
          return this;
        },
        json(body) {
          this.body = body;
          return this;
        },
      };
      let passed = false;
      limiter({ authUser: user, ip: '203.0.113.9', socket: {}, headers: {} }, res, () => {
        passed = true;
      });
      last = { passed, res };
    }
    return last;
  }

  it('cihaz kaydı 60/saat/kullanıcı: 61. istek 429 + Retry-After; başka kullanıcı etkilenmez', () => {
    pushRegisterLimiter.reset();
    assert.equal(hit(pushRegisterLimiter, users.resident, 60).passed, true);
    const blocked = hit(pushRegisterLimiter, users.resident, 1);
    assert.equal(blocked.passed, false);
    assert.equal(blocked.res.statusCode, 429);
    assert.ok(Number(blocked.res.headers['Retry-After']) > 0);
    assert.equal(hit(pushRegisterLimiter, users.other, 1).passed, true);
    pushRegisterLimiter.reset();
  });

  it('test bildirimi 5/gün/kullanıcı', () => {
    pushTestLimiter.reset();
    assert.equal(hit(pushTestLimiter, users.resident, 5).passed, true);
    const blocked = hit(pushTestLimiter, users.resident, 1);
    assert.equal(blocked.res.statusCode, 429);
    assert.ok(Number(blocked.res.headers['Retry-After']) > 23 * 3600, 'pencere 24 saat');
    pushTestLimiter.reset();
  });
});
