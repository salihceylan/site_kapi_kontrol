import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  buildChildEnv,
  buildMqttAclText,
  isSafeSyncCommand,
  isValidAclDeviceUid,
  isValidAclMqttPassword,
  isValidAclMqttUsername,
  partitionAclDevices,
} from '../src/mqtt_acl_sync.js';

function device(uid, overrides = {}) {
  return {
    device_uid: uid,
    mqtt_username: `device_${uid}`,
    mqtt_password: 'p'.repeat(32),
    ...overrides,
  };
}

describe('devices: ACL dogrulama', () => {
  it('UID: buyuk harf onaltilik 6-32', () => {
    assert.equal(isValidAclDeviceUid('D4C771A172E0'), true);
    assert.equal(isValidAclDeviceUid('00861A0D5020'), true);
    assert.equal(isValidAclDeviceUid('d4c771a172e0'), false);
    assert.equal(isValidAclDeviceUid('D4C77'), false);
    assert.equal(isValidAclDeviceUid('D4C771A172E0\ntopic readwrite #'), false);
    assert.equal(isValidAclDeviceUid('D4C771A172E0 '), false);
    assert.equal(isValidAclDeviceUid('+'), false);
    assert.equal(isValidAclDeviceUid('#'), false);
    assert.equal(isValidAclDeviceUid(null), false);
    assert.equal(isValidAclDeviceUid(123456), false);
  });

  it('kullanici adi: device_<UID> kalibi; api_bridge ve eski kullanicilar kabul edilmez', () => {
    assert.equal(isValidAclMqttUsername('device_D4C771A172E0'), true);
    assert.equal(isValidAclMqttUsername('api_bridge'), false);
    assert.equal(isValidAclMqttUsername('app_client'), false);
    assert.equal(isValidAclMqttUsername('device_D4C771A172E0\nuser api_bridge'), false);
    assert.equal(isValidAclMqttUsername('device_ zz'), false);
  });

  it('parola: bos/cok uzun/kontrol karakterli kabul edilmez', () => {
    assert.equal(isValidAclMqttPassword('abc-DEF_123'), true);
    assert.equal(isValidAclMqttPassword(''), false);
    assert.equal(isValidAclMqttPassword('x'.repeat(257)), false);
    assert.equal(isValidAclMqttPassword('abc\u0000def'), false);
    assert.equal(isValidAclMqttPassword('abc\ndef'), false);
    assert.equal(isValidAclMqttPassword(null), false);
  });
});

describe('devices: partitionAclDevices', () => {
  it('gecersiz ve yinelenen kayitlari ayirir (fail-closed)', () => {
    const { valid, invalid } = partitionAclDevices([
      device('D4C771A172E0'),
      device('00861A0D5020'),
      device('D4C771A172E0'),
      device('BAD UID'),
      device('A1B2C3D4E5F6', { mqtt_username: 'api_bridge' }),
      device('A1B2C3D4E5F7', { mqtt_password: 'ab\ncd' }),
    ]);
    assert.deepEqual(valid.map((item) => item.device_uid), ['D4C771A172E0', '00861A0D5020']);
    assert.deepEqual(invalid.map((item) => item.reason), ['duplicate', 'device_uid', 'mqtt_username', 'mqtt_password']);
  });

  it('dizi olmayan girdi bos sonuc verir', () => {
    assert.deepEqual(partitionAclDevices(null), { valid: [], invalid: [] });
  });
});

