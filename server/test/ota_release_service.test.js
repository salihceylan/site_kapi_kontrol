// OTA firmware yayini (services/firmware_release_service.js): imza zorunlulugu, surum dusurme korumasi, gecis (eski paketler) ve denetim izi.
// Gercek dosya sistemi (gecici klasor) + calisma aninda uretilen Ed25519 anahtarlari; DB / ag yok. Ozel anahtar depoya GIRMEZ.
import { afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import {
  DEFAULT_MAX_FIRMWARE_BYTES,
  OTA_UPLOAD_TARGETS,
  assertEspImage,
  listFirmwareReleases,
  maxFirmwareBytes,
  parseReleaseOptions,
  publishFirmwareRelease,
  readOtaSigFile,
  releaseFileNames,
  resolveUploadTarget,
} from '../src/services/firmware_release_service.js';
import { buildOtaSignedMessage, otaKeyId, parseOtaSigFile, renderOtaSigFile } from '../src/services/ota_signature.js';

const FIXED_NOW = new Date('2026-10-29T10:00:00.000Z');

function newKeys() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  return { publicKey, privateKey, keyId: otaKeyId(publicKey) };
}

const keyStateOf = (...keys) => ({
  configured: true, ok: true, keys: keys.map((item) => ({ key: item.publicKey, keyId: item.keyId })), key: keys[0].publicKey, keyId: keys[0].keyId,
});

function fakeImage(target, seed = 'a', size = 6000) {
  const pattern = crypto.createHash('sha512').update(`${target}:${seed}`).digest();
  const image = Buffer.alloc(size);
  for (let i = 0; i < size; i += 1) {
    image[i] = pattern[i % pattern.length];
  }
  image[0] = 0xe9;
  image.writeUInt16LE(OTA_UPLOAD_TARGETS[target], 12);
  return image;
}

const sha256Of = (buffer) => crypto.createHash('sha256').update(buffer).digest('hex');

/** tools/ota_imza `.sig` nesnesi (format ve alanlar araci ile ayni). `override` ile alan bozulabilir. */
function sigObject(keys, { target, version, firmware, format = 'KAPI-OTA-IMZA-V1', rollbackMax = null, override = {} }) {
  const fields = { target, version, size: firmware.length, sha256: sha256Of(firmware) };
  const signature = crypto.sign(null, buildOtaSignedMessage({ format, ...fields, rollbackMax }), keys.privateKey);
  return {
    format, algorithm: 'Ed25519', ...fields, ...(rollbackMax ? { rollback_max: rollbackMax } : {}), key_id: keys.keyId, signature: signature.toString('hex'), ...override,
  };
}

async function rejects(promise, { status, code }) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.statusCode, status, `durum: ${error.statusCode} ${error.code} ${error.message}`);
    assert.equal(error.code, code, error.message);
    assert.ok(typeof error.message === 'string' && error.message.length > 0);
    return true;
  });
}

