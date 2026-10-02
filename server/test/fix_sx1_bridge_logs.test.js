// SX1 duzeltme turu: MQTT koprusu cihaz bildirimine gore hardware_type onarimi + herkese acik /health'te ham hata
// metni olmamasi, door_log_service sema kilidi (db.connect reddi) ve bakim sagligi (isClean/kukla sayaci). DB'siz.
import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';

import { pool } from '../src/db.js';
import { applyStatusMessage, mqttBridgeHealth } from '../src/mqtt_bridge.js';
import { firmwareRouter } from '../src/routes/firmware_routes.js';
import {
  ensureDoorLogIdempotencySchema,
  resetDoorLogSchemaStateForTests,
} from '../src/services/door_log_service.js';
import { getDatabaseHealth } from '../src/services/maintenance_service.js';

const flat = (sql) => String(sql).replace(/\s+/g, ' ').trim();
const settle = (ms = 40) => new Promise((resolve) => setTimeout(resolve, ms));

function quiet(fn) {
  return async (...args) => {
    const originals = { error: console.error, warn: console.warn, log: console.log };
    console.error = () => {};
    console.warn = () => {};
    console.log = () => {};
    try {
      return await fn(...args);
    } finally {
      Object.assign(console, originals);
    }
  };
}

afterEach(() => {
  delete pool.query;
  delete pool.connect;
});

describe('SX1: MQTT koprusu devices.hardware_type\'i cihazin kendi bildirimine gore onarir', () => {
  function installBridgeDb({ registered = true, storedType = 'esp32_c3', failUpdate = false } = {}) {
    const calls = [];
    pool.query = async (sql, params) => {
      const text = flat(sql);
      calls.push({ text, params });
      if (/^SELECT hardware_type FROM devices/.test(text)) {
        return registered ? { rowCount: 1, rows: [{ hardware_type: storedType }] } : { rowCount: 0, rows: [] };
      }
      if (/^UPDATE devices SET hardware_type/.test(text) && failUpdate) {
        throw new Error('permission denied for table devices');
      }
      return { rowCount: 1, rows: [] };
    };
    return calls;
  }
  const typeSelects = (calls) => calls.filter((call) => /^SELECT hardware_type FROM devices/.test(call.text));
  const typeUpdates = (calls) => calls.filter((call) => /^UPDATE devices SET hardware_type/.test(call.text));
  const stateMessage = (target) => JSON.stringify({ locked: true, firmware_version: '5.1.0', hardware_target: target });

  it('state: kayitli esp32_c3 ama cihaz esp32-wroom bildiriyor -> hardware_type esp32_wroom olur (bir kez)', quiet(async () => {
    const calls = installBridgeDb({ storedType: 'esp32_c3' });
    const uid = 'A1B2C3D4E5F6';
    applyStatusMessage(`device/${uid}/state`, stateMessage('esp32-wroom'), { retain: false });
    await settle();
    const updates = typeUpdates(calls);
    assert.equal(updates.length, 1);
    assert.deepEqual(updates[0].params, [uid, 'esp32_wroom']);

    // ayni bildirim tekrar gelince ek sorgu atilmaz (surec basina cihaz/tip basina bir kez)
    applyStatusMessage(`device/${uid}/state`, stateMessage('esp32-wroom'), { retain: false });
    await settle();
    assert.equal(typeSelects(calls).length, 1);
    assert.equal(typeUpdates(calls).length, 1);
  }));

  it('availability de (bellekteki hedefle) tetikler; tip zaten dogruysa UPDATE atilmaz', quiet(async () => {
    const calls = installBridgeDb({ storedType: 'esp32_wroom' });
    const uid = 'A1B2C3D4E5F7';
    applyStatusMessage(`device/${uid}/state`, stateMessage('esp32-wroom'), { retain: false });
    await settle();
    applyStatusMessage(`device/${uid}/availability`, 'online', { retain: false });
    await settle();
    assert.equal(typeSelects(calls).length, 1);
    assert.equal(typeUpdates(calls).length, 0);
  }));

  it('event mesaji da hardware_target tasir: C3 bildirimi esp32_wroom kaydini esp32_c3e duzeltir', quiet(async () => {
    const calls = installBridgeDb({ storedType: 'esp32_wroom' });
    const uid = 'A1B2C3D4E5F8';
    applyStatusMessage(
      `device/${uid}/event`,
      JSON.stringify({ event: 'ota_up_to_date', hardware_target: 'esp32-c3' }),
      { retain: false },
    );
    await settle();
    assert.deepEqual(typeUpdates(calls).map((call) => call.params), [[uid, 'esp32_c3']]);
  }));

  it('hedef bildirilmemis veya taninmayan hedef: hicbir tip sorgusu/guncellemesi yok', quiet(async () => {
    const calls = installBridgeDb();
    applyStatusMessage('device/A1B2C3D4E5F9/availability', 'online', { retain: false });
    applyStatusMessage('device/A1B2C3D4E5FA/state', stateMessage('esp32-s3'), { retain: false });
    await settle();
    assert.equal(typeSelects(calls).length, 0);
    assert.equal(typeUpdates(calls).length, 0);
  }));

  it('DB\'de kayitli olmayan cihaza dokunulmaz; kayit sonrasi bir sonraki bildirimde yeniden denenir', quiet(async () => {
    const calls = installBridgeDb({ registered: false });
    const uid = 'A1B2C3D4E5FB';
    applyStatusMessage(`device/${uid}/state`, stateMessage('esp32-wroom'), { retain: false });
    await settle();
    applyStatusMessage(`device/${uid}/state`, stateMessage('esp32-wroom'), { retain: false });
    await settle();
    assert.equal(typeUpdates(calls).length, 0);
    assert.equal(typeSelects(calls).length, 2, 'kayitsizken isaret birakilmaz (kayit sonrasi onarilabilir)');
  }));
});

