import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  DOOR_CHANNELS,
  assertDoorOpenAllowed,
  doorDeviceHasScreen,
  evaluateDoorOpenPolicy,
  isDoorChannelAllowed,
  normalizeLocalIp,
  parsePositiveDoorId,
  parseScanQrPayload,
} from '../src/services/door_access_policy.js';

const user = { id: 42, role: 'apartment_owner' };
const superUser = { id: 1, role: 'super_user' };

function codeOf(fn) {
  try {
    fn();
  } catch (error) {
    return { code: error.code, statusCode: error.statusCode };
  }
  return null;
}

describe('assertDoorOpenAllowed (C2) - kanal x bayrak matrisi', () => {
  const allOn = {
    feature_remote_open_enabled: true,
    feature_qr_enabled: true,
    qr_entry_active: true,
    feature_guest_pass_enabled: true,
    feature_local_udp_enabled: true,
  };

  it('tum bayraklar acikken tum kanallara izin verir', () => {
    for (const channel of DOOR_CHANNELS) {
      assert.doesNotThrow(() => assertDoorOpenAllowed({ door: allOn, channel, authUser: user }));
    }
  });

  it('bayrak kolonu hic yoksa (undefined/null) geriye donuk uyum icin izin verir', () => {
    for (const channel of DOOR_CHANNELS) {
      assert.doesNotThrow(() => assertDoorOpenAllowed({ door: {}, channel, authUser: user }));
      assert.doesNotThrow(() =>
        assertDoorOpenAllowed({
          door: { feature_remote_open_enabled: null, feature_qr_enabled: null, qr_entry_active: null },
          channel,
          authUser: user,
        }),
      );
    }
  });

  it("remote: feature_remote_open_enabled=false -> 403 REMOTE_OPEN_DISABLED", () => {
    const result = codeOf(() =>
      assertDoorOpenAllowed({
        door: { ...allOn, feature_remote_open_enabled: false },
        channel: 'remote',
        authUser: user,
      }),
    );
    assert.deepEqual(result, { code: 'REMOTE_OPEN_DISABLED', statusCode: 403 });
  });

  it('remote: mevcut kullanici mesaji korunur', () => {
    try {
      assertDoorOpenAllowed({
        door: { feature_remote_open_enabled: false },
        channel: 'remote',
        authUser: user,
      });
      assert.fail('hata bekleniyordu');
    } catch (error) {
      assert.match(error.message, /uzaktan kapi acma yetkisi kapalidir/);
      assert.match(error.message, /QR okuyucuyu kullanin/);
    }
  });

  it("remote kapaliyken QR/guest/local kanallari etkilenmez", () => {
    const door = { ...allOn, feature_remote_open_enabled: false };
    for (const channel of ['qr', 'guest', 'local']) {
      assert.doesNotThrow(() => assertDoorOpenAllowed({ door, channel, authUser: user }));
    }
  });

  it('qr: feature_qr_enabled=false -> QR_DISABLED, qr_entry_active=false -> QR_ENTRY_INACTIVE', () => {
    assert.deepEqual(
      codeOf(() => assertDoorOpenAllowed({ door: { feature_qr_enabled: false }, channel: 'qr', authUser: user })),
      { code: 'QR_DISABLED', statusCode: 403 },
    );
    assert.deepEqual(
      codeOf(() => assertDoorOpenAllowed({ door: { qr_entry_active: false }, channel: 'qr', authUser: user })),
      { code: 'QR_ENTRY_INACTIVE', statusCode: 403 },
    );
    // ikisi birden: once ozellik kapali hatasi
    assert.equal(
      codeOf(() =>
        assertDoorOpenAllowed({
          door: { feature_qr_enabled: false, qr_entry_active: false },
          channel: 'qr',
          authUser: user,
        }),
      ).code,
      'QR_DISABLED',
    );
  });

  it('guest: feature_guest_pass_enabled=false -> GUEST_DISABLED (super_user istisnasi YOK)', () => {
    const door = { feature_guest_pass_enabled: false };
    assert.deepEqual(codeOf(() => assertDoorOpenAllowed({ door, channel: 'guest', authUser: user })), {
      code: 'GUEST_DISABLED',
      statusCode: 403,
    });
    assert.equal(codeOf(() => assertDoorOpenAllowed({ door, channel: 'guest', authUser: superUser })).code, 'GUEST_DISABLED');
    // authUser olmadan da calisir (S4b halka acik gecis)
    assert.equal(codeOf(() => assertDoorOpenAllowed({ door, channel: 'guest' })).code, 'GUEST_DISABLED');
  });

  it('local: feature_local_udp_enabled=false -> LOCAL_DISABLED', () => {
    assert.deepEqual(
      codeOf(() =>
        assertDoorOpenAllowed({ door: { feature_local_udp_enabled: false }, channel: 'local', authUser: user }),
      ),
      { code: 'LOCAL_DISABLED', statusCode: 403 },
    );
  });

  it('super_user istisnasi remote/qr/local kanallarinda korunur', () => {
    const allOff = {
      feature_remote_open_enabled: false,
      feature_qr_enabled: false,
      qr_entry_active: false,
      feature_local_udp_enabled: false,
    };
    for (const channel of ['remote', 'qr', 'local']) {
      assert.doesNotThrow(() => assertDoorOpenAllowed({ door: allOff, channel, authUser: superUser }));
    }
  });

  it('is_active alani politikayi etkilemez (misafir gecisi satirlarinda is_active gecis alanidir)', () => {
    assert.doesNotThrow(() =>
      assertDoorOpenAllowed({ door: { is_active: false, feature_guest_pass_enabled: true }, channel: 'guest' }),
    );
  });

  it('door yoksa 404 DOOR_NOT_FOUND, gecersiz kanalda 500 INVALID_DOOR_CHANNEL', () => {
    assert.deepEqual(codeOf(() => assertDoorOpenAllowed({ door: null, channel: 'remote', authUser: user })), {
      code: 'DOOR_NOT_FOUND',
      statusCode: 404,
    });
    assert.deepEqual(codeOf(() => assertDoorOpenAllowed({ door: {}, channel: 'telepati', authUser: user })), {
      code: 'INVALID_DOOR_CHANNEL',
      statusCode: 500,
    });
    assert.deepEqual(codeOf(() => assertDoorOpenAllowed({})), {
      code: 'INVALID_DOOR_CHANNEL',
      statusCode: 500,
    });
  });

  it('isDoorChannelAllowed fırlatmaz; evaluateDoorOpenPolicy izinliyse null doner', () => {
    assert.equal(isDoorChannelAllowed({ door: { feature_local_udp_enabled: false }, channel: 'local', authUser: user }), false);
    assert.equal(isDoorChannelAllowed({ door: {}, channel: 'local', authUser: user }), true);
    assert.equal(evaluateDoorOpenPolicy({ door: {}, channel: 'remote', authUser: user }), null);
  });
});

