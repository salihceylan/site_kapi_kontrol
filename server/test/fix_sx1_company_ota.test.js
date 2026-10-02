// SX1 duzeltme turu: sirket araci kaydi (hardware_type cikarimi, DB hatalarinin yutulmamasi, silmede tek transaction
// + MQTT ACL senkronu) ve POST /api/company/labeled-devices hiz sinirlayicisinin yetkiden ONCE calismasi. DB'siz.
import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import express from 'express';

import '../src/utils/async_errors.js';
import { pool } from '../src/db.js';
import {
  companyAccessLimiter,
  companyRouter,
  removeCompanyDeviceRecord,
  resolveCompanyHardwareType,
  syncAclAfterCompanyDelete,
  syncCompanyDeviceRecord,
} from '../src/routes/company_routes.js';
import { requireCompanyAccess } from '../src/middlewares/company_auth.js';
import { createErrorHandler } from '../src/middlewares/error_handler.js';

const read = (relative) => fs.readFileSync(fileURLToPath(new URL(relative, import.meta.url)), 'utf8');
const COMPANY_SOURCE = read('../src/routes/company_routes.js');
const SERVER_SOURCE = read('../src/server.js');
const FIRMWARE_SOURCE = read('../src/routes/firmware_routes.js');

const KEY = 'company-key-for-tests-0123456789abcdef'; // sahte test degeri
const flat = (sql) => String(sql).replace(/\s+/g, ' ').trim();

afterEach(() => {
  delete pool.query;
  delete pool.connect;
});

describe('SX1: sirket araci hardware_type cikarimi (WROOM kart OTA 403e dusmesin)', () => {
  it('chip/hardware_target/hardware_type alanlarindan: c3 -> esp32_c3, wroom -> esp32_wroom', () => {
    assert.equal(resolveCompanyHardwareType({ chip: 'ESP32-WROOM' }), 'esp32_wroom');
    assert.equal(resolveCompanyHardwareType({ chip: 'ESP32-C3' }), 'esp32_c3');
    assert.equal(resolveCompanyHardwareType({ chip: 'ESP32-C3 (QFN32) (revision v0.4)' }), 'esp32_c3');
    assert.equal(resolveCompanyHardwareType({ chip: 'ESP32-D0WD-V3' }), 'esp32_wroom');
    assert.equal(resolveCompanyHardwareType({ hardware_target: 'esp32-wroom' }), 'esp32_wroom');
    assert.equal(resolveCompanyHardwareType({ hardware_type: 'esp32_c3' }), 'esp32_c3');
    // acik hardware_type/hardware_target chip metninden ONCE okunur
    assert.equal(resolveCompanyHardwareType({ hardware_target: 'esp32-wroom', chip: 'ESP32-C3' }), 'esp32_wroom');
  });

  it('belirsiz/bos/gecersiz deger tahmin edilmez (null): genel "ESP32" C3 kartini WROOM yapmaz', () => {
    for (const body of [{}, { chip: 'ESP32' }, { chip: '' }, { chip: 'Okunmadi' }, { hardware_type: 'arduino', chip: 'ESP32' }, null, undefined]) {
      assert.equal(resolveCompanyHardwareType(body), null, JSON.stringify(body));
    }
    // gecersiz acik deger sonraki kaynaga (chip) dusebilir
    assert.equal(resolveCompanyHardwareType({ hardware_type: 'arduino', chip: 'ESP32-C3' }), 'esp32_c3');
  });
});