describe('SX1: GET /health ham hata metnini sizdirmaz', () => {
  it('kopru DB hatasi: yalniz has_error + kisa genel kod (db_error); tablo/kolon/host metni yok', quiet(async () => {
    const secret = 'relation "devices_secret_tbl" does not exist at 10.0.0.5:5432';
    pool.query = async (sql) => {
      if (/^INSERT INTO device_runtime_status/.test(flat(sql))) {
        throw new Error(secret);
      }
      return { rowCount: 1, rows: [] };
    };
    applyStatusMessage('device/B1B2C3D4E5F6/availability', 'online', { retain: false });
    await settle();

    const health = mqttBridgeHealth();
    assert.equal(health.has_error, true);
    assert.equal(health.last_error, 'db_error');
    assert.ok(!JSON.stringify(health).includes('devices_secret_tbl'));

    // Herkese acik uc: gercek firmwareRouter, sahte DB baglantisi
    delete pool.query;
    pool.connect = async () => ({ async query() {}, release() {} });
    const app = express();
    app.use(firmwareRouter);
    const server = await new Promise((resolve) => {
      const s = app.listen(0, '127.0.0.1', () => resolve(s));
    });
    try {
      const response = await fetch(`http://127.0.0.1:${server.address().port}/health`);
      assert.equal(response.status, 200);
      const text = await response.text();
      const body = JSON.parse(text);
      assert.equal(body.ok, true);
      assert.equal(body.mqtt.has_error, true);
      assert.equal(body.mqtt.last_error, 'db_error');
      assert.ok(!text.includes('devices_secret_tbl') && !text.includes('10.0.0.5'));
    } finally {
      server.closeAllConnections?.();
      await new Promise((resolve) => server.close(resolve));
    }
  }));
});

describe('SX1: ensureDoorLogIdempotencySchema db.connect() reddi inFlight\'i kalici takmaz', () => {
  function makeDb({ failConnect = true, throwSync = false } = {}) {
    const state = { connects: 0, released: 0, fail: failConnect };
    state.db = {
      connect() {
        state.connects += 1;
        if (state.fail && throwSync) {
          throw new Error('sync boom');
        }
        if (state.fail) {
          return Promise.reject(Object.assign(new Error('timeout exceeded when trying to connect'), { code: 'ETIMEDOUT' }));
        }
        return Promise.resolve({
          async query() {
            return { rowCount: 0, rows: [] };
          },
          release() {
            state.released += 1;
          },
        });
      },
    };
    return state;
  }

  it('baglanti reddedilince FIRLATMAZ (false: dogal anahtar dedupe), sonraki cagri reddedilmis promise almaz', quiet(async () => {
    resetDoorLogSchemaStateForTests();
    const state = makeDb();
    assert.equal(await ensureDoorLogIdempotencySchema(state.db), false);
    // kisa geri cekilme icinde hemen false (ayni reddedilmis promise DEGIL) ve yeni baglanti denenmez
    assert.equal(await ensureDoorLogIdempotencySchema(state.db), false);
    assert.equal(state.connects, 1);

    // geri cekilme sonrasi DB geri geldi: sema eklenir (kalici takilma yok)
    state.fail = false;
    const realNow = Date.now;
    Date.now = () => realNow() + 60 * 1000;
    try {
      assert.equal(await ensureDoorLogIdempotencySchema(state.db), true);
    } finally {
      Date.now = realNow;
    }
    assert.equal(state.connects, 2);
    assert.equal(state.released, 1);
    resetDoorLogSchemaStateForTests();
  }));

  it('db.connect() senkron firlatsa da inFlight temizlenir', quiet(async () => {
    resetDoorLogSchemaStateForTests();
    const state = makeDb({ throwSync: true });
    assert.equal(await ensureDoorLogIdempotencySchema(state.db), false);
    state.fail = false;
    const realNow = Date.now;
    Date.now = () => realNow() + 60 * 1000;
    try {
      assert.equal(await ensureDoorLogIdempotencySchema(state.db), true);
    } finally {
      Date.now = realNow;
    }
    resetDoorLogSchemaStateForTests();
  }));

  it('es zamanli cagrilar ayni denemeyi paylasir ve hepsi false ile biter (islenmemis ret yok)', quiet(async () => {
    resetDoorLogSchemaStateForTests();
    const state = makeDb();
    const results = await Promise.all([
      ensureDoorLogIdempotencySchema(state.db),
      ensureDoorLogIdempotencySchema(state.db),
      ensureDoorLogIdempotencySchema(state.db),
    ]);
    assert.deepEqual(results, [false, false, false]);
    assert.equal(state.connects, 1);
    resetDoorLogSchemaStateForTests();
  }));
});

