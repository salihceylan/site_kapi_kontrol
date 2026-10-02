// SX1 duzeltme turu: cihaz JSON alanlari (hardware_type / hardware_target / owner_user_code), findDevice* SELECT
// listeleri, PATCH /admin/devices/:id kismi guncelleme, kendi parolasini /admin/users/:id ile degistirme engeli,
// /admin/sites page_size ust siniri. DB'siz (pool.query/pool.connect sahte).
import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

import { pool } from '../src/db.js';
import {
  hardwareTargetFromType,
  mapDeviceRow,
  normalizeHardwareType,
} from '../src/utils/helpers.js';
import {
  findDeviceById,
  findDeviceByUid,
  findManagedDeviceById,
  listCompanyDevices,
  listManagedDevicesForUser,
  updateDeviceDetails,
} from '../src/services/device_service.js';
import { adminRouter } from '../src/routes/admin_routes.js';

const ADMIN_SOURCE = fs.readFileSync(fileURLToPath(new URL('../src/routes/admin_routes.js', import.meta.url)), 'utf8');

const flat = (sql) => String(sql).replace(/\s+/g, ' ').trim();

afterEach(() => {
  delete pool.query;
  delete pool.connect;
});

function findRoute(method, routePath) {
  const layer = adminRouter.stack.find(
    (item) => item.route && item.route.path === routePath && item.route.methods[method],
  );
  assert.ok(layer, `${method.toUpperCase()} ${routePath} rotasi bulunamadi`);
  return layer.route;
}

async function call(method, routePath, { params = {}, body = {}, query = {} } = {}) {
  const route = findRoute(method, routePath);
  const handler = route.stack[route.stack.length - 1].handle;
  const req = {
    params,
    body,
    query,
    headers: {},
    authUser: { id: 1, user_code: 1, role: 'super_user', email: 'admin@example.test' },
  };
  const res = {
    statusCode: 200,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    setHeader() {},
    json(payload) {
      this.body = payload;
      return this;
    },
    send() {
      return this;
    },
  };
  await handler(req, res);
  return res;
}