describe('OTA yayin servisi', () => {
  let root;
  let keys;
  let audit;

  const dirOf = (target) => path.join(root, target);
  const readManifest = (target) => JSON.parse(fs.readFileSync(path.join(dirOf(target), 'manifest.json'), 'utf8'));
  const listDir = (target) => (fs.existsSync(dirOf(target)) ? fs.readdirSync(dirOf(target)).sort() : []);

  /**
   * Imzali paketi yayinlar. `signatureInput` verilmezse dogru `.sig` uretilir; `signatureInput: null` imza girdisini cikarir.
   * `sig` ile `.sig` alanlari bozulabilir; `rollbackMax` imzaya girer.
   */
  async function publish({
    target = 'esp32-c3', version, seed = version, query = {}, firmware, signatureInput, keyState, actor = { userCode: 7 }, now = FIXED_NOW, sig = {}, format, rollbackMax,
  } = {}) {
    const image = firmware ?? fakeImage(target, seed);
    const signedVersion = version ?? '1.0.0';
    let input = signatureInput;
    if (input === undefined) {
      input = { kind: 'sigfile', sig: sigObject(keys, { target, version: signedVersion, firmware: image, format, rollbackMax, override: sig }) };
    }
    return publishFirmwareRelease({
      firmwareRoot: root,
      target,
      firmware: image,
      signatureInput: input ?? undefined,
      keyState: keyState ?? keyStateOf(keys),
      options: parseReleaseOptions({ ...(version === undefined ? {} : { version }), ...query }),
      actor,
      recordAudit: audit.record,
      now: () => now,
    });
  }

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'ota-release-'));
    keys = newKeys();
    audit = {
      entries: [],
      result: true,
      record: async (entry) => {
        audit.entries.push(entry);
        if (audit.result === 'throw') {
          throw new Error('db down');
        }
        return audit.result;
      },
    };
  });

  afterEach(() => {
    fs.rmSync(root, { recursive: true, force: true });
  });

  describe('A) imzali yukleme', () => {
    it('imzali paket yayinlanir: imaj + KANONIK .sig + yayin kaydi + manifest (surum, sha256, imza, yukleyen, zaman) yazilir; surum .sig dosyasindan gelir', async () => {
      const image = fakeImage('esp32-c3', 'c3-4.3.4');
      const result = await publish({ version: '4.3.4', firmware: image, query: { notes: 'Deneme surumu', allowed_uids: 'd4c771a172e0, AABBCCDDEEFF' } });

      assert.equal(result.ok, true);
      assert.equal(result.filename, 'firmware-v4.3.4.bin');
      assert.equal(result.signed, true);
      assert.equal(result.signature_format, 'KAPI-OTA-IMZA-V1');
      assert.equal(result.sha256, sha256Of(image));
      assert.equal(result.size_bytes, image.length);
      assert.equal(result.previous_version, null);
      assert.equal(result.downgrade, false);
      assert.equal(result.audience, 'allowed_uids');
      assert.equal(result.audited, true);

      const dir = dirOf('esp32-c3');
      assert.deepEqual(listDir('esp32-c3'), ['firmware-v4.3.4.bin', 'firmware-v4.3.4.bin.sig', 'firmware-v4.3.4.release.json', 'manifest.json']);
      assert.ok(fs.readFileSync(path.join(dir, 'firmware-v4.3.4.bin')).equals(image));

      // .sig dosyasi: aracin bicimi (kanonik JSON); disaridan ayristirilabilir ve imza hex'i manifestle ayni
      const sigText = fs.readFileSync(path.join(dir, 'firmware-v4.3.4.bin.sig'), 'utf8');
      const sigFile = parseOtaSigFile(sigText);
      assert.equal(sigFile.ok, true);
      assert.equal(sigText, renderOtaSigFile({
        format: 'KAPI-OTA-IMZA-V1', target: 'esp32-c3', version: '4.3.4', size: image.length, sha256: sha256Of(image), keyId: keys.keyId, signature: Buffer.from(sigFile.sig.signature, 'hex'),
      }));
      assert.deepEqual(readOtaSigFile(path.join(dir, 'firmware-v4.3.4.bin.sig')), { state: 'ok', sig: sigFile.sig });
      assert.equal(sigFile.sig.key_id, keys.keyId);

      const manifest = readManifest('esp32-c3');
      assert.equal(manifest.enabled, true);
      assert.equal(manifest.target, 'esp32-c3');
      assert.equal(manifest.version, '4.3.4');
      assert.equal(manifest.filename, 'firmware-v4.3.4.bin');
      assert.equal(manifest.sha256, sha256Of(image));
      assert.equal(manifest.md5, crypto.createHash('md5').update(image).digest('hex'));
      assert.match(manifest.signature, /^[0-9a-f]{128}$/, 'manifestte imza 128 hane hex');
      assert.equal(manifest.signature, sigFile.sig.signature);
      assert.equal(manifest.signature_alg, 'Ed25519');
      assert.equal(manifest.signature_format, 'KAPI-OTA-IMZA-V1');
      assert.equal(manifest.signature_key_id, keys.keyId);
      assert.equal(manifest.signature_file, 'firmware-v4.3.4.bin.sig');
      assert.deepEqual(manifest.allowed_uids, ['D4C771A172E0', 'AABBCCDDEEFF']);
      assert.equal(manifest.notes, 'Deneme surumu');
      assert.equal(manifest.interval_hours, 24);
      assert.equal(manifest.usb_required, false);
      assert.equal(manifest.release.published_at, FIXED_NOW.toISOString());
      assert.equal(manifest.release.published_by_user_code, 7);
      assert.equal(manifest.release.uploaded_by_user_code, 7);
      assert.equal(manifest.downgrade, undefined);
      assert.equal(manifest.rollback_max, undefined);

      const record = JSON.parse(fs.readFileSync(path.join(dir, 'firmware-v4.3.4.release.json'), 'utf8'));
      assert.deepEqual(
        { version: record.version, sha256: record.sha256, size: record.size_bytes, signature: record.signature, by: record.uploaded_by_user_code, at: record.uploaded_at, key: record.signature_key_id },
        { version: '4.3.4', sha256: sha256Of(image), size: image.length, signature: sigFile.sig.signature, by: 7, at: FIXED_NOW.toISOString(), key: keys.keyId },
      );

      assert.equal(audit.entries.length, 1);
      assert.equal(audit.entries[0].action, 'ota_release_published');
      assert.equal(audit.entries[0].targetType, 'firmware');
      assert.equal(audit.entries[0].targetId, 'esp32-c3@4.3.4');
      assert.equal(audit.entries[0].details.sha256, sha256Of(image));
      assert.equal(JSON.stringify(audit.entries[0]).includes('PRIVATE'), false);
    });

    it('imza girdisi YOK -> 400 FIRMWARE_SIGNATURE_REQUIRED; diske hicbir sey yazilmaz', async () => {
      await rejects(publish({ version: '4.3.4', signatureInput: null }), { status: 400, code: 'FIRMWARE_SIGNATURE_REQUIRED' });
      await rejects(publish({ version: '4.3.4', signatureInput: { kind: 'bilinmeyen' } }), { status: 400, code: 'FIRMWARE_SIGNATURE_REQUIRED' });
      assert.deepEqual(listDir('esp32-c3'), []);
      assert.equal(audit.entries.length, 0);
    });

    it('bozuk / sifir / baska anahtarli imza 400; diske HICBIR sey yazilmaz (dosya imzasi ve ciplak imza)', async () => {
      const image = fakeImage('esp32-c3', 'x');
      const other = newKeys();
      const good = sigObject(keys, { target: 'esp32-c3', version: '4.3.4', firmware: image });

      const cases = {
        'sifir imza (dosya)': [{ kind: 'sigfile', sig: { ...good, signature: '0'.repeat(128) } }, 'FIRMWARE_SIGNATURE_INVALID'],
        'tek bit bozuk imza (dosya)': [{ kind: 'sigfile', sig: { ...good, signature: `${(parseInt(good.signature[0], 16) ^ 1).toString(16)}${good.signature.slice(1)}` } }, 'FIRMWARE_SIGNATURE_INVALID'],
        'baska anahtarin imzasi, key_id GUVENILEN anahtarin kimligi': [{ kind: 'sigfile', sig: { ...sigObject(other, { target: 'esp32-c3', version: '4.3.4', firmware: image }), key_id: keys.keyId } }, 'FIRMWARE_SIGNATURE_INVALID'],
        'baska anahtarin imzasi, kendi key_id\'siyle': [{ kind: 'sigfile', sig: sigObject(other, { target: 'esp32-c3', version: '4.3.4', firmware: image }) }, 'FIRMWARE_SIGNATURE_KEY_UNKNOWN'],
        'sifir ciplak imza': [{ kind: 'bare', signature: Buffer.alloc(64) }, 'FIRMWARE_SIGNATURE_INVALID'],
        'baska anahtarin ciplak imzasi': [{ kind: 'bare', signature: crypto.sign(null, buildOtaSignedMessage({ target: 'esp32-c3', version: '4.3.4', size: image.length, sha256: sha256Of(image) }), other.privateKey) }, 'FIRMWARE_SIGNATURE_INVALID'],
        'ham imajin imzasi (metin degil)': [{ kind: 'bare', signature: crypto.sign(null, image, keys.privateKey) }, 'FIRMWARE_SIGNATURE_INVALID'],
      };
      for (const [name, [signatureInput, code]] of Object.entries(cases)) {
        await rejects(publish({ version: '4.3.4', firmware: image, signatureInput }), { status: 400, code });
        assert.deepEqual(listDir('esp32-c3'), [], `${name}: dosya yazilmamali`);
      }
      assert.equal(audit.entries.length, 0);
    });

    it('.sig alanlari paketle BIREBIR ayni olmali: hedef, surum, boyut, sha256 uyusmazligi 400 FIRMWARE_SIGNATURE_MISMATCH', async () => {
      const image = fakeImage('esp32-c3', 'uyum');
      const good = sigObject(keys, { target: 'esp32-c3', version: '4.3.4', firmware: image });

      // imza baska hedef / surum / boyut / ozet icin (imza o alanlar icin GECERLI olsa bile paketle uyusmuyor)
      const wrongTarget = sigObject(keys, { target: 'esp32-wroom', version: '4.3.4', firmware: image });
      await rejects(publish({ version: '4.3.4', firmware: image, signatureInput: { kind: 'sigfile', sig: wrongTarget } }), { status: 400, code: 'FIRMWARE_SIGNATURE_MISMATCH' });
      const otherImage = fakeImage('esp32-c3', 'baska');
      const otherSig = sigObject(keys, { target: 'esp32-c3', version: '4.3.4', firmware: otherImage });
      await rejects(publish({ version: '4.3.4', firmware: image, signatureInput: { kind: 'sigfile', sig: otherSig } }), { status: 400, code: 'FIRMWARE_SIGNATURE_MISMATCH' });
      const resized = sigObject(keys, { target: 'esp32-c3', version: '4.3.4', firmware: Buffer.concat([image, Buffer.alloc(16)]) });
      await rejects(publish({ version: '4.3.4', firmware: image, signatureInput: { kind: 'sigfile', sig: { ...resized, sha256: good.sha256 } } }), { status: 400, code: 'FIRMWARE_SIGNATURE_MISMATCH' });
      // alani elle degistirilmis .sig: imza artik o alan icin gecerli degil ya da paketle uyusmuyor
      for (const tampered of [{ version: '4.3.5' }, { size: good.size + 1 }, { sha256: 'b'.repeat(64) }, { target: 'esp32-wroom' }]) {
        await rejects(publish({ version: '4.3.4', firmware: image, signatureInput: { kind: 'sigfile', sig: { ...good, ...tampered } } }), { status: 400, code: 'FIRMWARE_SIGNATURE_MISMATCH' });
      }
      // sorgudaki surum .sig'dekiyle ayni olmali
      await rejects(publish({ version: '4.3.5', firmware: image, signatureInput: { kind: 'sigfile', sig: good } }), { status: 400, code: 'FIRMWARE_SIGNATURE_MISMATCH' });
      assert.deepEqual(listDir('esp32-c3'), []);

      // alanlar paketle ayni ama imza o alanlari baglamiyor (imza baska surum icin atilmis, .sig'deki surum elle degistirilmis)
      const forgedVersion = { ...sigObject(keys, { target: 'esp32-c3', version: '4.3.3', firmware: image }), version: '4.3.4' };
      await rejects(publish({ version: '4.3.4', firmware: image, signatureInput: { kind: 'sigfile', sig: forgedVersion } }), { status: 400, code: 'FIRMWARE_SIGNATURE_INVALID' });
      assert.deepEqual(listDir('esp32-c3'), []);
    });

    it('imza gecerliyken bile icerik degistirilirse (tek bayt) reddedilir', async () => {
      const image = fakeImage('esp32-c3', 'tek-bayt');
      const signatureInput = { kind: 'sigfile', sig: sigObject(keys, { target: 'esp32-c3', version: '2.0.0', firmware: image }) };
      const tampered = Buffer.from(image);
      tampered[1000] ^= 0x01;
      await rejects(publish({ firmware: tampered, signatureInput }), { status: 400, code: 'FIRMWARE_SIGNATURE_MISMATCH' });
      // .sig'deki ozet de yeni icerige gore guncellenirse imza o ozet icin gecerli degildir
      await rejects(
        publish({ firmware: tampered, signatureInput: { kind: 'sigfile', sig: { ...signatureInput.sig, sha256: sha256Of(tampered) } } }),
        { status: 400, code: 'FIRMWARE_SIGNATURE_INVALID' },
      );
      assert.deepEqual(listDir('esp32-c3'), []);
    });

    it('CIPLAK imza: surum sorgudan (zorunlu), bicim otomatik bulunur; .sig dosyasi sunucuda KANONIK bicimde uretilir', async () => {
      const image = fakeImage('esp32-wroom', 'ciplak');
      const signature = crypto.sign(null, buildOtaSignedMessage({ target: 'esp32-wroom', version: '5.2.2', size: image.length, sha256: sha256Of(image) }), keys.privateKey);
      await rejects(publish({ target: 'esp32-wroom', firmware: image, signatureInput: { kind: 'bare', signature } }), { status: 400, code: 'FIRMWARE_VERSION_INVALID' });
      assert.deepEqual(listDir('esp32-wroom'), []);

      const result = await publish({ target: 'esp32-wroom', version: '5.2.2', firmware: image, signatureInput: { kind: 'bare', signature } });
      assert.equal(result.signature_format, 'KAPI-OTA-IMZA-V1');
      const sigFile = parseOtaSigFile(fs.readFileSync(path.join(dirOf('esp32-wroom'), 'firmware-v5.2.2.bin.sig'), 'utf8'));
      assert.equal(sigFile.ok, true);
      assert.deepEqual(
        { target: sigFile.sig.target, version: sigFile.sig.version, size: sigFile.sig.size, sha256: sigFile.sig.sha256, key_id: sigFile.sig.key_id, signature: sigFile.sig.signature },
        { target: 'esp32-wroom', version: '5.2.2', size: image.length, sha256: sha256Of(image), key_id: keys.keyId, signature: signature.toString('hex') },
      );
      assert.equal(readManifest('esp32-wroom').signature, signature.toString('hex'));
    });

    it('anahtar DONUSU: .sig\'deki key_id guvenilen anahtarlardan birini secer; birincil olmayan anahtarin imzasi da kabul edilir', async () => {
      const second = newKeys();
      const both = keyStateOf(keys, second);
      const image = fakeImage('esp32-c3', 'donus');
      const bySecond = { kind: 'sigfile', sig: sigObject(second, { target: 'esp32-c3', version: '4.3.4', firmware: image }) };
      const result = await publish({ version: '4.3.4', firmware: image, signatureInput: bySecond, keyState: both });
      assert.equal(result.signature_key_id, second.keyId);
      assert.equal(readManifest('esp32-c3').signature_key_id, second.keyId);
      // yalniz birincil anahtar guveniliyorsa ikincinin imzasi kimlik bilinmediginden reddedilir
      await rejects(publish({ version: '4.3.5', seed: 'x', signatureInput: { kind: 'sigfile', sig: sigObject(second, { target: 'esp32-c3', version: '4.3.5', firmware: fakeImage('esp32-c3', 'x') }) } }), { status: 400, code: 'FIRMWARE_SIGNATURE_KEY_UNKNOWN' });
    });

    it('imaj denetimi: bos, kucuk, 0xE9 olmayan ve baska donanima ait imaj reddedilir (imzali olsa bile)', async () => {
      await rejects(publish({ version: '1.0.0', firmware: Buffer.alloc(0), signatureInput: { kind: 'bare', signature: Buffer.alloc(64) } }), { status: 400, code: 'FIRMWARE_EMPTY' });
      await rejects(publish({ version: '1.0.0', firmware: Buffer.from([0xe9, 1, 2, 3]), signatureInput: { kind: 'bare', signature: Buffer.alloc(64) } }), { status: 400, code: 'FIRMWARE_IMAGE_INVALID' });
      const notImage = fakeImage('esp32-c3', 'z');
      notImage[0] = 0x7f;
      await rejects(publish({ version: '1.0.0', firmware: notImage }), { status: 400, code: 'FIRMWARE_IMAGE_INVALID' });

      // C3 imaji WROOM klasorune (hedef karisikligi) imzali olsa da konamaz; tersi de
      const c3 = fakeImage('esp32-c3', 'c3');
      await rejects(publish({ target: 'esp32-wroom', version: '1.0.0', firmware: c3 }), { status: 400, code: 'FIRMWARE_TARGET_MISMATCH' });
      const wroom = fakeImage('esp32-wroom', 'wroom');
      await rejects(publish({ target: 'esp32-c3', version: '1.0.0', firmware: wroom }), { status: 400, code: 'FIRMWARE_TARGET_MISMATCH' });
      assert.deepEqual(listDir('esp32-c3'), []);
      assert.deepEqual(listDir('esp32-wroom'), []);
    });

    it('assertEspImage: gercek cihaz imaji basliklari (C3 cip kimligi 5, WROOM 0) kabul edilir', () => {
      // sahadaki gercek imajlardan alinan 32 baytlik basliklar (yalniz bicim dogrulamasi icin; icerik firmware degildir)
      const c3Header = Buffer.from('e905022f381a3840ee0000000500000000ffff00000000012000153c901e0500', 'hex');
      const wroomHeader = Buffer.from('e9050220e42c0840ee0000000000000000ffff00000000012000403f740b0400', 'hex');
      const pad = (header) => Buffer.concat([header, Buffer.alloc(8192, 0x11)]);
      assert.doesNotThrow(() => assertEspImage(pad(c3Header), 'esp32-c3'));
      assert.doesNotThrow(() => assertEspImage(pad(wroomHeader), 'esp32-wroom'));
      assert.throws(() => assertEspImage(pad(c3Header), 'esp32-wroom'), /çip kimliği/);
      assert.throws(() => assertEspImage(pad(wroomHeader), 'esp32-c3'), /çip kimliği/);
    });

    it('hedef ve sinirlar: yalniz bilinen donanim hedefleri; yol enjeksiyonu yok; boyut siniri ortamdan', () => {
      assert.equal(resolveUploadTarget('esp32-c3'), 'esp32-c3');
      assert.equal(resolveUploadTarget('ESP32_WROOM'), 'esp32-wroom');
      for (const bad of ['../etc', 'esp32-s3', '', undefined, 'constructor', '__proto__', 'esp32-c3/../x']) {
        assert.throws(() => resolveUploadTarget(bad), (error) => error.statusCode === 400 && error.code === 'FIRMWARE_TARGET_INVALID', String(bad));
      }
      assert.deepEqual(releaseFileNames('4.3.4'), { bin: 'firmware-v4.3.4.bin', sig: 'firmware-v4.3.4.bin.sig', meta: 'firmware-v4.3.4.release.json' });
      for (const bad of ['../1.0.0', '1.0.0/../x', '1.0.0\n', '1', '1.0', 'v1.0.0', '']) {
        assert.throws(() => releaseFileNames(bad), (error) => error.statusCode === 400, bad);
      }
      assert.equal(maxFirmwareBytes({}), DEFAULT_MAX_FIRMWARE_BYTES);
      assert.equal(DEFAULT_MAX_FIRMWARE_BYTES, 0x1e0000);
      assert.equal(maxFirmwareBytes({ OTA_MAX_FIRMWARE_BYTES: '2097152' }), 2097152);
      assert.equal(maxFirmwareBytes({ OTA_MAX_FIRMWARE_BYTES: '10' }), 64 * 1024);
      assert.equal(maxFirmwareBytes({ OTA_MAX_FIRMWARE_BYTES: '999999999' }), 8 * 1024 * 1024);
      assert.equal(maxFirmwareBytes({ OTA_MAX_FIRMWARE_BYTES: 'cok' }), DEFAULT_MAX_FIRMWARE_BYTES);
    });
  });

  describe('secenekler', () => {
    it('gecerli secenekler normalize edilir; bilinmeyenler yok sayilir; surum ISTEGE BAGLI (imza dosyasindan gelir)', () => {
      assert.deepEqual(
        parseReleaseOptions({ version: ' 4.3.4 ', notes: ' not\nsatiri\u0007 ', allowed_uids: 'd4c771a172e0,D4C771A172E0,aabbccddeeff', interval_hours: '12', enabled: '0', bilinmeyen: 'x' }),
        { version: '4.3.4', notes: 'not satiri', allowedUids: ['D4C771A172E0', 'AABBCCDDEEFF'], intervalHours: 12, enabled: false, allowDowngrade: false, downgradeReason: null, rollbackMax: null },
      );
      assert.deepEqual(parseReleaseOptions({}), {
        version: null, notes: '', allowedUids: [], intervalHours: null, enabled: true, allowDowngrade: false, downgradeReason: null, rollbackMax: null,
      });
      assert.deepEqual(
        parseReleaseOptions({ allow_downgrade: '1', downgrade_reason: '  acil   geri donus gerekcesi  ', rollback_max: '4.4.1' }),
        {
          version: null, notes: '', allowedUids: [], intervalHours: null, enabled: true, allowDowngrade: true, downgradeReason: 'acil geri donus gerekcesi', rollbackMax: '4.4.1',
        },
      );
    });

    it('gecersiz secenekler 400 verir', () => {
      const bad = [
        [{ version: 'v4.3.4' }, 'FIRMWARE_VERSION_INVALID'],
        [{ version: '4.3' }, 'FIRMWARE_VERSION_INVALID'],
        [{ version: '4.3.4-beta' }, 'FIRMWARE_VERSION_INVALID'],
        [{ version: '4.03.4' }, 'FIRMWARE_VERSION_INVALID'],
        [{ version: ['4.3.4', '4.3.5'] }, 'FIRMWARE_OPTIONS_INVALID'],
        [{ version: '4.3.4', notes: 'x'.repeat(501) }, 'FIRMWARE_OPTIONS_INVALID'],
        [{ version: '4.3.4', allowed_uids: 'xyz' }, 'FIRMWARE_OPTIONS_INVALID'],
        [{ version: '4.3.4', allowed_uids: 'D4C771A172E0,' }, 'FIRMWARE_OPTIONS_INVALID'],
        [{ version: '4.3.4', allowed_uids: Array.from({ length: 201 }, (_, i) => (0x100000 + i).toString(16).toUpperCase()).join(',') }, 'FIRMWARE_OPTIONS_INVALID'],
        [{ version: '4.3.4', interval_hours: '0' }, 'FIRMWARE_OPTIONS_INVALID'],
        [{ version: '4.3.4', interval_hours: '169' }, 'FIRMWARE_OPTIONS_INVALID'],
        [{ version: '4.3.4', interval_hours: 'iki' }, 'FIRMWARE_OPTIONS_INVALID'],
        [{ version: '4.3.4', enabled: 'belki' }, 'FIRMWARE_OPTIONS_INVALID'],
        [{ version: '4.3.4', allow_downgrade: '1' }, 'FIRMWARE_DOWNGRADE_REASON_REQUIRED'],
        [{ version: '4.3.4', allow_downgrade: '1', downgrade_reason: 'kisa' }, 'FIRMWARE_DOWNGRADE_REASON_REQUIRED'],
        [{ version: '4.3.4', allow_downgrade: '1', downgrade_reason: 'x'.repeat(301) }, 'FIRMWARE_DOWNGRADE_REASON_REQUIRED'],
        [{ version: '4.3.4', rollback_max: '4.4.1' }, 'FIRMWARE_OPTIONS_INVALID'],
        [{ version: '4.3.4', allow_downgrade: '1', downgrade_reason: 'yeterince uzun gerekce', rollback_max: 'v4.4' }, 'FIRMWARE_OPTIONS_INVALID'],
      ];
      for (const [query, code] of bad) {
        assert.throws(() => parseReleaseOptions(query), (error) => error.statusCode === 400 && error.code === code, `${JSON.stringify(query).slice(0, 80)} -> ${code}`);
      }
    });
  });

  describe('B) surum dusurme korumasi ve izli istisna', () => {
    it('yukseltme serbest; onceki surum kaydi tutulur; interval_hours onceki yayindan devralinir, allowed_uids DEVRALINMAZ', async () => {
      await publish({ version: '4.3.4', query: { interval_hours: '6', allowed_uids: 'D4C771A172E0' } });
      const result = await publish({ version: '4.3.5' });
      assert.equal(result.previous_version, '4.3.4');
      const manifest = readManifest('esp32-c3');
      assert.equal(manifest.version, '4.3.5');
      assert.equal(manifest.interval_hours, 6);
      assert.deepEqual(manifest.allowed_uids, []);
      assert.equal(manifest.release.previous_version, '4.3.4');
      // eski surumun dosyalari silinmez (geri donus / inceleme icin kalir)
      assert.ok(fs.existsSync(path.join(dirOf('esp32-c3'), 'firmware-v4.3.4.bin')));
    });

    it('canli surumden DUSUK surum reddedilir (409 FIRMWARE_DOWNGRADE_REJECTED): canli yayin ve dosyalar DEGISMEZ, iz yazilmaz', async () => {
      await publish({ version: '4.3.5' });
      const before = fs.readFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), 'utf8');
      const filesBefore = listDir('esp32-c3');
      audit.entries.length = 0;

      await assert.rejects(publish({ version: '4.3.4' }), (error) => {
        assert.equal(error.statusCode, 409);
        assert.equal(error.code, 'FIRMWARE_DOWNGRADE_REJECTED');
        assert.match(error.message, /allow_downgrade/);
        assert.deepEqual(error.extra, { live_version: '4.3.5', requested_version: '4.3.4' });
        return true;
      });
      assert.equal(fs.readFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), 'utf8'), before);
      assert.deepEqual(listDir('esp32-c3'), filesBefore);
      assert.equal(audit.entries.length, 0);
      // 10.x > 9.x gibi sayisal (metin degil) karsilastirma
      await publish({ version: '4.10.0' });
      await rejects(publish({ version: '4.9.9' }), { status: 409, code: 'FIRMWARE_DOWNGRADE_REJECTED' });
    });

    it('elle yazilmis eski manifestte "v" onekli surum de dusurmeyi engeller (cihaz ayristiricisi "v"yi yok sayar)', async () => {
      fs.mkdirSync(dirOf('esp32-c3'), { recursive: true });
      fs.writeFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), JSON.stringify({ enabled: true, version: 'v5.0.5', filename: 'firmware.bin', sha256: 'a'.repeat(64) }));
      await rejects(publish({ version: '4.0.0' }), { status: 409, code: 'FIRMWARE_DOWNGRADE_REJECTED' });
      await publish({ version: '5.0.6' });
    });

    it('allow_downgrade + gerekce ile surum dusurme YAPILIR ve denetim kaydina yazilir (izli); canli manifest "downgrade" isaretini tasir', async () => {
      await publish({ version: '4.3.5' });
      audit.entries.length = 0;
      const reason = '4.3.5 sahada role surucusunu kilitliyor; onceki kararli surume acil donus';
      const result = await publish({ version: '4.3.4', query: { allow_downgrade: '1', downgrade_reason: reason }, actor: { userCode: 11 } });

      assert.equal(result.downgrade, true);
      assert.equal(result.previous_version, '4.3.5');
      assert.equal(result.audited, true);
      assert.equal(result.rollback_max, null);
      const manifest = readManifest('esp32-c3');
      assert.equal(manifest.version, '4.3.4');
      assert.equal(manifest.downgrade.authorized, true);
      assert.equal(manifest.downgrade.from_version, '4.3.5');
      assert.equal(manifest.downgrade.reason, reason);
      assert.equal(manifest.downgrade.authorized_by_user_code, 11);
      assert.equal(manifest.downgrade.authorized_at, FIXED_NOW.toISOString());
      assert.equal(manifest.rollback_max, undefined);

      assert.equal(audit.entries.length, 1);
      const entry = audit.entries[0];
      assert.equal(entry.action, 'ota_release_downgrade');
      assert.equal(entry.targetId, 'esp32-c3@4.3.4');
      assert.equal(entry.details.downgrade, true);
      assert.equal(entry.details.reason, reason);
      assert.equal(entry.details.previous_version, '4.3.5');
      assert.equal(entry.details.version, '4.3.4');
    });

    const DOWNGRADE_QUERY = { allow_downgrade: '1', downgrade_reason: 'acil geri donus gerekcesi yeterince uzun' };

    it('KAPI-OTA-IMZA-V1 + rollback_max (imzali surum dusurme yetkisi): yetki .sig dosyasinda tasinir; manifest, kanonik .sig ve denetim kaydina yansir', async () => {
      await publish({ version: '4.3.5' });
      const result = await publish({ version: '4.3.4', rollbackMax: '4.3.5', query: DOWNGRADE_QUERY });
      assert.equal(result.downgrade, true);
      assert.equal(result.rollback_max, '4.3.5');
      assert.equal(result.signature_format, 'KAPI-OTA-IMZA-V1');
      const manifest = readManifest('esp32-c3');
      assert.equal(manifest.version, '4.3.4');
      assert.equal(manifest.rollback_max, '4.3.5');
      assert.equal(manifest.signature_format, 'KAPI-OTA-IMZA-V1');
      assert.equal(manifest.downgrade.authorized, true);
      assert.equal(audit.entries.at(-1).details.rollback_max, '4.3.5');

      // diskteki .sig KANONIK bicimde (tools/ota_imza ile ayni alan sirasi) ve rollback_max tasir; yeniden ayristirilabilir
      const stored = fs.readFileSync(path.join(dirOf('esp32-c3'), 'firmware-v4.3.4.bin.sig'), 'utf8');
      assert.deepEqual(Object.keys(JSON.parse(stored)), ['format', 'algorithm', 'target', 'version', 'size', 'sha256', 'rollback_max', 'key_id', 'signature']);
      const parsed = parseOtaSigFile(stored);
      assert.equal(parsed.ok, true);
      assert.equal(parsed.sig.rollback_max, '4.3.5');
      assert.equal(readOtaSigFile(path.join(dirOf('esp32-c3'), 'firmware-v4.3.4.bin.sig')).sig.rollback_max, '4.3.5');
    });

    it('rollback_max: sorguda ayrica verilirse imzadakiyle AYNI olmali; imzada yokken sorguda verilirse de reddedilir; imza alani bozulursa dogrulanmaz', async () => {
      await publish({ version: '4.3.5' });
      const image = fakeImage('esp32-c3', 'rollback');
      const signed = { kind: 'sigfile', sig: sigObject(keys, { target: 'esp32-c3', version: '4.3.4', firmware: image, rollbackMax: '4.3.5' }) };
      await rejects(publish({ version: '4.3.4', firmware: image, signatureInput: signed, query: { ...DOWNGRADE_QUERY, rollback_max: '4.9.9' } }), { status: 400, code: 'FIRMWARE_SIGNATURE_MISMATCH' });
      const plain = { kind: 'sigfile', sig: sigObject(keys, { target: 'esp32-c3', version: '4.3.4', firmware: image }) };
      await rejects(publish({ version: '4.3.4', firmware: image, signatureInput: plain, query: { ...DOWNGRADE_QUERY, rollback_max: '4.3.5' } }), { status: 400, code: 'FIRMWARE_SIGNATURE_MISMATCH' });
      // .sig'deki rollback_max elle degistirilirse (imza o deger icin atilmamis) dogrulanmaz
      const tampered = { kind: 'sigfile', sig: { ...signed.sig, rollback_max: '4.9.9' } };
      await rejects(publish({ version: '4.3.4', firmware: image, signatureInput: tampered, query: DOWNGRADE_QUERY }), { status: 400, code: 'FIRMWARE_SIGNATURE_INVALID' });
      // alan eklenirse / kaldirilirsa da
      const added = { kind: 'sigfile', sig: { ...plain.sig, rollback_max: '4.3.5' } };
      await rejects(publish({ version: '4.3.4', firmware: image, signatureInput: added, query: DOWNGRADE_QUERY }), { status: 400, code: 'FIRMWARE_SIGNATURE_INVALID' });
      const { rollback_max: _atilan, ...removed } = signed.sig;
      await rejects(publish({ version: '4.3.4', firmware: image, signatureInput: { kind: 'sigfile', sig: removed }, query: DOWNGRADE_QUERY }), { status: 400, code: 'FIRMWARE_SIGNATURE_INVALID' });
      assert.equal(readManifest('esp32-c3').version, '4.3.5');

      const ok = await publish({ version: '4.3.4', firmware: image, signatureInput: signed, query: { ...DOWNGRADE_QUERY, rollback_max: '4.3.5' } });
      assert.equal(ok.rollback_max, '4.3.5');
    });

    it('CIPLAK imza + sorgudaki rollback_max: sorgudaki deger imzaya girmisse dogrulanir (kanonik .sig rollback_max tasir); girmemisse / farkliysa reddedilir', async () => {
      await publish({ version: '4.3.5' });
      const image = fakeImage('esp32-c3', 'rollback-bare');
      const sign = (rollbackMax) => crypto.sign(
        null,
        buildOtaSignedMessage({ target: 'esp32-c3', version: '4.3.4', size: image.length, sha256: sha256Of(image), rollbackMax }),
        keys.privateKey,
      );
      const bare = (rollbackMax) => ({ kind: 'bare', signature: sign(rollbackMax) });
      await rejects(publish({ version: '4.3.4', firmware: image, signatureInput: bare(null), query: { ...DOWNGRADE_QUERY, rollback_max: '4.3.5' } }), { status: 400, code: 'FIRMWARE_SIGNATURE_INVALID' });
      await rejects(publish({ version: '4.3.4', firmware: image, signatureInput: bare('4.3.5'), query: DOWNGRADE_QUERY }), { status: 400, code: 'FIRMWARE_SIGNATURE_INVALID' });
      await rejects(publish({ version: '4.3.4', firmware: image, signatureInput: bare('4.3.5'), query: { ...DOWNGRADE_QUERY, rollback_max: '4.9.9' } }), { status: 400, code: 'FIRMWARE_SIGNATURE_INVALID' });
      const ok = await publish({ version: '4.3.4', firmware: image, signatureInput: bare('4.3.5'), query: { ...DOWNGRADE_QUERY, rollback_max: '4.3.5' } });
      assert.equal(ok.rollback_max, '4.3.5');
      assert.equal(parseOtaSigFile(fs.readFileSync(path.join(dirOf('esp32-c3'), 'firmware-v4.3.4.bin.sig'), 'utf8')).sig.rollback_max, '4.3.5');
    });

    it('rollback_max tasiyan imza allow_downgrade OLMADAN yuklenemez (400 FIRMWARE_ROLLBACK_NOT_ALLOWED); dusurme olmayan yuklemede de anlamsizdir (FIRMWARE_ROLLBACK_NOT_DOWNGRADE)', async () => {
      await publish({ version: '4.3.5' });
      const before = fs.readFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), 'utf8');
      const filesBefore = listDir('esp32-c3');
      await rejects(publish({ version: '4.3.4', rollbackMax: '4.3.5' }), { status: 400, code: 'FIRMWARE_ROLLBACK_NOT_ALLOWED' });
      // canli surumden DUSUK degil (yukseltme): rollback_max anlamsiz
      await rejects(publish({ version: '4.3.6', rollbackMax: '4.3.9', query: DOWNGRADE_QUERY }), { status: 400, code: 'FIRMWARE_ROLLBACK_NOT_DOWNGRADE' });
      await rejects(publish({ version: '4.3.5', rollbackMax: '4.3.9', query: DOWNGRADE_QUERY }), { status: 400, code: 'FIRMWARE_ROLLBACK_NOT_DOWNGRADE' });
      assert.equal(fs.readFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), 'utf8'), before);
      assert.deepEqual(listDir('esp32-c3'), filesBefore, 'reddedilen yuklemeler dosya birakmaz');
    });

    it('rollback_max paket surumunden BUYUK olmali: esit / kucuk deger 400 FIRMWARE_ROLLBACK_INVALID (hicbir cihaz dusurulemez)', async () => {
      await publish({ version: '4.3.5' });
      for (const rollbackMax of ['4.3.4', '4.3.3', '4.3.4.0']) {
        await rejects(publish({ version: '4.3.4', rollbackMax, query: DOWNGRADE_QUERY }), { status: 400, code: 'FIRMWARE_ROLLBACK_INVALID' });
      }
      assert.equal(readManifest('esp32-c3').version, '4.3.5');
    });

    it('surum dusurmede denetim kaydi yazilamazsa (false ya da hata) islem YAPILMAZ: 503, canli yayin degismez', async () => {
      await publish({ version: '4.3.5' });
      const before = fs.readFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), 'utf8');
      const query = { allow_downgrade: '1', downgrade_reason: 'acil geri donus gerekcesi yeterince uzun' };

      audit.result = false;
      await rejects(publish({ version: '4.3.4', query }), { status: 503, code: 'FIRMWARE_AUDIT_UNAVAILABLE' });
      assert.equal(fs.readFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), 'utf8'), before);

      audit.result = 'throw';
      await rejects(publish({ version: '4.3.4', query }), { status: 503, code: 'FIRMWARE_AUDIT_UNAVAILABLE' });
      assert.equal(fs.readFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), 'utf8'), before);

      // iz yazilabilince ayni istek basarili olur (yarim kalan dosyalar sorun cikarmaz)
      audit.result = true;
      const result = await publish({ version: '4.3.4', query });
      assert.equal(result.downgrade, true);
      assert.equal(readManifest('esp32-c3').version, '4.3.4');
    });

    it('allow_downgrade bayragi yukseltmeyi etkilemez (iz yazilmaz, manifestte downgrade yok)', async () => {
      await publish({ version: '4.3.4' });
      audit.entries.length = 0;
      const result = await publish({ version: '4.3.5', query: { allow_downgrade: '1', downgrade_reason: 'gereksiz ama gecerli gerekce' } });
      assert.equal(result.downgrade, false);
      assert.equal(readManifest('esp32-c3').downgrade, undefined);
      assert.equal(audit.entries[0].action, 'ota_release_published');
    });

    it('ayni surum: ayni icerik yeniden yayinlanabilir (ilk yukleme bilgisi korunur); FARKLI icerik 409 FIRMWARE_VERSION_EXISTS', async () => {
      const image = fakeImage('esp32-c3', 'sabit');
      await publish({ version: '4.3.4', firmware: image, actor: { userCode: 7 }, now: new Date('2026-10-29T10:00:00.000Z') });
      const republished = await publish({
        version: '4.3.4', firmware: image, actor: { userCode: 9 }, now: new Date('2026-10-30T12:00:00.000Z'), query: { allowed_uids: 'D4C771A172E0' },
      });
      assert.equal(republished.republish, true);
      assert.equal(republished.downgrade, false);
      const manifest = readManifest('esp32-c3');
      assert.deepEqual(manifest.allowed_uids, ['D4C771A172E0']);
      assert.equal(manifest.release.uploaded_by_user_code, 7);
      assert.equal(manifest.release.uploaded_at, '2026-10-29T10:00:00.000Z');
      assert.equal(manifest.release.published_by_user_code, 9);
      assert.equal(manifest.release.published_at, '2026-10-30T12:00:00.000Z');

      const before = fs.readFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), 'utf8');
      await rejects(publish({ version: '4.3.4', seed: 'baska-icerik' }), { status: 409, code: 'FIRMWARE_VERSION_EXISTS' });
      assert.equal(fs.readFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), 'utf8'), before);
      assert.ok(fs.readFileSync(path.join(dirOf('esp32-c3'), 'firmware-v4.3.4.bin')).equals(image), 'yayinlanmis imaj degismemeli');
    });

    it('eski bir surum numarasi (artik canli degil) FARKLI icerikle yeniden kullanilamaz', async () => {
      await publish({ version: '4.3.4', seed: 'ilk' });
      await publish({ version: '4.3.5' });
      // 4.3.4 dosyasi diskte; ayni numaraya baska icerik: surum dusurme bayragiyla bile yayinlanmis icerik degisemez
      const query = { allow_downgrade: '1', downgrade_reason: 'eski surum numarasi yeniden kullanilmaya calisiliyor' };
      await rejects(publish({ version: '4.3.4', seed: 'farkli', query }), { status: 409, code: 'FIRMWARE_VERSION_EXISTS' });
    });

    it('bozuk canli manifest (okunamayan JSON) surum denetimi yapilamadigindan yuklemeyi durdurur (409)', async () => {
      fs.mkdirSync(dirOf('esp32-c3'), { recursive: true });
      fs.writeFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), '{ bozuk');
      await rejects(publish({ version: '1.0.0' }), { status: 409, code: 'FIRMWARE_MANIFEST_UNREADABLE' });
      assert.deepEqual(listDir('esp32-c3'), ['manifest.json']);
    });

    it('normal yayinda denetim kaydi yazilamazsa yayin yine yapilir (audited:false), hata sizmaz', async () => {
      audit.result = 'throw';
      const result = await publish({ version: '1.0.0' });
      assert.equal(result.audited, false);
      assert.equal(readManifest('esp32-c3').version, '1.0.0');
    });
  });

  describe('C) gecis: eski (imzasiz) paketler', () => {
    it('imzasiz eski manifest ve firmware.bin OLDUGU GIBI kalir; yeni imzali yayin alan devralmasini yapar', async () => {
      const dir = dirOf('esp32-wroom');
      fs.mkdirSync(dir, { recursive: true });
      const legacyBin = fakeImage('esp32-wroom', 'eski');
      fs.writeFileSync(path.join(dir, 'firmware.bin'), legacyBin);
      fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({
        enabled: true, target: 'esp32-wroom', version: '5.0.5', filename: 'firmware.bin', force: true, usb_required: false,
        partition_scheme: 'ota_4mb_littlefs_v1', interval_hours: 1, allowed_uids: [], sha256: sha256Of(legacyBin), notes: 'eski',
      }, null, 2));

      const result = await publish({ target: 'esp32-wroom', version: '5.2.2' });
      assert.equal(result.previous_version, '5.0.5');
      assert.ok(fs.readFileSync(path.join(dir, 'firmware.bin')).equals(legacyBin), 'eski imaj degismemeli');
      const manifest = readManifest('esp32-wroom');
      assert.equal(manifest.version, '5.2.2');
      assert.equal(manifest.partition_scheme, 'ota_4mb_littlefs_v1');
      assert.equal(manifest.interval_hours, 1);
      assert.equal(manifest.filename, 'firmware-v5.2.2.bin');
    });

    it('eski surumun altina imzasiz yeni yukleme yapilamaz: imza her yeni yuklemede zorunlu', async () => {
      fs.mkdirSync(dirOf('esp32-c3'), { recursive: true });
      fs.writeFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), JSON.stringify({ enabled: true, version: '3.5.0', filename: 'firmware.bin' }));
      const image = fakeImage('esp32-c3', 'imzasiz');
      await rejects(publish({ version: '4.0.0', firmware: image, signatureInput: { kind: 'bare', signature: Buffer.alloc(64) } }), { status: 400, code: 'FIRMWARE_SIGNATURE_INVALID' });
      await rejects(publish({ version: '4.0.0', firmware: image, signatureInput: null }), { status: 400, code: 'FIRMWARE_SIGNATURE_REQUIRED' });
      assert.equal(readManifest('esp32-c3').version, '3.5.0');
    });
  });

  describe('es zamanli yayinlar ve hedef ayrimi', () => {
    it('ayni hedefe es zamanli yayinlar siraya girer: son manifest tutarlidir, yarim dosya kalmaz', async () => {
      const results = await Promise.allSettled([
        publish({ version: '4.1.0' }),
        publish({ version: '4.2.0' }),
        publish({ version: '4.3.0' }),
      ]);
      assert.deepEqual(results.map((r) => r.status), ['fulfilled', 'fulfilled', 'fulfilled']);
      assert.equal(readManifest('esp32-c3').version, '4.3.0');
      assert.ok(listDir('esp32-c3').every((name) => !name.endsWith('.tmp')));

      const reverse = await Promise.allSettled([publish({ version: '4.5.0' }), publish({ version: '4.4.0' })]);
      assert.equal(reverse[0].status, 'fulfilled');
      assert.equal(reverse[1].status, 'rejected');
      assert.equal(reverse[1].reason.code, 'FIRMWARE_DOWNGRADE_REJECTED');
      assert.equal(readManifest('esp32-c3').version, '4.5.0');
    });

    it('iki donanim hedefi tamamen ayridir (klasorler, manifestler ve surumler karismaz)', async () => {
      await publish({ target: 'esp32-c3', version: '4.3.4' });
      await publish({ target: 'esp32-wroom', version: '5.2.2' });
      assert.equal(readManifest('esp32-c3').version, '4.3.4');
      assert.equal(readManifest('esp32-wroom').version, '5.2.2');
      assert.equal(readManifest('esp32-c3').target, 'esp32-c3');
      assert.equal(readManifest('esp32-wroom').target, 'esp32-wroom');
      assert.deepEqual(listDir('esp32-c3').filter((name) => name.endsWith('.bin')), ['firmware-v4.3.4.bin']);
      assert.deepEqual(listDir('esp32-wroom').filter((name) => name.endsWith('.bin')), ['firmware-v5.2.2.bin']);
      // wroom icin 4.x yukleme, c3 canli surumunden etkilenmez
      await publish({ target: 'esp32-wroom', version: '5.3.0' });
    });
  });

  describe('surum listesi', () => {
    it('imzali yayin kayitlarini yeni -> eski siralar; canli yayinin sunucuda dogrulandigini gosterir; imza degeri ve kisisel veri donmez', async () => {
      await publish({ version: '4.3.4' });
      await publish({ version: '4.10.0' });
      await publish({ version: '4.3.9' }).catch(() => {}); // dusurme reddedilir
      const keyState = keyStateOf(keys);
      const listing = listFirmwareReleases({ firmwareRoot: root, target: 'esp32-c3', keyState });
      assert.deepEqual(listing.releases.map((r) => r.version), ['4.10.0', '4.3.4']);
      assert.equal(listing.live.version, '4.10.0');
      assert.equal(listing.live.signed, true);
      assert.equal(listing.live.server_verified, true);
      assert.equal(listing.live.readable, true);
      assert.equal(listing.live.signature_key_id, keys.keyId);
      assert.equal(listing.live.signature_format, 'KAPI-OTA-IMZA-V1');
      assert.equal(listing.live.previous_version, '4.3.4');
      assert.equal(listing.live.published_by_user_code, 7);
      assert.equal(JSON.stringify(listing).includes(readManifest('esp32-c3').signature), false, 'imza degeri listede yok');

      // anahtar yoksa dogrulanamaz (null); elle degistirilmis manifest dogrulanamaz (false); baska anahtarla imzali: dogrulanamaz (null)
      assert.equal(listFirmwareReleases({ firmwareRoot: root, target: 'esp32-c3' }).live.server_verified, null);
      assert.equal(listFirmwareReleases({ firmwareRoot: root, target: 'esp32-c3', keyState: keyStateOf(newKeys()) }).live.server_verified, null);
      const manifestPath = path.join(dirOf('esp32-c3'), 'manifest.json');
      const manifest = readManifest('esp32-c3');
      fs.writeFileSync(manifestPath, JSON.stringify({ ...manifest, version: '9.9.9' }));
      assert.equal(listFirmwareReleases({ firmwareRoot: root, target: 'esp32-c3', keyState }).live.server_verified, false);
    });

    it('olmayan hedef klasoru ve bozuk manifest hata vermez', () => {
      assert.deepEqual(listFirmwareReleases({ firmwareRoot: root, target: 'esp32-c3' }), { target: 'esp32-c3', live: null, releases: [] });
      fs.mkdirSync(dirOf('esp32-c3'), { recursive: true });
      fs.writeFileSync(path.join(dirOf('esp32-c3'), 'manifest.json'), 'yok');
      assert.deepEqual(listFirmwareReleases({ firmwareRoot: root, target: 'esp32-c3' }).live, { readable: false });
    });
  });
});
