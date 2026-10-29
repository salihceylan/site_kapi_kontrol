// Node crypto (OpenSSL) ile SHA-512 / Ed25519 / OTA imza yuku test vektorleri uretir -> imza_vectors.txt (git'e girmez).
//
// TEST ANAHTARI - uretimde kullanilmaz: dosyadaki tohumlar (seed) her calistirmada RASTGELE uretilen gecici anahtarlara aittir;
// kalici/gercek hicbir anahtar degildir. Firmware cekirdegi (include/ota_ed25519.h, ota_imza.h) bunlarla t_imza.cpp icinde capraz dogrulanir.
//
// Satir bicimleri (bosluk ayracli, '-' = bos):
//   H <ileti hex|-> <sha512 hex>                                       SHA-512 (OpenSSL)
//   M <bayt hex> <adet> <sha512 hex>                                   ayni baytin <adet> kez tekrari (ornegin 1.000.000 x 'a')
//   E <genel anahtar> <ileti|-> <imza> <tohum>                         Ed25519, Node imzali
//   K <32 bayt hex> <1|0>                                              genel anahtar gecerli mi? (tools/ota_anahtar.mjs BigInt gerceklemesi)
//   O <genel anahtar> <tohum> <hedef> <surum> <boyut> <sha256> <rollback_max|-> <imza>   OTA imza yuku, Node imzali
//   T <genel anahtar> <hedef> <surum> <boyut> <sha256> <rollback_max|-> <imza>   IMZALAMA ARACININ bilinen-cevap vektoru
//                                                                              (tools/ota_imza/test/vektorler.json; ozel anahtar YOK)
//   P <.sig dosyasi baytlari hex> <beklenen imza hex>                           ARACIN GERCEK .sig serilestiricisinin ciktisi (t_mqtt S13: cihaz JSON ayristiricisi)
//
// IMZALAYAN taraf icin referans uygulama tools/ota_imza/lib/bicim.mjs'tir (BAGLAYICI TANIM: tools/ota_imza/README.md). imzaYuku() bu
// dosyanin kendi kurucusudur (cihazin "-rc1" gibi esnek surumlerini de denemek icin) ve kati surumlerde ARAC KURUCUSUYLA BAYT-BAYT ayni
// olmak ZORUNDADIR (aksi halde uretim durur): cihaz, arac ve sunucu ayni baytlari imzalar/dogrular (docs/OTA_IMZA_CIHAZ.md "Imzalanan ileti").
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { imzaDosyasiKur, imzaDosyasiMetni, imzaMesajiKur } from '../../tools/ota_imza/lib/bicim.mjs';
import { anahtarDogrula } from '../tools/ota_anahtar.mjs';

const PKCS8_ONEK = Buffer.from('302e020100300506032b657004220420', 'hex');
const ARAC_VEKTORLERI = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'tools', 'ota_imza', 'test', 'vektorler.json');
const KATI_SURUM = /^(?:0|[1-9][0-9]{0,3})(?:\.(?:0|[1-9][0-9]{0,3})){2,3}$/;

export function tohumdanAnahtar(tohum) {
  const ozel = crypto.createPrivateKey({ key: Buffer.concat([PKCS8_ONEK, tohum]), format: 'der', type: 'pkcs8' });
  const genelDer = crypto.createPublicKey(ozel).export({ format: 'der', type: 'spki' });
  return { ozel, genel: Buffer.from(genelDer.subarray(genelDer.length - 32)) };
}

