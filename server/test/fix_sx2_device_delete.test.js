// SX2 (device-ota-logs#8, manager_routes kismi): DELETE /manager/devices/:id sonrasi MQTT ACL/passwd senkronu.
import { describe, it, before, after, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import { pool } from '../src/db.js';
import { managerRouter } from '../src/routes/manager_routes.js';

const norm = (text) => String(text).replace(/\s+/g, ' ').trim();
const users = {
  superUser: { id: 1, user_code: 1, db_id: 1, role: 'super_user', email: 'root@example.com' },
  manager: { id: 42, user_code: 42, db_id: 7, role: 'site_manager', email: 'yonetici@example.com' },
};

describe('DELETE /manager/devices/:id: silme sonrasi broker ACL senkronu (admin silme yoluyla ayni desen)', () => {
  let server;
  let baseUrl;
  let sqls;
  let deviceExists;
  const savedEnv = {};

  before(async () => {
    for (const layer of managerRouter.stack) {
      if (layer.route?.path === '/manager/devices/:id' && layer.route.methods.delete) {
        layer.route.stack[0].handle = (req, _res, next) => {
          req.authUser = JSON.parse(req.headers['x-test-user']);
          next();
        };
      }
    }
    const app = express();
    app.use(express.json());
    app.use(managerRouter);
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(() => new Promise((resolve) => {
    delete pool.query;
    delete pool.connect;
    server.closeAllConnections?.();
    server.close(resolve);
  }));

  beforeEach(() => {
    for (const name of ['MQTT_SYNC_COMMAND', 'MQTT_SYNC_ARGS', 'MQTT_SYNC_REQUIRED']) {
      savedEnv[name] = process.env[name];
      delete process.env[name];
    }
    sqls = [];
    deviceExists = true;
    pool.query = async (text) => {
      const sql = norm(text);
      sqls.push(sql);
      if (/WHERE devices\.id = \$1/.test(sql)) {
        return deviceExists ? { rows: [{ id: 5, device_uid: 'D4C771A172E0' }], rowCount: 1 } : { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: 0 };
    };
    pool.connect = async () => ({
      query: async (text) => {
        const sql = norm(text);
        sqls.push(sql);
        return /^DELETE FROM devices/.test(sql) ? { rowCount: 1, rows: [] } : { rowCount: 0, rows: [] };
      },
      release() {},
    });
  });

  afterEach(() => {
    delete pool.query;
    delete pool.connect;
    for (const [name, value] of Object.entries(savedEnv)) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
  });

  const del = async (user = users.superUser, id = 5) => {
    const response = await fetch(`${baseUrl}/manager/devices/${id}`, {
      method: 'DELETE',
      headers: { 'x-test-user': JSON.stringify(user) },
    });
    const text = await response.text();
    return { status: response.status, body: text ? JSON.parse(text) : null };
  };

  it('senkron yapilandirilmamissa (MQTT_SYNC_COMMAND yok) silme 204 ile biter', async () => {
    const res = await del();
    assert.equal(res.status, 204);
    assert.ok(sqls.some((sql) => /^DELETE FROM devices WHERE id = \$1/.test(sql)), 'cihaz silinmeli');
  });

  it('senkron ZORUNLU ve basarisiz: cihaz silinir ama 503 + guvenli ozet doner (stdout/stderr/ham hata sizmaz)', async () => {
    process.env.MQTT_SYNC_COMMAND = '/nonexistent/sx2-no-such-command';
    process.env.MQTT_SYNC_REQUIRED = '1';
    const log = console.error;
    console.error = () => {};
    let res;
    try {
      res = await del();
    } finally {
      console.error = log;
    }
    assert.equal(res.status, 503);
    assert.equal(res.body.error, 'Cihaz silindi ama MQTT broker senkronu basarisiz.');
    assert.deepEqual(Object.keys(res.body.mqtt_sync).sort(), ['configured', 'message', 'ok', 'reason', 'skipped']);
    assert.equal(res.body.mqtt_sync.configured, true);
    assert.equal(res.body.mqtt_sync.ok, false);
    assert.equal(res.body.mqtt_sync.message, 'MQTT ACL senkronu tamamlanamadi.');
    assert.equal(JSON.stringify(res.body).includes('sx2-no-such-command'), false, 'komut yolu/ham hata sizmamali');
    assert.ok(sqls.some((sql) => /^DELETE FROM devices WHERE id = \$1/.test(sql)), 'silme senkrondan once yapilmis olmali');
  });

  it('cihaz yoksa 404 ve senkron calistirilmaz; super user degilse 403 ve silme yok', async () => {
    process.env.MQTT_SYNC_COMMAND = '/nonexistent/sx2-no-such-command';
    process.env.MQTT_SYNC_REQUIRED = '1';
    deviceExists = false;
    assert.equal((await del()).status, 404);
    assert.equal(sqls.some((sql) => /^DELETE FROM devices/.test(sql)), false);

    deviceExists = true;
    sqls.length = 0;
    assert.equal((await del(users.manager)).status, 403);
    assert.equal(sqls.some((sql) => /^DELETE FROM devices/.test(sql)), false);
  });

  it('gecersiz cihaz id 400', async () => {
    assert.equal((await del(users.superUser, 'abc')).status, 400);
  });
});
