// OTA imza yardimcilari (services/ota_signature.js): imzalanan metin sozlesmesi (tools/ota_imza "KAPI-OTA-IMZA-V1" ile bilinen-cevap vektorleri
// dahil), `.sig` dosyasi, genel anahtar bicimleri, imza cozme ve dogrulama.
// Test anahtarlari testin KENDISI tarafindan calisma aninda uretilir (crypto.generateKeyPairSync); depoda hicbir ozel anahtar yoktur.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';

import { validateEnv } from '../src/config/env.js';
import {
  OTA_PRIMARY_FORMAT,
  OTA_SIGNATURE_ALGORITHM,
  OTA_SIGNATURE_FORMATS,
  buildOtaSignedMessage,
  decodeOtaSignature,
  decodeOtaSignatureInput,
  isOtaImageSize,
  isOtaTargetName,
  isSha256Hex,
  isStrictOtaVersion,
  loadOtaPublicKey,
  otaEnvWarnings,
  otaKeyId,
  parseOtaPublicKey,
  parseOtaPublicKeys,
  parseOtaSigFile,
  renderOtaSigFile,
  resolveServeUnsigned,
  verifyOtaSignature,
  verifyOtaSignatureWithKeys,
} from '../src/services/ota_signature.js';

const SHA = 'a1'.repeat(32);

function newKeys() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const der = publicKey.export({ format: 'der', type: 'spki' });
  return {
    publicKey,
    privateKey,
    keyId: otaKeyId(publicKey),
    pem: publicKey.export({ format: 'pem', type: 'spki' }),
    der,
    raw32: der.subarray(der.length - 32),
  };
}

const FIELDS = { target: 'esp32-c3', version: '4.3.4', size: 1794320, sha256: SHA };

function sign(privateKey, fields = FIELDS, format = OTA_PRIMARY_FORMAT) {
  return crypto.sign(null, buildOtaSignedMessage({ format, ...fields }), privateKey);
}

// TEST ANAHTARI - uretimde kullanilmaz. Kaynak: tools/ota_imza/test/vektorler.json (yalniz ACIK veri: genel anahtar, mesaj, imza; OZEL ANAHTAR YOK).
// Imaj bu formulle yeniden uretilir: bayt[i] = (i*31+7) mod 256; sonra bayt[0]=0xE9, bayt[1]=0x05, bayt[12..13]=cip kimligi (LE).
const TOOL_VECTORS = Object.freeze({
  publicKeyHex: '040b4068ce86e2849f9e290b3f23a2adf14b6b21ebb4d7f03baaf088524dd24c',
  keyId: '33883b77b7f5fdbc',
  vectors: [
    {
      target: 'esp32-c3', chipId: 5, version: '4.3.4', size: 4096,
      sha256: 'c3789af686a4995a2d1264a0eea34c7cc19524515ab20cbac88b002658be6252',
      message: 'KAPI-OTA-IMZA-V1\ntarget=esp32-c3\nversion=4.3.4\nsize=4096\nsha256=c3789af686a4995a2d1264a0eea34c7cc19524515ab20cbac88b002658be6252\n',
      signatureHex: '71e564c0f321ba8a876f7e115eccea92f256296ee26accd33c8106ad0dff268f2f3d82ea315007d3257d4e5c4f48287276d1f1dffbfc93bef6f1e5b762b03c01',
    },
    {
      target: 'esp32-wroom', chipId: 0, version: '5.2.3', size: 8192,
      sha256: 'a4fa27da11d1a94e8b279787179e2b104bf90253d56f640bbe7fc37bb561d618',
      message: 'KAPI-OTA-IMZA-V1\ntarget=esp32-wroom\nversion=5.2.3\nsize=8192\nsha256=a4fa27da11d1a94e8b279787179e2b104bf90253d56f640bbe7fc37bb561d618\n',
      signatureHex: '73fe2d62adbb3aff07037e87af3738744655bad918457a9c7f89e5d5662df86c698adf0ddb6bbfafee352b015c069d223b59e4a6780a9c97eedccc89e0caea0f',
    },
  ],
});

function syntheticImage(size, chipId) {
  const image = Buffer.alloc(size);
  for (let i = 0; i < size; i += 1) {
    image[i] = (i * 31 + 7) % 256;
  }
  image[0] = 0xe9;
  image[1] = 0x05;
  image[12] = chipId % 256;
  image[13] = Math.floor(chipId / 256);
  return image;
}