// OTA imza yuku (cihaz ota_imza.h otaImzaYukuOlustur ile AYNI baytlar): ASCII, her satir "\n" ile biter.
export function imzaYuku({ target, version, size, sha256, rollbackMax }) {
  let s = `KAPI-OTA-IMZA-V1\ntarget=${target}\nversion=${version}\nsize=${size}\nsha256=${sha256}\n`;
  if (rollbackMax) {
    s += `rollback_max=${rollbackMax}\n`;
  }
  const yuk = Buffer.from(s, 'utf8');
  // Kati surumlerde imzalama aracinin kurucusuyla BAYT-BAYT ayni olmali (tek bicim; sessiz ayrisma olamaz)
  if (KATI_SURUM.test(version) && (!rollbackMax || KATI_SURUM.test(rollbackMax))) {
    const arac = imzaMesajiKur({ hedef: target, surum: version, boyut: size, sha256, rollbackMax: rollbackMax || undefined });
    if (!arac.equals(yuk)) {
      throw new Error(`imzaYuku(): arac kurucusuyla (tools/ota_imza/lib/bicim.mjs) ayni degil: ${JSON.stringify(s)}`);
    }
  }
  return yuk;
}

function hexVeyaTire(b) {
  return b.length ? b.toString('hex') : '-';
}