function silence(fn) {
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

describe('SX1: donanim tipi yardimcilari ve mapDeviceRow cihaz JSON alanlari', () => {
  it('normalizeHardwareType / hardwareTargetFromType: _ ve - esdeger, taninmayan null (varsayilan uydurulmaz)', () => {
    assert.equal(normalizeHardwareType('esp32_c3'), 'esp32_c3');
    assert.equal(normalizeHardwareType('ESP32-WROOM'), 'esp32_wroom');
    assert.equal(normalizeHardwareType(' esp32-c3 '), 'esp32_c3');
    for (const bad of ['', null, undefined, 'esp32', 'arduino', 'esp32-s3']) {
      assert.equal(normalizeHardwareType(bad), null, String(bad));
    }
    assert.equal(hardwareTargetFromType('esp32_wroom'), 'esp32-wroom');
    assert.equal(hardwareTargetFromType('esp32_c3'), 'esp32-c3');
    assert.equal(hardwareTargetFromType('x'), null);
  });

  it('mapDeviceRow: hardware_type DB degeri, hardware_target yoksa tipten turetilir', () => {
    const mapped = mapDeviceRow({ id: 5, device_uid: 'D4C771A172E0', hardware_type: 'esp32_wroom' });
    assert.equal(mapped.hardware_type, 'esp32_wroom');
    assert.equal(mapped.hardware_target, 'esp32-wroom');
  });

  it('mapDeviceRow: cihazin bildirdigi hardware_target oncelikli; DB tipi aynen kalir', () => {
    const mapped = mapDeviceRow({
      id: 5, device_uid: 'D4C771A172E0', hardware_type: 'esp32_wroom', hardware_target: 'esp32-c3',
    });
    assert.equal(mapped.hardware_type, 'esp32_wroom');
    assert.equal(mapped.hardware_target, 'esp32-c3');
  });

  it('mapDeviceRow: satirda tip yoksa uydurulmaz (null) veya bildirilen hedeften turetilir', () => {
    const none = mapDeviceRow({ id: 1, device_uid: 'AA' });
    assert.equal(none.hardware_type, null);
    assert.equal(none.hardware_target, null);
    const fromTarget = mapDeviceRow({ id: 1, device_uid: 'AA', hardware_target: 'esp32-wroom' });
    assert.equal(fromTarget.hardware_type, 'esp32_wroom');
    assert.equal(fromTarget.hardware_target, 'esp32-wroom');
  });

  it('mapDeviceRow: owner_user_code (users.user_code) ve owner_user_id birlikte doner', () => {
    const owned = mapDeviceRow({ id: 1, device_uid: 'AA', owner_user_id: '12', owner_user_code: '4455' });
    assert.equal(owned.owner_user_id, 12);
    assert.equal(owned.owner_user_code, 4455);
    const free = mapDeviceRow({ id: 1, device_uid: 'AA' });
    assert.equal(free.owner_user_code, null);
    assert.equal(free.owner_user_id, null);
  });
});

describe('SX1: cihaz SELECT listeleri gercek alanlari tasir', () => {
  function captureSql(rowsFor = [{ id: 1, device_uid: 'D4C771A172E0', total_count: 1 }]) {
    const calls = [];
    pool.query = async (sql, params) => {
      calls.push({ sql: flat(sql), params });
      return { rowCount: rowsFor.length, rows: rowsFor };
    };
    return calls;
  }

  it('findDeviceByUid: hardware_type, owner_user_id, owner_user_code, is_defective secilir (sahip dali olu kalmaz)', async () => {
    const calls = captureSql();
    await findDeviceByUid('D4C771A172E0');
    const sql = calls[0].sql;
    assert.match(sql, /devices\.hardware_type/);
    assert.match(sql, /devices\.owner_user_id/);
    assert.match(sql, /owner_u\.user_code AS owner_user_code/);
    assert.match(sql, /LEFT JOIN users owner_u ON owner_u\.id = devices\.owner_user_id/);
    assert.match(sql, /devices\.is_defective/);
    assert.match(sql, /runtime\.hardware_target/);
    // yonetici aramasi (findDeviceByUid) sahip adi/e-postasi veya envanter notu SIZDIRMAZ
    assert.ok(!/owner_u\.email|owner_u\.full_name|inventory_notes/.test(sql));
  });

  it('findDeviceById (PATCH yaniti): liste ile ayni alanlar (tip, ariza, sahip, envanter notu)', async () => {
    const calls = captureSql();
    await findDeviceById(9);
    const sql = calls[0].sql;
    for (const column of [
      'devices.hardware_type', 'runtime.hardware_target', 'devices.qr_reader_enabled', 'devices.is_defective',
      'devices.defective_reason', 'devices.inventory_notes', 'devices.owner_user_id', 'devices.claimed_at',
      'owner_u.user_code AS owner_user_code', 'owner_u.full_name AS owner_full_name', 'owner_u.email AS owner_email',
    ]) {
      assert.ok(sql.includes(column), `${column} eksik`);
    }
  });

  it('listCompanyDevices: runtime.hardware_target geri eklendi ve owner_user_code secilir', async () => {
    const calls = captureSql();
    await listCompanyDevices({ page: 1, pageSize: 10 });
    const sql = calls[0].sql;
    assert.match(sql, /runtime\.hardware_target/);
    assert.match(sql, /devices\.hardware_type/);
    assert.match(sql, /u\.user_code AS owner_user_code/);
  });

  it('yonetici listesi/tekil sorgulari da owner_user_code tasir', async () => {
    const calls = captureSql();
    const authUser = { id: 7, user_code: 7, db_id: 70, role: 'site_manager' };
    await listManagedDevicesForUser(authUser);
    await findManagedDeviceById({ authUser, deviceId: 3 });
    for (const call of calls) {
      assert.match(call.sql, /owner_u\.user_code AS owner_user_code/);
      assert.match(call.sql, /LEFT JOIN users owner_u ON owner_u\.id = devices\.owner_user_id/);
    }
  });

  it('listCompanyDevices satiri mapDeviceRow ile hardware_type + hardware_target + owner_user_code uretir', async () => {
    captureSql([{
      id: 3, device_uid: 'D4C771A172E0', hardware_type: 'esp32_wroom', hardware_target: null,
      owner_user_id: 12, owner_user_code: 4455, total_count: 1,
    }]);
    const { rows } = await listCompanyDevices({ page: 1, pageSize: 10 });
    const mapped = mapDeviceRow(rows[0]);
    assert.equal(mapped.hardware_type, 'esp32_wroom');
    assert.equal(mapped.hardware_target, 'esp32-wroom');
    assert.equal(mapped.owner_user_code, 4455);
  });
});

describe('SX1: PATCH /admin/devices/:id kismi guncelleme', () => {
  function installFake() {
    const calls = [];
    pool.query = async (sql, params) => {
      const text = flat(sql);
      calls.push({ text, params });
      if (/^UPDATE devices SET assigned_user_code/.test(text)) {
        return { rowCount: 1, rows: [{ id: 5 }] };
      }
      if (/^UPDATE devices SET local_control_token/.test(text)) {
        return { rowCount: 1, rows: [{ device_uid: 'D4C771A172E0', local_control_token: params[0] }] };
      }
      if (/FROM devices LEFT JOIN site_doors door/.test(text)) {
        return {
          rowCount: 1,
          rows: [{ id: 5, device_uid: 'D4C771A172E0', hardware_type: 'esp32_wroom', site_code: 1234567890, gate_name: 'Ana Kapi' }],
        };
      }
      return { rowCount: 1, rows: [{ id: 1 }] };
    };
    return calls;
  }

  const updateCall = (calls) => calls.find((entry) => /^UPDATE devices SET assigned_user_code/.test(entry.text));

  it('yalniz hardware_type: atama alanlari korunur ($7..$9 false) ve yerel kontrol anahtari dondurulmez', silence(async () => {
    const calls = installFake();
    const res = await call('patch', '/admin/devices/:id', { params: { id: '5' }, body: { hardware_type: 'esp32_wroom' } });
    assert.equal(res.statusCode, 200);
    const update = updateCall(calls);
    assert.deepEqual(update.params, [null, null, null, null, 'esp32_wroom', 5, false, false, false]);
    assert.ok(!calls.some((entry) => /SET local_control_token/.test(entry.text)), 'tip duzeltmesi anahtar dondurmemeli');
    // yanit gercek tipi gosterir (findDeviceById artik hardware_type secer)
    assert.equal(res.body.device.hardware_type, 'esp32_wroom');
    assert.equal(res.body.device.hardware_target, 'esp32-wroom');
  }));

  it('tek alan (gate_name) gonderilince yalniz o alan degisir', silence(async () => {
    const calls = installFake();
    const res = await call('patch', '/admin/devices/:id', { params: { id: '5' }, body: { gate_name: 'Arka Kapi' } });
    assert.equal(res.statusCode, 200);
    assert.deepEqual(updateCall(calls).params, [null, null, 'Arka Kapi', null, null, 5, false, false, true]);
    assert.ok(calls.some((entry) => /SET local_control_token/.test(entry.text)), 'atama alani degisti: anahtar doner');
  }));

  it('uygulama tam govdesi (anahtarlar null olsa bile var): eski davranis, alanlar temizlenir', silence(async () => {
    const calls = installFake();
    const res = await call('patch', '/admin/devices/:id', {
      params: { id: '5' },
      body: { assigned_user_code: null, site_code: null, gate_name: null },
    });
    assert.equal(res.statusCode, 200);
    assert.deepEqual(updateCall(calls).params, [null, null, null, null, null, 5, true, true, true]);
    assert.ok(calls.some((entry) => /SET local_control_token/.test(entry.text)));
  }));

  it('updateDeviceDetails: bayraklar false ise yalniz tip/qr degisir ve anahtar dondurulmez (servis)', silence(async () => {
    const calls = installFake();
    await updateDeviceDetails({
      deviceId: 5,
      hardwareType: 'esp32_c3',
      assignedUserCodeProvided: false,
      siteCodeProvided: false,
      gateNameProvided: false,
    });
    assert.deepEqual(updateCall(calls).params, [null, null, null, null, 'esp32_c3', 5, false, false, false]);
    assert.ok(!calls.some((entry) => /SET local_control_token/.test(entry.text)));
  }));

  it('route kaynagi: gonderilen anahtarlar hasOwnProperty ile tespit edilir ve servise gecer', () => {
    assert.match(ADMIN_SOURCE, /hasField\('assigned_user_code'\)/);
    assert.match(ADMIN_SOURCE, /assignedUserCodeProvided,\s+siteCodeProvided,\s+gateNameProvided,/);
  });
});

describe('SX1: PATCH /admin/users/:id kendi parolasi', () => {
  it('kendi hesabi icin parola alani 400 USE_PROFILE_PASSWORD_CHANGE (DB sorgusu yok)', silence(async () => {
    pool.query = async () => {
      throw new Error('DB cagrilmamali');
    };
    const res = await call('patch', '/admin/users/:id', {
      params: { id: '1' },
      body: { password: 'Yeni-Parola-123' },
    });
    assert.equal(res.statusCode, 400);
    assert.equal(res.body.code, 'USE_PROFILE_PASSWORD_CHANGE');
    assert.match(res.body.error, /Profilim/);
  }));

  it('kendi hesabinda bos parola "degistirme" sayilir ve diger alanlar duzenlenebilir', silence(async () => {
    const queries = [];
    pool.query = async (sql, params) => {
      queries.push({ text: flat(sql), params });
      return {
        rowCount: 1,
        rows: [{ id: 1, user_code: 1, full_name: 'Yeni Ad Soyad', email: 'a@b.c', role: 'super_user', is_active: true, email_verified: true }],
      };
    };
    const res = await call('patch', '/admin/users/:id', {
      params: { id: '1' },
      body: { full_name: 'Yeni Ad Soyad', password: '' },
    });
    assert.equal(res.statusCode, 200);
    const update = queries.find((query) => /^UPDATE users/.test(query.text));
    assert.ok(update);
    assert.ok(!/password_hash/.test(update.text));
  }));

  it('baska kullanicinin parolasi (super user yetkisi) bu kuraldan etkilenmez', silence(async () => {
    const queries = [];
    pool.query = async (sql, params) => {
      const text = flat(sql);
      queries.push({ text, params });
      if (/^SELECT role FROM users/.test(text)) {
        return { rowCount: 1, rows: [{ role: 'site_manager' }] };
      }
      return {
        rowCount: 1,
        rows: [{ id: 2, user_code: 2, full_name: 'Yonetici Kisi', email: 'y@b.c', role: 'site_manager', is_active: true, email_verified: true }],
      };
    };
    const res = await call('patch', '/admin/users/:id', {
      params: { id: '2' },
      body: { password: 'Gecerli-Parola-123' },
    });
    assert.equal(res.statusCode, 200);
    assert.ok(queries.some((query) => /^UPDATE users/.test(query.text) && /password_hash/.test(query.text)));
  }));
});

describe('SX1: GET /admin/sites page_size ust siniri', () => {
  it('page_size=100 kirpilmaz (istemci kapi kontrolu 100 ister); 200 ustu 200e iner', silence(async () => {
    const seenLimits = [];
    pool.query = async (sql, params) => {
      const text = flat(sql);
      if (/COUNT\(\*\)/.test(text)) {
        return { rowCount: 1, rows: [{ total: 0 }] };
      }
      seenLimits.push(params?.[0]);
      return { rowCount: 0, rows: [] };
    };
    const hundred = await call('get', '/admin/sites', { query: { page_size: '100' } });
    assert.equal(hundred.statusCode, 200);
    assert.equal(hundred.body.page_size, 100);
    const huge = await call('get', '/admin/sites', { query: { page_size: '5000' } });
    assert.equal(huge.body.page_size, 200);
    assert.ok(seenLimits.includes(100) && seenLimits.includes(200), JSON.stringify(seenLimits));
  }));
});

describe('SX1: 5xx yanitlari errorId tasir ve sunucu loguna yazilir (sessiz catch yok)', () => {
  const DOOR_LOG_SOURCE = fs.readFileSync(fileURLToPath(new URL('../src/routes/door_log_routes.js', import.meta.url)), 'utf8');

  it('liste uclari DB hatasinda genel mesaj + errorId doner; ic hata metni sizmaz', silence(async () => {
    pool.query = async () => {
      throw new Error('relation "devices" column "x" does not exist');
    };
    for (const [routePath, query] of [['/admin/devices', {}], ['/admin/sites', {}], ['/admin/users', {}]]) {
      const res = await call('get', routePath, { query });
      assert.equal(res.statusCode, 500, routePath);
      assert.ok(res.body.errorId, `${routePath}: errorId yok`);
      assert.ok(!JSON.stringify(res.body).includes('does not exist'), `${routePath}: ic hata metni sizdi`);
    }
  }));

  it('admin_routes.js: hatayi yutan "catch (_error)" kalmadi', () => {
    assert.ok(!/catch \(_error\)/.test(ADMIN_SOURCE));
  });

  it('door_log_routes.js: uc 500 yaniti da errorId uretir', () => {
    assert.equal((DOOR_LOG_SOURCE.match(/const errorId = newErrorId\(\);/g) || []).length, 3);
    assert.equal((DOOR_LOG_SOURCE.match(/status\(500\)\.json\(\{ error: '[^']+', errorId \}\)/g) || []).length, 3);
  });
});
