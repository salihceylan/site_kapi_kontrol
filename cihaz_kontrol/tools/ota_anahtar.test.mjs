// ota_anahtar.mjs testleri: node --test cihaz_kontrol/tools/
// TEST ANAHTARLARI - uretimde kullanilmaz: her calistirmada crypto.generateKeyPairSync ile uretilen gecici anahtarlardir.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  VARSAYILAN_BASLIK,
  YER_TUTUCU,
  anahtarCozumle,
  anahtarDogrula,
  baslikUret,
  calistir,
  ikiliKontrol,
  parmakIzi,
} from './ota_anahtar.mjs';

const KUCUK_MERTEBELI = [
  '0100000000000000000000000000000000000000000000000000000000000000',
  'ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
  '0000000000000000000000000000000000000000000000000000000000000080',
  '0000000000000000000000000000000000000000000000000000000000000000',
  'c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a',
  'c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa',
  '26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05',
  '26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85',
];

function yeniAnahtar() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const jwk = publicKey.export({ format: 'jwk' });
  return {
    bayt: Buffer.from(jwk.x, 'base64url'),
    pem: publicKey.export({ format: 'pem', type: 'spki' }),
    ozelPem: privateKey.export({ format: 'pem', type: 'pkcs8' }),
    spkiDer: publicKey.export({ format: 'der', type: 'spki' }),
  };
}

// console ciktisini yakalar
function sustur(fn) {
  const eski = { log: console.log, error: console.error };
  const log = [];
  const hata = [];
  console.log = (...a) => log.push(a.join(' '));
  console.error = (...a) => hata.push(a.join(' '));
  try {
    return { sonuc: fn(), log: log.join('\n'), hata: hata.join('\n') };
  } finally {
    console.log = eski.log;
    console.error = eski.error;
  }
}

function geciciDizin() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'ota-anahtar-'));
}

test('gercek Ed25519 genel anahtarlari kabul edilir (OpenSSL ile uretilen 100 anahtar)', () => {
  for (let i = 0; i < 100; i += 1) {
    const k = yeniAnahtar();
    assert.deepEqual(anahtarDogrula(k.bayt), { ok: true, neden: '' });
  }
});

test('8 bilinen kucuk mertebeli nokta, tum-sifir, yer tutucu, kanonik olmayan y ve yanlis uzunluk reddedilir', () => {
  for (const h of KUCUK_MERTEBELI) {
    assert.equal(anahtarDogrula(Buffer.from(h, 'hex')).ok, false, `kucuk mertebeli kabul edildi: ${h}`);
  }
  assert.equal(anahtarDogrula(YER_TUTUCU).ok, false);
  assert.match(anahtarDogrula(YER_TUTUCU).neden, /YER TUTUCU/);
  assert.equal(anahtarDogrula(Buffer.alloc(32)).ok, false);
  assert.equal(anahtarDogrula(Buffer.from('edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f', 'hex')).ok, false, 'y = p');
  assert.equal(anahtarDogrula(Buffer.alloc(31, 1)).ok, false);
  assert.equal(anahtarDogrula(Buffer.alloc(33, 1)).ok, false);
  assert.equal(anahtarDogrula('metin').ok, false);
});

test('rastgele 32 baytlar: egride olmayanlar reddedilir, hicbiri istisna firlatmaz', () => {
  let kabul = 0;
  let red = 0;
  for (let i = 0; i < 200; i += 1) {
    const r = anahtarDogrula(crypto.randomBytes(32));
    if (r.ok) kabul += 1; else red += 1;
  }
  assert.ok(kabul > 40 && red > 40, `kabul=${kabul} red=${red} (yaklasik yari yari beklenir)`);
});

test('anahtarCozumle: hex, BUYUK hex+bosluk, base64, base64url, SPKI DER base64, PEM metni, PEM dosyasi', () => {
  const k = yeniAnahtar();
  const hex = k.bayt.toString('hex');
  assert.deepEqual(anahtarCozumle(hex), k.bayt);
  assert.deepEqual(anahtarCozumle(`  ${hex.toUpperCase().replace(/(.{8})/g, '$1 ')}\n`), k.bayt);
  assert.deepEqual(anahtarCozumle(k.bayt.toString('base64')), k.bayt);
  assert.deepEqual(anahtarCozumle(k.bayt.toString('base64url')), k.bayt);
  assert.deepEqual(anahtarCozumle(k.spkiDer.toString('base64')), k.bayt);
  assert.deepEqual(anahtarCozumle(k.pem), k.bayt);
  const dizin = geciciDizin();
  const dosya = path.join(dizin, 'genel.pem');
  fs.writeFileSync(dosya, k.pem);
  assert.deepEqual(anahtarCozumle(dosya), k.bayt);
  fs.rmSync(dizin, { recursive: true, force: true });
});

