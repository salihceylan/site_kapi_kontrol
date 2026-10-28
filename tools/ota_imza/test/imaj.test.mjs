// Imaj okuma, ESP32 baslik denetimi ve yardimci fonksiyon testleri:  node --test "tools/ota_imza/test/*.test.mjs"

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { afterEach, beforeEach, describe, it } from 'node:test';
import { MAKS_IMAJ_BAYT } from '../lib/bicim.mjs';
import { guvenliMetin } from '../lib/hata.mjs';
import { BASLIK_BAYT, hedefUyumunuDenetle, imajBasliginiCoz, imajOku, imajdaSurumVarMi } from '../lib/imaj.mjs';
import { geciciDizin, sahteImaj, temizle } from './yardimci.mjs';

function baslik({ magic = 0xe9, segment = 5, cip = 0x0005 } = {}) {
  const b = Buffer.alloc(BASLIK_BAYT + 8);
  b[0] = magic;
  b[1] = segment;
  b.writeUInt16LE(cip, 12);
  return b;
}

describe('imajBasliginiCoz', () => {
  it('gecerli basligi cozer: cip kimligi little-endian bayt 12-13, cip adi', () => {
    assert.deepEqual(
      (({ gecerli, segmentSayisi, cipKimligi, cipAdi }) => ({ gecerli, segmentSayisi, cipKimligi, cipAdi }))(imajBasliginiCoz(baslik())),
      { gecerli: true, segmentSayisi: 5, cipKimligi: 0x0005, cipAdi: 'ESP32-C3' },
    );
    assert.equal(imajBasliginiCoz(baslik({ cip: 0x0000 })).cipAdi, 'ESP32');
    assert.equal(imajBasliginiCoz(baslik({ cip: 0x0009 })).cipAdi, 'ESP32-S3');
    assert.match(imajBasliginiCoz(baslik({ cip: 0x1234 })).cipAdi, /bilinmeyen cip \(0x1234\)/);
  });

  it('cip kimligi iki bayttir: yuksek bayt da okunur (0x0105 C3 sayilmaz)', () => {
    const b = baslik();
    b[12] = 0x05;
    b[13] = 0x01;
    assert.equal(imajBasliginiCoz(b).cipKimligi, 0x0105);
    assert.equal(hedefUyumunuDenetle('esp32-c3', b).ok, false);
  });

  it('gecersiz basliklari reddeder: kisa, yanlis taniticisi, segment sayisi 0 ve 17', () => {
    assert.equal(imajBasliginiCoz(Buffer.alloc(10)).gecerli, false);
    assert.equal(imajBasliginiCoz(Buffer.alloc(0)).gecerli, false);
    assert.match(imajBasliginiCoz(baslik({ magic: 0x7f })).neden, /\(0xE9\) yok/);
    assert.match(imajBasliginiCoz(baslik({ segment: 0 })).neden, /segment sayisi/);
    assert.match(imajBasliginiCoz(baslik({ segment: 17 })).neden, /segment sayisi/);
    assert.equal(imajBasliginiCoz(baslik({ segment: 16 })).gecerli, true);
    assert.equal(imajBasliginiCoz(baslik({ segment: 1 })).gecerli, true);
  });
});

describe('hedefUyumunuDenetle', () => {
  it('her hedef yalniz kendi cipinin imajini kabul eder', () => {
    assert.equal(hedefUyumunuDenetle('esp32-c3', baslik({ cip: 0x0005 })).ok, true);
    assert.equal(hedefUyumunuDenetle('esp32-wroom', baslik({ cip: 0x0000 })).ok, true);
    assert.equal(hedefUyumunuDenetle('esp32-wroom', baslik({ cip: 0x0005 })).ok, false);
    assert.equal(hedefUyumunuDenetle('esp32-c3', baslik({ cip: 0x0000 })).ok, false);
    assert.equal(hedefUyumunuDenetle('esp32-c3', baslik({ cip: 0x0009 })).ok, false);
    assert.equal(hedefUyumunuDenetle('esp32-wroom', baslik({ cip: 0x0009 })).ok, false);
  });

  it('gecersiz baslik ayrintida nedenini soyler', () => {
    const sonuc = hedefUyumunuDenetle('esp32-c3', Buffer.from('duz metin dosyasi, ESP32 imaji degil'));
    assert.equal(sonuc.ok, false);
    assert.match(sonuc.ayrinti, /\(0xE9\) yok/);
  });
});

