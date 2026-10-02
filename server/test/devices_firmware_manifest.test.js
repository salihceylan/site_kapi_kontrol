import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import express from 'express';

import {
  canonicalFirmwareTarget,
  checkDeviceFirmwareTarget,
  hardwareTypeToFirmwareTarget,
  normalizeClientIp,
  parseManifestQueryUid,
  resolveManifestTarget,
} from '../src/services/firmware_manifest_service.js';

describe('devices: firmware hedef yardimcilari', () => {
  it('canonicalFirmwareTarget: _ ve - esdeger, kucuk harf; gecersiz null', () => {
    assert.equal(canonicalFirmwareTarget('esp32_c3'), 'esp32-c3');
    assert.equal(canonicalFirmwareTarget('ESP32-WROOM'), 'esp32-wroom');
    assert.equal(canonicalFirmwareTarget(' esp32-c3 '), 'esp32-c3');
    assert.equal(canonicalFirmwareTarget('../etc'), null);
    assert.equal(canonicalFirmwareTarget(''), null);
    assert.equal(canonicalFirmwareTarget(null), null);
  });

  it('hardwareTypeToFirmwareTarget: DB donanim tipini klasor hedefine esler', () => {
    assert.equal(hardwareTypeToFirmwareTarget('esp32_c3'), 'esp32-c3');
    assert.equal(hardwareTypeToFirmwareTarget('esp32_wroom'), 'esp32-wroom');
  });

  it('resolveManifestTarget: manifestteki hedef kullanilir, klasorle uyusmazlik isaretlenir', () => {
    assert.deepEqual(
      resolveManifestTarget({ target: 'esp32-c3' }, 'esp32-c3'),
      { target: 'esp32-c3', declared: 'esp32-c3', mismatch: false },
    );
    // hedef yoksa klasor adi
    assert.deepEqual(
      resolveManifestTarget({}, 'esp32-wroom'),
      { target: 'esp32-wroom', declared: null, mismatch: false },
    );
    // _ / - farki uyusmazlik sayilmaz; yanit hedefi manifestten gelir
    assert.deepEqual(
      resolveManifestTarget({ target: 'esp32-c3' }, 'esp32_c3'),
      { target: 'esp32-c3', declared: 'esp32-c3', mismatch: false },
    );
    // yanlis klasore konmus manifest
    const wrong = resolveManifestTarget({ target: 'esp32-c3' }, 'esp32-wroom');
    assert.equal(wrong.mismatch, true);
    assert.equal(wrong.target, 'esp32-c3');
    // bozuk hedef alani
    const bad = resolveManifestTarget({ target: '../x' }, 'esp32-c3');
    assert.equal(bad.mismatch, true);
    assert.equal(bad.target, 'esp32-c3');
  });

  it('checkDeviceFirmwareTarget: bilinen cihazin donanimi hedefle uyusmali', () => {
    assert.deepEqual(
      checkDeviceFirmwareTarget({ folderTarget: 'esp32-wroom', hardwareType: 'esp32_wroom' }),
      { ok: true, checked: true, expected: 'esp32-wroom', requested: 'esp32-wroom' },
    );
    const mismatch = checkDeviceFirmwareTarget({ folderTarget: 'esp32-wroom', hardwareType: 'esp32_c3' });
    assert.equal(mismatch.ok, false);
    assert.equal(mismatch.expected, 'esp32-c3');
    // donanim tipi bilinmiyorsa kontrol yapilamaz
    assert.equal(checkDeviceFirmwareTarget({ folderTarget: 'esp32-c3', hardwareType: null }).checked, false);
    assert.equal(checkDeviceFirmwareTarget({ folderTarget: 'esp32-c3', hardwareType: null }).ok, true);
  });

  it('checkDeviceFirmwareTarget: cihazin bildirdigi hedef (reportedTarget) kesin bilgidir ve DB tipine ustundur', () => {
    // DB tipi yanlis (varsayilan esp32_c3) ama cihaz wroom bildirmis ve wroom klasoru istiyor -> uyumlu
    const healed = checkDeviceFirmwareTarget({
      folderTarget: 'esp32-wroom', hardwareType: 'esp32_c3', reportedTarget: 'esp32-wroom',
    });
    assert.equal(healed.ok, true);
    assert.equal(healed.source, 'reported');
    // cihaz kendi hedefiyle celisen klasoru istiyorsa kesin uyusmazlik
    const conflict = checkDeviceFirmwareTarget({
      folderTarget: 'esp32-wroom', hardwareType: 'esp32_wroom', reportedTarget: 'esp32_c3',
    });
    assert.equal(conflict.ok, false);
    assert.equal(conflict.source, 'reported');
    assert.equal(conflict.expected, 'esp32-c3');
    // gecersiz/bos bildirim yok sayilir: eski davranis (source yok -> kesin degil)
    const fallback = checkDeviceFirmwareTarget({ folderTarget: 'esp32-wroom', hardwareType: 'esp32_c3', reportedTarget: '../x' });
    assert.equal(fallback.ok, false);
    assert.equal(fallback.source, undefined);
  });

  it('parseManifestQueryUid ve normalizeClientIp', () => {
    assert.equal(parseManifestQueryUid('d4c771a172e0'), 'D4C771A172E0');
    assert.equal(parseManifestQueryUid('ZZ'), '');
    assert.equal(parseManifestQueryUid('D4C771A172E0\nX'), '');
    assert.equal(parseManifestQueryUid(undefined), '');
    assert.equal(normalizeClientIp('::ffff:203.0.113.9'), '203.0.113.9');
    assert.equal(normalizeClientIp('2001:db8::1'), '2001:db8::1');
    assert.equal(normalizeClientIp('1.2.3.4, 5.6.7.8'), '');
    assert.equal(normalizeClientIp(''), '');
  });
});