test('anahtarCozumle: OZEL anahtar (PEM metni ya da dosyasi) ve cop girdi reddedilir', () => {
  const k = yeniAnahtar();
  assert.throws(() => anahtarCozumle(k.ozelPem), /OZEL ANAHTAR/);
  const dizin = geciciDizin();
  const dosya = path.join(dizin, 'ozel.pem');
  fs.writeFileSync(dosya, k.ozelPem);
  assert.throws(() => anahtarCozumle(dosya), /OZEL ANAHTAR/);
  fs.rmSync(dizin, { recursive: true, force: true });
  assert.throws(() => anahtarCozumle(''), /verilmedi/);
  assert.throws(() => anahtarCozumle('merhaba dunya'), /taninmadi/);
  assert.throws(() => anahtarCozumle('abcd'), /taninmadi/);
});

test('parmakIzi: SHA-256 ilk 8 bayt (cihaz seri cikisiyla ayni tanim)', () => {
  assert.equal(parmakIzi(Buffer.alloc(32)), '66687aadf862bd77');  // SHA-256(32 sifir bayt) = 66687aadf862bd776c8f...
  const k = yeniAnahtar();
  assert.equal(parmakIzi(k.bayt), crypto.createHash('sha256').update(k.bayt).digest('hex').slice(0, 16));
});

test('teslim edilen include/ota_public_key.h sablonla BAYT-BAYT ayni (yer tutucu ya da yerlestirilmis anahtar)', () => {
  const metin = fs.readFileSync(VARSAYILAN_BASLIK, 'utf8').replace(/\r\n/g, '\n');
  const bloklar = [...metin.matchAll(/0x([0-9a-f]{2})/g)].map((m) => m[1]);
  assert.equal(bloklar.length, 32, 'baslikta tam 32 bayt olmali');
  const bayt = Buffer.from(bloklar.join(''), 'hex');
  const beklenen = bayt.equals(YER_TUTUCU) ? baslikUret(null) : baslikUret(bayt);
  assert.equal(metin, beklenen, 'baslik ota_anahtar.mjs sablonundan sapmis; "yaz"/"yer-tutucu" ile yeniden uretin');
  if (!bayt.equals(YER_TUTUCU)) {
    assert.equal(anahtarDogrula(bayt).ok, true, 'yerlestirilmis anahtar gecerli olmali');
  }
});

test('yaz: basligi bastan yazar, parmak izini gosterir; EOL korunur; gecersiz anahtarda dosyaya DOKUNMAZ', () => {
  const dizin = geciciDizin();
  const hedef = path.join(dizin, 'ota_public_key.h');
  fs.writeFileSync(hedef, 'ESKI ICERIK\r\nikinci satir\r\n');   // CRLF'li mevcut dosya
  const k = yeniAnahtar();
  const o = sustur(() => calistir(['yaz', k.bayt.toString('hex'), '--cikti', hedef]));
  assert.equal(o.sonuc, 0);
  const yazilan = fs.readFileSync(hedef, 'utf8');
  assert.ok(yazilan.includes('\r\n') && !/[^\r]\n/.test(yazilan), 'CRLF korunmali');
  assert.equal(yazilan, baslikUret(k.bayt, '\r\n'));
  assert.match(yazilan, /DURUM: GERCEK ANAHTAR/);
  assert.ok(!yazilan.includes('YER TUTUCU  (gercek'), 'yer tutucu durum satiri kalmamali');
  assert.ok(o.log.includes(parmakIzi(k.bayt)) && o.log.includes(k.bayt.toString('hex')));
  // geri okuma: baslikta yazan bayt dizisi girdiyle ayni
  const geri = Buffer.from([...yazilan.matchAll(/0x([0-9a-f]{2})/g)].map((m) => m[1]).join(''), 'hex');
  assert.deepEqual(geri, k.bayt);

  // gecersiz (kucuk mertebeli) -> hata, dosya degismez
  const once = fs.readFileSync(hedef, 'utf8');
  const kotu = sustur(() => calistir(['yaz', KUCUK_MERTEBELI[0], '--cikti', hedef]));
  assert.equal(kotu.sonuc, 1);
  assert.match(kotu.hata, /kucuk mertebeli/);
  assert.equal(fs.readFileSync(hedef, 'utf8'), once);
  // yer tutucu metni -> hata
  const yt = sustur(() => calistir(['yaz', YER_TUTUCU.toString('hex'), '--cikti', hedef]));
  assert.equal(yt.sonuc, 1);
  assert.equal(fs.readFileSync(hedef, 'utf8'), once);
  // OZEL anahtar PEM -> hata, dosya degismez
  const oz = sustur(() => calistir(['yaz', k.ozelPem, '--cikti', hedef]));
  assert.equal(oz.sonuc, 1);
  assert.match(oz.hata, /OZEL ANAHTAR/);
  assert.equal(fs.readFileSync(hedef, 'utf8'), once);
  fs.rmSync(dizin, { recursive: true, force: true });
});