describe('OTA imza: tools/ota_imza ile birlikte calisabilirlik (bilinen-cevap vektorleri)', () => {
  it('sunucu, aracin referans vektorlerindeki imzalanan metni BIREBIR uretir ve imzayi dogrular', () => {
    const parsed = parseOtaPublicKey(TOOL_VECTORS.publicKeyHex);
    assert.equal(parsed.ok, true);
    assert.equal(parsed.keyId, TOOL_VECTORS.keyId, 'key_id tanimi araci ile ayni (SHA-256 ilk 8 bayt)');
    for (const vector of TOOL_VECTORS.vectors) {
      const image = syntheticImage(vector.size, vector.chipId);
      const sha256 = crypto.createHash('sha256').update(image).digest('hex');
      assert.equal(sha256, vector.sha256, `${vector.target}: sentetik imaj ozeti`);
      const message = buildOtaSignedMessage({ target: vector.target, version: vector.version, size: image.length, sha256 });
      assert.equal(message.toString('ascii'), vector.message, `${vector.target}: imzalanan metin`);
      assert.equal(
        verifyOtaSignature({
          publicKey: parsed.key, target: vector.target, version: vector.version, size: image.length, sha256, signature: Buffer.from(vector.signatureHex, 'hex'),
        }),
        true,
        `${vector.target}: arac imzasi sunucuda dogrulanir`,
      );
    }
  });

  it('aracin imzasi baska hedef / surum / boyut / ozet icin DOGRULANMAZ', () => {
    const parsed = parseOtaPublicKey(TOOL_VECTORS.publicKeyHex);
    const [c3] = TOOL_VECTORS.vectors;
    const base = { publicKey: parsed.key, target: c3.target, version: c3.version, size: c3.size, sha256: c3.sha256, signature: Buffer.from(c3.signatureHex, 'hex') };
    assert.equal(verifyOtaSignature(base), true);
    assert.equal(verifyOtaSignature({ ...base, target: 'esp32-wroom' }), false);
    assert.equal(verifyOtaSignature({ ...base, version: '4.3.5' }), false);
    assert.equal(verifyOtaSignature({ ...base, size: c3.size + 1 }), false);
    assert.equal(verifyOtaSignature({ ...base, sha256: 'b'.repeat(64) }), false);
    assert.equal(verifyOtaSignature({ ...base, format: 'SKP-OTA-V1' }), false, 'baska bicim etiketi ayni imzayi dogrulamaz');
  });
});