describe('parsePositiveDoorId', () => {
  it('yalnizca pozitif guvenli tamsayi kabul eder', () => {
    assert.equal(parsePositiveDoorId('12'), 12);
    assert.equal(parsePositiveDoorId(7), 7);
    for (const bad of ['0', '-1', '1.5', '1e3', '12abc', '', ' ', null, undefined, 'abc', '99999999999999999999', '0x10']) {
      assert.equal(parsePositiveDoorId(bad), null, `reddedilmeli: ${String(bad)}`);
    }
  });
});

describe('normalizeLocalIp', () => {
  it('yalnizca gecerli IP literallerini kabul eder', () => {
    assert.equal(normalizeLocalIp('192.168.1.20'), '192.168.1.20');
    assert.equal(normalizeLocalIp(' 10.0.0.5 '), '10.0.0.5');
    assert.equal(normalizeLocalIp('fe80::1'), 'fe80::1');
    assert.equal(normalizeLocalIp('evil.example.com'), null);
    assert.equal(normalizeLocalIp('1.2.3.4\nINJECT'), null);
    assert.equal(normalizeLocalIp('x'.repeat(100)), null);
    assert.equal(normalizeLocalIp(undefined), null);
  });
});

describe('parseScanQrPayload', () => {
  it('desteklenen karekod bicimlerini cozer', () => {
    assert.deepEqual(parseScanQrPayload('AHBU:DOOR:D4C771A172E0:ab12cd'), { uid: 'D4C771A172E0', token: 'AB12CD' });
    assert.deepEqual(parseScanQrPayload('AHBU:DOOR:D4C771A172E0'), { uid: 'D4C771A172E0', token: '' });
    assert.deepEqual(parseScanQrPayload('d4c771a172e0'), { uid: 'D4C771A172E0', token: '' });
    assert.deepEqual(parseScanQrPayload('  D4C771A172E0:XYZ123  '), { uid: 'D4C771A172E0', token: 'XYZ123' });
  });

  it('gecersiz/cok uzun/yazi olmayan girisi reddeder', () => {
    assert.equal(parseScanQrPayload(undefined), null);
    assert.equal(parseScanQrPayload(12345), null);
    assert.equal(parseScanQrPayload(''), null);
    assert.equal(parseScanQrPayload('   '), null);
    assert.equal(parseScanQrPayload('AHBU:DOOR:'), null);
    assert.equal(parseScanQrPayload('A'.repeat(200)), null);
  });
});

describe('doorDeviceHasScreen', () => {
  it('C3 ekransiz, WROOM ekranli, bilinmeyen ekranli kabul edilir (fail-closed)', () => {
    assert.equal(doorDeviceHasScreen({ assigned_device_hardware_type: 'esp32_c3' }), false);
    assert.equal(doorDeviceHasScreen({ assigned_device_hardware_target: 'esp32-c3' }), false);
    assert.equal(doorDeviceHasScreen({ assigned_device_hardware_type: 'esp32_wroom' }), true);
    assert.equal(doorDeviceHasScreen({ assigned_device_hardware_target: 'esp32-wroom', assigned_device_hardware_type: 'esp32_c3' }), true);
    assert.equal(doorDeviceHasScreen({}), true);
  });
});