describe('SX1: syncCompanyDeviceRecord (POST /api/company/labeled-devices DB adimi)', () => {
  function fakeDb({ existing = false, updateRowCount = 1, failOn = null } = {}) {
    const calls = [];
    return {
      calls,
      async query(sql, params) {
        const text = flat(sql);
        calls.push({ text, params });
        if (failOn && failOn.test(text)) {
          throw new Error('connection terminated');
        }
        if (/^SELECT id FROM devices/.test(text)) {
          return { rowCount: existing ? 1 : 0, rows: existing ? [{ id: 4 }] : [] };
        }
        if (/^UPDATE devices/.test(text)) {
          return { rowCount: updateRowCount, rows: [] };
        }
        return { rowCount: 1, rows: [] };
      },
    };
  }

  it('yeni cihaz: hardware_type (WROOM) + qr_reader_enabled TRUE ile eklenir', async () => {
    const db = fakeDb();
    const result = await syncCompanyDeviceRecord(db, { deviceUid: 'D4C771A172E0', hardwareType: 'esp32_wroom' });
    assert.deepEqual(result, { created: true, hardware_type_updated: false });
    const insert = db.calls.find((call) => /^INSERT INTO devices/.test(call.text));
    assert.ok(insert);
    assert.match(insert.text, /\(device_uid, hardware_type, qr_reader_enabled, created_at\) VALUES \(\$1, \$2, TRUE, NOW\(\)\)/);
    assert.match(insert.text, /ON CONFLICT \(device_uid\) DO NOTHING/);
    assert.deepEqual(insert.params, ['D4C771A172E0', 'esp32_wroom']);
  });

  it('yeni cihaz + belirlenemeyen donanim: DB varsayilani (esp32_c3) yazilir, cihaz MQTT bildirimi duzeltir', async () => {
    const db = fakeDb();
    await syncCompanyDeviceRecord(db, { deviceUid: 'D4C771A172E0', hardwareType: null });
    const insert = db.calls.find((call) => /^INSERT INTO devices/.test(call.text));
    assert.deepEqual(insert.params, ['D4C771A172E0', 'esp32_c3']);
  });

  it('mevcut ve sahiplenilmemis kayit: tip cihazdan okunan degerle duzeltilir (sahipli satira dokunulmaz)', async () => {
    const db = fakeDb({ existing: true });
    const result = await syncCompanyDeviceRecord(db, { deviceUid: 'D4C771A172E0', hardwareType: 'esp32_wroom' });
    assert.deepEqual(result, { created: false, hardware_type_updated: true });
    assert.ok(!db.calls.some((call) => /^INSERT/.test(call.text)));
    const update = db.calls.find((call) => /^UPDATE devices/.test(call.text));
    assert.match(update.text, /SET hardware_type = \$2 WHERE UPPER\(device_uid\) = \$1 AND owner_user_id IS NULL AND hardware_type IS DISTINCT FROM \$2/);
    assert.deepEqual(update.params, ['D4C771A172E0', 'esp32_wroom']);
  });

  it('mevcut kayit + belirsiz donanim: hicbir sey degismez', async () => {
    const db = fakeDb({ existing: true });
    const result = await syncCompanyDeviceRecord(db, { deviceUid: 'D4C771A172E0', hardwareType: null });
    assert.deepEqual(result, { created: false, hardware_type_updated: false });
    assert.equal(db.calls.length, 1);
  });

  it('DB hatasi YUTULMAZ (cagiran 500 doner)', async () => {
    const db = fakeDb({ failOn: /^INSERT INTO devices/ });
    await assert.rejects(
      syncCompanyDeviceRecord(db, { deviceUid: 'D4C771A172E0', hardwareType: 'esp32_wroom' }),
      /connection terminated/,
    );
  });
});