describe('OTA imza: imzalanan metin sozlesmesi', () => {
  it('metin KAPI-OTA-IMZA-V1 + target + version + size + sha256, her satir tek LF ile biter, yalniz ASCII', () => {
    const message = buildOtaSignedMessage(FIELDS);
    assert.equal(message.toString('ascii'), `KAPI-OTA-IMZA-V1\ntarget=esp32-c3\nversion=4.3.4\nsize=1794320\nsha256=${SHA}\n`);
    assert.equal(OTA_PRIMARY_FORMAT, 'KAPI-OTA-IMZA-V1');
    assert.equal(OTA_SIGNATURE_ALGORITHM, 'Ed25519');
    assert.equal(message.includes(0x0d), false, 'CR olmamali');
    assert.ok(message.every((byte) => byte < 0x80), 'yalniz ASCII');
    assert.equal(message[message.length - 1], 0x0a);
  });

  it('firmware taslagi bicimi SKP-OTA-V1: ayni alanlar; YALNIZ izinli dusurmede son satir rollback_max', () => {
    assert.equal(
      buildOtaSignedMessage({ format: 'SKP-OTA-V1', ...FIELDS }).toString('ascii'),
      `SKP-OTA-V1\ntarget=esp32-c3\nversion=4.3.4\nsize=1794320\nsha256=${SHA}\n`,
    );
    assert.equal(
      buildOtaSignedMessage({ format: 'SKP-OTA-V1', ...FIELDS, rollbackMax: '4.4.1' }).toString('ascii'),
      `SKP-OTA-V1\ntarget=esp32-c3\nversion=4.3.4\nsize=1794320\nsha256=${SHA}\nrollback_max=4.4.1\n`,
    );
    // KAPI bicimi rollback_max tasimaz; gecersiz rollback_max reddedilir
    assert.throws(() => buildOtaSignedMessage({ ...FIELDS, rollbackMax: '4.4.1' }), TypeError);
    assert.throws(() => buildOtaSignedMessage({ format: 'SKP-OTA-V1', ...FIELDS, rollbackMax: 'v4.4' }), TypeError);
    assert.throws(() => buildOtaSignedMessage({ format: 'SKP-OTA-V1', ...FIELDS, rollbackMax: '4.4.1\nsha256=x' }), TypeError);
    assert.deepEqual(Object.keys(OTA_SIGNATURE_FORMATS), ['KAPI-OTA-IMZA-V1', 'SKP-OTA-V1']);
  });

  it('bicim disi girdi reddedilir (satir sonu enjeksiyonu, buyuk harf, eksik/fazla parca, onek/sonek, bos/tasan boyut, bilinmeyen bicim)', () => {
    assert.doesNotThrow(() => buildOtaSignedMessage({ ...FIELDS, target: 'esp32-wroom', version: '5.2.2' }));
    const bad = [
      { ...FIELDS, version: '4.3.4\nsha256=' + 'b'.repeat(64) },
      { ...FIELDS, version: 'v4.3.4' },
      { ...FIELDS, version: '4.3.4-beta' },
      { ...FIELDS, version: '4.3' },
      { ...FIELDS, version: '4' },
      { ...FIELDS, version: '1.2.3.4.5' },
      { ...FIELDS, version: '4.03.4' },
      { ...FIELDS, version: '10000.0.0' },
      { ...FIELDS, version: '' },
      { ...FIELDS, target: 'ESP32-C3' },
      { ...FIELDS, target: 'esp32 c3' },
      { ...FIELDS, target: 'esp32-c3\nx' },
      { ...FIELDS, target: '-esp32' },
      { ...FIELDS, target: 'a'.repeat(17) },
      { ...FIELDS, target: '' },
      { ...FIELDS, target: '../x' },
      { ...FIELDS, size: 0 },
      { ...FIELDS, size: -1 },
      { ...FIELDS, size: 16 * 1024 * 1024 + 1 },
      { ...FIELDS, size: 1.5 },
      { ...FIELDS, size: '1794320' },
      { ...FIELDS, size: undefined },
      { ...FIELDS, sha256: SHA.toUpperCase() },
      { ...FIELDS, sha256: SHA.slice(1) },
      { ...FIELDS, sha256: `${SHA}0` },
      { ...FIELDS, sha256: undefined },
      { ...FIELDS, format: 'AHBT-OTA-V9' },
      { ...FIELDS, format: '__proto__' },
    ];
    for (const fields of bad) {
      assert.throws(() => buildOtaSignedMessage(fields), TypeError, JSON.stringify(fields));
    }
  });

  it('kati alan denetimleri (cihaz ayristiricisi ve arac ile uyumlu): surum X.Y.Z[.W], parca basina 0-9999, bas sifir yok', () => {
    for (const version of ['4.3.3', '5.2.2', '1.2.3.4', '0.0.1', '0.0.0', '10.20.30', '9999.9999.9999.9999']) {
      assert.equal(isStrictOtaVersion(version), true, version);
    }
    for (const version of ['4', '4.3', '4.', '.4', 'v4.3.3', '4.3.3-beta', '4..3', '4.3.3.3.3', ' 4.3.3', '4.3.3 ', '٤.٣.٣', '4.03.4', '04.3.4', '4.3.00', '10000.0.0', null, undefined, 4.33]) {
      assert.equal(isStrictOtaVersion(version), false, String(version));
    }
    assert.equal(isSha256Hex(SHA), true);
    assert.equal(isSha256Hex(SHA.toUpperCase()), false);
    assert.equal(isOtaTargetName('esp32-wroom'), true);
    assert.equal(isOtaTargetName('Esp32'), false);
    assert.equal(isOtaImageSize(1), true);
    assert.equal(isOtaImageSize(16 * 1024 * 1024), true);
    assert.equal(isOtaImageSize(0), false);
    assert.equal(isOtaImageSize(2 ** 40), false);
  });
});