describe('SX1: getDatabaseHealth - kukla sayaci ve isClean', () => {
  function healthDb({ dummy = 0, pending = {} } = {}) {
    const queries = [];
    return {
      queries,
      async query(sql) {
        const text = flat(sql);
        queries.push(text);
        if (/AS total_users/.test(text)) {
          return {
            rows: [{
              total_users: 12, dummy_users: dummy, super_users: 1, site_managers: 2, individuals: 3, apartment_owners: 6,
            }],
          };
        }
        if (/AS sites_count/.test(text)) {
          return {
            rows: [{
              sites_count: 1, blocks_count: 1, apartments_count: 6, doors_count: 1, devices_count: 1,
              online_devices_count: 1, connectivity_logs_count: 5, door_logs_count: 5, qr_tokens_count: 5,
            }],
          };
        }
        if (/AS expired_qr_tokens/.test(text)) {
          return {
            rows: [{
              expired_qr_tokens: 0, expired_email_verifications: 0, old_connectivity_logs: 0, old_door_logs: 0, ...pending,
            }],
          };
        }
        return { rows: [{ executed_at: '2026-10-01T00:00:00.000Z' }] };
      },
    };
  }

  it('gercek daire sakini (@ahbu.local, daireye/uyeliğe bagli) hesaplari kukla sayilmaz: yalniz yetim hesaplar', quiet(async () => {
    const db = healthDb({ dummy: 0 });
    const health = await getDatabaseHealth(db);
    assert.equal(health.success, true);
    assert.equal(health.users.dummy, 0);
    assert.equal(health.users.real, 12, 'real = toplam - kukla');
    const userSql = db.queries.find((text) => /AS total_users/.test(text));
    assert.match(userSql, /du\.email LIKE '%@ahbu\.local'/);
    assert.match(userSql, /NOT EXISTS \(SELECT 1 FROM apartments a WHERE a\.resident_user_code = du\.user_code\)/);
    assert.match(userSql, /NOT EXISTS \(SELECT 1 FROM apartment_memberships am WHERE am\.user_code = du\.user_code\)/);
    assert.match(userSql, /NOT EXISTS \(SELECT 1 FROM site_memberships sm WHERE sm\.user_code = du\.user_code\)/);
  }));

  it('isClean yalnizca temizligin silebilecegi kayitlara baglidir (yetim hesap durumu sonsuza dek turuncu tutmaz)', quiet(async () => {
    const orphanOnly = await getDatabaseHealth(healthDb({ dummy: 3 }));
    assert.equal(orphanOnly.users.dummy, 3);
    assert.equal(orphanOnly.users.real, 9);
    assert.equal(orphanOnly.isClean, true);
    assert.deepEqual(orphanOnly.pendingCleanup, {
      expiredQrTokens: 0, expiredEmailVerifications: 0, oldConnectivityLogs: 0, oldDoorLogs: 0,
    });

    const pending = await getDatabaseHealth(healthDb({ pending: { expired_qr_tokens: 4, old_door_logs: 2 } }));
    assert.equal(pending.isClean, false);
    assert.equal(pending.pendingCleanup.expiredQrTokens, 4);
    assert.equal(pending.pendingCleanup.oldDoorLogs, 2);
  }));

  it('yanit sekli geriye uyumlu (users/structure/devices/logs/lastCleanedAt/isClean)', quiet(async () => {
    const health = await getDatabaseHealth(healthDb());
    assert.deepEqual(Object.keys(health.users).sort(), [
      'apartmentOwners', 'dummy', 'individuals', 'real', 'siteManagers', 'superUsers', 'total',
    ]);
    assert.deepEqual(Object.keys(health.structure), ['sites', 'blocks', 'apartments', 'doors']);
    assert.ok('lastCleanedAt' in health && 'isClean' in health && 'devices' in health && 'logs' in health);
  }));
});
