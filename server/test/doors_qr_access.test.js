import { describe, it, mock, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../src/db.js';
import {
  generateQrTokenForDoor,
  getQrTokenStatus,
  verifyQrTokenAndOpenDoor,
} from '../src/services/qr_access_service.js';

const baseDevice = {
  id: 1,
  device_uid: 'D4C771A172E0',
  qr_reader_enabled: true,
  site_code: 101,
  assigned_door_id: 10,
  assigned_door_site_code: 101,
  assigned_door_name: 'Ana Kapi',
};

const baseToken = {
  id: 900,
  token: 'QR:abc',
  site_code: 101,
  door_id: 10,
  user_code: 42,
  user_role: 'apartment_owner',
  user_name: 'Ayse Yilmaz',
  is_active: true,
  is_used: false,
  use_count: 0,
  used_at: null,
  expires_at: new Date(Date.now() + 20000),
  superseded_at: null,
  last_denial_reason: null,
  is_expired: false,
  user_is_active: true,
  user_email_verified: true,
  user_approval_status: 'approved',
  user_current_role: 'apartment_owner',
  user_email: 'ayse@example.com',
  user_full_name: 'Ayse Yilmaz',
};

const accessibleDoor = {
  id: 10,
  site_code: 101,
  door_name: 'Ana Kapi',
  feature_qr_enabled: true,
  qr_entry_active: true,
  feature_remote_open_enabled: true,
};

function norm(text) {
  return String(text).replace(/\s+/g, ' ').trim();
}

function installFakePool(overrides = {}) {
  const calls = [];
  const state = { device: baseDevice, token: baseToken, door: accessibleDoor, consumeRows: 1, ...overrides };
  pool.query = async (text, params) => {
    const sql = norm(text);
    calls.push({ sql, params });
    if (sql.startsWith('SELECT d.id, d.device_uid, d.qr_reader_enabled')) {
      return state.device ? { rows: [state.device], rowCount: 1 } : { rows: [], rowCount: 0 };
    }
    if (sql.includes('FROM qr_access_tokens t INNER JOIN users u')) {
      return state.token ? { rows: [state.token], rowCount: 1 } : { rows: [], rowCount: 0 };
    }
    if (sql.includes('FROM site_doors d INNER JOIN sites s')) {
      return state.door ? { rows: [state.door], rowCount: 1 } : { rows: [], rowCount: 0 };
    }
    if (sql.startsWith('UPDATE qr_access_tokens SET is_used = TRUE')) {
      return { rows: state.consumeRows ? [{ id: 900 }] : [], rowCount: state.consumeRows };
    }
    return { rows: [], rowCount: 1 };
  };
  return calls;
}

afterEach(() => {
  delete pool.query;
  delete pool.connect;
  mock.restoreAll();
});

function quiet() {
  mock.method(console, 'log', () => {});
  mock.method(console, 'warn', () => {});
  mock.method(console, 'error', () => {});
}

function logInserts(calls) {
  return calls.filter((c) => c.sql.startsWith('INSERT INTO door_access_logs'));
}

describe('verifyQrTokenAndOpenDoor - pulse sonucuna bagli log ve token iadesi', () => {
  it('pulse gonderilemezse: PULSE_FAILED, token geri verilir, "acildi" logu YAZILMAZ', async () => {
    quiet();
    // mqtt koprusu baslatilmadi => publishDoorPulse MQTT_BRIDGE_NOT_CONNECTED firlatir
    const calls = installFakePool();
    const result = await verifyQrTokenAndOpenDoor({ deviceUid: 'd4c771a172e0', token: 'QR:abc' });
    assert.deepEqual(result, { allowed: false, reason: 'PULSE_FAILED' });

    const consumeIndex = calls.findIndex((c) => c.sql.startsWith('UPDATE qr_access_tokens SET is_used = TRUE'));
    const rollbackIndex = calls.findIndex((c) => c.sql.includes('SET is_used = FALSE') && c.sql.includes("'PULSE_FAILED'"));
    assert.ok(consumeIndex >= 0, 'token once tuketilmeli');
    assert.ok(rollbackIndex > consumeIndex, 'tuketim pulse basarisizsa geri alinmali');

    const inserts = logInserts(calls);
    assert.equal(inserts.length, 1);
    assert.match(inserts[0].params[4], /Komutu Gönderilemedi/);
    // duz kullanici adiyla "acildi" kaydi olmamali
    assert.equal(inserts.some((c) => c.params[4] === 'Ayse Yilmaz'), false);
  });

  it('tuketim sorgusu aktiflik/hukumsuzluk/sure kosullarini da icerir (atomik)', async () => {
    quiet();
    const calls = installFakePool();
    await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: 'QR:abc' });
    const consume = calls.find((c) => c.sql.startsWith('UPDATE qr_access_tokens SET is_used = TRUE'));
    assert.match(consume.sql, /is_used = FALSE/);
    assert.match(consume.sql, /is_active = TRUE/);
    assert.match(consume.sql, /superseded_at IS NULL/);
    assert.match(consume.sql, /expires_at > NOW\(\)/);
  });

  it('site karekod ozelligini kapattiysa tuketimde reddedilir (QR_DISABLED), token tuketilmez', async () => {
    quiet();
    const calls = installFakePool({ door: { ...accessibleDoor, feature_qr_enabled: false } });
    const result = await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: 'QR:abc' });
    assert.deepEqual(result, { allowed: false, reason: 'QR_DISABLED' });
    assert.equal(calls.some((c) => c.sql.startsWith('UPDATE qr_access_tokens SET is_used = TRUE')), false);
  });

  it('qr_entry_active=false -> QR_ENTRY_INACTIVE', async () => {
    quiet();
    installFakePool({ door: { ...accessibleDoor, qr_entry_active: false } });
    const result = await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: 'QR:abc' });
    assert.equal(result.reason, 'QR_ENTRY_INACTIVE');
  });

  it('kullanicinin kapi yetkisi kalkmissa tuketimde ACCESS_REVOKED', async () => {
    quiet();
    const calls = installFakePool({ door: null });
    const result = await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: 'QR:abc' });
    assert.deepEqual(result, { allowed: false, reason: 'ACCESS_REVOKED' });
    assert.equal(calls.some((c) => c.sql.startsWith('UPDATE qr_access_tokens SET is_used = TRUE')), false);
  });

  it('super_user icin site QR politikasi istisnasi korunur (pulse asamasina kadar gecer)', async () => {
    quiet();
    installFakePool({
      token: { ...baseToken, user_current_role: 'super_user', user_role: 'super_user' },
      door: { ...accessibleDoor, feature_qr_enabled: false, qr_entry_active: false },
    });
    const result = await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: 'QR:abc' });
    assert.equal(result.reason, 'PULSE_FAILED'); // politika gecti, kopru yok
  });

  it('hesap pasif / e-posta dogrulanmamis / onay bekliyor -> TOKEN_OR_USER_INACTIVE', async () => {
    quiet();
    for (const patch of [
      { user_is_active: false },
      { user_email_verified: false },
      { user_approval_status: 'pending' },
      { user_approval_status: 'rejected' },
    ]) {
      installFakePool({ token: { ...baseToken, ...patch } });
      const result = await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: 'QR:abc' });
      assert.equal(result.reason, 'TOKEN_OR_USER_INACTIVE', JSON.stringify(patch));
    }
  });

  it('daha once kullanilmis / hukumsuz / suresi dolmus / baska kapi / bilinmeyen token', async () => {
    quiet();
    installFakePool({ token: { ...baseToken, is_used: true } });
    assert.equal((await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: 'QR:abc' })).reason, 'ALREADY_USED');
    installFakePool({ token: { ...baseToken, superseded_at: new Date() } });
    assert.equal((await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: 'QR:abc' })).reason, 'SUPERSEDED_TOKEN');
    installFakePool({ token: { ...baseToken, is_expired: true } });
    assert.equal((await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: 'QR:abc' })).reason, 'EXPIRED_TOKEN');
    installFakePool({ token: { ...baseToken, door_id: 99 } });
    assert.equal((await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: 'QR:abc' })).reason, 'DOOR_MISMATCH');
    installFakePool({ token: null });
    assert.equal((await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: 'QR:zzz' })).reason, 'INVALID_TOKEN');
  });

  it('eszamanli tuketim kaybedilirse ALREADY_USED (pulse gonderilmez)', async () => {
    quiet();
    const calls = installFakePool({ consumeRows: 0 });
    const result = await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: 'QR:abc' });
    assert.deepEqual(result, { allowed: false, reason: 'ALREADY_USED' });
    assert.equal(logInserts(calls).length, 0);
  });

  it('parametre eksik / cihaz bilinmiyor / okuyucu kapali / kapi atanmamis', async () => {
    quiet();
    installFakePool();
    assert.equal((await verifyQrTokenAndOpenDoor({ deviceUid: '', token: 'x' })).reason, 'PARAM_MISSING');
    assert.equal((await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: '' })).reason, 'PARAM_MISSING');
    installFakePool({ device: null });
    assert.equal((await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: 'x' })).reason, 'DEVICE_NOT_FOUND');
    installFakePool({ device: { ...baseDevice, qr_reader_enabled: false } });
    assert.equal((await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: 'x' })).reason, 'QR_READER_NOT_ENABLED');
    installFakePool({ device: { ...baseDevice, assigned_door_id: null } });
    assert.equal((await verifyQrTokenAndOpenDoor({ deviceUid: 'D4C771A172E0', token: 'x' })).reason, 'DOOR_NOT_ASSIGNED');
  });
});