describe('OTA imza: .sig dosyasi (tools/ota_imza bicimi)', () => {
  const keys = newKeys();
  const sigHex = sign(keys.privateKey).toString('hex');
  const sample = {
    format: 'KAPI-OTA-IMZA-V1',
    algorithm: 'Ed25519',
    target: 'esp32-c3',
    version: '4.3.4',
    size: 1794320,
    sha256: SHA,
    key_id: keys.keyId,
    signature: sigHex,
  };
  const canonical = `${JSON.stringify(sample, null, 2)}\n`;

  it('kanonik metin aracin ciktisiyla ayni: sabit alan sirasi, 2 bosluk girinti, sonda LF; ayristirma gidis-donus', () => {
    const rendered = renderOtaSigFile({
      format: sample.format, target: sample.target, version: sample.version, size: sample.size, sha256: SHA, keyId: keys.keyId, signature: Buffer.from(sigHex, 'hex'),
    });
    assert.equal(rendered, canonical);
    assert.match(rendered, /^\{\n {2}"format": "KAPI-OTA-IMZA-V1",\n {2}"algorithm": "Ed25519",\n {2}"target": "esp32-c3",\n {2}"version": "4\.3\.4",\n {2}"size": 1794320,\n/);
    assert.deepEqual(parseOtaSigFile(rendered), { ok: true, sig: sample });
  });

  it('bilinmeyen ek alanlar yok sayilir (ileriye uyum); BOM tolere edilir; SKP bicimi de kabul edilir', () => {
    const extra = JSON.stringify({ ...sample, signed_at: '2026-10-29', notlar: { x: 1 } });
    assert.deepEqual(parseOtaSigFile(extra), { ok: true, sig: sample });
    assert.deepEqual(parseOtaSigFile(`${String.fromCharCode(0xfeff)}${canonical}`), { ok: true, sig: sample });
    assert.equal(parseOtaSigFile(JSON.stringify({ ...sample, format: 'SKP-OTA-V1' })).ok, true);
    assert.equal(parseOtaSigFile(JSON.stringify({ ...sample, algorithm: 'ed25519' })).sig.algorithm, 'Ed25519', 'algoritma adi normalize edilir');
  });

  it('bozuk .sig sikica reddedilir: hangi alanin bozuk oldugu soylenir', () => {
    const cases = [
      ['', 'empty'],
      [undefined, 'empty'],
      ['x'.repeat(4097), 'too_large'],
      ['{ bozuk', 'not_json'],
      ['[]', 'not_object'],
      ['null', 'not_object'],
      ['"metin"', 'not_object'],
      [JSON.stringify({ ...sample, format: 'BASKA-V1' }), 'unsupported_format'],
      [JSON.stringify({ ...sample, format: undefined }), 'unsupported_format'],
      [JSON.stringify({ ...sample, algorithm: 'RSA' }), 'unsupported_algorithm'],
      [JSON.stringify({ ...sample, target: 'ESP32-C3' }), 'invalid_target'],
      [JSON.stringify({ ...sample, version: 'v4.3.4' }), 'invalid_version'],
      [JSON.stringify({ ...sample, version: '4.3' }), 'invalid_version'],
      [JSON.stringify({ ...sample, size: '1794320' }), 'invalid_size'],
      [JSON.stringify({ ...sample, size: 0 }), 'invalid_size'],
      [JSON.stringify({ ...sample, sha256: SHA.toUpperCase() }), 'invalid_sha256'],
      [JSON.stringify({ ...sample, sha256: SHA.slice(2) }), 'invalid_sha256'],
      [JSON.stringify({ ...sample, key_id: keys.keyId.toUpperCase() }), 'invalid_key_id'],
      [JSON.stringify({ ...sample, key_id: 'abc' }), 'invalid_key_id'],
      [JSON.stringify({ ...sample, signature: sigHex.toUpperCase() }), 'invalid_signature'],
      [JSON.stringify({ ...sample, signature: sigHex.slice(2) }), 'invalid_signature'],
      [JSON.stringify({ ...sample, signature: 7 }), 'invalid_signature'],
    ];
    for (const [text, error] of cases) {
      assert.deepEqual(parseOtaSigFile(text), { ok: false, error }, String(text).slice(0, 70));
    }
  });

  it('decodeOtaSignatureInput: .sig dosyasinin base64\'u, tek satirlik ham JSON ve CIPLAK imza (hex / base64) uzunlukla ayrilir', () => {
    const raw = crypto.randomBytes(64);
    // .sig dosyasi: base64 (satir sonlu da olur), ham tek satir JSON, dosya metninin kendisi
    for (const form of [
      Buffer.from(canonical).toString('base64'),
      Buffer.from(canonical).toString('base64url'),
      `\n ${Buffer.from(canonical).toString('base64')} \r\n`,
      JSON.stringify(sample),
      JSON.stringify(sample, null, 2).replace(/\n\s*/g, ' '),
    ]) {
      const decoded = decodeOtaSignatureInput(form);
      assert.equal(decoded.ok, true, form.slice(0, 40));
      assert.equal(decoded.kind, 'sigfile');
      assert.deepEqual(decoded.sig, sample);
    }
    // ciplak imza
    for (const form of [raw.toString('hex'), raw.toString('hex').toUpperCase(), raw.toString('base64'), ` ${raw.toString('base64')}\n`]) {
      const decoded = decodeOtaSignatureInput(form);
      assert.equal(decoded.ok, true, form);
      assert.equal(decoded.kind, 'bare');
      assert.ok(decoded.signature.equals(raw));
    }
    // ilk bayti '{' (0x7B) olan ciplak imza dosya sanilmaz (ayrim uzunluga gore)
    const braceFirst = Buffer.concat([Buffer.from('{'), crypto.randomBytes(63)]);
    const brace = decodeOtaSignatureInput(braceFirst.toString('base64'));
    assert.equal(brace.kind, 'bare');
    assert.ok(brace.signature.equals(braceFirst));
    // hatalar
    for (const bad of ['', '   ', 'bu bir imza degil!', 'AAAA', 'x'.repeat(300), '{}', '{"format":1}', Buffer.from('{ bozuk').toString('base64')]) {
      assert.equal(decodeOtaSignatureInput(bad).ok, false, bad);
    }
    assert.equal(decodeOtaSignatureInput(JSON.stringify({ ...sample, signature: 'zz' })).error, 'invalid_signature');
  });
});

describe('OTA imza: genel anahtar bicimleri (OTA_PUBLIC_KEY)', () => {
  it('PEM, tek satirda \\n kacisli PEM, tirnakli deger, ham 32 bayt base64/base64url/onaltilik ve DER base64 ayni anahtari verir', () => {
    const keys = newKeys();
    const forms = {
      pem: keys.pem,
      pemEscaped: keys.pem.trim().replace(/\n/g, '\\n'),
      pemQuoted: `"${keys.pem.trim().replace(/\n/g, '\\n')}"`,
      rawBase64: keys.raw32.toString('base64'),
      rawBase64Url: keys.raw32.toString('base64url'),
      rawHex: keys.raw32.toString('hex'),
      rawHexUpper: keys.raw32.toString('hex').toUpperCase(),
      derBase64: keys.der.toString('base64'),
      spaced: `  ${keys.raw32.toString('hex')}  `,
    };
    for (const [name, value] of Object.entries(forms)) {
      const parsed = parseOtaPublicKey(value);
      assert.equal(parsed.ok, true, `${name}: ${JSON.stringify(parsed)}`);
      assert.equal(parsed.keyId, keys.keyId, name);
      assert.equal(parsed.key.asymmetricKeyType, 'ed25519', name);
      const signature = sign(keys.privateKey);
      assert.equal(verifyOtaSignature({ publicKey: parsed.key, ...FIELDS, signature }), true, name);
    }
  });

  it('anahtar DONUSU: birden fazla genel anahtar (bosluk / virgul / noktali virgul / art arda PEM) kabul edilir, tekrarlar atilir, en cok 4', () => {
    const a = newKeys();
    const b = newKeys();
    const c = newKeys();
    const ids = (parsed) => parsed.keys.map((item) => item.keyId);
    assert.deepEqual(ids(parseOtaPublicKeys(`${a.raw32.toString('hex')},${b.raw32.toString('hex')}`)), [a.keyId, b.keyId]);
    assert.deepEqual(ids(parseOtaPublicKeys(`${a.raw32.toString('hex')} ; ${b.raw32.toString('base64')}\n${c.raw32.toString('hex')}`)), [a.keyId, b.keyId, c.keyId]);
    assert.deepEqual(ids(parseOtaPublicKeys(`${a.pem}${b.pem}`)), [a.keyId, b.keyId]);
    assert.deepEqual(ids(parseOtaPublicKeys(`${a.pem.trim().replace(/\n/g, '\\n')},${b.pem.trim().replace(/\n/g, '\\n')}`)), [a.keyId, b.keyId], 'kacisli PEM listesi');
    assert.deepEqual(ids(parseOtaPublicKeys(`${a.raw32.toString('hex')} ${a.raw32.toString('hex')}`)), [a.keyId], 'tekrar atilir');
    const many = Array.from({ length: 5 }, () => newKeys().raw32.toString('hex')).join(',');
    assert.deepEqual(parseOtaPublicKeys(many), { ok: false, error: 'too_many' });
    // bir tanesi bozuksa TUMU reddedilir (kismi guven yok)
    assert.equal(parseOtaPublicKeys(`${a.raw32.toString('hex')},bozuk`).ok, false);
    assert.equal(parseOtaPublicKeys(`${a.pem} bozuk metin`).ok, false);
    // tek anahtar kolayligi ilkini doner
    assert.equal(parseOtaPublicKey(`${a.raw32.toString('hex')},${b.raw32.toString('hex')}`).keyId, a.keyId);
  });

  it('OZEL anahtar (PEM) genel anahtar yerine konulursa REDDEDILIR; ozel anahtar sunucuda kullanilmaz', () => {
    const keys = newKeys();
    const privatePem = keys.privateKey.export({ format: 'pem', type: 'pkcs8' });
    assert.deepEqual(parseOtaPublicKey(privatePem), { ok: false, error: 'private_key' });
    assert.deepEqual(parseOtaPublicKey(privatePem.trim().replace(/\n/g, '\\n')), { ok: false, error: 'private_key' });
    assert.deepEqual(parseOtaPublicKeys(`${keys.raw32.toString('hex')},${privatePem}`), { ok: false, error: 'private_key' }, 'listede biri ozelse tumu red');
    // sabit "BEGIN ... PRIVATE KEY" baslik metni kaynakta durmasin (gizli-anahtar tarayicilari yanlis alarm vermesin): calisma aninda birlestirilir
    const openssh = ['-----BEGIN OPENSSH', 'PRIVATE KEY-----'].join(' ');
    assert.deepEqual(parseOtaPublicKey(`${openssh}\nabc\n${openssh.replace('BEGIN', 'END')}`), { ok: false, error: 'private_key' });
  });

  it('Ed25519 olmayan anahtar, bos ve bozuk degerler reddedilir', () => {
    const rsa = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 }).publicKey.export({ format: 'pem', type: 'spki' });
    assert.deepEqual(parseOtaPublicKey(rsa), { ok: false, error: 'not_ed25519' });
    const ec = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' }).publicKey.export({ format: 'pem', type: 'spki' });
    assert.deepEqual(parseOtaPublicKey(ec), { ok: false, error: 'not_ed25519' });
    assert.deepEqual(parseOtaPublicKey(''), { ok: false, error: 'empty' });
    assert.deepEqual(parseOtaPublicKey('   '), { ok: false, error: 'empty' });
    assert.deepEqual(parseOtaPublicKey(undefined), { ok: false, error: 'empty' });
    for (const garbage of ['not a key', 'abcd', '00'.repeat(31), '00'.repeat(33), 'AAAA'.repeat(10), '-----BEGIN PUBLIC KEY-----\nAAAA\n-----END PUBLIC KEY-----', '!!!']) {
      assert.equal(parseOtaPublicKey(garbage).ok, false, garbage);
    }
  });

  it('loadOtaPublicKey: ortamdan okur, yapilandirilmamis / gecersiz / gecerli (tek ve coklu) durumlari ayirir', () => {
    const keys = newKeys();
    const other = newKeys();
    assert.deepEqual(loadOtaPublicKey({}), { configured: false, ok: false, error: 'empty' });
    assert.deepEqual(loadOtaPublicKey({ OTA_PUBLIC_KEY: '   ' }), { configured: false, ok: false, error: 'empty' });
    const invalid = loadOtaPublicKey({ OTA_PUBLIC_KEY: 'zzz' });
    assert.equal(invalid.configured, true);
    assert.equal(invalid.ok, false);
    const valid = loadOtaPublicKey({ OTA_PUBLIC_KEY: keys.raw32.toString('hex') });
    assert.equal(valid.configured, true);
    assert.equal(valid.ok, true);
    assert.equal(valid.keyId, keys.keyId);
    assert.deepEqual(valid.keys.map((item) => item.keyId), [keys.keyId]);
    assert.equal(loadOtaPublicKey({ OTA_PUBLIC_KEY: keys.raw32.toString('hex') }), valid, 'ayni deger: onbellek');
    const both = loadOtaPublicKey({ OTA_PUBLIC_KEY: `${keys.raw32.toString('hex')},${other.raw32.toString('hex')}` });
    assert.deepEqual(both.keys.map((item) => item.keyId), [keys.keyId, other.keyId]);
    assert.equal(both.keyId, keys.keyId, 'birincil = ilk anahtar');
  });
});