describe('SX1: removeCompanyDeviceRecord (DELETE /api/company/labeled-devices/:uid DB adimi)', () => {
  function fakePool({ failOn = null, deleteRowCount = 1 } = {}) {
    const statements = [];
    let released = 0;
    return {
      statements,
      get released() {
        return released;
      },
      async connect() {
        return {
          async query(sql) {
            const text = flat(sql);
            statements.push(text.split(' ').slice(0, 2).join(' '));
            if (failOn && failOn.test(text)) {
              throw new Error('deadlock detected');
            }
            return { rowCount: /^DELETE/.test(text) ? deleteRowCount : 1, rows: [] };
          },
          release() {
            released += 1;
          },
        };
      },
    };
  }

  it('kapi atamasi temizleme + silme TEK transaction (BEGIN ... COMMIT) ve true doner', async () => {
    const db = fakePool();
    assert.equal(await removeCompanyDeviceRecord(db, 'D4C771A172E0'), true);
    assert.deepEqual(db.statements, ['BEGIN', 'UPDATE site_doors', 'DELETE FROM', 'COMMIT']);
    assert.equal(db.released, 1);
  });

  it('satir yoksa false (dosya temizligi yine yapilir, ACL senkronu gerekmez)', async () => {
    const db = fakePool({ deleteRowCount: 0 });
    assert.equal(await removeCompanyDeviceRecord(db, 'D4C771A172E0'), false);
  });

  it('hata: ROLLBACK, istemci serbest, hata YUTULMAZ', async () => {
    const db = fakePool({ failOn: /^DELETE FROM devices/ });
    await assert.rejects(removeCompanyDeviceRecord(db, 'D4C771A172E0'), /deadlock detected/);
    assert.ok(db.statements.includes('ROLLBACK'));
    assert.ok(!db.statements.includes('COMMIT'));
    assert.equal(db.released, 1);
  });
});

describe('SX1: syncAclAfterCompanyDelete (silinen cihazin broker kimligi iptali)', () => {
  const silenced = async (fn) => {
    const original = console.error;
    console.error = () => {};
    try {
      return await fn();
    } finally {
      console.error = original;
    }
  };

  it('senkron company_device_deleted nedeniyle calisir ve guvenli ozet doner (stdout/stderr yok)', async () => {
    const reasons = [];
    const summary = await syncAclAfterCompanyDelete(async ({ reason }) => {
      reasons.push(reason);
      return { configured: true, ok: true, skipped: false, stdout: 'GIZLI-CIKTI', stderr: 'GIZLI-HATA' };
    });
    assert.deepEqual(reasons, ['company_device_deleted']);
    assert.deepEqual(summary, { configured: true, ok: true, skipped: false, message: 'MQTT ACL senkronu tamamlandi.' });
    assert.ok(!JSON.stringify(summary).includes('GIZLI'));
  });

  it('yapilandirilmamis senkron (skipped) hata degildir; ozet skipped:true doner', async () => {
    const summary = await syncAclAfterCompanyDelete(async () => ({ configured: false, ok: false, skipped: true }));
    assert.equal(summary.ok, false);
    assert.equal(summary.skipped, true);
  });

  it('MQTT_SYNC_REQUIRED hatasi silmeyi bozmaz: firlatmaz, ok:false ozeti doner', async () => {
    const summary = await silenced(() => syncAclAfterCompanyDelete(async () => {
      const error = new Error('MQTT ACL senkronu basarisiz.');
      error.code = 'MQTT_ACL_SYNC_FAILED';
      error.syncResult = { configured: true, ok: false, skipped: false, message: 'mosquitto reload hata kodu: 1', stderr: 'GIZLI-HATA' };
      throw error;
    }));
    assert.equal(summary.ok, false);
    assert.equal(summary.configured, true);
    assert.ok(!JSON.stringify(summary).includes('GIZLI'));
  });

  it('beklenmeyen hata (syncResult yok) da firlatmaz', async () => {
    const summary = await silenced(() => syncAclAfterCompanyDelete(async () => {
      throw new Error('spawn ENOENT');
    }));
    assert.equal(summary.ok, false);
  });
});