describe('getQrTokenStatus - yalnizca sahibi gorur', () => {
  it('sorgu user_code ile sinirlanir; userCode gecersizse sorgu yok', async () => {
    const calls = [];
    pool.query = async (text, params) => {
      calls.push({ sql: norm(text), params });
      return { rows: [], rowCount: 0 };
    };
    const res = await getQrTokenStatus({ token: 'QR:abc', userCode: 42 });
    assert.equal(res.success, false);
    assert.match(calls[0].sql, /t\.token = \$1 AND t\.user_code = \$2/);
    assert.deepEqual(calls[0].params, ['QR:abc', 42]);

    calls.length = 0;
    for (const bad of [undefined, null, NaN, 'x', 0, -1]) {
      assert.equal((await getQrTokenStatus({ token: 'QR:abc', userCode: bad })).success, false);
    }
    assert.equal(calls.length, 0);
  });
});

describe('generateQrTokenForDoor - politika + tek transaction', () => {
  const door = {
    id: 10,
    site_code: 101,
    site_name: 'Site',
    door_name: 'Ana Kapi',
    assigned_device_uid: 'D4C771A172E0',
    assigned_device_hardware_type: 'esp32_wroom',
    assigned_device_qr_reader_enabled: true,
    feature_qr_enabled: true,
    qr_entry_active: true,
    require_geofence: false,
    qr_rotation_seconds: 30,
  };
  const authUser = { id: 42, user_code: 42, role: 'apartment_owner', full_name: 'Ayse' };

  function fakeTxPool(doorRow) {
    const txLog = [];
    pool.query = async () => ({ rows: doorRow ? [doorRow] : [], rowCount: doorRow ? 1 : 0 });
    pool.connect = async () => ({
      async query(text, params) {
        const sql = norm(text);
        txLog.push({ sql, params });
        if (sql.startsWith('INSERT INTO qr_access_tokens')) {
          return {
            rows: [{ id: 1, token: params[0], site_code: 101, door_id: 10, user_code: 42, user_role: 'apartment_owner', user_name: 'Ayse', created_at: new Date(), expires_at: new Date(Date.now() + 30000) }],
            rowCount: 1,
          };
        }
        return { rows: [], rowCount: 0 };
      },
      release() {},
    });
    return txLog;
  }

  it('supersede + insert ayni transaction icinde (BEGIN ... COMMIT) ve advisory kilit ile', async () => {
    const txLog = fakeTxPool(door);
    const result = await generateQrTokenForDoor({ authUser, doorId: 10, clientLocation: { latitude: 'abc', longitude: null } });
    assert.match(result.token, /^QR:[0-9a-f]{48}$/);
    const steps = txLog.map((entry) => entry.sql.split(' ').slice(0, 3).join(' '));
    assert.deepEqual(steps, ['BEGIN', 'SELECT pg_advisory_xact_lock(hashtext($1))', 'UPDATE qr_access_tokens SET', 'INSERT INTO qr_access_tokens', 'COMMIT']);
    // gecersiz konum degerleri NaN olarak degil NULL olarak yazilir
    const insert = txLog.find((entry) => entry.sql.startsWith('INSERT'));
    assert.equal(insert.params[6], null);
    assert.equal(insert.params[7], null);
  });

  it('insert hatasinda ROLLBACK yapilir', async () => {
    const txLog = [];
    pool.query = async () => ({ rows: [door], rowCount: 1 });
    pool.connect = async () => ({
      async query(text) {
        const sql = norm(text);
        txLog.push(sql.split(' ')[0]);
        if (sql.startsWith('INSERT')) {
          throw new Error('unique ihlali');
        }
        return { rows: [], rowCount: 0 };
      },
      release() {},
    });
    await assert.rejects(() => generateQrTokenForDoor({ authUser, doorId: 10, clientLocation: {} }), /unique ihlali/);
    assert.ok(txLog.includes('ROLLBACK'));
    assert.equal(txLog.includes('COMMIT'), false);
  });

  it('karekod kapali sitede 403 QR_DISABLED; qr_entry_active=false -> QR_ENTRY_INACTIVE; super_user muaf', async () => {
    fakeTxPool({ ...door, feature_qr_enabled: false });
    await assert.rejects(
      () => generateQrTokenForDoor({ authUser, doorId: 10, clientLocation: {} }),
      (err) => err.statusCode === 403 && err.code === 'QR_DISABLED',
    );
    fakeTxPool({ ...door, qr_entry_active: false });
    await assert.rejects(
      () => generateQrTokenForDoor({ authUser, doorId: 10, clientLocation: {} }),
      (err) => err.statusCode === 403 && err.code === 'QR_ENTRY_INACTIVE',
    );
    fakeTxPool({ ...door, feature_qr_enabled: false, qr_entry_active: false });
    const result = await generateQrTokenForDoor({ authUser: { ...authUser, role: 'super_user' }, doorId: 10, clientLocation: {} });
    assert.ok(result.token);
  });

  it('geofence zorunluysa konum olmadan GEOFENCE_LOCATION_REQUIRED', async () => {
    fakeTxPool({ ...door, require_geofence: true, geofence_latitude: 41.0, geofence_longitude: 29.0, geofence_radius_meters: 100 });
    await assert.rejects(
      () => generateQrTokenForDoor({ authUser, doorId: 10, clientLocation: {} }),
      (err) => err.statusCode === 403 && err.code === 'GEOFENCE_LOCATION_REQUIRED',
    );
  });
});