describe('OTA imza: ciplak imza metnini cozme', () => {
  const raw = crypto.randomBytes(64);

  it('base64 (dolgulu/dolgusuz/url-guvenli) ve onaltilik metin ayni 64 bayti verir; kenar bosluklari yok sayilir', () => {
    const forms = [
      raw.toString('base64'),
      raw.toString('base64').replace(/=+$/, ''),
      raw.toString('base64url'),
      raw.toString('hex'),
      raw.toString('hex').toUpperCase(),
      `\n  ${raw.toString('base64')}\r\n`,
    ];
    for (const form of forms) {
      const decoded = decodeOtaSignature(form);
      assert.equal(decoded.ok, true, form);
      assert.ok(decoded.signature.equals(raw), form);
    }
  });

  it('bos, bozuk, yanlis uzunluk ve kanonik olmayan kodlama reddedilir', () => {
    assert.deepEqual(decodeOtaSignature(''), { ok: false, error: 'empty' });
    assert.deepEqual(decodeOtaSignature(undefined), { ok: false, error: 'empty' });
    assert.equal(decodeOtaSignature('not a signature!').ok, false);
    assert.equal(decodeOtaSignature('a'.repeat(127)).ok, false);
    assert.equal(decodeOtaSignature(crypto.randomBytes(63).toString('base64')).ok, false);
    assert.equal(decodeOtaSignature(crypto.randomBytes(65).toString('base64')).ok, false);
    assert.equal(decodeOtaSignature(`${raw.toString('base64')}=`).ok, false);
    assert.equal(decodeOtaSignature(`${raw.toString('base64').slice(0, 40)}=${raw.toString('base64').slice(40)}`).ok, false);
    // son base64 karakterinin kullanilmayan bitleri sifir olmali (kanonik kodlama)
    const canonical = raw.toString('base64').replace(/=+$/, '');
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const last = alphabet.indexOf(canonical[canonical.length - 1]);
    const mutated = alphabet[(last & 0x3c) | ((last & 0x03) ^ 0x01)];
    assert.equal(decodeOtaSignature(canonical.slice(0, -1) + mutated).ok, false);
  });
});

