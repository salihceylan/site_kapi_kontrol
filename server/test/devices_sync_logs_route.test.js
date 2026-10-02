import { afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { pool } from '../src/db.js';
import { doorLogRouter, syncDeviceLogsHandler } from '../src/routes/door_log_routes.js';
import { resetDoorLogSchemaStateForTests } from '../src/services/door_log_service.js';

const flat = (sql) => String(sql).replace(/\s+/g, ' ').trim();

const NOW_MS = Date.now();
const NOW_SEC = Math.floor(NOW_MS / 1000);

const DEVICE = {
  id: 7,
  device_uid: 'D4C771A172E0',
  site_code: 1234567890,
  assigned_door_id: 55,
  assigned_door_site_code: 1234567890,
};

function entry(overrides = {}) {
  return {
    client_log_id: `D4C771A172E0-1-${Math.floor(Math.random() * 1e9)}`,
    epoch: NOW_SEC - 30,
    trigger_type: 'local_wifi',
    user_name: 'Yerel Kullanici',
    ...overrides,
  };
}

function fakeRes() {
  const res = {
    statusCode: 200,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
  return res;
}

function fakeReq({ body = {}, headers = {}, authUser, ip = '203.0.113.9' } = {}) {
  return { body, headers, authUser, ip };
}

// Sahte veritabani: SQL metnine gore yanit verir.
function installFakeDb(config = {}) {
  const settings = {
    device: DEVICE,
    managerAccess: false,
    ownerAccess: false,
    accessibleDoors: [],
    failInsert: false,
    ...config,
  };
  const state = { inserts: [], accessCalls: 0 };
  const seenKeys = new Set();

  pool.query = async (sql, params) => {
    const text = flat(sql);
    if (/devices\.device_uid = \$1/.test(text) && /door\.site_code AS assigned_door_site_code/.test(text)) {
      return settings.device && params[0] === settings.device.device_uid
        ? { rowCount: 1, rows: [settings.device] }
        : { rowCount: 0, rows: [] };
    }
    if (/FROM site_manager_sites WHERE site_code = \$1 AND manager_user_code = \$2/.test(text)) {
      state.accessCalls += 1;
      return { rowCount: settings.managerAccess ? 1 : 0, rows: [] };
    }
    if (/FROM site_memberships WHERE site_code = \$1 AND user_code = \$2/.test(text)) {
      state.accessCalls += 1;
      return { rowCount: settings.ownerAccess ? 1 : 0, rows: [] };
    }
    if (/^SELECT DISTINCT d\.id/.test(text)) {
      state.accessCalls += 1;
      return { rowCount: settings.accessibleDoors.length, rows: settings.accessibleDoors };
    }
    if (/FROM devices d LEFT JOIN site_doors sd/.test(text)) {
      return {
        rowCount: 1,
        rows: [{
          id: DEVICE.id,
          device_site_code: DEVICE.site_code,
          gate_name: 'Kapi',
          door_id: DEVICE.assigned_door_id,
          door_name: 'Ana Kapi',
          door_site_code: DEVICE.assigned_door_site_code,
        }],
      };
    }
    throw new Error(`beklenmeyen pool.query: ${text.slice(0, 60)}`);
  };

  pool.connect = async () => ({
    async query(sql, params) {
      const text = flat(sql);
      if (/^INSERT INTO door_access_logs/.test(text)) {
        if (settings.failInsert) {
          throw new Error('SECRET_DB_DETAIL relation "door_access_logs" is broken');
        }
        state.inserts.push(params);
        const key = `${params[9]}|${params[10]}`;
        if (seenKeys.has(key)) {
          return { rowCount: 0, rows: [] };
        }
        seenKeys.add(key);
        return { rowCount: 1, rows: [{ id: seenKeys.size }] };
      }
      return { rowCount: 0, rows: [] };
    },
    release() {},
  });

  return state;
}

describe('devices: POST /device/sync-logs', () => {
  beforeEach(() => {
    resetDoorLogSchemaStateForTests();
  });

  afterEach(() => {
    delete pool.query;
    delete pool.connect;
  });

  it('router JWT (authRequired) ile korunur: Authorization yoksa 401', async () => {
    const layer = doorLogRouter.stack.find((item) => item.route?.path === '/device/sync-logs');
    assert.ok(layer, 'rota tanimli olmali');
    assert.equal(layer.route.methods.post, true);
    const handlers = layer.route.stack.map((item) => item.name);
    assert.equal(handlers.length, 2, 'authRequired + handler');
    assert.equal(handlers[0], 'authRequired');

    // authRequired Authorization basligi olmadan DB'ye gitmeden 401 doner
    const res = fakeRes();
    let nextCalled = false;
    await layer.route.stack[0].handle(fakeReq({ headers: {} }), res, () => {
      nextCalled = true;
    });
    assert.equal(res.statusCode, 401);
    assert.equal(nextCalled, false);
  });

  it('device_uid yoksa 400 (govde veya X-AHBU-Device-UID basligi)', async () => {
    installFakeDb();
    const res = fakeRes();
    await syncDeviceLogsHandler(fakeReq({ body: { logs: [] }, authUser: { role: 'super_user', id: 1 } }), res);
    assert.equal(res.statusCode, 400);
  });

  it('logs dizi degilse 400', async () => {
    installFakeDb();
    const res = fakeRes();
    await syncDeviceLogsHandler(
      fakeReq({ body: { device_uid: 'D4C771A172E0', logs: 'x' }, authUser: { role: 'super_user', id: 1 } }),
      res,
    );
    assert.equal(res.statusCode, 400);
  });

  it('200 kayittan fazlasi 413 TOO_MANY_LOGS; icerik uzunlugu siniri 413', async () => {
    installFakeDb();
    const tooMany = fakeRes();
    await syncDeviceLogsHandler(
      fakeReq({
        body: { device_uid: 'D4C771A172E0', logs: Array.from({ length: 201 }, () => entry()) },
        authUser: { role: 'super_user', id: 1 },
      }),
      tooMany,
    );
    assert.equal(tooMany.statusCode, 413);
    assert.equal(tooMany.body.code, 'TOO_MANY_LOGS');

    const tooBig = fakeRes();
    await syncDeviceLogsHandler(
      fakeReq({
        body: { device_uid: 'D4C771A172E0', logs: [] },
        headers: { 'content-length': String(300 * 1024) },
        authUser: { role: 'super_user', id: 1 },
      }),
      tooBig,
    );
    assert.equal(tooBig.statusCode, 413);
    assert.equal(tooBig.body.code, 'PAYLOAD_TOO_LARGE');
  });

  it('kayitli olmayan cihaz: 404', async () => {
    installFakeDb({ device: null });
    const res = fakeRes();
    await syncDeviceLogsHandler(
      fakeReq({ body: { device_uid: 'D4C771A172E0', logs: [entry()] }, authUser: { role: 'super_user', id: 1 } }),
      res,
    );
    assert.equal(res.statusCode, 404);
  });

  it('yetkisiz kullanici (yonetici degil, kapiya erisimi yok): 403 ve hicbir sey yazilmaz', async () => {
    const state = installFakeDb({ managerAccess: false, ownerAccess: false, accessibleDoors: [] });
    const res = fakeRes();
    await syncDeviceLogsHandler(
      fakeReq({
        body: { device_uid: 'D4C771A172E0', logs: [entry()] },
        authUser: { role: 'individual', id: 22222, user_code: 22222 },
      }),
      res,
    );
    assert.equal(res.statusCode, 403);
    assert.equal(state.inserts.length, 0);
  });

  it('baska cihazin kapisina erisimi olan kullanici: 403', async () => {
    const state = installFakeDb({ accessibleDoors: [{ id: 99, assigned_device_id: 8 }] });
    const res = fakeRes();
    await syncDeviceLogsHandler(
      fakeReq({
        body: { device_uid: 'D4C771A172E0', logs: [entry()] },
        authUser: { role: 'apartment_owner', id: 22222, user_code: 22222 },
      }),
      res,
    );
    assert.equal(res.statusCode, 403);
    assert.equal(state.inserts.length, 0);
  });

  it('super_user: gercek sayilar doner (synced/duplicate/rejected) ve tekrar gonderim idempotent', async () => {
    const state = installFakeDb();
    const logs = [
      entry({ client_log_id: 'D4C771A172E0-1-1' }),
      entry({ client_log_id: 'D4C771A172E0-1-2' }),
      entry({ trigger_type: 'bogus' }),
    ];
    const first = fakeRes();
    await syncDeviceLogsHandler(
      fakeReq({ body: { device_uid: 'D4C771A172E0', logs }, authUser: { role: 'super_user', id: 1 } }),
      first,
    );
    assert.equal(first.statusCode, 200);
    assert.deepEqual(first.body, { ok: true, synced_count: 2, duplicate_count: 0, rejected_count: 1 });
    assert.equal(state.accessCalls, 0, 'super_user icin ek yetki sorgusu gerekmez');

    const second = fakeRes();
    await syncDeviceLogsHandler(
      fakeReq({ body: { device_uid: 'D4C771A172E0', logs }, authUser: { role: 'super_user', id: 1 } }),
      second,
    );
    assert.deepEqual(second.body, { ok: true, synced_count: 0, duplicate_count: 2, rejected_count: 1 });
  });

  it('geriye donuk uyum: device_uid yalnizca X-Ahbu-Device-Uid basliginda gelirse kabul edilir', async () => {
    const state = installFakeDb();
    const res = fakeRes();
    await syncDeviceLogsHandler(
      fakeReq({
        body: { logs: [entry({ client_log_id: undefined })] },
        headers: { 'x-ahbu-device-uid': 'd4c771a172e0' },
        authUser: { role: 'super_user', id: 1 },
      }),
      res,
    );
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.synced_count, 1);
    assert.equal(state.inserts[0][9], 'D4C771A172E0');
  });

  it('uygulamanin mevcut alanlari (opened_at ISO, user_label, user_role) kabul edilir', async () => {
    const state = installFakeDb();
    const res = fakeRes();
    await syncDeviceLogsHandler(
      fakeReq({
        body: {
          device_uid: 'D4C771A172E0',
          logs: [{
            trigger_type: 'offline_sync',
            user_label: 'Mobil Kullanici',
            user_role: 'apartment_owner',
            apartment_label: 'A-3',
            opened_at: new Date(NOW_MS - 60000).toISOString(),
          }],
        },
        authUser: { role: 'super_user', id: 1 },
      }),
      res,
    );
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.synced_count, 1);
    assert.equal(state.inserts[0][3], 'Mobil Kullanici');
    assert.equal(state.inserts[0][8], '203.0.113.9', 'uygulama kaynaginda ip adresi etiketi');
  });

  it('site yoneticisi (site_manager_sites): 200', async () => {
    installFakeDb({ managerAccess: true });
    const res = fakeRes();
    await syncDeviceLogsHandler(
      fakeReq({
        body: { device_uid: 'D4C771A172E0', logs: [entry()] },
        authUser: { role: 'site_manager', id: 11111, user_code: 11111 },
      }),
      res,
    );
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.synced_count, 1);
  });

  it('cihazin kapisina erisimi olan sakin: 200', async () => {
    installFakeDb({ accessibleDoors: [{ id: 55, assigned_device_id: 7 }] });
    const res = fakeRes();
    await syncDeviceLogsHandler(
      fakeReq({
        body: { device_uid: 'D4C771A172E0', logs: [entry()] },
        authUser: { role: 'apartment_owner', id: 22222, user_code: 22222 },
      }),
      res,
    );
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.synced_count, 1);
  });

  it('DB hatasi yutulmaz: 500 doner ve hata metni sizmaz', async () => {
    installFakeDb({ failInsert: true });
    const res = fakeRes();
    const originalError = console.error;
    console.error = () => {};
    try {
      await syncDeviceLogsHandler(
        fakeReq({ body: { device_uid: 'D4C771A172E0', logs: [entry()] }, authUser: { role: 'super_user', id: 1 } }),
        res,
      );
    } finally {
      console.error = originalError;
    }
    assert.equal(res.statusCode, 500);
    assert.ok(!JSON.stringify(res.body).includes('SECRET_DB_DETAIL'));
    // 5xx sozlesmesi: genel mesaj + errorId (ayrinti yalnizca sunucu logunda)
    assert.deepEqual(Object.keys(res.body), ['error', 'errorId']);
  });
});