describe('SX1: company route HTTP - DB hatasi ok:true olarak maskelenmez', () => {
  async function withApp(run) {
    const app = express();
    app.set('env', 'test');
    app.post('/api/company/labeled-devices', requireCompanyAccess, express.json({ limit: '5mb' }));
    app.use(express.json({ limit: '1mb' }));
    app.use(companyRouter);
    app.use(createErrorHandler({ logger: { error: () => {}, log: () => {}, warn: () => {} } }));
    const server = await new Promise((resolve) => {
      const s = app.listen(0, '127.0.0.1', () => resolve(s));
    });
    const savedKey = process.env.COMPANY_API_KEY;
    process.env.COMPANY_API_KEY = KEY;
    const silent = { error: console.error, warn: console.warn, log: console.log };
    console.error = () => {};
    try {
      await run(`http://127.0.0.1:${server.address().port}`);
    } finally {
      Object.assign(console, silent);
      if (savedKey === undefined) delete process.env.COMPANY_API_KEY;
      else process.env.COMPANY_API_KEY = savedKey;
      server.closeAllConnections?.();
      await new Promise((resolve) => server.close(resolve));
    }
  }

  it('POST: DB erisilemezse 500 {ok:false, db_synced:false, errorId}; DB hatasi metni sizmaz', async () => {
    pool.query = async () => {
      throw new Error('connect ECONNREFUSED 10.0.0.5:5432');
    };
    await withApp(async (baseUrl) => {
      const response = await fetch(`${baseUrl}/api/company/labeled-devices`, {
        method: 'POST',
        headers: { 'X-Company-Key': KEY, 'Content-Type': 'application/json' },
        body: JSON.stringify({ device_uid: '00861A0D5020', chip: 'ESP32-WROOM' }),
      });
      assert.equal(response.status, 500);
      const body = await response.json();
      assert.equal(body.ok, false);
      assert.equal(body.db_synced, false);
      assert.ok(body.errorId);
      assert.ok(!JSON.stringify(body).includes('ECONNREFUSED'));
    });
  });

  it('DELETE: DB hatasinda 500 (dosyalara dokunulmadan) - "basariyla silindi" donmez', async () => {
    pool.connect = async () => {
      throw new Error('too many clients already');
    };
    await withApp(async (baseUrl) => {
      const response = await fetch(`${baseUrl}/api/company/labeled-devices/00861A0D5020`, {
        method: 'DELETE',
        headers: { 'X-Company-Key': KEY },
      });
      assert.equal(response.status, 500);
      const body = await response.json();
      assert.equal(body.ok, false);
      assert.ok(!/basariyla silindi/.test(JSON.stringify(body)));
    });
  });
});

