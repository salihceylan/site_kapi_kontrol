import { describe, it, mock, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import {
  getAccessibleDoorForUser,
  listAccessibleDoorsForUser,
  localDoorControlForStatus,
  recordDoorAccessLog,
  replaceDoorDevice,
} from '../src/services/door_service.js';

// DB'siz: pool.query / pool.connect gecici olarak sahte fonksiyonla degistirilir
function installFakePool({ query, connect } = {}) {
  const calls = [];
  pool.query = async (text, params) => {
    calls.push({ text: String(text), params });
    if (!query) {
      throw new Error('beklenmeyen pool.query');
    }
    return query(String(text), params);
  };
  if (connect) {
    pool.connect = connect;
  }
  return calls;
}

function restoreFakePool() {
  delete pool.query;
  delete pool.connect;
}

function quiet() {
  return [mock.method(console, 'log', () => {}), mock.method(console, 'warn', () => {}), mock.method(console, 'error', () => {})];
}

afterEach(() => {
  restoreFakePool();
  mock.restoreAll();
});

describe('getAccessibleDoorForUser - filtre SQL tarafinda', () => {
  it('normal kullanici: kapi id sorguya parametre olarak gider, ilk satir doner', async () => {
    const calls = installFakePool({ query: async () => ({ rows: [{ id: 5, door_name: 'Ana Kapi' }], rowCount: 1 }) });
    const door = await getAccessibleDoorForUser({ authUser: { id: 42, role: 'apartment_owner' }, doorId: '5' });
    assert.equal(door.id, 5);
    assert.equal(calls.length, 1);
    assert.match(calls[0].text, /d\.id = \$2::BIGINT/);
    assert.deepEqual(calls[0].params, [42, 5]);
  });

  it('super_user: filtre SQL parametresi gecer', async () => {
    const calls = installFakePool({ query: async () => ({ rows: [], rowCount: 0 }) });
    const door = await getAccessibleDoorForUser({ authUser: { id: 1, role: 'super_user' }, doorId: 9 });
    assert.equal(door, null);
    assert.match(calls[0].text, /d\.id = \$1::BIGINT/);
    assert.deepEqual(calls[0].params, [9]);
  });

  it('gecersiz kapi id sorgu calistirmadan null doner', async () => {
    const calls = installFakePool({ query: async () => ({ rows: [{ id: 1 }], rowCount: 1 }) });
    for (const bad of [undefined, null, 'abc', 0, -4, 1.5, '1e3']) {
      assert.equal(await getAccessibleDoorForUser({ authUser: { id: 1, role: 'apartment_owner' }, doorId: bad }), null, String(bad));
    }
    assert.equal(calls.length, 0);
  });

  it('listAccessibleDoorsForUser filtresiz cagri tum kapilari getirir (null parametre)', async () => {
    const calls = installFakePool({ query: async () => ({ rows: [{ id: 1 }, { id: 2 }], rowCount: 2 }) });
    const doors = await listAccessibleDoorsForUser({ id: 42, role: 'apartment_owner' });
    assert.equal(doors.length, 2);
    assert.deepEqual(calls[0].params, [42, null]);
  });

  it('SELECT listesinde qr_totp_secret yok', async () => {
    const calls = installFakePool({ query: async () => ({ rows: [], rowCount: 0 }) });
    await listAccessibleDoorsForUser({ id: 42, role: 'apartment_owner' });
    await listAccessibleDoorsForUser({ id: 1, role: 'super_user' });
    for (const call of calls) {
      assert.doesNotMatch(call.text, /qr_totp_secret/);
    }
  });
});

describe('recordDoorAccessLog - hata yutulur ama loglanir', () => {
  it('DB hatasinda false doner, firlatmaz ve hata loglanir', async () => {
    installFakePool({ query: async () => { throw new Error('baglanti koptu'); } });
    const [logSpy, , errSpy] = quiet();
    const ok = await recordDoorAccessLog({ siteCode: 7, doorId: 3, doorName: 'K', userName: 'U', triggerType: 'qr_scanner' });
    assert.equal(ok, false);
    assert.equal(errSpy.mock.calls.length >= 1, true);
    const audit = logSpy.mock.calls.map((c) => c.arguments.join(' ')).join('\n');
    assert.match(audit, /door_access_log_write_failed/);
    assert.match(audit, /baglanti koptu/);
  });

  it('basarida true, siteCode yoksa false (sorgu yok)', async () => {
    const calls = installFakePool({ query: async () => ({ rowCount: 1, rows: [] }) });
    quiet();
    assert.equal(await recordDoorAccessLog({ siteCode: 7, doorName: 'K', userName: 'U' }), true);
    assert.equal(calls.length, 1);
    assert.equal(await recordDoorAccessLog({ doorName: 'K', userName: 'U' }), false);
    assert.equal(calls.length, 1);
  });
});

describe('localDoorControlForStatus - allowLocal=false', () => {
  it('token verilmez, available=false, DB/MQTT cagrilmaz', async () => {
    installFakePool(); // pool.query cagrilirsa hata
    const result = await localDoorControlForStatus({
      deviceUid: 'D4C771A172E0',
      currentToken: 'gizli-token',
      status: { local_ip: '192.168.1.5', local_control_port: 8765, local_control_available: true, mqtt_connected: true },
      allowLocal: false,
    });
    assert.deepEqual(result, { token: null, ip: '192.168.1.5', port: 8765, available: false });
  });

  it('varsayilan (allowLocal verilmedi): mevcut davranis korunur', async () => {
    const result = await localDoorControlForStatus({
      deviceUid: 'D4C771A172E0',
      currentToken: 'tok',
      status: { local_ip: '10.0.0.2', local_control_port: 8765, local_control_available: true, mqtt_connected: true },
    });
    assert.equal(result.token, 'tok');
    assert.equal(result.available, true);
  });
});

describe('replaceDoorDevice - atanabilirlik kurali ve hata kodlari (S4b rotasi icin)', () => {
  const defaultDoor = { id: 10, site_code: 101, door_name: 'Ana', assigned_device_id: 77, site_name: 'S' };

  function fakeClient(deviceRow, { doorRow = defaultDoor } = {}) {
    const log = [];
    const client = {
      log,
      sqls: [],
      released: false,
      async query(text) {
        const sql = String(text);
        client.sqls.push(sql);
        log.push(sql.trim().split(/\s+/).slice(0, 3).join(' '));
        if (/FROM site_doors d JOIN sites s/.test(sql.replace(/\s+/g, ' '))) {
          return doorRow ? { rowCount: 1, rows: [doorRow] } : { rowCount: 0, rows: [] };
        }
        if (/FROM devices\s+LEFT JOIN site_doors assigned_door/.test(sql)) {
          return deviceRow ? { rowCount: 1, rows: [deviceRow] } : { rowCount: 0, rows: [] };
        }
        return { rowCount: 0, rows: [] };
      },
      release() {
        this.released = true;
      },
    };
    return client;
  }

  const managerOf101 = async (text) =>
    (/site_manager_sites/.test(text) ? { rows: [{ site_code: 101 }], rowCount: 1 } : { rows: [], rowCount: 0 });
  const manager = { id: 42, user_code: 42, role: 'site_manager' };
  const isCode = (code, statusCode) => (err) => {
    assert.equal(err.message, code); // mevcut rotalar error.message ile de eslestirir
    assert.equal(err.code, code);
    assert.equal(err.statusCode, statusCode);
    return true;
  };

  it('arizali cihaz (super_user dahil) -> DEVICE_DEFECTIVE / 409 ve ROLLBACK', async () => {
    const client = fakeClient({ id: 5, device_uid: 'AA', site_code: null, owner_user_id: null, assigned_user_code: null, is_defective: true, assigned_door_site_code: null });
    installFakePool({ connect: async () => client, query: async () => ({ rows: [], rowCount: 0 }) });
    await assert.rejects(
      () => replaceDoorDevice({ doorId: 10, newDeviceId: 5, authUser: { id: 1, role: 'super_user' } }),
      isCode('DEVICE_DEFECTIVE', 409),
    );
    assert.ok(client.log.includes('ROLLBACK'));
    assert.equal(client.released, true);
  });

  it('baska kullanicinin sahip oldugu cihaz -> DEVICE_OWNED_BY_ANOTHER / 409', async () => {
    const client = fakeClient({ id: 6, device_uid: 'BB', site_code: null, owner_user_id: 999, assigned_user_code: 999, is_defective: false, assigned_door_site_code: null });
    installFakePool({ connect: async () => client, query: managerOf101 });
    await assert.rejects(
      () => replaceDoorDevice({ doorId: 10, newDeviceId: 6, authUser: manager }),
      isCode('DEVICE_OWNED_BY_ANOTHER', 409),
    );
  });

  it('yonetilmeyen siteye atanmis cihaz -> DEVICE_NOT_ASSIGNABLE / 403', async () => {
    const client = fakeClient({ id: 7, device_uid: 'CC', site_code: 555, owner_user_id: 42, assigned_user_code: 42, is_defective: false, assigned_door_site_code: 555 });
    installFakePool({ connect: async () => client, query: managerOf101 });
    await assert.rejects(
      () => replaceDoorDevice({ doorId: 10, newDeviceId: 7, authUser: manager }),
      isCode('DEVICE_NOT_ASSIGNABLE', 403),
    );
  });

  it('sahipsiz (sahiplenilmemis) envanter cihazi newDeviceId yoluyla -> DEVICE_NOT_ASSIGNABLE / 403', async () => {
    const client = fakeClient({ id: 8, device_uid: 'DD', site_code: null, owner_user_id: null, assigned_user_code: null, is_defective: false, assigned_door_site_code: null });
    installFakePool({ connect: async () => client, query: managerOf101 });
    await assert.rejects(
      () => replaceDoorDevice({ doorId: 10, newDeviceId: 8, authUser: manager }),
      isCode('DEVICE_NOT_ASSIGNABLE', 403),
    );
  });

  it('kendi cihazi, yonetilen sitede -> atama devam eder (hata yok)', async () => {
    const client = fakeClient({ id: 9, device_uid: 'EE', site_code: null, owner_user_id: 42, assigned_user_code: 42, is_defective: false, assigned_door_site_code: null });
    installFakePool({ connect: async () => client, query: managerOf101 });
    const result = await replaceDoorDevice({ doorId: 10, newDeviceId: 9, authUser: manager });
    assert.equal(result.newDeviceUid, 'EE');
    assert.ok(client.log.includes('COMMIT'));
    assert.ok(client.sqls.some((sql) => /UPDATE site_doors SET assigned_device_id = \$1 WHERE id = \$2/.test(sql.replace(/\s+/g, ' '))));
  });

  it('olmayan cihaz -> DEVICE_NOT_FOUND / 404; olmayan kapi -> DOOR_NOT_FOUND / 404; cihaz belirtilmedi -> MISSING_NEW_DEVICE / 400', async () => {
    installFakePool({ connect: async () => fakeClient(null), query: async () => ({ rows: [], rowCount: 0 }) });
    await assert.rejects(
      () => replaceDoorDevice({ doorId: 10, newDeviceId: 8, authUser: { id: 1, role: 'super_user' } }),
      isCode('DEVICE_NOT_FOUND', 404),
    );
    installFakePool({ connect: async () => fakeClient(null, { doorRow: null }), query: async () => ({ rows: [], rowCount: 0 }) });
    await assert.rejects(
      () => replaceDoorDevice({ doorId: 10, newDeviceId: 8, authUser: { id: 1, role: 'super_user' } }),
      isCode('DOOR_NOT_FOUND', 404),
    );
    installFakePool({ connect: async () => fakeClient(null), query: async () => ({ rows: [], rowCount: 0 }) });
    await assert.rejects(
      () => replaceDoorDevice({ doorId: 10, authUser: { id: 1, role: 'super_user' } }),
      isCode('MISSING_NEW_DEVICE', 400),
    );
  });

  it('QR/UID girisi yoluyla: baskasinin cihazi 409; arizali 409; gecersiz UID icin cihaz satiri OLUSTURULMAZ (404)', async () => {
    const owned = fakeClient({ id: 6, device_uid: 'D4C771A172E0', site_code: null, owner_user_id: 999, assigned_user_code: 999, is_defective: false, assigned_door_site_code: null });
    installFakePool({ connect: async () => owned, query: managerOf101 });
    await assert.rejects(
      () => replaceDoorDevice({ doorId: 10, newDeviceInput: 'GD-WROOM-D4C771A172E0', authUser: manager }),
      isCode('DEVICE_OWNED_BY_ANOTHER', 409),
    );

    const defective = fakeClient({ id: 6, device_uid: 'D4C771A172E0', site_code: null, owner_user_id: 42, assigned_user_code: 42, is_defective: true, assigned_door_site_code: null });
    installFakePool({ connect: async () => defective, query: managerOf101 });
    await assert.rejects(
      () => replaceDoorDevice({ doorId: 10, newDeviceInput: 'D4C771A172E0', authUser: manager }),
      isCode('DEVICE_DEFECTIVE', 409),
    );

    const none = fakeClient(null);
    installFakePool({ connect: async () => none, query: managerOf101 });
    await assert.rejects(
      () => replaceDoorDevice({ doorId: 10, newDeviceInput: '<script>alert(1)</script>', authUser: manager }),
      isCode('DEVICE_NOT_FOUND', 404),
    );
    assert.equal(none.sqls.some((sql) => /INSERT INTO devices/.test(sql)), false);
  });
});

describe('getAccessibleDoorForUser - politika kolonlari SELECT listesinde KALIR (S4b misafir gecisi kullanir)', () => {
  it('site politika ve geofence kolonlari her iki sorguda da secilir', async () => {
    const calls = installFakePool({ query: async () => ({ rows: [], rowCount: 0 }) });
    await getAccessibleDoorForUser({ authUser: { id: 42, role: 'apartment_owner' }, doorId: 5 });
    await getAccessibleDoorForUser({ authUser: { id: 1, role: 'super_user' }, doorId: 5 });
    for (const call of calls) {
      for (const column of [
        's.feature_qr_enabled',
        's.feature_remote_open_enabled',
        's.feature_local_udp_enabled',
        's.feature_guest_pass_enabled',
        's.qr_entry_active',
        's.require_geofence',
        's.geofence_latitude',
        's.geofence_longitude',
        's.geofence_radius_meters',
        's.qr_rotation_seconds',
        'devices.local_control_token',
        'd.access_scope',
        'd.block_id',
      ]) {
        assert.ok(call.text.includes(column), `${column} SELECT listesinde olmali`);
      }
    }
  });
});