describe('OTA imza: dogrulama', () => {
  const keys = newKeys();
  const signature = sign(keys.privateKey);

  it('dogru anahtar + dogru hedef/surum/boyut/sha256 -> true', () => {
    assert.equal(verifyOtaSignature({ publicKey: keys.publicKey, ...FIELDS, signature }), true);
  });

  it('hedef, surum, boyut veya sha256 degisirse false (baska donanima / baska surum numarasina yeniden etiketleme dogrulanmaz)', () => {
    assert.equal(verifyOtaSignature({ publicKey: keys.publicKey, ...FIELDS, target: 'esp32-wroom', signature }), false);
    assert.equal(verifyOtaSignature({ publicKey: keys.publicKey, ...FIELDS, version: '4.3.5', signature }), false);
    assert.equal(verifyOtaSignature({ publicKey: keys.publicKey, ...FIELDS, version: '9.9.9', signature }), false);
    assert.equal(verifyOtaSignature({ publicKey: keys.publicKey, ...FIELDS, size: FIELDS.size + 1, signature }), false);
    assert.equal(verifyOtaSignature({ publicKey: keys.publicKey, ...FIELDS, sha256: 'b2'.repeat(32), signature }), false);
  });

  it('baska anahtar, bozulmus / kisaltilmis / uzatilmis imza ve bozuk girdi false doner (asla firlatmaz)', () => {
    const other = newKeys();
    assert.equal(verifyOtaSignature({ publicKey: other.publicKey, ...FIELDS, signature }), false);
    const flipped = Buffer.from(signature);
    flipped[10] ^= 0x01;
    assert.equal(verifyOtaSignature({ publicKey: keys.publicKey, ...FIELDS, signature: flipped }), false);
    const flippedS = Buffer.from(signature);
    flippedS[63] ^= 0x80;
    assert.equal(verifyOtaSignature({ publicKey: keys.publicKey, ...FIELDS, signature: flippedS }), false);
    assert.equal(verifyOtaSignature({ publicKey: keys.publicKey, ...FIELDS, signature: signature.subarray(0, 63) }), false);
    assert.equal(verifyOtaSignature({ publicKey: keys.publicKey, ...FIELDS, signature: Buffer.concat([signature, Buffer.from([0])]) }), false);
    assert.equal(verifyOtaSignature({ publicKey: keys.publicKey, ...FIELDS, signature: Buffer.alloc(64) }), false);
    assert.equal(verifyOtaSignature({ publicKey: keys.publicKey, ...FIELDS, signature: signature.toString('hex') }), false);
    assert.equal(verifyOtaSignature({ publicKey: null, ...FIELDS, signature }), false);
    assert.equal(verifyOtaSignature({ publicKey: keys.publicKey, ...FIELDS, version: 'v4.3.4', signature }), false);
    assert.equal(verifyOtaSignature({ publicKey: keys.publicKey, ...FIELDS, size: undefined, signature }), false);
    assert.equal(verifyOtaSignature({}), false);
    assert.equal(verifyOtaSignature(), false);
  });

  it('ham imaji imzalamak (metin degil) KABUL EDILMEZ: imza yalniz sozlesmedeki metin icindir', () => {
    const image = syntheticImage(8192, 5);
    const rawSignature = crypto.sign(null, image, keys.privateKey);
    assert.equal(
      verifyOtaSignature({
        publicKey: keys.publicKey, target: 'esp32-c3', version: '4.3.4', size: image.length, sha256: crypto.createHash('sha256').update(image).digest('hex'), signature: rawSignature,
      }),
      false,
    );
  });

  it('verifyOtaSignatureWithKeys: key_id ipucuyla dogru anahtari secer, bilinmeyen kimligi ayirir, bicimleri dener, rollback_max tasir', () => {
    const second = newKeys();
    const keyState = { configured: true, ok: true, keys: [{ key: keys.publicKey, keyId: keys.keyId }, { key: second.publicKey, keyId: second.keyId }] };
    const signedBySecond = sign(second.privateKey);

    assert.deepEqual(verifyOtaSignatureWithKeys({ keyState, signature: signedBySecond, ...FIELDS }), { ok: true, format: 'KAPI-OTA-IMZA-V1', keyId: second.keyId }, 'ipucu yok: hepsi denenir');
    assert.deepEqual(verifyOtaSignatureWithKeys({ keyState, keyId: second.keyId, signature: signedBySecond, ...FIELDS }), { ok: true, format: 'KAPI-OTA-IMZA-V1', keyId: second.keyId });
    assert.deepEqual(verifyOtaSignatureWithKeys({ keyState, keyId: second.keyId.toUpperCase(), signature: signedBySecond, ...FIELDS }).ok, true, 'kimlik buyuk/kucuk harf duyarsiz');
    // yanlis kimlik ipucu: o anahtarla dogrulanamaz
    assert.deepEqual(verifyOtaSignatureWithKeys({ keyState, keyId: keys.keyId, signature: signedBySecond, ...FIELDS }), { ok: false, reason: 'invalid' });
    // guvenilen anahtarlar arasinda olmayan kimlik
    assert.deepEqual(verifyOtaSignatureWithKeys({ keyState, keyId: '0123456789abcdef', signature: signedBySecond, ...FIELDS }), { ok: false, reason: 'key_unknown' });
    assert.deepEqual(verifyOtaSignatureWithKeys({ keyState: { ok: false }, signature: signedBySecond, ...FIELDS }), { ok: false, reason: 'no_keys' });
    // yalniz belirtilen bicim denenir
    const skp = sign(keys.privateKey, FIELDS, 'SKP-OTA-V1');
    assert.equal(verifyOtaSignatureWithKeys({ keyState, signature: skp, ...FIELDS }).format, 'SKP-OTA-V1', 'bicim verilmezse tum kayitli bicimler denenir');
    assert.equal(verifyOtaSignatureWithKeys({ keyState, formats: ['KAPI-OTA-IMZA-V1'], signature: skp, ...FIELDS }).ok, false);
    // rollback_max imzaya girmisse ayni deger gerekir
    const rollback = crypto.sign(null, buildOtaSignedMessage({ format: 'SKP-OTA-V1', ...FIELDS, rollbackMax: '4.4.1' }), keys.privateKey);
    assert.equal(verifyOtaSignatureWithKeys({ keyState, signature: rollback, ...FIELDS, rollbackMax: '4.4.1' }).ok, true);
    assert.equal(verifyOtaSignatureWithKeys({ keyState, signature: rollback, ...FIELDS, rollbackMax: '4.4.2' }).ok, false);
    assert.equal(verifyOtaSignatureWithKeys({ keyState, signature: rollback, ...FIELDS }).ok, false, 'rollback_max satiri olmadan dogrulanmaz');
  });
});