describe('imajdaSurumVarMi', () => {
  it('surumu NUL sonlu dize olarak arar: 4.3.4, 4.3.45 icinde sayilmaz', () => {
    assert.equal(imajdaSurumVarMi(Buffer.from('abc\x004.3.4\x00xyz'), '4.3.4'), true);
    assert.equal(imajdaSurumVarMi(Buffer.from('abc\x004.3.45\x00xyz'), '4.3.4'), false);
    assert.equal(imajdaSurumVarMi(Buffer.from('abc\x004.3.3\x00xyz'), '4.3.4'), false);
    assert.equal(imajdaSurumVarMi(Buffer.from('4.3.4'), '4.3.4'), false, 'sonlandirici NUL yoksa bulunmaz');
  });

  it('bilinen sinirlama: daha uzun bir dizenin sonu da eslesir (yalniz UYARI uretmek icin kullanilan bir sezgidir)', () => {
    assert.equal(imajdaSurumVarMi(Buffer.from('x14.3.4\x00'), '4.3.4'), true);
  });
});

describe('imajOku', () => {
  let dizin;
  beforeEach(() => {
    dizin = geciciDizin();
  });
  afterEach(() => temizle(dizin));

  it('boyut, SHA-256 (kucuk harf hex) ve baytlari dondurur', () => {
    const imaj = sahteImaj({ boyut: 12345 });
    const yol = path.join(dizin, 'a.bin');
    fs.writeFileSync(yol, imaj);
    const sonuc = imajOku(yol);
    assert.equal(sonuc.boyut, imaj.length);
    assert.equal(sonuc.sha256, crypto.createHash('sha256').update(imaj).digest('hex'));
    assert.match(sonuc.sha256, /^[0-9a-f]{64}$/);
    assert.deepEqual(sonuc.veri, imaj);
  });

  it('bos, olmayan, klasor ve cok buyuk dosyayi reddeder', () => {
    const bos = path.join(dizin, 'bos.bin');
    fs.writeFileSync(bos, '');
    const buyuk = path.join(dizin, 'buyuk.bin');
    fs.writeFileSync(buyuk, '');
    fs.truncateSync(buyuk, MAKS_IMAJ_BAYT + 1);
    assert.throws(() => imajOku(bos), /bos/);
    assert.throws(() => imajOku(path.join(dizin, 'yok.bin')), /okunamadi/);
    assert.throws(() => imajOku(dizin), /dosya degil/);
    assert.throws(() => imajOku(buyuk), /cok buyuk/);
  });

  it('en buyuk izinli boyuttaki dosya okunur', () => {
    const sinir = path.join(dizin, 'sinir.bin');
    fs.writeFileSync(sinir, '');
    fs.truncateSync(sinir, MAKS_IMAJ_BAYT);
    assert.equal(imajOku(sinir).boyut, MAKS_IMAJ_BAYT);
  });
});

describe('guvenliMetin', () => {
  it('denetim karakterlerini (C0, DEL, C1) etkisizlestirir ve uzun metni kisaltir', () => {
    const kirli = guvenliMetin('a\u001b[31mb\u0007c\u007fd\u009be\nf');
    // eslint-disable-next-line no-control-regex -- sonucta HICBIR denetim karakteri kalmadigini denetler
    assert.ok(!/[\u0000-\u001f\u007f-\u009f]/.test(kirli));
    assert.equal(guvenliMetin('x'.repeat(200)).length, 80 + 3 + 2, 'tirnaklar + 80 karakter + ...');
    assert.equal(guvenliMetin(undefined), '""');
    assert.equal(guvenliMetin(null), '""');
    assert.equal(guvenliMetin(42), '"42"');
  });
});