test('yer-tutucu: basligi teslim edilen yer tutucu haline dondurur', () => {
  const dizin = geciciDizin();
  const hedef = path.join(dizin, 'ota_public_key.h');
  const k = yeniAnahtar();
  sustur(() => calistir(['yaz', k.bayt.toString('hex'), '--cikti', hedef]));
  const o = sustur(() => calistir(['yer-tutucu', '--cikti', hedef]));
  assert.equal(o.sonuc, 0);
  assert.equal(fs.readFileSync(hedef, 'utf8'), baslikUret(null));
  fs.rmSync(dizin, { recursive: true, force: true });
});

test('ikiliKontrol: yer tutucu -> 2 (yer tutucu kazanir), beklenen anahtar yok -> 3, tamam -> 0', () => {
  const k = yeniAnahtar();
  const baska = yeniAnahtar();
  const dolgu = crypto.randomBytes(5000);
  const temiz = Buffer.concat([dolgu, k.bayt, crypto.randomBytes(100)]);
  assert.equal(ikiliKontrol(temiz, k.bayt).kod, 0);
  assert.equal(ikiliKontrol(temiz, null).kod, 0);
  assert.equal(ikiliKontrol(temiz, baska.bayt).kod, 3);
  const yerTutuculu = Buffer.concat([dolgu, YER_TUTUCU, crypto.randomBytes(100)]);
  assert.equal(ikiliKontrol(yerTutuculu, null).kod, 2);
  assert.equal(ikiliKontrol(yerTutuculu, k.bayt).kod, 2);
  assert.equal(ikiliKontrol(Buffer.concat([temiz, YER_TUTUCU]), k.bayt).kod, 2, 'gercek anahtar da varken yer tutucu kalmissa YAYINLANMAZ');
  assert.match(ikiliKontrol(yerTutuculu, null).mesaj, /YER TUTUCU/);
});

test('kontrol komutu: cikis kodlari 0 / 2 / 3 / 1 ve dosya okuma', () => {
  const dizin = geciciDizin();
  const k = yeniAnahtar();
  const baska = yeniAnahtar();
  const iyi = path.join(dizin, 'iyi.bin');
  const yt = path.join(dizin, 'yer_tutuculu.bin');
  fs.writeFileSync(iyi, Buffer.concat([crypto.randomBytes(2000), k.bayt]));
  fs.writeFileSync(yt, Buffer.concat([crypto.randomBytes(2000), YER_TUTUCU]));
  assert.equal(sustur(() => calistir(['kontrol', iyi, k.bayt.toString('hex')])).sonuc, 0);
  assert.equal(sustur(() => calistir(['kontrol', iyi])).sonuc, 0);
  assert.equal(sustur(() => calistir(['kontrol', iyi, baska.bayt.toString('hex')])).sonuc, 3);
  const r2 = sustur(() => calistir(['kontrol', yt, k.bayt.toString('hex')]));
  assert.equal(r2.sonuc, 2);
  assert.match(r2.hata, /YER TUTUCU/);
  assert.equal(sustur(() => calistir(['kontrol', path.join(dizin, 'yok.bin')])).sonuc, 1);
  assert.equal(sustur(() => calistir(['kontrol', iyi, KUCUK_MERTEBELI[1]])).sonuc, 1, 'gecersiz beklenen anahtar');
  assert.equal(sustur(() => calistir(['kontrol'])).sonuc, 1);
  fs.rmSync(dizin, { recursive: true, force: true });
});

test('parmak-izi komutu ve bilinmeyen komut', () => {
  const k = yeniAnahtar();
  const o = sustur(() => calistir(['parmak-izi', k.bayt.toString('hex')]));
  assert.equal(o.sonuc, 0);
  assert.equal(o.log, parmakIzi(k.bayt));
  assert.equal(sustur(() => calistir(['bilinmeyen'])).sonuc, 1);
  assert.equal(sustur(() => calistir([])).sonuc, 0);
});
