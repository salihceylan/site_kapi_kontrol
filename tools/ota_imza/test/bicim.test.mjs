// Imza bicimi (KAPI-OTA-IMZA-V1) testleri:  node --test "tools/ota_imza/test/*.test.mjs"
// Mesaj bayt-bayt sabit olmali: firmware (C++) ve sunucu (Node) AYNI baytlari kurar; bu testler bicimin sessizce degismesini engeller.

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  ALGORITMA,
  FORMAT,
  HEDEFLER,
  MAKS_IMAJ_BAYT,
  MAKS_SIG_BAYT,
  imzaDosyasiAyristir,
  imzaDosyasiKur,
  imzaDosyasiMetni,
  imzaMesajiKur,
} from '../lib/bicim.mjs';
import { IslemHatasi } from '../lib/hata.mjs';

const SHA = 'ab'.repeat(32);
const IMZA = 'cd'.repeat(64);
const KIMLIK = '0123456789abcdef';
const TEMEL = { hedef: 'esp32-wroom', surum: '5.2.3', boyut: 1826304, sha256: SHA, anahtarKimligi: KIMLIK, imzaHex: IMZA };

describe('imza mesaji', () => {
  it('bicim bayt-bayt sabittir', () => {
    const mesaj = imzaMesajiKur({ hedef: 'esp32-c3', surum: '4.3.4', boyut: 1234567, sha256: SHA });
    assert.equal(mesaj.toString('latin1'), `KAPI-OTA-IMZA-V1\ntarget=esp32-c3\nversion=4.3.4\nsize=1234567\nsha256=${SHA}\n`);
    assert.ok(Buffer.isBuffer(mesaj));
    assert.ok(!mesaj.includes(0x0d), 'CR (0x0D) bulunmamali');
    assert.ok(![...mesaj].some((bayt) => bayt > 0x7e || (bayt < 0x20 && bayt !== 0x0a)), 'yalniz yazdirilabilir ASCII ve LF');
    assert.equal(mesaj.at(-1), 0x0a, 'mesaj LF ile biter');
    assert.equal(mesaj.toString('ascii').split('\n').length, 6, '5 satir + son LF');
  });

  it('format etiketi sabittir', () => {
    assert.equal(FORMAT, 'KAPI-OTA-IMZA-V1');
    assert.equal(ALGORITMA, 'Ed25519');
  });

  it('hedef, surum, boyut ve sha256 degerlerinden her biri mesaji degistirir', () => {
    const temel = { hedef: 'esp32-c3', surum: '4.3.4', boyut: 1000, sha256: SHA };
    const ana = imzaMesajiKur(temel).toString('latin1');
    for (const degisiklik of [{ hedef: 'esp32-wroom' }, { surum: '4.3.5' }, { boyut: 1001 }, { sha256: 'ac'.repeat(32) }]) {
      assert.notEqual(imzaMesajiKur({ ...temel, ...degisiklik }).toString('latin1'), ana, JSON.stringify(degisiklik));
    }
  });

  it('bilinen hedefler: esp32-c3 ve esp32-wroom (cip kimlikleri 0x0005 ve 0x0000)', () => {
    assert.deepEqual(Object.keys(HEDEFLER).sort(), ['esp32-c3', 'esp32-wroom']);
    assert.equal(HEDEFLER['esp32-c3'].cipKimligi, 0x0005);
    assert.equal(HEDEFLER['esp32-wroom'].cipKimligi, 0x0000);
  });

  const gecersizHedefler = ['esp32c3', 'ESP32-C3', 'esp32-c3 ', 'esp32-c3\nsize=1', 'esp32-s3', '', null, undefined, 5, '__proto__', 'constructor', 'toString'];
  for (const hedef of gecersizHedefler) {
    it(`gecersiz hedef reddedilir: ${JSON.stringify(hedef)}`, () => {
      assert.throws(() => imzaMesajiKur({ hedef, surum: '4.3.4', boyut: 10, sha256: SHA }), IslemHatasi);
    });
  }

  const gecersizSurumler = [
    '4.3', '4', 'v4.3.4', '4.3.4-beta', '4.03.4', '04.3.4', '4.3.4 ', ' 4.3.4', '4.3.4\nsize=1', '4.3.4\r\n', '4.3.4.5.6', '4..3', '4.3.', '',
    '4.3.99999', '-4.3.4', '4.3.4\0', String.fromCharCode(0x664, 0x2e, 0x663, 0x2e, 0x664), null, undefined, 4.3, ['4.3.4'],
  ];
  for (const surum of gecersizSurumler) {
    it(`gecersiz surum reddedilir: ${JSON.stringify(surum)}`, () => {
      assert.throws(() => imzaMesajiKur({ hedef: 'esp32-c3', surum, boyut: 10, sha256: SHA }), IslemHatasi);
    });
  }

  for (const surum of ['0.0.0', '4.3.4', '10.20.30', '1.2.3.4', '9999.9999.9999']) {
    it(`gecerli surum kabul edilir: ${surum}`, () => {
      assert.doesNotThrow(() => imzaMesajiKur({ hedef: 'esp32-c3', surum, boyut: 10, sha256: SHA }));
    });
  }

  const gecersizBoyutlar = [0, -1, 1.5, Number.NaN, Number.POSITIVE_INFINITY, '100', null, undefined, MAKS_IMAJ_BAYT + 1, 2 ** 53];
  for (const boyut of gecersizBoyutlar) {
    it(`gecersiz boyut reddedilir: ${String(boyut)}`, () => {
      assert.throws(() => imzaMesajiKur({ hedef: 'esp32-c3', surum: '4.3.4', boyut, sha256: SHA }), IslemHatasi);
    });
  }

  it('gecerli sinir boyutlari kabul edilir (1 ve en buyuk imaj)', () => {
    assert.doesNotThrow(() => imzaMesajiKur({ hedef: 'esp32-c3', surum: '4.3.4', boyut: 1, sha256: SHA }));
    assert.doesNotThrow(() => imzaMesajiKur({ hedef: 'esp32-c3', surum: '4.3.4', boyut: MAKS_IMAJ_BAYT, sha256: SHA }));
  });

  const gecersizOzetler = ['AB'.repeat(32), 'ab'.repeat(31), 'ab'.repeat(33), `0x${'ab'.repeat(32)}`, ` ${'ab'.repeat(32)}`, `${'ab'.repeat(32)}\n`, 'zz'.repeat(32), '', null, undefined];
  for (const sha256 of gecersizOzetler) {
    it(`gecersiz sha256 reddedilir: ${JSON.stringify(sha256)?.slice(0, 30)}`, () => {
      assert.throws(() => imzaMesajiKur({ hedef: 'esp32-c3', surum: '4.3.4', boyut: 10, sha256 }), IslemHatasi);
    });
  }
});