describe('SX1: kaynak korumalari (company_routes/server)', () => {
  it('POST: DB adimi dosya yazimindan ONCE, hata yutulmaz; DELETE: DB basarisindan sonra dosya silinir', () => {
    const postStart = COMPANY_SOURCE.indexOf("companyRouter.post('/api/company/labeled-devices'");
    const deleteStart = COMPANY_SOURCE.indexOf("companyRouter.delete('/api/company/labeled-devices/:deviceUid'");
    assert.ok(postStart > 0 && deleteStart > postStart);
    const postBlock = COMPANY_SOURCE.slice(postStart, deleteStart);
    assert.ok(postBlock.indexOf('syncCompanyDeviceRecord(pool') < postBlock.indexOf('writeLabeledDevices(devices)'));
    assert.ok(postBlock.indexOf('syncCompanyDeviceRecord(pool') < postBlock.indexOf('fs.writeFileSync'));
    assert.ok(!/cihaz DB kaydi basarisiz:', dbErr\);\s*\}\s*\r?\n\s*auditLog/.test(postBlock), 'DB hatasi yutulmamali');
    const deleteBlock = COMPANY_SOURCE.slice(deleteStart);
    assert.ok(deleteBlock.indexOf('removeCompanyDeviceRecord(pool') < deleteBlock.indexOf('fs.unlinkSync'));
    assert.ok(deleteBlock.indexOf('removeCompanyDeviceRecord(pool') < deleteBlock.indexOf('writeLabeledDevices(devices)'));
  });

  it('DELETE: DB satiri silindiyse broker ACL senkronu (syncAclAfterCompanyDelete) DB adiminden SONRA cagrilir', () => {
    const deleteBlock = COMPANY_SOURCE.slice(COMPANY_SOURCE.indexOf("companyRouter.delete('/api/company/labeled-devices/:deviceUid'"));
    assert.match(deleteBlock, /const mqttSync = dbRemoved \? await syncAclAfterCompanyDelete\(\) : null;/);
    assert.ok(deleteBlock.indexOf('removeCompanyDeviceRecord(pool') < deleteBlock.indexOf('syncAclAfterCompanyDelete()'));
    assert.match(COMPANY_SOURCE, /import \{ syncMqttAclOrThrow \} from '..\/mqtt_acl_sync\.js';/);
  });

  it('firmware_routes: cihaz aramasi runtime hardware_target alanini da getirir; yalniz cihaz bildirimi 403 uretir', () => {
    assert.match(FIRMWARE_SOURCE, /SELECT d\.hardware_type, r\.hardware_target/);
    assert.match(FIRMWARE_SOURCE, /LEFT JOIN device_runtime_status r ON r\.device_uid = d\.device_uid/);
    assert.match(FIRMWARE_SOURCE, /reportedTarget: knownDevice\.hardware_target/);
    assert.match(FIRMWARE_SOURCE, /if \(targetCheck\.source === 'reported'\) \{\s*return res\.status\(403\)/);
  });

  it('server.js: POST /api/company/labeled-devices hiz sinirlayicisi yetkiden ONCE', () => {
    assert.match(
      SERVER_SOURCE,
      /app\.post\('\/api\/company\/labeled-devices', companyAccessLimiter, requireCompanyAccess, express\.json\(\{ limit: '5mb' \}\)\);/,
    );
    assert.match(SERVER_SOURCE, /import \{ companyRouter, companyAccessLimiter \} from '\.\/routes\/company_routes\.js';/);
  });
});

describe('SX1: companyAccessLimiter (yetkiden once calisir, istek tek sayilir)', () => {
  it('yanlis X-Company-Key denemesi de limiter\'a sayilir (limiter -> requireCompanyAccess sirasi)', async () => {
    companyAccessLimiter.reset();
    const app = express();
    app.set('env', 'test');
    app.post('/api/company/labeled-devices', companyAccessLimiter, requireCompanyAccess, express.json({ limit: '5mb' }));
    app.use(createErrorHandler({ logger: { error: () => {}, log: () => {}, warn: () => {} } }));
    const server = await new Promise((resolve) => {
      const s = app.listen(0, '127.0.0.1', () => resolve(s));
    });
    const savedKey = process.env.COMPANY_API_KEY;
    process.env.COMPANY_API_KEY = KEY;
    try {
      assert.equal(companyAccessLimiter.size(), 0);
      const response = await fetch(`http://127.0.0.1:${server.address().port}/api/company/labeled-devices`, {
        method: 'POST',
        headers: { 'X-Company-Key': 'yanlis-anahtar', 'Content-Type': 'application/json' },
        body: '{}',
      });
      assert.equal(response.status, 401);
      assert.equal(companyAccessLimiter.size(), 1, 'yetkisiz istek de sayilmali (limiter yetkiden once)');
    } finally {
      if (savedKey === undefined) delete process.env.COMPANY_API_KEY;
      else process.env.COMPANY_API_KEY = savedKey;
      companyAccessLimiter.reset();
      server.closeAllConnections?.();
      await new Promise((resolve) => server.close(resolve));
    }
  });

  it('ayni istek zincirde iki kez gecse de TEK sayilir (300/15dk korunur, 150e dusmez)', () => {
    companyAccessLimiter.reset();
    let blockedAt = null;
    for (let i = 1; i <= 301; i += 1) {
      const req = { ip: '203.0.113.77', socket: {} };
      let status = 200;
      const res = {
        setHeader() {},
        status(code) {
          status = code;
          return this;
        },
        json() {
          return this;
        },
      };
      let passed = false;
      // server.js (app.post) + companyRouter.use: ayni req uzerinde iki kez
      companyAccessLimiter(req, res, () => {
        companyAccessLimiter(req, res, () => {
          passed = true;
        });
      });
      if (!passed) {
        blockedAt = { i, status };
        break;
      }
    }
    assert.deepEqual(blockedAt, { i: 301, status: 429 });
    companyAccessLimiter.reset();
  });
});
