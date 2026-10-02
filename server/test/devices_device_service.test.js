import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { pool } from '../src/db.js';
import {
  UPDATE_DEVICE_DETAILS_SQL,
  parseCompanyDeviceUid,
  registerCompanyDevice,
  releaseDeviceOwnership,
  updateDeviceDetails,
} from '../src/services/device_service.js';

const flat = (sql) => String(sql).replace(/\s+/g, ' ').trim();

function placeholders(sql) {
  return [...new Set([...String(sql).matchAll(/\$(\d+)/g)].map((m) => Number(m[1])))].sort((a, b) => a - b);
}

function patchPool({ query, connect }) {
  if (query) {
    pool.query = query;
  }
  if (connect) {
    pool.connect = connect;
  }
  return () => {
    delete pool.query;
    delete pool.connect;
  };
}

describe('devices: updateDeviceDetails SQL', () => {
  it('tek WHERE, $1..$9 ardisik ve yinelenen sutun atamasi yok', () => {
    const sql = flat(UPDATE_DEVICE_DETAILS_SQL);
    assert.deepEqual(placeholders(sql), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    assert.equal((sql.match(/\bWHERE\b/g) || []).length, 1);
    assert.equal((sql.match(/\bgate_name =/g) || []).length, 1);
    assert.equal((sql.match(/\bSET\b/g) || []).length, 1);
    assert.match(sql, /WHERE id = \$6 RETURNING id$/);
    assert.match(sql, /qr_reader_enabled = COALESCE\(\$4::boolean, qr_reader_enabled\)/);
    assert.match(sql, /hardware_type = COALESCE\(\$5::text, hardware_type\)/);
  });

  it('atama alanlari kismi guncelleme: gonderilmeyen alan mevcut degerini korur (CASE ... ELSE kolon)', () => {
    const sql = flat(UPDATE_DEVICE_DETAILS_SQL);
    assert.match(sql, /assigned_user_code = CASE WHEN \$7::boolean THEN \$1::integer ELSE assigned_user_code END/);
    assert.match(sql, /site_code = CASE WHEN \$8::boolean THEN \$2::bigint ELSE site_code END/);
    assert.match(sql, /gate_name = CASE WHEN \$9::boolean THEN \$3::text ELSE gate_name END/);
  });
});

describe('devices: updateDeviceDetails', () => {
  let restore = null;
  afterEach(() => {
    if (restore) {
      restore();
      restore = null;
    }
  });

  function installUpdateFake({ updateRowCount }) {
    const calls = [];
    restore = patchPool({
      query: async (sql, params) => {
        const text = flat(sql);
        calls.push({ text, params });
        if (/^UPDATE devices SET assigned_user_code/.test(text)) {
          return { rowCount: updateRowCount, rows: updateRowCount ? [{ id: 9 }] : [] };
        }
        if (/^UPDATE devices SET local_control_token/.test(text)) {
          return { rowCount: 1, rows: [{ device_uid: 'D4C771A172E0', local_control_token: params[0] }] };
        }
        if (/FROM devices LEFT JOIN site_doors door/.test(text)) {
          return { rowCount: 1, rows: [{ id: 9, device_uid: 'D4C771A172E0', hardware_type: 'esp32_wroom' }] };
        }
        throw new Error(`beklenmeyen sorgu: ${text.slice(0, 50)}`);
      },
    });
    return calls;
  }

  it('SQL parametre sayisi yer tutucularla eslesir ve guncellenmis cihaz doner', async () => {
    const calls = installUpdateFake({ updateRowCount: 1 });
    const device = await updateDeviceDetails({
      deviceId: 9,
      assignedUserCode: 12345,
      siteCode: 1234567890,
      gateName: 'Ana Kapi',
      qrReaderEnabled: false,
      hardwareType: 'esp32_wroom',
    });
    const updateCall = calls.find((call) => /^UPDATE devices SET assigned_user_code/.test(call.text));
    assert.ok(updateCall);
    assert.equal(updateCall.params.length, 9);
    // bayrak verilmeyen cagri eski (tam degistirme) davranisini korur: $7..$9 = true
    assert.deepEqual(updateCall.params, [12345, 1234567890, 'Ana Kapi', false, 'esp32_wroom', 9, true, true, true]);
    assert.equal(device.id, 9);
    // token rotasyonu yapildi
    assert.ok(calls.some((call) => /SET local_control_token/.test(call.text)));
  });

  it('qr_reader_enabled/hardware_type verilmezse null gecer (degismez)', async () => {
    const calls = installUpdateFake({ updateRowCount: 1 });
    await updateDeviceDetails({
      deviceId: 9,
      assignedUserCode: null,
      siteCode: null,
      gateName: null,
      qrReaderEnabled: undefined,
      hardwareType: 'bilinmeyen',
    });
    const updateCall = calls.find((call) => /^UPDATE devices SET assigned_user_code/.test(call.text));
    assert.deepEqual(updateCall.params, [null, null, null, null, null, 9, true, true, true]);
  });

  it('cihaz yoksa null doner ve token rotasyonu yapilmaz', async () => {
    const calls = installUpdateFake({ updateRowCount: 0 });
    const device = await updateDeviceDetails({
      deviceId: 404,
      assignedUserCode: null,
      siteCode: null,
      gateName: null,
    });
    assert.equal(device, null);
    assert.ok(!calls.some((call) => /local_control_token/.test(call.text)));
  });
});

describe('devices: parseCompanyDeviceUid', () => {
  it('12 haneli onaltilik; : - bosluk ayiraclari kaldirilir', () => {
    assert.equal(parseCompanyDeviceUid('D4C771A172E0'), 'D4C771A172E0');
    assert.equal(parseCompanyDeviceUid('d4:c7:71:a1:72:e0'), 'D4C771A172E0');
    assert.equal(parseCompanyDeviceUid(' d4-c7-71-a1-72-e0 '), 'D4C771A172E0');
  });

  it('gecersizler: kisa/uzun, hex olmayan, satir sonu, bos', () => {
    for (const value of ['', null, undefined, 'D4C771A172E', 'D4C771A172E00', 'G4C771A172E0', 'D4C771A172E0\nX', 'ZZZZZZZZZZZZ', '../../etc']) {
      assert.equal(parseCompanyDeviceUid(value), null, `reddedilmeli: ${JSON.stringify(value)}`);
    }
  });
});

describe('devices: registerCompanyDevice', () => {
  let restore = null;
  afterEach(() => {
    if (restore) {
      restore();
      restore = null;
    }
  });

  it('gecersiz UID: 400 ve hicbir sorgu calismaz', async () => {
    let queryCount = 0;
    restore = patchPool({
      query: async () => {
        queryCount += 1;
        return { rowCount: 0, rows: [] };
      },
    });
    for (const uid of ['D4C771', 'XYZ', 'D4C771A172E0;DROP', 'G4C771A172E0']) {
      await assert.rejects(
        registerCompanyDevice({ deviceUid: uid, authUser: { email: 'a@b.c' } }),
        (error) => error.statusCode === 400 && /UID/.test(error.message),
      );
    }
    assert.equal(queryCount, 0);
  });

  it('gecerli UID normallestirilir; MQTT parola ve token rastgele/benzersiz uretilir', async () => {
    const inserts = [];
    restore = patchPool({
      query: async (sql, params) => {
        const text = flat(sql);
        if (/^SELECT id, device_uid, hardware_type/.test(text)) {
          return { rowCount: 0, rows: [] };
        }
        if (/^INSERT INTO devices/.test(text)) {
          inserts.push(params);
          return { rowCount: 1, rows: [{ id: 1, device_uid: params[0] }] };
        }
        throw new Error(`beklenmeyen sorgu: ${text.slice(0, 40)}`);
      },
    });
    await registerCompanyDevice({ deviceUid: 'd4:c7:71:a1:72:e0', hardwareType: 'esp32_c3', authUser: { email: 'a@b.c' } });
    await registerCompanyDevice({ deviceUid: '00861A0D5020', authUser: { email: 'a@b.c' } });
    assert.equal(inserts.length, 2);
    assert.equal(inserts[0][0], 'D4C771A172E0');
    assert.equal(inserts[0][1], 'esp32_c3');
    assert.equal(inserts[0][3], 'device_D4C771A172E0');
    assert.equal(inserts[1][1], 'esp32_wroom');
    for (const params of inserts) {
      assert.match(params[4], /^[A-Za-z0-9_-]{32,}$/, 'mqtt parolasi base64url (crypto) olmali');
      assert.match(params[5], /^[A-Za-z0-9_-]{43,}$/, 'yerel kontrol anahtari base64url (crypto) olmali');
    }
    assert.notEqual(inserts[0][4], inserts[1][4]);
    assert.notEqual(inserts[0][5], inserts[1][5]);
  });

  it('kayitli cihaz: 409', async () => {
    restore = patchPool({
      query: async () => ({ rowCount: 1, rows: [{ id: 1, device_uid: 'D4C771A172E0' }] }),
    });
    await assert.rejects(
      registerCompanyDevice({ deviceUid: 'D4C771A172E0', authUser: { email: 'a@b.c' } }),
      (error) => error.statusCode === 409,
    );
  });
});

describe('devices: releaseDeviceOwnership', () => {
  let restore = null;
  afterEach(() => {
    if (restore) {
      restore();
      restore = null;
    }
  });

  it('commit sonrasi yerel kontrol anahtarini doner (onceki sahibin onbellegi gecersiz olur)', async () => {
    const clientStatements = [];
    const poolStatements = [];
    restore = patchPool({
      query: async (sql, params) => {
        const text = flat(sql);
        poolStatements.push(text);
        if (/^UPDATE devices SET local_control_token/.test(text)) {
          return { rowCount: 1, rows: [{ device_uid: 'D4C771A172E0', local_control_token: params[0] }] };
        }
        throw new Error(`beklenmeyen sorgu: ${text.slice(0, 40)}`);
      },
      connect: async () => ({
        async query(sql) {
          const text = flat(sql);
          clientStatements.push(text.split(' ').slice(0, 2).join(' '));
          if (/^SELECT id, device_uid, site_code, owner_user_id FROM devices/.test(text)) {
            return { rowCount: 1, rows: [{ id: 3, device_uid: 'D4C771A172E0', site_code: 1, owner_user_id: 8 }] };
          }
          if (/^UPDATE devices SET owner_user_id = NULL/.test(text)) {
            return { rowCount: 1, rows: [{ id: 3, device_uid: 'D4C771A172E0', hardware_type: 'esp32_wroom' }] };
          }
          return { rowCount: 1, rows: [] };
        },
        release() {},
      }),
    });

    const updated = await releaseDeviceOwnership({ deviceId: 3, authUser: { email: 'a@b.c' } });
    assert.equal(updated.device_uid, 'D4C771A172E0');
    assert.ok(clientStatements.includes('COMMIT'));
    assert.equal(poolStatements.filter((text) => /SET local_control_token/.test(text)).length, 1);
  });
});