describe('OTA imza: yapilandirma ve validateEnv uyarilari', () => {
  it('resolveServeUnsigned: bos / 1 -> acik (varsayilan), 0 -> kapali, sacma deger -> varsayilan + gecersiz', () => {
    assert.deepEqual(resolveServeUnsigned({}), { value: true, valid: true });
    assert.deepEqual(resolveServeUnsigned({ OTA_SERVE_UNSIGNED: '' }), { value: true, valid: true });
    assert.deepEqual(resolveServeUnsigned({ OTA_SERVE_UNSIGNED: '1' }), { value: true, valid: true });
    assert.deepEqual(resolveServeUnsigned({ OTA_SERVE_UNSIGNED: ' TRUE ' }), { value: true, valid: true });
    assert.deepEqual(resolveServeUnsigned({ OTA_SERVE_UNSIGNED: '0' }), { value: false, valid: true });
    assert.deepEqual(resolveServeUnsigned({ OTA_SERVE_UNSIGNED: 'false' }), { value: false, valid: true });
    assert.deepEqual(resolveServeUnsigned({ OTA_SERVE_UNSIGNED: 'Hayir' }), { value: false, valid: true });
    assert.deepEqual(resolveServeUnsigned({ OTA_SERVE_UNSIGNED: 'fals' }), { value: true, valid: false });
  });

  it('otaEnvWarnings: gecerli anahtar sessiz; uretimde tanimsiz / gecersiz / ozel anahtar uyarilir; anahtar degeri ASLA yazilmaz', () => {
    const keys = newKeys();
    assert.deepEqual(otaEnvWarnings({ NODE_ENV: 'production', OTA_PUBLIC_KEY: keys.raw32.toString('hex') }), []);
    assert.deepEqual(otaEnvWarnings({ NODE_ENV: 'development' }), []);
    assert.equal(otaEnvWarnings({ NODE_ENV: 'production' }).length, 1);
    const secretish = 'gizli-deger-yazilmamali-0123456789';
    const invalid = otaEnvWarnings({ NODE_ENV: 'production', OTA_PUBLIC_KEY: secretish });
    assert.equal(invalid.length, 1);
    assert.match(invalid[0], /OTA_PUBLIC_KEY/);
    assert.equal(invalid[0].includes(secretish), false);
    const privatePem = keys.privateKey.export({ format: 'pem', type: 'pkcs8' });
    const priv = otaEnvWarnings({ OTA_PUBLIC_KEY: privatePem });
    assert.equal(priv.length, 1);
    assert.match(priv[0], /OZEL anahtar/);
    assert.equal(priv[0].includes('BEGIN'), false);
    assert.match(otaEnvWarnings({ OTA_SERVE_UNSIGNED: 'belki' }).join('\n'), /OTA_SERVE_UNSIGNED/);
  });

  it('validateEnv OTA uyarilarini ekler ve asla hata uretmez', () => {
    const base = { JWT_SECRET: 'k9Fz-test-only-long-secret-value-0123456789abcdef' };
    const bad = validateEnv({ ...base, OTA_PUBLIC_KEY: 'bozuk' });
    assert.deepEqual(bad.errors, []);
    assert.match(bad.warnings.join('\n'), /OTA_PUBLIC_KEY kullanilamiyor/);
    const keys = newKeys();
    const good = validateEnv({ ...base, OTA_PUBLIC_KEY: keys.pem });
    assert.equal(good.warnings.some((warning) => /OTA_PUBLIC_KEY/.test(warning)), false);
  });
});