describe('devices: buildMqttAclText', () => {
  const acl = buildMqttAclText([device('D4C771A172E0'), device('00861A0D5020')]);
  const lines = acl.split('\n');

  it('api_bridge: C6 gereği device/+/logs okuma izni var', () => {
    assert.ok(lines.includes('user api_bridge'));
    assert.ok(lines.includes('topic read device/+/logs'));
    assert.ok(lines.includes('topic read device/+/state'));
    assert.ok(lines.includes('topic read device/+/qr_verify'));
    assert.ok(lines.includes('topic write device/+/cmd'));
    assert.ok(lines.includes('topic write device/+/qr_result'));
  });

  it('cihaz: kendi UID konularina logs yazma izni var, baskasininkine yok', () => {
    assert.ok(lines.includes('user device_D4C771A172E0'));
    assert.ok(lines.includes('topic write device/D4C771A172E0/logs'));
    assert.ok(lines.includes('topic write device/00861A0D5020/logs'));
    assert.ok(lines.includes('topic read device/D4C771A172E0/cmd'));
    assert.ok(lines.includes('topic read device/D4C771A172E0/qr_result'));
    // Cihaza genel wildcard izni verilmez
    const deviceBlock = acl.split('user device_D4C771A172E0')[1].split('user device_00861A0D5020')[0];
    assert.ok(!/device\/\+|#/.test(deviceBlock));
    assert.ok(!deviceBlock.includes('00861A0D5020'));
  });

  it('cihaz basina izinler: cmd/qr_result okuma; state/event/availability/qr_verify/screen_qr/logs yazma', () => {
    const block = acl.split('user device_D4C771A172E0')[1].split('user device_00861A0D5020')[0];
    const topics = block.split('\n').filter((line) => line.startsWith('topic ')).sort();
    assert.deepEqual(topics, [
      'topic read device/D4C771A172E0/cmd',
      'topic read device/D4C771A172E0/qr_result',
      'topic write device/D4C771A172E0/availability',
      'topic write device/D4C771A172E0/event',
      'topic write device/D4C771A172E0/logs',
      'topic write device/D4C771A172E0/qr_verify',
      'topic write device/D4C771A172E0/screen_qr',
      'topic write device/D4C771A172E0/state',
    ]);
  });

  it('enjeksiyon: satir sonu/bosluk iceren UID ve kullanici adi ACL metnine GIRMEZ', () => {
    const evil = buildMqttAclText([
      device('D4C771A172E0\ntopic readwrite #'),
      device('A1B2C3D4E5F6', { mqtt_username: 'device_A1B2C3D4E5F6\nuser admin' }),
      device('112233445566'),
    ]);
    assert.ok(!evil.includes('readwrite'));
    assert.ok(!evil.includes('user admin'));
    assert.ok(!evil.includes('A1B2C3D4E5F6'));
    assert.ok(evil.includes('user device_112233445566'));
    assert.ok(evil.endsWith('\n'));
    assert.ok(!evil.endsWith('\n\n'));
  });

  it('cihaz yoksa yalnizca api_bridge blogu uretilir', () => {
    const only = buildMqttAclText([]);
    assert.ok(only.startsWith('user api_bridge\n'));
    assert.ok(!only.includes('user device_'));
  });
});

describe('devices: senkron komutu guvenligi', () => {
  it('buildChildEnv gizli degiskenleri gecirmez, gerekenleri gecirir', () => {
    const env = buildChildEnv({
      PATH: '/usr/bin',
      HOME: '/root',
      JWT_SECRET: 'gizli',
      COMPANY_API_KEY: 'gizli',
      SMTP_PASS: 'gizli',
      SMTP_USER: 'u',
      DB_HOST: 'localhost',
      DB_PASSWORD: 'dbpass',
      MQTT_PASSWD_FILE: '/etc/mosquitto/passwd',
      MQTT_ACL_FILE: '/etc/mosquitto/acl',
      MOSQUITTO_PASSWD_BIN: 'mosquitto_passwd',
      KAPI_APP_DIR: '/var/www/x',
      LC_ALL: 'C',
      TZ: 'Europe/Istanbul',
      OTHER: 'x',
    });
    assert.deepEqual(Object.keys(env).sort(), [
      'DB_HOST',
      'DB_PASSWORD',
      'HOME',
      'KAPI_APP_DIR',
      'LC_ALL',
      'MOSQUITTO_PASSWD_BIN',
      'MQTT_ACL_FILE',
      'MQTT_PASSWD_FILE',
      'PATH',
      'TZ',
    ]);
    assert.equal(env.JWT_SECRET, undefined);
    assert.equal(env.SMTP_PASS, undefined);
    assert.equal(env.COMPANY_API_KEY, undefined);
  });

  it('isSafeSyncCommand: tipik komutlar gecer, metakarakterler gecmez', () => {
    assert.equal(isSafeSyncCommand('/usr/bin/sudo', ['-n', '/usr/local/sbin/kapi-mqtt-sync']), true);
    assert.equal(isSafeSyncCommand('sudo', []), true);
    assert.equal(isSafeSyncCommand('/bin/sh', ['-c', 'x']), true);
    assert.equal(isSafeSyncCommand('/bin/sh;rm', []), false);
    assert.equal(isSafeSyncCommand('/usr/bin/sudo', ['$(id)']), false);
    assert.equal(isSafeSyncCommand('/usr/bin/sudo', ['a|b']), false);
    assert.equal(isSafeSyncCommand('', []), false);
    assert.equal(isSafeSyncCommand('cmd\nx', []), false);
  });
});
