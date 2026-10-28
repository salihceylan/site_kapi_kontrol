// OTA imza - HTTP duzeyi: gercek firmware_routes.js (cihaz ucu) + firmware_admin_routes.js (yukleme ucu), gecici FIRMWARE_DIR,
// gercek authRequired/requireSuperUser (DB yerine sahte pool.query). Test anahtarlari calisma aninda uretilir; depoda ozel anahtar YOK.
import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';

import express from 'express';

const SECRET = 'k9Fz-test-only-long-secret-value-0123456789abcdef';
const HASH = '$2a$10$AAAAAAAAAAAAAAAAAAAAAA';
const BASE = 'https://api.example.test';

const sha256Of = (buffer) => crypto.createHash('sha256').update(buffer).digest('hex');

describe('OTA imza: yukleme ucu + cihaz ucu (HTTP)', () => {
  let tmpDir;
  let server;
  let baseUrl;
  let keys;
  let publicKeyHex;
  let pool;
  let adminSensitiveLimiter;
  let restoreRouteHooks;
  let restoreAdminHooks;
  let adminRouterUnderTest;
  let tokenFor;
  let auditEntries;
  let auditResult;
  let sigLib;
  let OTA_UPLOAD_TARGETS;
  const savedEnv = {};
  const savedConsole = { log: console.log, error: console.error, warn: console.warn };

  const dirOf = (target) => path.join(tmpDir, target);
  const readManifest = (target) => JSON.parse(fs.readFileSync(path.join(dirOf(target), 'manifest.json'), 'utf8'));
  const listDir = (target) => (fs.existsSync(dirOf(target)) ? fs.readdirSync(dirOf(target)).sort() : []);
  const rawPublicHex = (publicKey) => publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('hex');

  function fakeImage(target, seed) {
    const pattern = crypto.createHash('sha512').update(`${target}:${seed}`).digest();
    const image = Buffer.alloc(8192);
    for (let i = 0; i < image.length; i += 1) {
      image[i] = pattern[i % pattern.length];
    }
    image[0] = 0xe9;
    image.writeUInt16LE(OTA_UPLOAD_TARGETS[target], 12);
    return image;
  }

  /** tools/ota_imza `.sig` nesnesi. `override` ile alanlar bozulabilir. */
  function sigObject({ target, version, image, signKey = keys, format = 'KAPI-OTA-IMZA-V1', rollbackMax = null, override = {} }) {
    const fields = { target, version, size: image.length, sha256: sha256Of(image) };
    const signature = crypto.sign(null, sigLib.buildOtaSignedMessage({ format, ...fields, rollbackMax }), signKey.privateKey);
    return {
      format, algorithm: 'Ed25519', ...fields, key_id: sigLib.otaKeyId(signKey.publicKey), signature: signature.toString('hex'), ...override,
    };
  }

  const sigFileText = (sig) => sigLib.renderOtaSigFile({
    format: sig.format, target: sig.target, version: sig.version, size: sig.size, sha256: sig.sha256, keyId: sig.key_id, signature: sig.signature,
  });

  async function withEnv(vars, fn) {
    const previous = {};
    for (const [name, value] of Object.entries(vars)) {
      previous[name] = process.env[name];
      if (value === undefined) {
        delete process.env[name];
      } else {
        process.env[name] = value;
      }
    }
    try {
      return await fn();
    } finally {
      for (const [name, value] of Object.entries(previous)) {
        if (value === undefined) {
          delete process.env[name];
        } else {
          process.env[name] = value;
        }
      }
    }
  }

  /**
   * Paketi yukler. Varsayilan imza girdisi: dogru `.sig` DOSYASININ base64'u (curl: -H "X-Ota-Signature: $(base64 -w0 firmware.bin.sig)").
   * `signatureHeader: null` basligi cikarir; `signatureHeader` metin verilirse aynen gonderilir; `sigOverride` `.sig` alanlarini bozar.
   */
  async function upload({
    target = 'esp32-c3', version, seed = version, image, query = {}, token = tokenFor(1), contentType = 'application/octet-stream',
    signatureHeader, signKey, sigOverride, format, rollbackMax, sendVersion = true, headers = {}, keepLimiter = false,
  } = {}) {
    if (!keepLimiter) {
      adminSensitiveLimiter.reset(); // hiz siniri ayri bir testte sinanir; diger testler arka arkaya cok istek atar
    }
    const firmware = image ?? fakeImage(target, seed);
    const params = new URLSearchParams({ ...(version !== undefined && sendVersion ? { version } : {}), ...query });
    const requestHeaders = { 'Content-Type': contentType, ...headers };
    if (token) {
      requestHeaders.Authorization = `Bearer ${token}`;
    }
    let header = signatureHeader;
    if (header === undefined) {
      try {
        header = Buffer.from(sigFileText(sigObject({ target, version, image: firmware, signKey, format, rollbackMax, override: sigOverride }))).toString('base64');
      } catch (_error) {
        header = Buffer.alloc(64).toString('base64'); // gecersiz surum/hedef icin imza uretilemez; sunucu zaten bicimden reddeder
      }
    }
    if (header !== null) {
      requestHeaders['X-Ota-Signature'] = header;
    }
    const response = await fetch(`${baseUrl}/admin/firmware/${target}/releases?${params}`, { method: 'POST', headers: requestHeaders, body: firmware });
    return { status: response.status, body: await response.json(), firmware };
  }

  async function manifestFor(target, currentVersion, extra = '') {
    const response = await fetch(`${baseUrl}/firmware/${target}/manifest.json?current_version=${currentVersion}${extra}`);
    return { status: response.status, body: await response.json() };
  }

  async function getBytes(urlPath) {
    const response = await fetch(`${baseUrl}${urlPath}`);
    return { status: response.status, headers: response.headers, bytes: Buffer.from(await response.arrayBuffer()) };
  }

  before(async () => {
    console.log = () => {};
    console.error = () => {};
    console.warn = () => {};
    for (const name of ['FIRMWARE_DIR', 'PUBLIC_BASE_URL', 'JWT_SECRET', 'OTA_PUBLIC_KEY', 'OTA_SERVE_UNSIGNED', 'OTA_MAX_FIRMWARE_BYTES']) {
      savedEnv[name] = process.env[name];
    }
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ota-http-'));
    keys = crypto.generateKeyPairSync('ed25519');
    publicKeyHex = rawPublicHex(keys.publicKey);
    process.env.FIRMWARE_DIR = tmpDir;
    process.env.PUBLIC_BASE_URL = BASE;
    process.env.JWT_SECRET = SECRET;
    process.env.OTA_PUBLIC_KEY = publicKeyHex;
    delete process.env.OTA_SERVE_UNSIGNED;
    delete process.env.OTA_MAX_FIRMWARE_BYTES;

    ({ pool } = await import('../src/db.js'));
    ({ adminSensitiveLimiter } = await import('../src/middlewares/rate_limiters.js'));
    const { signAccessToken } = await import('../src/jwt.js');
    const { createErrorHandler } = await import('../src/middlewares/error_handler.js');
    ({ OTA_UPLOAD_TARGETS } = await import('../src/services/firmware_release_service.js'));
    sigLib = await import('../src/services/ota_signature.js');
    const { firmwareRouter, setFirmwareRouteHooksForTests } = await import('../src/routes/firmware_routes.js');
    const { firmwareAdminRouter, setFirmwareAdminHooksForTests } = await import('../src/routes/firmware_admin_routes.js');
    adminRouterUnderTest = firmwareAdminRouter;

    // Sahte kullanici tablosu (authRequired DB'ye bu sorguyla gider): 1 super, 2 site yoneticisi, 3 bireysel
    const roles = { 1: 'super_user', 2: 'site_manager', 3: 'individual' };
    pool.query = async (_sql, params) => {
      const code = Number(params?.[0]);
      const role = roles[code];
      if (!role) {
        return { rows: [], rowCount: 0 };
      }
      return {
        rowCount: 1,
        rows: [{
          db_id: code, id: code, user_code: code, full_name: `Test ${code}`, email: `u${code}@example.test`, login_name: null, role,
          is_active: true, email_verified: true, approval_status: 'approved', phone_number: null, created_at: new Date(), password_hash: HASH,
        }],
      };
    };
    tokenFor = (code) => signAccessToken({ id: code }, { passwordHash: HASH });

    auditEntries = [];
    auditResult = true;
    restoreAdminHooks = setFirmwareAdminHooksForTests({
      recordAudit: async (entry) => {
        auditEntries.push(entry);
        return auditResult;
      },
    });
    restoreRouteHooks = setFirmwareRouteHooksForTests({ lookupDevice: async () => null, updatePublicIp: async () => {} });

    const app = express();
    app.use(firmwareRouter);
    app.use(firmwareAdminRouter);
    app.use(createErrorHandler({ logger: { error() {} } }));
    await new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', resolve);
    });
    baseUrl = `http://127.0.0.1:${server.address().port}`;
  });

  after(async () => {
    Object.assign(console, savedConsole);
    restoreRouteHooks?.();
    restoreAdminHooks?.();
    if (pool) {
      delete pool.query;
    }
    if (server) {
      await new Promise((resolve) => server.close(resolve));
    }
    for (const [name, value] of Object.entries(savedEnv)) {
      if (value === undefined) {
        delete process.env[name];
      } else {
        process.env[name] = value;
      }
    }
    if (tmpDir) {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  beforeEach(() => {
    adminSensitiveLimiter.reset();
    auditEntries.length = 0;
    auditResult = true;
    for (const target of ['esp32-c3', 'esp32-wroom']) {
      fs.rmSync(dirOf(target), { recursive: true, force: true });
    }
  });

  describe('A) yukleme ucu: imza zorunlu', () => {
    it('kimliksiz istek 401, yetkisiz roller 403 (govde okunmadan)', async () => {
      const noToken = await upload({ version: '4.3.4', token: null });
      assert.equal(noToken.status, 401);
      assert.equal((await upload({ version: '4.3.4', token: tokenFor(2) })).status, 403);
      assert.equal((await upload({ version: '4.3.4', token: tokenFor(3) })).status, 403);
      const list = await fetch(`${baseUrl}/admin/firmware/esp32-c3/releases`, { headers: { Authorization: `Bearer ${tokenFor(2)}` } });
      assert.equal(list.status, 403);
      assert.equal((await fetch(`${baseUrl}/admin/firmware/esp32-c3/releases`)).status, 401);
      assert.deepEqual(listDir('esp32-c3'), []);
    });

    it('ara katman zinciri sabit: kimlik -> super kullanici -> hiz siniri -> on kontrol -> ham govde -> yayin (govde yetkiden ONCE okunmaz)', () => {
      const find = (method) => adminRouterUnderTest.stack.find(
        (layer) => layer.route && layer.route.path === '/admin/firmware/:target/releases' && layer.route.methods[method],
      ).route;
      const post = find('post');
      assert.deepEqual(post.stack.map((layer) => layer.name), ['authRequired', 'requireSuperUser', adminSensitiveLimiter.name, 'prepareRelease', 'receiveFirmware', 'handleRelease']);
      assert.equal(post.stack[2].handle, adminSensitiveLimiter);
      const get = find('get');
      assert.deepEqual(get.stack.slice(0, 2).map((layer) => layer.name), ['authRequired', 'requireSuperUser']);
    });

    it('hiz siniri: ayni yoneticiden 15 dakikada en fazla 10 yukleme denemesi (basarisizlar dahil); 11.si 429', async () => {
      const statuses = [];
      for (let i = 0; i < 11; i += 1) {
        statuses.push((await upload({ version: '4.3.4', signatureHeader: null, keepLimiter: true })).status);
      }
      assert.deepEqual(statuses, [...Array(10).fill(400), 429]);
    });

    it('IMZASIZ yukleme 400 FIRMWARE_SIGNATURE_REQUIRED + Turkce mesaj; diske hicbir sey yazilmaz', async () => {
      const response = await upload({ version: '4.3.4', signatureHeader: null });
      assert.equal(response.status, 400);
      assert.equal(response.body.code, 'FIRMWARE_SIGNATURE_REQUIRED');
      assert.match(response.body.error, /İmzasız paket yüklenemez/);
      const blank = await upload({ version: '4.3.4', signatureHeader: '   ' });
      assert.equal(blank.status, 400);
      assert.equal(blank.body.code, 'FIRMWARE_SIGNATURE_REQUIRED');
      assert.deepEqual(listDir('esp32-c3'), []);
      assert.equal(auditEntries.length, 0);
    });

    it('BOZUK biçimli imza 400 FIRMWARE_SIGNATURE_MALFORMED; biçimi dogru ama YANLIS imza 400 FIRMWARE_SIGNATURE_INVALID', async () => {
      for (const header of ['bu bir imza degil!', 'AAAA', 'x'.repeat(300), Buffer.from('{ bozuk json').toString('base64'), '{"format":"KAPI-OTA-IMZA-V1"}']) {
        const response = await upload({ version: '4.3.4', signatureHeader: header });
        assert.equal(response.status, 400, header);
        assert.equal(response.body.code, 'FIRMWARE_SIGNATURE_MALFORMED', header);
      }
      const zeroBare = await upload({ version: '4.3.4', signatureHeader: Buffer.alloc(64).toString('hex') });
      assert.equal(zeroBare.status, 400);
      assert.equal(zeroBare.body.code, 'FIRMWARE_SIGNATURE_INVALID');
      assert.match(zeroBare.body.error, /İmza doğrulanamadı/);
      const zeroFile = await upload({ version: '4.3.4', sigOverride: { signature: '0'.repeat(128) } });
      assert.equal(zeroFile.body.code, 'FIRMWARE_SIGNATURE_INVALID');

      const otherKey = crypto.generateKeyPairSync('ed25519');
      const forged = await upload({ version: '4.3.4', signKey: otherKey });
      assert.equal(forged.status, 400);
      assert.equal(forged.body.code, 'FIRMWARE_SIGNATURE_KEY_UNKNOWN', 'baska anahtarin key_id\'si guvenilen anahtarlar arasinda degil');
      const spoofed = await upload({ version: '4.3.4', signKey: otherKey, sigOverride: { key_id: sigLib.otaKeyId(keys.publicKey) } });
      assert.equal(spoofed.body.code, 'FIRMWARE_SIGNATURE_INVALID', 'key_id taklidi imzayi gecerli kilmaz');

      // gecerli imza ama baska icerik / baska surum / baska hedef icin
      const image = fakeImage('esp32-c3', 'a');
      const wrongContent = await upload({ version: '4.3.4', image, signatureHeader: Buffer.from(sigFileText(sigObject({ target: 'esp32-c3', version: '4.3.4', image: fakeImage('esp32-c3', 'b') }))).toString('base64') });
      assert.equal(wrongContent.body.code, 'FIRMWARE_SIGNATURE_MISMATCH');
      const wrongVersion = await upload({ version: '4.3.4', image, signatureHeader: Buffer.from(sigFileText(sigObject({ target: 'esp32-c3', version: '4.3.3', image }))).toString('base64') });
      assert.equal(wrongVersion.body.code, 'FIRMWARE_SIGNATURE_MISMATCH');
      const wrongTarget = await upload({ version: '4.3.4', image, signatureHeader: Buffer.from(sigFileText(sigObject({ target: 'esp32-wroom', version: '4.3.4', image }))).toString('base64') });
      assert.equal(wrongTarget.body.code, 'FIRMWARE_SIGNATURE_MISMATCH');
      assert.deepEqual(listDir('esp32-c3'), []);
      assert.equal(auditEntries.length, 0);
    });

    it('imzali paket 201: .sig dosyasinin base64\'u, tek satirlik ham JSON ve ciplak imza (hex / base64) ile yuklenebilir; surum .sig\'den alinir', async () => {
      // (1) curl ornegi: sorguda surum YOK, hepsi .sig dosyasindan
      const image = fakeImage('esp32-c3', 'hex');
      const first = await upload({ version: '4.3.4', image, sendVersion: false, query: { notes: 'Ilk imzali surum' } });
      assert.equal(first.status, 201, JSON.stringify(first.body));
      assert.equal(first.body.ok, true);
      assert.equal(first.body.version, '4.3.4');
      assert.equal(first.body.signed, true);
      assert.equal(first.body.signature_format, 'KAPI-OTA-IMZA-V1');
      assert.equal(first.body.sha256, sha256Of(image));
      assert.equal(first.body.size_bytes, image.length);
      assert.equal(first.body.url, `${BASE}/firmware/esp32-c3/firmware-v4.3.4.bin`);
      assert.equal(first.body.signature_url, `${BASE}/firmware/esp32-c3/firmware-v4.3.4.bin.sig`);
      assert.equal(first.body.audience, 'all');
      assert.match(first.body.message, /İmza doğrulandı/);
      assert.deepEqual(listDir('esp32-c3'), ['firmware-v4.3.4.bin', 'firmware-v4.3.4.bin.sig', 'firmware-v4.3.4.release.json', 'manifest.json']);
      assert.equal(auditEntries.length, 1);
      assert.equal(auditEntries[0].action, 'ota_release_published');
      assert.equal(auditEntries[0].actor.user_code, 1, 'denetim kaydina yukleyen kimligi eklenir');

      // (2) tek satirlik ham JSON basligi
      const rawJson = JSON.stringify(sigObject({ target: 'esp32-c3', version: '4.3.5', image: fakeImage('esp32-c3', '4.3.5') }));
      assert.equal((await upload({ version: '4.3.5', signatureHeader: rawJson })).status, 201);
      // (3) ciplak imza (onaltilik) + zorunlu surum sorgusu; (4) ciplak imza base64
      const bareImage = fakeImage('esp32-c3', 'bare');
      const bareSignature = crypto.sign(null, sigLib.buildOtaSignedMessage({ target: 'esp32-c3', version: '4.3.6', size: bareImage.length, sha256: sha256Of(bareImage) }), keys.privateKey);
      const noVersion = await upload({ version: '4.3.6', image: bareImage, sendVersion: false, signatureHeader: bareSignature.toString('hex') });
      assert.equal(noVersion.status, 400);
      assert.equal(noVersion.body.code, 'FIRMWARE_VERSION_INVALID');
      assert.equal((await upload({ version: '4.3.6', image: bareImage, signatureHeader: bareSignature.toString('hex') })).status, 201);
      const bare64Image = fakeImage('esp32-c3', 'bare64');
      const bare64 = crypto.sign(null, sigLib.buildOtaSignedMessage({ target: 'esp32-c3', version: '4.3.7', size: bare64Image.length, sha256: sha256Of(bare64Image) }), keys.privateKey);
      assert.equal((await upload({ version: '4.3.7', image: bare64Image, signatureHeader: bare64.toString('base64') })).status, 201);
      assert.equal(readManifest('esp32-c3').version, '4.3.7');
    });

    it('hedef / surum / icerik turu / boyut / anahtar on kontrolleri govdeyi okumadan reddeder', async () => {
      assert.equal((await upload({ target: 'esp32-s3', version: '1.0.0' })).body.code, 'FIRMWARE_TARGET_INVALID');
      assert.equal((await upload({ version: 'v4.3.4' })).body.code, 'FIRMWARE_VERSION_INVALID');
      assert.equal((await upload({ version: '4.3' })).body.code, 'FIRMWARE_VERSION_INVALID');
      assert.equal((await upload({ version: '4.3.4', query: { allowed_uids: 'xyz' } })).body.code, 'FIRMWARE_OPTIONS_INVALID');
      const json = await upload({ version: '4.3.4', contentType: 'application/json' });
      assert.equal(json.status, 415);
      assert.equal(json.body.code, 'FIRMWARE_CONTENT_TYPE');

      await withEnv({ OTA_MAX_FIRMWARE_BYTES: '65536' }, async () => {
        const huge = Buffer.alloc(70000, 0x11);
        huge[0] = 0xe9;
        const tooLarge = await upload({ version: '4.3.4', image: huge });
        assert.equal(tooLarge.status, 413);
        assert.equal(tooLarge.body.code, 'FIRMWARE_TOO_LARGE');
        assert.equal(tooLarge.body.max_bytes, 65536);
      });

      // imzasiz paket, sunucu anahtari tanimli olmasa bile 400 alir (503 degil)
      await withEnv({ OTA_PUBLIC_KEY: undefined }, async () => {
        assert.equal((await upload({ version: '4.3.4', signatureHeader: null })).status, 400);
        const noKey = await upload({ version: '4.3.4' });
        assert.equal(noKey.status, 503);
        assert.equal(noKey.body.code, 'OTA_KEY_NOT_CONFIGURED');
        assert.match(noKey.body.error, /OTA_PUBLIC_KEY/);
      });
      await withEnv({ OTA_PUBLIC_KEY: 'bozuk-anahtar' }, async () => {
        const badKey = await upload({ version: '4.3.4' });
        assert.equal(badKey.status, 503);
        assert.equal(badKey.body.code, 'OTA_KEY_INVALID');
      });
      assert.deepEqual(listDir('esp32-c3'), []);
    });

    it('boyut siniri: tam sinir boyutundaki (OTA bolumu 0x1E0000) imaj kabul edilir, bir bayt fazlasi 413; parcali (chunked) govde de sinirlanir', async () => {
      const limit = 0x1e0000;
      const full = Buffer.alloc(limit, 0x5a);
      full[0] = 0xe9;
      full.writeUInt16LE(OTA_UPLOAD_TARGETS['esp32-wroom'], 12);
      const ok = await upload({ target: 'esp32-wroom', version: '5.2.2', image: full });
      assert.equal(ok.status, 201, JSON.stringify(ok.body));
      assert.equal(ok.body.size_bytes, limit);
      assert.equal(fs.statSync(path.join(dirOf('esp32-wroom'), 'firmware-v5.2.2.bin')).size, limit);

      const over = Buffer.alloc(limit + 1, 0x5a);
      over[0] = 0xe9;
      const tooLarge = await upload({ target: 'esp32-wroom', version: '5.2.3', image: over });
      assert.equal(tooLarge.status, 413);
      assert.equal(tooLarge.body.code, 'FIRMWARE_TOO_LARGE');
      assert.equal(readManifest('esp32-wroom').version, '5.2.2');

      // Content-Length olmadan (chunked) gelen govde on kontrolden gecer ama ayristirici sinirinda kesilir
      await withEnv({ OTA_MAX_FIRMWARE_BYTES: '65536' }, async () => {
        const chunk = Buffer.alloc(30000, 0x11);
        const result = await new Promise((resolve, reject) => {
          const request = http.request(
            `${baseUrl}/admin/firmware/esp32-c3/releases?version=4.3.4`,
            {
              method: 'POST',
              headers: {
                Authorization: `Bearer ${tokenFor(1)}`,
                'Content-Type': 'application/octet-stream',
                'X-Ota-Signature': Buffer.alloc(64, 1).toString('base64'),
                'Transfer-Encoding': 'chunked',
              },
            },
            (response) => {
              const parts = [];
              response.on('data', (part) => parts.push(part));
              response.on('end', () => resolve({ status: response.statusCode, body: JSON.parse(Buffer.concat(parts).toString('utf8')) }));
            },
          );
          request.on('error', reject);
          request.write(chunk);
          request.write(chunk);
          request.write(chunk);
          request.end();
        });
        assert.equal(result.status, 413);
        assert.equal(result.body.code, 'FIRMWARE_TOO_LARGE');
      });
      assert.deepEqual(listDir('esp32-c3'), []);
    });

    it('imza gecerli olsa bile baska donanima ait imaj (C3 imaji WROOM hedefine) 400 FIRMWARE_TARGET_MISMATCH', async () => {
      const c3Image = fakeImage('esp32-c3', 'karisik');
      const response = await upload({ target: 'esp32-wroom', version: '5.2.2', image: c3Image });
      assert.equal(response.status, 400);
      assert.equal(response.body.code, 'FIRMWARE_TARGET_MISMATCH');
      assert.deepEqual(listDir('esp32-wroom'), []);
    });

    it('hata gövdelerinde sunucu yolu / anahtar / yigin izi SIZMAZ', async () => {
      fs.mkdirSync(dirOf('esp32-c3'), { recursive: true });
      fs.writeFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), '{ bozuk');
      const response = await upload({ version: '4.3.4' });
      assert.equal(response.status, 409);
      const text = JSON.stringify(response.body);
      assert.equal(text.includes(tmpDir), false);
      assert.equal(text.includes(publicKeyHex), false);
      assert.equal(/at .*\.js:\d+/.test(text), false);
    });
  });

  describe('cihaz ucu: imzali yayin sunumu (D) ve indirme', () => {
    it('manifest imza alanlarini tasir; .bin ve .sig indirilir ve imza cihazdaki gibi dogrulanir', async () => {
      const image = fakeImage('esp32-c3', 'sunum');
      assert.equal((await upload({ version: '4.3.4', image })).status, 201);

      const { status, body } = await manifestFor('esp32-c3', '4.3.3');
      assert.equal(status, 200);
      assert.equal(body.update_available, true);
      assert.equal(body.version, '4.3.4');
      assert.equal(body.target, 'esp32-c3');
      assert.equal(body.url, `${BASE}/firmware/esp32-c3/firmware-v4.3.4.bin`);
      assert.equal(body.sha256, sha256Of(image));
      assert.match(body.signature, /^[0-9a-f]{128}$/, 'imza 128 hane hex (tools/ota_imza sozlesmesi)');
      assert.equal(body.signature_alg, 'Ed25519');
      assert.equal(body.signature_format, 'KAPI-OTA-IMZA-V1');
      assert.equal(body.signature_key_id, sigLib.otaKeyId(keys.publicKey));
      assert.equal(body.signature_url, `${BASE}/firmware/esp32-c3/firmware-v4.3.4.bin.sig`);
      assert.equal(body.allow_downgrade, undefined);
      // yukleyen kimligi / yayin kaydi cihaza SIZMAZ
      assert.equal(JSON.stringify(body).includes('uploaded_by'), false);
      assert.equal(JSON.stringify(body).includes('release'), false);

      const bin = await getBytes('/firmware/esp32-c3/firmware-v4.3.4.bin');
      assert.equal(bin.status, 200);
      assert.ok(bin.bytes.equals(image));
      assert.equal(bin.headers.get('content-type'), 'application/octet-stream');
      assert.equal(bin.headers.get('cache-control'), 'no-store');
      assert.equal(bin.headers.get('x-md5'), crypto.createHash('md5').update(image).digest('hex'));

      const sig = await getBytes('/firmware/esp32-c3/firmware-v4.3.4.bin.sig');
      assert.equal(sig.status, 200);
      assert.equal(sig.headers.get('content-type'), 'application/octet-stream');
      assert.equal(sig.headers.get('cache-control'), 'no-store');
      assert.equal(sig.headers.get('x-md5'), null);
      const sigFile = sigLib.parseOtaSigFile(sig.bytes.toString('utf8'));
      assert.equal(sigFile.ok, true, '.sig dosyasi tools/ota_imza bicimini tasir');
      assert.equal(sigFile.sig.signature, body.signature, 'manifestteki imza ile .sig ayni');
      assert.equal(sigFile.sig.size, image.length);

      // cihazin yaptigi dogrulama: kendi hedefi + manifest surumu + indirdigi baytlarin boyutu/sha256'si + gomulu genel anahtar
      const publicKey = crypto.createPublicKey({ key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), Buffer.from(publicKeyHex, 'hex')]), format: 'der', type: 'spki' });
      assert.equal(
        sigLib.verifyOtaSignature({
          publicKey, target: 'esp32-c3', version: body.version, size: bin.bytes.length, sha256: sha256Of(bin.bytes), signature: Buffer.from(body.signature, 'hex'),
        }),
        true,
      );
    });

    it('guncel cihaza (ayni surum) teklif yok; sunum sirasinda surum yukseltmesi calisir', async () => {
      await upload({ version: '4.3.4' });
      const same = await manifestFor('esp32-c3', '4.3.4');
      assert.equal(same.body.update_available, false);
      assert.equal(same.body.url, null);
      assert.equal(same.body.message, '');
      assert.equal(same.body.signature_url, null, 'teklif yoksa imza adresi de yok');
      await upload({ version: '4.3.5' });
      assert.equal((await manifestFor('esp32-c3', '4.3.4')).body.update_available, true);
      assert.equal((await manifestFor('esp32-c3', '4.3.4')).body.version, '4.3.5');
    });

    it('.sig sunumu guvenli: yalnizca <ad>.bin.sig, yol gezintisi / ust dizin / buyuk dosya / diger uzantilar yok', async () => {
      await upload({ version: '4.3.4' });
      assert.equal((await getBytes('/firmware/esp32-c3/firmware-v9.9.9.bin.sig')).status, 404);
      for (const bad of [
        'manifest.json.sig', 'firmware-v4.3.4.bin.sig.sig', 'firmware-v4.3.4.release.json',
        '..%2Fmanifest.bin.sig', '%2e%2e%2f%2e%2e%2fetc%2fpasswd.bin.sig', '.sig', 'a.sig',
      ]) {
        const response = await getBytes(`/firmware/esp32-c3/${bad}`);
        assert.ok([400, 404].includes(response.status), `${bad}: ${response.status}`);
      }
      assert.equal((await getBytes('/firmware/esp32-wroom/firmware-v4.3.4.bin.sig')).status, 404, 'baska hedef klasorunden sunulmaz');
      fs.writeFileSync(path.join(dirOf('esp32-c3'), 'buyuk.bin.sig'), Buffer.alloc(5000, 1));
      assert.equal((await getBytes('/firmware/esp32-c3/buyuk.bin.sig')).status, 404, 'beklenmedik buyuk dosya imza diye sunulmaz');
      // sidecar kayit (yukleyen bilgisi) indirilemez
      assert.equal((await getBytes('/firmware/esp32-c3/firmware-v4.3.4.release.json')).status, 400);
    });

    it('sunucuda imza dogrulamasi: elle bozulan imzali manifest (surum / sha256 / hedef / imza) SUNULMAZ', async () => {
      await upload({ version: '4.3.4' });
      const manifestPath = path.join(dirOf('esp32-c3'), 'manifest.json');
      const original = fs.readFileSync(manifestPath, 'utf8');
      const mutate = (changes) => fs.writeFileSync(manifestPath, JSON.stringify({ ...JSON.parse(original), ...changes }));

      for (const [name, changes] of Object.entries({
        version: { version: '9.0.0' },
        sha256: { sha256: 'b'.repeat(64) },
        target: { target: 'esp32-wroom' },
        signature: { signature: 'ab'.repeat(64) },
        garbage: { signature: 'bozuk imza metni!!' },
        object: { signature: { value: 'x' } },
        rollback: { rollback_max: '9.9.9' },
      })) {
        mutate(changes);
        const { body } = await manifestFor('esp32-c3', '4.0.0');
        assert.equal(body.update_available, false, name);
        assert.equal(body.url, null, name);
        assert.equal(body.signature, undefined, `${name}: gecersiz imza cihaza verilmez`);
        if (name !== 'target') {
          assert.match(body.message, /imza/i, name);
        }
      }
      // paket dosyasi degistirilirse (boyut degisir) imza artik uymaz
      fs.writeFileSync(manifestPath, original);
      assert.equal((await manifestFor('esp32-c3', '4.0.0')).body.update_available, true, 'orijinal manifest yine sunulur');
      const binPath = path.join(dirOf('esp32-c3'), 'firmware-v4.3.4.bin');
      const binBefore = fs.readFileSync(binPath);
      fs.writeFileSync(binPath, Buffer.concat([binBefore, Buffer.from([0])]));
      const resized = await manifestFor('esp32-c3', '4.0.0');
      assert.equal(resized.body.update_available, false, 'boyutu degisen paket sunulmaz');
      fs.writeFileSync(binPath, binBefore);
      assert.equal((await manifestFor('esp32-c3', '4.0.0')).body.update_available, true);
    });

    it('sunucu anahtari yoksa imzali yayin yine sunulur (cihaz kendi anahtariyla dogrular) ama sunucu-dogrulamali istisnalar devre disi kalir', async () => {
      await upload({ version: '4.3.4' });
      await withEnv({ OTA_PUBLIC_KEY: undefined }, async () => {
        const { body } = await manifestFor('esp32-c3', '4.0.0');
        assert.equal(body.update_available, true);
        assert.equal(typeof body.signature, 'string');
      });
    });

    it('anahtar DONUSU: sunucu anahtari degisince eski anahtarla imzali canli yayin kapanmaz; iki anahtar birlikte guvenilirse dogrulanir; yeni yuklemeler yeni anahtarla', async () => {
      await upload({ version: '4.3.5' });
      await upload({ version: '4.3.4', query: { allow_downgrade: '1', downgrade_reason: 'acil geri donus gerekcesi yeterince uzun' } });
      const next = crypto.generateKeyPairSync('ed25519');
      const nextHex = rawPublicHex(next.publicKey);

      await withEnv({ OTA_PUBLIC_KEY: nextHex }, async () => {
        // yalniz yeni anahtar guveniliyor: eski anahtarla imzali canli yayin sunucuda dogrulanamaz ama cihazlara sunulmaya devam eder
        const older = await manifestFor('esp32-c3', '4.3.3');
        assert.equal(older.body.update_available, true);
        assert.equal(older.body.version, '4.3.4');
        assert.equal(typeof older.body.signature, 'string');
        // ama dogrulanmamis imza surum dusurme istisnasini ACMAZ
        const rollback = await manifestFor('esp32-c3', '4.3.5');
        assert.equal(rollback.body.update_available, false);
        assert.equal(rollback.body.allow_downgrade, undefined);

        const listing = await fetch(`${baseUrl}/admin/firmware/esp32-c3/releases`, { headers: { Authorization: `Bearer ${tokenFor(1)}` } });
        assert.equal((await listing.json()).live.server_verified, null, 'sunucu dogrulayamadi (false degil null)');

        // yeni yuklemeler YALNIZ guvenilen anahtarlarla kabul edilir
        const oldKeySigned = await upload({ version: '4.4.0' });
        assert.equal(oldKeySigned.status, 400);
        assert.equal(oldKeySigned.body.code, 'FIRMWARE_SIGNATURE_KEY_UNKNOWN');
        const newKeySigned = await upload({ version: '4.4.0', signKey: next });
        assert.equal(newKeySigned.status, 201, JSON.stringify(newKeySigned.body));
        assert.equal(newKeySigned.body.signature_key_id, sigLib.otaKeyId(next.publicKey));
        assert.equal((await manifestFor('esp32-c3', '4.3.3')).body.version, '4.4.0');
      });

      // gecis penceresi: ikisi de guveniliyorsa (virgulle) eski anahtarin imzasi yine DOGRULANIR (surum dusurme istisnasi geri gelir)
      fs.rmSync(dirOf('esp32-c3'), { recursive: true, force: true });
      await upload({ version: '4.3.5' });
      await upload({ version: '4.3.4', query: { allow_downgrade: '1', downgrade_reason: 'acil geri donus gerekcesi yeterince uzun' } });
      await withEnv({ OTA_PUBLIC_KEY: `${nextHex},${publicKeyHex}` }, async () => {
        const rollback = await manifestFor('esp32-c3', '4.3.5');
        assert.equal(rollback.body.update_available, true);
        assert.equal(rollback.body.allow_downgrade, true);
        assert.equal((await upload({ version: '4.4.0', signKey: next })).status, 201, 'yeni anahtar da kabul');
      });

      // kimligi guvenilen anahtarla eslesen ama imzasi bozuk manifest hala kapanir (yalniz BILINMEYEN kimlik "dogrulayamaz" sayilir)
      const manifestPath = path.join(dirOf('esp32-c3'), 'manifest.json');
      const current = readManifest('esp32-c3');
      fs.writeFileSync(manifestPath, JSON.stringify({ ...current, signature_key_id: 'ffffffffffffffff' }));
      assert.equal((await manifestFor('esp32-c3', '4.3.3')).body.update_available, true, 'bilinmeyen kimlik: sunulur');
      fs.writeFileSync(manifestPath, JSON.stringify({ ...current, version: '9.9.9' }));
      await withEnv({ OTA_PUBLIC_KEY: `${nextHex},${publicKeyHex}` }, async () => {
        assert.equal((await manifestFor('esp32-c3', '4.3.3')).body.update_available, false, 'kimligi eslesen ama bozuk imza: sunulmaz');
      });
    });

    it('allowed_uids ile kademeli yayin: listede olmayan cihaza teklif yok', async () => {
      assert.equal((await upload({ version: '4.3.4', query: { allowed_uids: 'D4C771A172E0' } })).status, 201);
      const outsider = await manifestFor('esp32-c3', '4.0.0', '&uid=AABBCCDDEEFF');
      assert.equal(outsider.body.update_available, false);
      assert.equal(outsider.body.message, 'Cihaz bu yayin grubunda degil.');
      const insider = await manifestFor('esp32-c3', '4.0.0', '&uid=d4c771a172e0');
      assert.equal(insider.body.update_available, true);
    });
  });

  describe('B) surum dusurme korumasi (cihaz ucu + izli istisna)', () => {
    it('cihaz yayin surumunden YENIYSE guncelleme sunulmaz (surum dusurme yok), esitse de yok', async () => {
      await upload({ version: '4.3.4' });
      const newer = await manifestFor('esp32-c3', '4.4.0');
      assert.equal(newer.body.update_available, false);
      assert.equal(newer.body.url, null);
      assert.match(newer.body.message, /surum dusurme sunulmuyor/);
      assert.equal(newer.body.allow_downgrade, undefined);
      assert.equal(newer.body.signature_url, null);
      assert.equal((await manifestFor('esp32-c3', '10.0.0')).body.update_available, false);
      assert.equal((await manifestFor('esp32-c3', '4.3.4')).body.update_available, false);
      assert.equal((await manifestFor('esp32-c3', '4.3.3')).body.update_available, true);
    });

    it('canli surumden dusuk yukleme 409 FIRMWARE_DOWNGRADE_REJECTED; canli yayin degismez; iz yazilmaz', async () => {
      await upload({ version: '4.3.5' });
      auditEntries.length = 0;
      const response = await upload({ version: '4.3.4' });
      assert.equal(response.status, 409);
      assert.equal(response.body.code, 'FIRMWARE_DOWNGRADE_REJECTED');
      assert.equal(response.body.live_version, '4.3.5');
      assert.match(response.body.error, /sürüm düşürme reddedildi/);
      assert.equal(readManifest('esp32-c3').version, '4.3.5');
      assert.equal(auditEntries.length, 0);
    });

    it('bayrak gerekcesiz kullanilamaz (400); gerekceyle surum dusurme 201, denetim kaydina yazilir ve cihazlara allow_downgrade:true ile sunulur', async () => {
      await upload({ version: '4.3.5' });
      const noReason = await upload({ version: '4.3.4', query: { allow_downgrade: '1' } });
      assert.equal(noReason.status, 400);
      assert.equal(noReason.body.code, 'FIRMWARE_DOWNGRADE_REASON_REQUIRED');
      assert.equal(readManifest('esp32-c3').version, '4.3.5');

      auditEntries.length = 0;
      const reason = 'Role surucusu hatasi nedeniyle 4.3.5 geri cekiliyor';
      const down = await upload({ version: '4.3.4', query: { allow_downgrade: '1', downgrade_reason: reason }, token: tokenFor(1) });
      assert.equal(down.status, 201, JSON.stringify(down.body));
      assert.equal(down.body.downgrade, true);
      assert.equal(down.body.previous_version, '4.3.5');
      assert.match(down.body.message, /Sürüm düşürme yayınlandı ve denetim kaydına yazıldı/);

      // IZ: denetim kaydi (kim, ne zaman: kayit zamani DB'de), neden, hangi surumden hangisine
      assert.equal(auditEntries.length, 1);
      assert.equal(auditEntries[0].action, 'ota_release_downgrade');
      assert.equal(auditEntries[0].targetId, 'esp32-c3@4.3.4');
      assert.equal(auditEntries[0].details.reason, reason);
      assert.equal(auditEntries[0].details.previous_version, '4.3.5');
      assert.equal(auditEntries[0].actor.user_code, 1);
      const manifest = readManifest('esp32-c3');
      assert.equal(manifest.downgrade.authorized, true);
      assert.equal(manifest.downgrade.reason, reason);
      assert.equal(manifest.downgrade.from_version, '4.3.5');

      // cihaz ucu: 4.3.5'teki cihaza geri donus teklifi; 4.3.4 / 4.3.3 cihazlar icin normal davranis
      const rollback = await manifestFor('esp32-c3', '4.3.5');
      assert.equal(rollback.body.update_available, true);
      assert.equal(rollback.body.allow_downgrade, true);
      assert.equal(rollback.body.rollback_max, undefined, 'imzaya rollback_max girmediyse alan yok');
      assert.equal(rollback.body.version, '4.3.4');
      assert.equal(rollback.body.url, `${BASE}/firmware/esp32-c3/firmware-v4.3.4.bin`);
      assert.match(rollback.body.signature, /^[0-9a-f]{128}$/);
      const equal = await manifestFor('esp32-c3', '4.3.4');
      assert.equal(equal.body.update_available, false);
      const older = await manifestFor('esp32-c3', '4.3.3');
      assert.equal(older.body.update_available, true);
      assert.equal(older.body.allow_downgrade, undefined, 'yukseltme downgrade diye isaretlenmez');
    });

    it('SKP-OTA-V1 + rollback_max: imzalanan kapsam sorguda verilirse dogrulanir, cihaza allow_downgrade ve rollback_max ile sunulur', async () => {
      await upload({ version: '4.3.5' });
      const base = { allow_downgrade: '1', downgrade_reason: 'acil geri donus gerekcesi yeterince uzun' };
      const image = fakeImage('esp32-c3', 'rollback-http');
      const signed = { version: '4.3.4', image, format: 'SKP-OTA-V1', rollbackMax: '4.3.5' };
      assert.equal((await upload({ ...signed, query: base })).body.code, 'FIRMWARE_SIGNATURE_INVALID', 'rollback_max sorguda yok: imza dogrulanmaz');
      assert.equal((await upload({ ...signed, query: { ...base, rollback_max: '4.3.9' } })).body.code, 'FIRMWARE_SIGNATURE_INVALID');
      const ok = await upload({ ...signed, query: { ...base, rollback_max: '4.3.5' } });
      assert.equal(ok.status, 201, JSON.stringify(ok.body));
      assert.equal(ok.body.rollback_max, '4.3.5');
      assert.equal(ok.body.signature_format, 'SKP-OTA-V1');

      const rollback = await manifestFor('esp32-c3', '4.3.5');
      assert.equal(rollback.body.update_available, true);
      assert.equal(rollback.body.allow_downgrade, true);
      assert.equal(rollback.body.rollback_max, '4.3.5');
      assert.equal(rollback.body.signature_format, 'SKP-OTA-V1');
      const upgrade = await manifestFor('esp32-c3', '4.3.3');
      assert.equal(upgrade.body.allow_downgrade, undefined);
      assert.equal(upgrade.body.rollback_max, undefined, 'rollback_max yalniz dusurme teklifinde cihaza verilir');
    });

    it('surum dusurmede denetim kaydi yazilamazsa 503 ve canli yayin degismez', async () => {
      await upload({ version: '4.3.5' });
      auditResult = false;
      const response = await upload({ version: '4.3.4', query: { allow_downgrade: '1', downgrade_reason: 'acil geri donus gerekcesi yeterince uzun' } });
      assert.equal(response.status, 503);
      assert.equal(response.body.code, 'FIRMWARE_AUDIT_UNAVAILABLE');
      assert.equal(readManifest('esp32-c3').version, '4.3.5');
      assert.equal((await manifestFor('esp32-c3', '4.3.5')).body.update_available, false);
    });

    it('sunucu imzayi dogrulayamazsa (anahtar yok) onayli surum dusurme bile cihaza SUNULMAZ', async () => {
      await upload({ version: '4.3.5' });
      await upload({ version: '4.3.4', query: { allow_downgrade: '1', downgrade_reason: 'acil geri donus gerekcesi yeterince uzun' } });
      await withEnv({ OTA_PUBLIC_KEY: undefined }, async () => {
        const { body } = await manifestFor('esp32-c3', '4.3.5');
        assert.equal(body.update_available, false);
        assert.equal(body.allow_downgrade, undefined);
        assert.match(body.message, /surum dusurme sunulmuyor/);
      });
    });

    it('elle eklenmis "downgrade" / "allow_downgrade" bayragi ESKI (imzasiz) manifestte ise yaramaz: dusurme teklif edilmez, bayrak cihaza gecmez', async () => {
      fs.mkdirSync(dirOf('esp32-wroom'), { recursive: true });
      fs.writeFileSync(path.join(dirOf('esp32-wroom'), 'manifest.json'), JSON.stringify({
        enabled: true, target: 'esp32-wroom', version: '5.0.5', filename: 'firmware.bin', sha256: 'a'.repeat(64),
        downgrade: { authorized: true, reason: 'elle yazildi' }, allow_downgrade: true, rollback_max: '9.9.9',
      }));
      const { body } = await manifestFor('esp32-wroom', '5.2.2');
      assert.equal(body.update_available, false);
      assert.equal(body.allow_downgrade, undefined);
      assert.equal(body.rollback_max, undefined);
    });
  });

  describe('C) gecis: imzasiz eski paketler sunulmaya devam eder', () => {
    const KEYS = [
      'enabled', 'target', 'update_available', 'version', 'force', 'usb_required', 'url',
      'sha256', 'md5', 'notes', 'interval_hours', 'message',
    ].sort();

    function writeLegacy(target = 'esp32-wroom', extra = {}) {
      fs.mkdirSync(dirOf(target), { recursive: true });
      const legacyBin = fakeImage(target, 'eski');
      fs.writeFileSync(path.join(dirOf(target), 'firmware.bin'), legacyBin);
      fs.writeFileSync(path.join(dirOf(target), 'manifest.json'), JSON.stringify({
        enabled: true, target, version: '5.0.5', filename: 'firmware.bin', force: true, usb_required: false,
        partition_scheme: 'ota_4mb_littlefs_v1', interval_hours: 1, allowed_uids: [], sha256: sha256Of(legacyBin),
        md5: crypto.createHash('md5').update(legacyBin).digest('hex'), notes: 'eski imzasiz paket', ...extra,
      }));
      return legacyBin;
    }

    it('imzasiz kayitli paket (varsayilan) AYNEN sunulur: yanit sekli degismez, imza alani yok, indirme calisir', async () => {
      const legacyBin = writeLegacy();
      const { status, body } = await manifestFor('esp32-wroom', '5.0.0');
      assert.equal(status, 200);
      assert.deepEqual(Object.keys(body).sort(), KEYS);
      assert.equal(body.update_available, true);
      assert.equal(body.url, `${BASE}/firmware/esp32-wroom/firmware.bin`);
      assert.equal(body.message, '');
      const bin = await getBytes('/firmware/esp32-wroom/firmware.bin');
      assert.equal(bin.status, 200);
      assert.ok(bin.bytes.equals(legacyBin));
      assert.equal((await getBytes('/firmware/esp32-wroom/firmware.bin.sig')).status, 404, 'imzasiz pakette .sig yok');
    });

    it('imzali yayin ile eski paket ayni anda: hedefler bagimsiz (c3 imzali, wroom eski imzasiz) ve her ikisi de sunulur', async () => {
      writeLegacy();
      await upload({ version: '4.3.4' });
      const wroom = await manifestFor('esp32-wroom', '5.0.0');
      const c3 = await manifestFor('esp32-c3', '4.0.0');
      assert.equal(wroom.body.update_available, true);
      assert.equal(wroom.body.signature, undefined);
      assert.equal(c3.body.update_available, true);
      assert.equal(typeof c3.body.signature, 'string');
    });

    it('YENI yukleme imzasiz kabul edilmez, ama eski imzasiz paket yuklemeden etkilenmez', async () => {
      writeLegacy('esp32-c3');
      const before = fs.readFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), 'utf8');
      const rejected = await upload({ version: '9.0.0', signatureHeader: null });
      assert.equal(rejected.status, 400);
      assert.equal(fs.readFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), 'utf8'), before);
      assert.equal((await manifestFor('esp32-c3', '3.0.0')).body.update_available, true);
    });

    it('OTA_SERVE_UNSIGNED=0: imzasiz paket sunulmaz (acik mesaj), imzali paket sunulmaya devam eder', async () => {
      writeLegacy();
      await upload({ version: '4.3.4' });
      await withEnv({ OTA_SERVE_UNSIGNED: '0' }, async () => {
        const legacy = await manifestFor('esp32-wroom', '5.0.0');
        assert.equal(legacy.status, 200);
        assert.equal(legacy.body.update_available, false);
        assert.equal(legacy.body.url, null);
        assert.match(legacy.body.message, /Imzasiz paket sunulmuyor/);
        const signed = await manifestFor('esp32-c3', '4.0.0');
        assert.equal(signed.body.update_available, true);
      });
      // varsayilana donunce eski paket yine sunulur
      assert.equal((await manifestFor('esp32-wroom', '5.0.0')).body.update_available, true);
    });

    it('tools/ota_imza akisi (ELLE yerlestirme): bin + .sig + manifest.json; manifestte `signature` yoksa sunucu imzayi .sig dosyasindan alip cihaza iletir', async () => {
      const bin = fakeImage('esp32-wroom', 'elle');
      const sig = sigObject({ target: 'esp32-wroom', version: '5.2.3', image: bin });
      const dir = dirOf('esp32-wroom');
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, 'firmware.bin'), bin);
      fs.writeFileSync(path.join(dir, 'firmware.bin.sig'), sigFileText(sig));
      const manifest = {
        enabled: true, target: 'esp32-wroom', version: '5.2.3', filename: 'firmware.bin', force: false, usb_required: false, interval_hours: 1,
        allowed_uids: [], sha256: sha256Of(bin), md5: crypto.createHash('md5').update(bin).digest('hex'), notes: 'elle yerlestirilen imzali paket',
      };
      fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify(manifest));

      const served = await manifestFor('esp32-wroom', '5.0.0');
      assert.equal(served.body.update_available, true);
      assert.equal(served.body.signature, sig.signature, 'imza .sig dosyasindan alinip manifest yanitina konur');
      assert.equal(served.body.signature_format, 'KAPI-OTA-IMZA-V1');
      assert.equal(served.body.signature_key_id, sig.key_id);
      assert.equal(served.body.signature_url, `${BASE}/firmware/esp32-wroom/firmware.bin.sig`);
      const file = await getBytes('/firmware/esp32-wroom/firmware.bin.sig');
      assert.equal(file.status, 200);
      assert.equal(sigLib.parseOtaSigFile(file.bytes.toString('utf8')).sig.signature, sig.signature);

      // .sig dosyasi manifest/paketle uyusmuyorsa ya da bozuksa yayin SUNULMAZ (cihazlari basarisiz indirmeye sokmaz)
      const sigPath = path.join(dir, 'firmware.bin.sig');
      for (const [name, text] of Object.entries({
        surum: sigFileText({ ...sig, version: '5.2.4' }),
        ozet: sigFileText({ ...sig, sha256: 'c'.repeat(64) }),
        boyut: sigFileText({ ...sig, size: sig.size + 1 }),
        hedef: sigFileText({ ...sig, target: 'esp32-c3' }),
        imza: sigFileText({ ...sig, signature: '12'.repeat(64) }),
        bozukJson: '{ bozuk',
        bosDosya: '',
      })) {
        fs.writeFileSync(sigPath, text);
        const { body } = await manifestFor('esp32-wroom', '5.0.0');
        assert.equal(body.update_available, false, name);
        assert.equal(body.signature, undefined, name);
      }
      fs.writeFileSync(sigPath, sigFileText(sig));
      assert.equal((await manifestFor('esp32-wroom', '5.0.0')).body.update_available, true);

      // .sig yoksa paket "imzasiz" sayilir (gecis dolayisiyla sunulur; OTA_SERVE_UNSIGNED=0 ile kapanir)
      fs.rmSync(sigPath);
      assert.equal((await manifestFor('esp32-wroom', '5.0.0')).body.update_available, true);
      assert.equal((await manifestFor('esp32-wroom', '5.0.0')).body.signature, undefined);
      await withEnv({ OTA_SERVE_UNSIGNED: '0' }, async () => {
        assert.equal((await manifestFor('esp32-wroom', '5.0.0')).body.update_available, false);
      });
    });
  });

  describe('C2) gecis: CIPLAK .sig dosyasi (firmware taslagi bicimi) ile elle yerlestirme', () => {
    it('bin + ciplak .sig (hex / ham 64 bayt / base64) + manifest: sunucu hedef/surum/boyut/ozeti manifest ve gercek dosyadan kurup dogrular; bozuk imza SUNULMAZ', async () => {
      const bin = fakeImage('esp32-c3', 'ciplak-sig');
      const sha256 = sha256Of(bin);
      const dir = dirOf('esp32-c3');
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, 'firmware.bin'), bin);
      fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({
        enabled: true, target: 'esp32-c3', version: '4.4.1', filename: 'firmware.bin', sha256, usb_required: false, interval_hours: 1,
      }));
      const signatureFor = (format) => crypto.sign(null, sigLib.buildOtaSignedMessage({ format, target: 'esp32-c3', version: '4.4.1', size: bin.length, sha256 }), keys.privateKey);
      const sigPath = path.join(dir, 'firmware.bin.sig');

      for (const [name, content, format] of [
        ['hex', signatureFor('SKP-OTA-V1').toString('hex'), 'SKP-OTA-V1'],
        ['hex + satir sonu', `${signatureFor('SKP-OTA-V1').toString('hex')}\n`, 'SKP-OTA-V1'],
        ['ham 64 bayt', signatureFor('SKP-OTA-V1'), 'SKP-OTA-V1'],
        ['base64', signatureFor('KAPI-OTA-IMZA-V1').toString('base64'), 'KAPI-OTA-IMZA-V1'],
      ]) {
        fs.writeFileSync(sigPath, content);
        const { body } = await manifestFor('esp32-c3', '4.4.0');
        assert.equal(body.update_available, true, name);
        assert.equal(body.signature, signatureFor(format).toString('hex'), `${name}: cihaza hex olarak iletilir`);
        assert.equal(body.signature_format, format, `${name}: hangi bicimle dogrulandigi bildirilir`);
        assert.equal(body.signature_key_id, sigLib.otaKeyId(keys.publicKey));
        assert.equal(body.signature_url, `${BASE}/firmware/esp32-c3/firmware.bin.sig`);
      }

      // yanlis anahtarin / baska icerigin / bozuk imzasi: sunulmaz
      const other = crypto.generateKeyPairSync('ed25519');
      const forged = crypto.sign(null, sigLib.buildOtaSignedMessage({ target: 'esp32-c3', version: '4.4.1', size: bin.length, sha256 }), other.privateKey);
      for (const [name, content] of Object.entries({
        baskaAnahtar: forged.toString('hex'),
        sifir: '0'.repeat(128),
        yarimImza: signatureFor('SKP-OTA-V1').toString('hex').slice(0, 100),
        metin: 'bu bir imza degil',
        buyukDosya: Buffer.alloc(5000, 7),
      })) {
        fs.writeFileSync(sigPath, content);
        const { body } = await manifestFor('esp32-c3', '4.4.0');
        assert.equal(body.update_available, false, name);
        assert.equal(body.signature, undefined, name);
      }
      // surum elle degistirilirse imza o surum icin gecerli degildir
      fs.writeFileSync(sigPath, signatureFor('KAPI-OTA-IMZA-V1').toString('hex'));
      fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ enabled: true, target: 'esp32-c3', version: '4.4.2', filename: 'firmware.bin', sha256 }));
      assert.equal((await manifestFor('esp32-c3', '4.4.0')).body.update_available, false);
    });
  });

  describe('surum listesi ucu', () => {
    it('super kullanici canli yayini ve imzali kayitlari gorur; imza degeri ve baska kisisel veri yok', async () => {
      await upload({ version: '4.3.4' });
      await upload({ version: '4.3.5', query: { notes: 'ikinci' } });
      const response = await fetch(`${baseUrl}/admin/firmware/esp32-c3/releases`, { headers: { Authorization: `Bearer ${tokenFor(1)}` } });
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.target, 'esp32-c3');
      assert.deepEqual(body.releases.map((r) => r.version), ['4.3.5', '4.3.4']);
      assert.equal(body.live.version, '4.3.5');
      assert.equal(body.live.signed, true);
      assert.equal(body.live.server_verified, true);
      assert.equal(body.live.published_by_user_code, 1);
      assert.equal(JSON.stringify(body).includes(readManifest('esp32-c3').signature), false);
      const bad = await fetch(`${baseUrl}/admin/firmware/esp32-s3/releases`, { headers: { Authorization: `Bearer ${tokenFor(1)}` } });
      assert.equal(bad.status, 400);
    });
  });
});