// ---- Route: gercek firmware_routes.js, gecici FIRMWARE_DIR ve sahte cihaz aramasi ---------------

describe('devices: GET /firmware/:target/manifest.json', () => {
  let tmpDir;
  let server;
  let baseUrl;
  let restoreHooks;
  let lookupCalls;
  let ipUpdates;
  let lookupImpl;

  const KEYS = [
    'enabled', 'target', 'update_available', 'version', 'force', 'usb_required', 'url',
    'sha256', 'md5', 'notes', 'interval_hours', 'message',
  ].sort();

  function writeManifest(folder, manifest) {
    fs.mkdirSync(path.join(tmpDir, folder), { recursive: true });
    fs.writeFileSync(path.join(tmpDir, folder, 'manifest.json'), JSON.stringify(manifest));
  }

  before(async () => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'fw-test-'));
    process.env.FIRMWARE_DIR = tmpDir;
    process.env.PUBLIC_BASE_URL = 'https://api.example.test';

    writeManifest('esp32-c3', {
      enabled: true, target: 'esp32-c3', version: '3.5.0', filename: 'firmware.bin', force: true,
      usb_required: false, interval_hours: 1, allowed_uids: [], sha256: 'a'.repeat(64),
      md5: 'b'.repeat(32), notes: 'c3 notu',
    });
    writeManifest('esp32-wroom', {
      enabled: true, target: 'esp32-wroom', version: '5.0.5', filename: 'firmware.bin', force: true,
      usb_required: false, interval_hours: 1, allowed_uids: [], sha256: 'c'.repeat(64),
      md5: 'd'.repeat(32), notes: 'wroom notu',
    });
    // klasor adi _ ile, manifest hedefi - ile: yanit hedefi manifestten, URL klasorden gelmeli
    writeManifest('esp32_c3', { enabled: true, target: 'esp32-c3', version: '9.0.0', filename: 'firmware.bin' });
    // yanlis klasore konmus manifest
    writeManifest('esp32-misplaced', { enabled: true, target: 'esp32-c3', version: '9.9.9', filename: 'firmware.bin' });

    const { firmwareRouter, setFirmwareRouteHooksForTests } = await import('../src/routes/firmware_routes.js');
    lookupCalls = [];
    ipUpdates = [];
    lookupImpl = async () => null;
    restoreHooks = setFirmwareRouteHooksForTests({
      lookupDevice: async (uid) => {
        lookupCalls.push(uid);
        return lookupImpl(uid);
      },
      updatePublicIp: async (uid, ip) => {
        ipUpdates.push({ uid, ip });
      },
    });

    const app = express();
    app.use(firmwareRouter);
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(async () => {
    if (restoreHooks) {
      restoreHooks();
    }
    if (server) {
      await new Promise((resolve) => server.close(resolve));
    }
    if (tmpDir) {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  async function getJson(pathAndQuery, headers = {}) {
    const response = await fetch(`${baseUrl}${pathAndQuery}`, { headers });
    return { status: response.status, body: await response.json() };
  }

  it('yanit sekli korunur ve hedef manifestten gelir', async () => {
    lookupCalls.length = 0;
    const { status, body } = await getJson('/firmware/esp32-c3/manifest.json?current_version=3.4.0');
    assert.equal(status, 200);
    assert.deepEqual(Object.keys(body).sort(), KEYS);
    assert.equal(body.enabled, true);
    assert.equal(body.target, 'esp32-c3');
    assert.equal(body.update_available, true);
    assert.equal(body.version, '3.5.0');
    assert.equal(body.force, true);
    assert.equal(body.usb_required, false);
    assert.equal(body.url, 'https://api.example.test/firmware/esp32-c3/firmware.bin');
    assert.equal(body.sha256, 'a'.repeat(64));
    assert.equal(body.md5, 'b'.repeat(32));
    assert.equal(body.notes, 'c3 notu');
    assert.equal(body.interval_hours, 1);
    assert.equal(body.message, '');
    assert.equal(lookupCalls.length, 0, 'uid yoksa cihaz aramasi yapilmaz');
  });

  it('wroom hedefi kendi manifestini ve klasorunu kullanir (hedefler karismaz)', async () => {
    const { body } = await getJson('/firmware/esp32-wroom/manifest.json?current_version=5.0.0');
    assert.equal(body.target, 'esp32-wroom');
    assert.equal(body.version, '5.0.5');
    assert.equal(body.url, 'https://api.example.test/firmware/esp32-wroom/firmware.bin');
  });

  it('guncel surumde update_available=false ve url=null', async () => {
    const { body } = await getJson('/firmware/esp32-c3/manifest.json?current_version=3.5.0');
    assert.equal(body.update_available, false);
    assert.equal(body.url, null);
  });

  it('klasor esp32_c3 iken yanit hedefi manifestteki esp32-c3, URL gercek klasorden', async () => {
    const { body } = await getJson('/firmware/esp32_c3/manifest.json?current_version=1.0.0');
    assert.equal(body.target, 'esp32-c3');
    assert.equal(body.update_available, true);
    assert.equal(body.url, 'https://api.example.test/firmware/esp32_c3/firmware.bin');
  });

  it('yanlis klasordeki manifest: guncelleme sunulmaz', async () => {
    const { status, body } = await getJson('/firmware/esp32-misplaced/manifest.json?current_version=1.0.0');
    assert.equal(status, 200);
    assert.equal(body.update_available, false);
    assert.equal(body.url, null);
    assert.equal(body.target, 'esp32-c3');
    assert.match(body.message, /uyusmuyor/);
  });

  it('manifesti olmayan hedef ve gecersiz hedef', async () => {
    const none = await getJson('/firmware/esp32-yok/manifest.json');
    assert.equal(none.status, 200);
    assert.equal(none.body.enabled, false);
    assert.equal(none.body.update_available, false);

    const invalid = await getJson('/firmware/a/manifest.json');
    assert.equal(invalid.status, 400);
  });

  it('bilinen cihaz + cihazin KENDI bildirdigi hedefle celisen istek: 403 FIRMWARE_TARGET_MISMATCH, IP guncellenmez', async () => {
    ipUpdates.length = 0;
    lookupImpl = async () => ({ hardware_type: 'esp32_c3', hardware_target: 'esp32-c3' });
    const { status, body } = await getJson(
      '/firmware/esp32-wroom/manifest.json?current_version=1.0.0&uid=D4C771A172E0',
    );
    assert.equal(status, 403);
    assert.equal(body.code, 'FIRMWARE_TARGET_MISMATCH');
    assert.equal(body.update_available, false);
    assert.equal(ipUpdates.length, 0);
  });

  it('SADECE DB hardware_type celisiyor (cihaz hedef bildirmemis): cihaz kalici 403e kilitlenmez, manifest sunulur', async () => {
    ipUpdates.length = 0;
    // sirket araci/uygulama kaydi WROOM kartini varsayilan esp32_c3 yazmis; cihaz henuz MQTT durumu yayinlamamis
    lookupImpl = async () => ({ hardware_type: 'esp32_c3', hardware_target: null });
    const { status, body } = await getJson(
      '/firmware/esp32-wroom/manifest.json?current_version=1.0.0&uid=D4C771A172E0',
    );
    assert.equal(status, 200);
    assert.notEqual(body.code, 'FIRMWARE_TARGET_MISMATCH');
    assert.equal(body.target, 'esp32-wroom');
    assert.equal(body.update_available, true);
    assert.equal(ipUpdates.length, 1);
  });

  it('cihazin bildirdigi hedef istenen klasorle uyusuyorsa DB tipi yanlis olsa bile 200 (cihaz bildirimi esastir)', async () => {
    ipUpdates.length = 0;
    lookupImpl = async () => ({ hardware_type: 'esp32_c3', hardware_target: 'esp32-wroom' });
    const { status, body } = await getJson(
      '/firmware/esp32-wroom/manifest.json?current_version=1.0.0&uid=D4C771A172E0',
    );
    assert.equal(status, 200);
    assert.equal(body.update_available, true);
    assert.equal(ipUpdates.length, 1);
    // yanit sekli degismez
    assert.deepEqual(Object.keys(body).sort(), KEYS);
  });

  it('bilinen cihaz + uyumlu donanim: 200 ve genel IP req.ip ile guncellenir (X-Forwarded-For yok sayilir)', async () => {
    ipUpdates.length = 0;
    lookupImpl = async () => ({ hardware_type: 'esp32_wroom' });
    const { status, body } = await getJson(
      '/firmware/esp32-wroom/manifest.json?current_version=1.0.0&uid=d4c771a172e0',
      { 'X-Forwarded-For': '1.2.3.4' },
    );
    assert.equal(status, 200);
    assert.equal(body.update_available, true);
    assert.equal(ipUpdates.length, 1);
    assert.equal(ipUpdates[0].uid, 'D4C771A172E0');
    assert.equal(ipUpdates[0].ip, '127.0.0.1');
  });

  it('DB\'de kayitli olmayan UID: durum/IP tutulmaz ama manifest yine sunulur', async () => {
    ipUpdates.length = 0;
    lookupImpl = async () => null;
    const { status, body } = await getJson('/firmware/esp32-c3/manifest.json?current_version=1.0.0&uid=AABBCCDDEEFF');
    assert.equal(status, 200);
    assert.equal(body.update_available, true);
    assert.equal(ipUpdates.length, 0);
  });

  it('gecersiz bicimli UID: DB aramasi ve IP guncellemesi yapilmaz', async () => {
    lookupCalls.length = 0;
    ipUpdates.length = 0;
    const { status } = await getJson('/firmware/esp32-c3/manifest.json?uid=ZZ-not-hex');
    assert.equal(status, 200);
    assert.equal(lookupCalls.length, 0);
    assert.equal(ipUpdates.length, 0);
  });

  it('cihaz aramasi hata verirse 503 (hata metni sizmaz)', async () => {
    lookupImpl = async () => {
      throw new Error('connect ECONNREFUSED 10.0.0.5:5432');
    };
    const { status, body } = await getJson('/firmware/esp32-c3/manifest.json?uid=D4C771A172E0');
    assert.equal(status, 503);
    assert.ok(!JSON.stringify(body).includes('ECONNREFUSED'));
    lookupImpl = async () => null;
  });
});