function uret() {
  const satirlar = [];
  satirlar.push('# TEST ANAHTARI - uretimde kullanilmaz. Her calistirmada rastgele uretilen gecici anahtarlar; git\'e girmez.');

  // SHA-512: sinir uzunluklari (blok/dolgu sinirlari) + bilinen iletiler
  const uzunluklar = [0, 1, 2, 3, 55, 56, 63, 64, 65, 111, 112, 113, 127, 128, 129, 200, 239, 240, 241, 255, 256, 257, 383, 384, 385, 1000, 1023, 1024, 2047, 5000];
  for (const n of uzunluklar) {
    const m = crypto.randomBytes(n);
    satirlar.push(`H ${hexVeyaTire(m)} ${crypto.createHash('sha512').update(m).digest('hex')}`);
  }
  for (const s of [
    'abc',
    'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
    'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu',
  ]) {
    const m = Buffer.from(s, 'ascii');
    satirlar.push(`H ${m.toString('hex')} ${crypto.createHash('sha512').update(m).digest('hex')}`);
  }
  const milyonA = crypto.createHash('sha512').update(Buffer.alloc(1000000, 0x61)).digest('hex');
  satirlar.push(`M 61 1000000 ${milyonA}`);

  // Ed25519: rastgele anahtar + rastgele ileti (ilk 20'si 0..19 bayt: kisa iletiler)
  for (let i = 0; i < 200; i += 1) {
    const tohum = crypto.randomBytes(32);
    const { ozel, genel } = tohumdanAnahtar(tohum);
    const n = i < 20 ? i : crypto.randomInt(0, 500);
    const m = crypto.randomBytes(n);
    const imza = crypto.sign(null, m, ozel);
    satirlar.push(`E ${genel.toString('hex')} ${hexVeyaTire(m)} ${imza.toString('hex')} ${tohum.toString('hex')}`);
  }

  // Genel anahtar gecerliligi: ayni kurallari uygulayan BAGIMSIZ JS (BigInt) gerceklemesi ile C++ (TweetNaCl) karsilastirilir.
  // Yapisal adaylar (y degeri 0..5, p-2.., p, p+1, 2^255-1; isaret biti 0/1) + 300 rastgele 32 bayt.
  const P = (1n << 255n) - 19n;
  const yAdaylari = [0n, 1n, 2n, 3n, 4n, 5n, 6n, 7n, 8n, 9n, 10n, 11n, 12n, 13n, 14n, 15n, 16n, 17n, 18n, 19n, P - 3n, P - 2n, P - 1n, P, P + 1n, P + 2n, P + 18n, (1n << 255n) - 1n];
  const anahtarAdaylari = [];
  for (const y of yAdaylari) {
    for (const isaret of [0n, 1n]) {
      let v = (y & ((1n << 255n) - 1n)) | (isaret << 255n);
      const b = Buffer.alloc(32);
      for (let i = 0; i < 32; i += 1) {
        b[i] = Number(v & 0xffn);
        v >>= 8n;
      }
      anahtarAdaylari.push(b);
    }
  }
  for (let i = 0; i < 300; i += 1) {
    anahtarAdaylari.push(crypto.randomBytes(32));
  }
  for (const b of anahtarAdaylari) {
    satirlar.push(`K ${b.toString('hex')} ${anahtarDogrula(b).ok ? 1 : 0}`);
  }

  // OTA imza yuku: gercekci alanlar
  const hedefler = ['esp32-c3', 'esp32-wroom'];
  for (let i = 0; i < 60; i += 1) {
    const tohum = crypto.randomBytes(32);
    const { ozel, genel } = tohumdanAnahtar(tohum);
    const hedef = hedefler[i % 2];
    const surum = `${crypto.randomInt(0, 21)}.${crypto.randomInt(0, 21)}.${crypto.randomInt(0, 100)}${i % 7 === 0 ? '-rc1' : ''}`;
    const boyut = crypto.randomInt(1, 1900000);
    const sha256 = crypto.randomBytes(32).toString('hex');
    const rollbackMax = i % 3 === 0 ? `${crypto.randomInt(0, 21)}.${crypto.randomInt(0, 21)}.${crypto.randomInt(0, 100)}` : '';
    const yuk = imzaYuku({ target: hedef, version: surum, size: boyut, sha256, rollbackMax });
    const imza = crypto.sign(null, yuk, ozel);
    satirlar.push(`O ${genel.toString('hex')} ${tohum.toString('hex')} ${hedef} ${surum} ${boyut} ${sha256} ${rollbackMax || '-'} ${imza.toString('hex')}`);
  }

  // Imzalama aracinin bilinen-cevap vektorleri (ozel anahtar yok): cihaz kodu bu imzalari gomulu-anahtar mantigiyla DOGRULAMALI
  const belge = JSON.parse(fs.readFileSync(ARAC_VEKTORLERI, 'utf8'));
  for (const v of belge.vektorler) {
    satirlar.push(`T ${belge.genel_anahtar_hex} ${v.hedef} ${v.surum} ${v.boyut} ${v.sha256} - ${v.imza_hex}`);
  }
  const r = belge.rollback_vektoru;
  satirlar.push(`T ${r.genel_anahtar_hex} ${r.hedef} ${r.surum} ${r.boyut} ${r.sha256} ${r.rollback_max} ${r.imza_hex}`);

  // Aracin GERCEK .sig serilestiricisi (imzaDosyasiKur + imzaDosyasiMetni): cihazin JSON ayristiricisi bu dosya baytlarindan imzayi cikarabilmeli
  for (const v of belge.vektorler) {
    const metin = imzaDosyasiMetni(imzaDosyasiKur({ hedef: v.hedef, surum: v.surum, boyut: v.boyut, sha256: v.sha256, anahtarKimligi: belge.anahtar_kimligi, imzaHex: v.imza_hex }));
    satirlar.push(`P ${Buffer.from(metin, 'utf8').toString('hex')} ${v.imza_hex}`);
  }
  const rmetin = imzaDosyasiMetni(imzaDosyasiKur({
    hedef: r.hedef, surum: r.surum, boyut: r.boyut, sha256: r.sha256, anahtarKimligi: r.anahtar_kimligi, imzaHex: r.imza_hex, rollbackMax: r.rollback_max,
  }));
  satirlar.push(`P ${Buffer.from(rmetin, 'utf8').toString('hex')} ${r.imza_hex}`);
  return satirlar;
}

function dogrudanCalistirildiMi() {
  if (!process.argv[1]) {
    return false;
  }
  const a = path.resolve(fileURLToPath(import.meta.url));
  const b = path.resolve(process.argv[1]);
  return process.platform === 'win32' ? a.toLowerCase() === b.toLowerCase() : a === b;  // Windows: surucu harfi buyuk/kucuk farki
}

if (dogrudanCalistirildiMi()) {
  const satirlar = uret();
  fs.writeFileSync('imza_vectors.txt', `${satirlar.join('\n')}\n`);
  console.log('imza vektor satiri', satirlar.length);
}