describe('.sig dosyasi', () => {
  it('kur -> metin -> ayristir gidis donus; alan sirasi sabit', () => {
    const sig = imzaDosyasiKur(TEMEL);
    assert.deepEqual(Object.keys(sig), ['format', 'algorithm', 'target', 'version', 'size', 'sha256', 'key_id', 'signature']);
    const metin = imzaDosyasiMetni(sig);
    assert.ok(metin.endsWith('}\n'), 'LF ile biter');
    assert.ok(!metin.includes('\r'), 'CR icermez');
    assert.ok(metin.length < MAKS_SIG_BAYT, 'tipik .sig sinirin cok altinda');
    assert.deepEqual(imzaDosyasiAyristir(metin), sig);
    assert.equal(sig.format, 'KAPI-OTA-IMZA-V1');
    assert.equal(sig.algorithm, 'Ed25519');
    assert.equal(sig.target, TEMEL.hedef);
    assert.equal(sig.version, TEMEL.surum);
    assert.equal(sig.size, TEMEL.boyut);
    assert.equal(sig.sha256, SHA);
    assert.equal(sig.key_id, KIMLIK);
    assert.equal(sig.signature, IMZA);
  });

  it('kur: gecersiz alanlar reddedilir', () => {
    for (const bozuk of [{ anahtarKimligi: 'ABCDEF0123456789' }, { anahtarKimligi: '0123' }, { imzaHex: 'cd'.repeat(63) }, { imzaHex: 'CD'.repeat(64) }, { hedef: 'x' }]) {
      assert.throws(() => imzaDosyasiKur({ ...TEMEL, ...bozuk }), IslemHatasi, JSON.stringify(bozuk));
    }
  });

  const gecersizMetinler = [
    ['bos metin', ''],
    ['JSON degil', 'bu bir imza degil'],
    ['yarim JSON', '{"format": "KAPI-OTA-IMZA-V1"'],
    ['dizi', '[]'],
    ['null', 'null'],
    ['sayi', '42'],
    ['metin', '"merhaba"'],
  ];
  for (const [ad, metin] of gecersizMetinler) {
    it(`ayristirma reddeder: ${ad}`, () => {
      assert.throws(() => imzaDosyasiAyristir(metin), IslemHatasi);
    });
  }

  it('ayristirma: cok buyuk dosya reddedilir', () => {
    assert.throws(() => imzaDosyasiAyristir(`{"x":"${'a'.repeat(MAKS_SIG_BAYT)}"}`), /cok buyuk/);
  });

  it('ayristirma: metin olmayan girdi reddedilir', () => {
    assert.throws(() => imzaDosyasiAyristir(undefined), IslemHatasi);
    assert.throws(() => imzaDosyasiAyristir(Buffer.from('{}')), IslemHatasi);
  });

  it('ayristirma: format ve algoritma uyusmazligi reddedilir', () => {
    const sig = imzaDosyasiKur(TEMEL);
    assert.throws(() => imzaDosyasiAyristir(JSON.stringify({ ...sig, format: 'KAPI-OTA-IMZA-V2' })), /bicimi desteklenmiyor/);
    assert.throws(() => imzaDosyasiAyristir(JSON.stringify({ ...sig, algorithm: 'RSA' })), /algoritmasi desteklenmiyor/);
    assert.throws(() => imzaDosyasiAyristir(JSON.stringify({ ...sig, format: undefined })), /bicimi desteklenmiyor/);
  });

  const bozukAlanlar = [
    ['target', 'esp32-s3'],
    ['target', 5],
    ['version', '4.3'],
    ['version', '4.3.4\nsize=1'],
    ['size', '100'],
    ['size', 0],
    ['size', -5],
    ['size', 1.5],
    ['sha256', 'AB'.repeat(32)],
    ['sha256', 'ab'.repeat(31)],
    ['key_id', 'ABCDEF0123456789'],
    ['key_id', 12],
    ['signature', 'CD'.repeat(64)],
    ['signature', 'cd'.repeat(63)],
    ['signature', 'cd'.repeat(65)],
    ['signature', null],
  ];
  for (const [alan, deger] of bozukAlanlar) {
    it(`ayristirma: "${alan}" alani bozuksa reddedilir ve alan adi mesajda gecer (${JSON.stringify(deger)?.slice(0, 20)})`, () => {
      const sig = { ...imzaDosyasiKur(TEMEL), [alan]: deger };
      assert.throws(() => imzaDosyasiAyristir(JSON.stringify(sig)), (hata) => hata instanceof IslemHatasi && hata.message.includes(`"${alan}"`));
    });
  }

  for (const alan of ['target', 'version', 'size', 'sha256', 'key_id', 'signature']) {
    it(`ayristirma: "${alan}" alani eksikse reddedilir`, () => {
      const sig = imzaDosyasiKur(TEMEL);
      delete sig[alan];
      assert.throws(() => imzaDosyasiAyristir(JSON.stringify(sig)), (hata) => hata instanceof IslemHatasi && hata.message.includes(`"${alan}"`));
    });
  }

  it('ayristirma: bilinmeyen ek alanlar yok sayilir ve sonuca tasinmaz', () => {
    const sig = { ...imzaDosyasiKur(TEMEL), ek_alan: 'x', notlar: { a: 1 } };
    const sonuc = imzaDosyasiAyristir(JSON.stringify(sig));
    assert.deepEqual(sonuc, imzaDosyasiKur(TEMEL));
    assert.ok(!('ek_alan' in sonuc));
  });

  it('ayristirma: UTF-8 BOM tolere edilir', () => {
    const metin = imzaDosyasiMetni(imzaDosyasiKur(TEMEL));
    assert.deepEqual(imzaDosyasiAyristir(`${String.fromCharCode(0xfeff)}${metin}`), imzaDosyasiKur(TEMEL));
  });

  it('ayristirma: "__proto__" anahtari prototipi kirletmez', () => {
    const metin = imzaDosyasiMetni(imzaDosyasiKur(TEMEL)).replace('{\n', '{\n  "__proto__": {"kirlendi": true},\n');
    const sonuc = imzaDosyasiAyristir(metin);
    assert.equal({}.kirlendi, undefined);
    assert.equal(sonuc.kirlendi, undefined);
  });
});
