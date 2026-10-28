#!/usr/bin/env node
// OTA imza GENEL anahtari yardimcisi (cihaz_kontrol/include/ota_public_key.h). Yalniz GENEL anahtarla calisir:
// OZEL ANAHTAR bu betige verilmez, okunmaz, yazilmaz, gunluge girmez (PEM "PRIVATE KEY" verilirse reddedilir).
//
// Kullanim:
//   node cihaz_kontrol/tools/ota_anahtar.mjs yaz <genel_anahtar> [--cikti <dosya>]
//       genel anahtari ota_public_key.h'a yazar (dosyayi BASTAN yazar), parmak izini gosterir.
//       <genel_anahtar>: 64 hane hex | base64 (32 bayt) | SPKI PEM metni | SPKI PEM dosya yolu
//   node cihaz_kontrol/tools/ota_anahtar.mjs yer-tutucu [--cikti <dosya>]
//       basligi teslim edilen YER TUTUCU haline dondurur (yalniz gelistirme/test icin)
//   node cihaz_kontrol/tools/ota_anahtar.mjs parmak-izi <genel_anahtar>
//       cihazin acilista seriye yazdigi parmak izini (SHA-256 ilk 8 bayt, 16 hane hex) gosterir
//   node cihaz_kontrol/tools/ota_anahtar.mjs kontrol <firmware.bin> [<genel_anahtar>]
//       YAYIN ONCESI: ikilide YER TUTUCU kalmadigini ve (verildiyse) beklenen anahtarin gomulu oldugunu denetler.
//       cikis kodu: 0 tamam | 2 yer tutucu iceriyor (YAYINLAMAYIN) | 3 beklenen anahtar ikilide yok | 1 baska hata
//
// Cihaz yer tutucuyu calisma zamaninda tanir ve HICBIR paketi kurmaz; yer tutuculu surum sahaya cikarsa o cihazlar bir daha OTA ile
// guncellenemez (USB gerekir). "kontrol" bu kazayi yayin oncesi yakalar. docs/OTA_IMZA_CIHAZ.md
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const BURASI = path.dirname(fileURLToPath(import.meta.url));
export const VARSAYILAN_BASLIK = path.resolve(BURASI, '..', 'include', 'ota_public_key.h');

// include/ota_imza.h OTA_IMZA_YER_TUTUCU_XOR tablosunun (0xA5 ile XOR'lanmis) acik hali: AYNI 32 bayt (ASCII metin; gecerli bir Ed25519
// anahtari degildir). Firmware'de acik metin YALNIZ ota_public_key.h yer tutucuysa bulunur (ikili taramasi yanlis alarm vermez).
export const YER_TUTUCU = Buffer.from('OTA-PUBLIC-KEY-NOT-SET-REPLACE!!', 'ascii');
const SPKI_ONEK = Buffer.from('302a300506032b6570032100', 'hex');

// ---- Ed25519 nokta denetimi (BigInt; cihazdaki ota_ed25519.h anahtarGecerliMi ile ayni kurallar) ---------------------------------
const P = (1n << 255n) - 19n;
const mod = (a) => ((a % P) + P) % P;
function us(taban, ust) {
  let sonuc = 1n;
  let t = mod(taban);
  let e = ust;
  while (e > 0n) {
    if (e & 1n) sonuc = mod(sonuc * t);
    t = mod(t * t);
    e >>= 1n;
  }
  return sonuc;
}
const ters = (a) => us(a, P - 2n);
const D = mod(-121665n * ters(121666n));
const KOK_EKSI_BIR = us(2n, (P - 1n) / 4n);

function noktaCoz(bayt) {
  let y = 0n;
  for (let i = 31; i >= 0; i -= 1) y = (y << 8n) | BigInt(bayt[i]);
  const isaret = (y >> 255n) & 1n;
  y &= (1n << 255n) - 1n;
  if (y >= P) return null;  // kanonik degil
  const y2 = mod(y * y);
  const u = mod(y2 - 1n);
  const v = mod(D * y2 + 1n);
  const v3 = mod(v * v * v);
  const v7 = mod(v3 * v3 * v);
  let x = mod(u * v3 * us(mod(u * v7), (P - 5n) / 8n));
  const vx2 = mod(v * x * x);
  if (vx2 !== u) {
    if (vx2 === mod(-u)) x = mod(x * KOK_EKSI_BIR);
    else return null;  // nokta egride degil
  }
  if (x === 0n && isaret === 1n) return null;
  if ((x & 1n) !== isaret) x = mod(-x);
  return { x, y };
}
function noktaTopla(a, b) {
  const t = mod(D * a.x * b.x * a.y * b.y);
  return {
    x: mod((a.x * b.y + a.y * b.x) * ters(mod(1n + t))),
    y: mod((a.y * b.y + a.x * b.x) * ters(mod(1n - t))),
  };
}

// { ok, neden }: 32 bayt, yer tutucu degil, tum-sifir degil, egride kanonik nokta, KUCUK MERTEBELI degil ([8]A != O)
export function anahtarDogrula(bayt) {
  if (!Buffer.isBuffer(bayt) || bayt.length !== 32) return { ok: false, neden: 'anahtar 32 bayt olmali' };
  if (bayt.equals(YER_TUTUCU)) return { ok: false, neden: 'bu YER TUTUCU metnidir, gercek anahtar degil' };
  if (bayt.every((b) => b === 0)) return { ok: false, neden: 'tum-sifir anahtar gecersiz' };
  const nokta = noktaCoz(bayt);
  if (!nokta) return { ok: false, neden: 'gecerli bir Ed25519 genel anahtari degil (nokta egride degil ya da kodlama kanonik degil)' };
  let q = nokta;
  for (let i = 0; i < 3; i += 1) q = noktaTopla(q, q);
  if (q.x === 0n && q.y === 1n) return { ok: false, neden: 'kucuk mertebeli (zayif) nokta: imza sahtekarligina acik, kullanilamaz' };
  return { ok: true, neden: '' };
}

// ---- Girdi cozumleme ---------------------------------------------------------------------------------------------------------
export function anahtarCozumle(girdi) {
  let metin = String(girdi ?? '').trim();
  if (!metin) throw new Error('genel anahtar verilmedi');
  if (metin.includes('PRIVATE KEY')) {
    throw new Error('OZEL ANAHTAR verildi. Bu betik yalniz GENEL anahtar kabul eder; ozel anahtari depoya/komuta yazmayin, imza aracindan GENEL anahtari alin.');
  }
  if (!metin.includes('-----BEGIN') && metin.length < 1024 && fs.existsSync(metin) && fs.statSync(metin).isFile()) {
    metin = fs.readFileSync(metin, 'utf8').trim();
    if (metin.includes('PRIVATE KEY')) {
      throw new Error('Dosya OZEL ANAHTAR iceriyor; yalniz GENEL anahtar kabul edilir.');
    }
  }
  if (metin.includes('-----BEGIN PUBLIC KEY-----')) {
    const jwk = crypto.createPublicKey(metin).export({ format: 'jwk' });
    if (jwk.kty !== 'OKP' || jwk.crv !== 'Ed25519') throw new Error('PEM bir Ed25519 genel anahtari degil');
    return Buffer.from(jwk.x, 'base64url');
  }
  const sade = metin.replace(/\s+/g, '');
  if (/^[0-9a-fA-F]{64}$/.test(sade)) return Buffer.from(sade, 'hex');
  if (/^[A-Za-z0-9+/_-]+={0,2}$/.test(sade)) {
    const b = Buffer.from(sade.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
    if (b.length === 32) return b;
    if (b.length === 44 && b.subarray(0, 12).equals(SPKI_ONEK)) return b.subarray(12);
  }
  throw new Error('genel anahtar taninmadi: 64 hane hex, base64 (32 bayt), SPKI PEM metni ya da PEM dosya yolu verin');
}

// cihazin acilista yazdigi parmak izi: SHA-256(anahtar) ilk 8 bayt, kucuk harf hex
export function parmakIzi(bayt) {
  return crypto.createHash('sha256').update(bayt).digest().subarray(0, 8).toString('hex');
}

// ---- Baslik sablonu (teslim edilen yer tutuculu dosya ile BAYT-BAYT ayni olmali; test denetler) ----------------------------------
function dizi(bayt) {
  const satirlar = [];
  for (let i = 0; i < 32; i += 16) {
    satirlar.push(`  ${Array.from(bayt.subarray(i, i + 16), (b) => `0x${b.toString(16).padStart(2, '0')}`).join(', ')},`);
  }
  return satirlar;
}

export function baslikUret(bayt, eol = '\n') {
  const yerTutucu = bayt === null;
  const anahtar = yerTutucu ? YER_TUTUCU : bayt;
  const durum = yerTutucu
    ? '//  DURUM: YER TUTUCU  (gercek anahtar henuz yerlestirilmedi)'
    : `//  DURUM: GERCEK ANAHTAR  (parmak izi ${parmakIzi(anahtar)}; cihaz acilista seriye ayni parmak izini yazar)`;
  const aciklama = yerTutucu
    ? '  // ASCII "OTA-PUBLIC-KEY-NOT-SET-REPLACE!!" (gecerli bir anahtar DEGILDIR)'
    : '  // Ed25519 genel anahtari (sir degildir; ozel anahtar depo disindadir)';
  const satirlar = [
    '#ifndef OTA_PUBLIC_KEY_H',
    '#define OTA_PUBLIC_KEY_H',
    '',
    '#include <stdint.h>',
    '',
    '// =====================================================================================================================',
    '//  OTA IMZA GENEL ANAHTARI (Ed25519, 32 bayt)',
    '//',
    durum,
    '//',
    '//  Bu dosyada YALNIZ GENEL (public) anahtar bulunur; sir degildir. OZEL (private) ANAHTAR ASLA bu depoya, bu dosyaya, bir gunluge',
    '//  ya da bir teste yazilmaz: imzalayan makinede, depo DISINDA saklanir (docs/OTA_IMZA_CIHAZ.md).',
    '//',
    '//  ANAHTAR URETINCE DEGISTIR (yer tutucu ile uretim derlemesi YAPMAYIN):',
    '//    1) Imza anahtar ciftini uretin (ozel anahtar depo disinda kalir; yalniz genel anahtar kopyalanir).',
    '//    2) Genel anahtari bu dosyaya yazin - elle duzenlemek yerine:',
    '//         node cihaz_kontrol/tools/ota_anahtar.mjs yaz <genel_anahtar: 64 hane hex | base64 | SPKI PEM dosyasi>',
    '//       (bu betik dosyayi bastan yazar ve parmak izini gosterir)',
    '//    3) Derleyin; yayinlamadan once ikilide yer tutucu KALMADIGINI ve dogru anahtarin gomuldugunu denetleyin:',
    '//         node cihaz_kontrol/tools/ota_anahtar.mjs kontrol <firmware.bin> <genel_anahtar>',
    '//    4) Kartin seri cikisinda "OTA imza anahtari: HAZIR (parmak izi ...)" satirini ve parmak izinin betigin gosterdigiyle ayni',
    '//       oldugunu dogrulayin.',
    '//    Yayin derlemesinde SKP_OTA_ANAHTAR_ZORUNLU=1 ortam degiskeni yer tutuculu derlemeyi DERLEME asamasinda durdurur',
    '//    (tools/ota_anahtar_kontrol_pio.py; yer tutucu varken bu degisken yoksa yalniz UYARI basar).',
    '//',
    '//  YER TUTUCU ILE NE OLUR: cihaz yer tutucuyu CALISMA ZAMANINDA tanir ve hicbir paketi KURMAZ ("imza anahtari yerlestirilmemis").',
    '//  Yani yanlislikla yer tutuculu bir surum yayinlanirsa o cihazlar bir daha OTA ile guncellenemez (USB gerekir). Bu yuzden',
    '//  yayin oncesi 3. adim ZORUNLUDUR.',
    '// =====================================================================================================================',
    'inline constexpr uint8_t OTA_IMZA_GENEL_ANAHTAR[32] = {',
    aciklama,
    ...dizi(anahtar),
    '};',
    '',
    '#endif',
    '',
  ];
  return satirlar.join(eol);
}

function eolBul(dosya) {
  try {
    return fs.readFileSync(dosya, 'utf8').includes('\r\n') ? '\r\n' : '\n';
  } catch {
    return '\n';
  }
}

// ---- Yayin oncesi ikili denetimi ---------------------------------------------------------------------------------------------------
function say(tampon, desen) {
  let n = 0;
  let konum = tampon.indexOf(desen);
  while (konum >= 0) {
    n += 1;
    konum = tampon.indexOf(desen, konum + 1);
  }
  return n;
}

// { kod, mesaj }: 0 tamam | 2 yer tutucu iceriyor | 3 beklenen anahtar yok
export function ikiliKontrol(ikili, beklenenAnahtar = null) {
  if (say(ikili, YER_TUTUCU) > 0) {
    return { kod: 2, mesaj: 'YER TUTUCU ANAHTAR IKILIDE: bu firmware yayinlanamaz (cihazlar OTA ile bir daha guncellenemez). ota_anahtar.mjs yaz ile gercek anahtari yazip yeniden derleyin.' };
  }
  if (beklenenAnahtar) {
    const n = say(ikili, beklenenAnahtar);
    if (n === 0) {
      return { kod: 3, mesaj: `beklenen anahtar (parmak izi ${parmakIzi(beklenenAnahtar)}) ikilide BULUNAMADI: farkli bir anahtar gomulu ya da baslik derlemeye girmemis.` };
    }
    return { kod: 0, mesaj: `TAMAM: yer tutucu yok; beklenen anahtar (parmak izi ${parmakIzi(beklenenAnahtar)}) ikilide ${n} kez bulundu.` };
  }
  return { kod: 0, mesaj: 'TAMAM: ikilide yer tutucu yok. (Hangi anahtarin gomulu oldugunu da denetlemek icin <genel_anahtar> verin.)' };
}

// ---- Komut satiri -------------------------------------------------------------------------------------------------------------------
function kullanim() {
  console.log([
    'Kullanim:',
    '  node cihaz_kontrol/tools/ota_anahtar.mjs yaz <genel_anahtar> [--cikti <dosya>]',
    '  node cihaz_kontrol/tools/ota_anahtar.mjs yer-tutucu [--cikti <dosya>]',
    '  node cihaz_kontrol/tools/ota_anahtar.mjs parmak-izi <genel_anahtar>',
    '  node cihaz_kontrol/tools/ota_anahtar.mjs kontrol <firmware.bin> [<genel_anahtar>]',
    '<genel_anahtar>: 64 hane hex | base64 (32 bayt) | SPKI PEM metni | SPKI PEM dosya yolu.  OZEL ANAHTAR VERMEYIN.',
  ].join('\n'));
}

function ciktiYolu(argumanlar) {
  const i = argumanlar.indexOf('--cikti');
  return i >= 0 && argumanlar[i + 1] ? path.resolve(argumanlar[i + 1]) : VARSAYILAN_BASLIK;
}

export function calistir(argumanlar) {
  const [komut, ...geri] = argumanlar;
  try {
    if (komut === 'yaz') {
      const bayt = anahtarCozumle(geri[0]);
      const sonuc = anahtarDogrula(bayt);
      if (!sonuc.ok) {
        console.error(`HATA: ${sonuc.neden}`);
        return 1;
      }
      const hedef = ciktiYolu(geri);
      fs.writeFileSync(hedef, baslikUret(bayt, eolBul(hedef)));
      console.log(`Yazildi: ${hedef}`);
      console.log(`Genel anahtar : ${bayt.toString('hex')}`);
      console.log(`Parmak izi    : ${parmakIzi(bayt)}   (cihaz acilista "OTA imza anahtari: HAZIR (...); parmak izi ${parmakIzi(bayt)}" yazmali)`);
      console.log('Sonraki adim  : firmware derleyin, sonra: node cihaz_kontrol/tools/ota_anahtar.mjs kontrol <firmware.bin> <genel_anahtar>');
      return 0;
    }
    if (komut === 'yer-tutucu') {
      const hedef = ciktiYolu(geri);
      fs.writeFileSync(hedef, baslikUret(null, eolBul(hedef)));
      console.log(`YER TUTUCU yazildi: ${hedef}  (UYARI: bu haliyle uretim derlemesi YAPILMAZ)`);
      return 0;
    }
    if (komut === 'parmak-izi') {
      const bayt = anahtarCozumle(geri[0]);
      console.log(parmakIzi(bayt));
      return 0;
    }
    if (komut === 'kontrol') {
      if (!geri[0]) {
        kullanim();
        return 1;
      }
      const ikili = fs.readFileSync(geri[0]);
      let anahtar = null;
      if (geri[1]) {
        anahtar = anahtarCozumle(geri[1]);
        const sonuc = anahtarDogrula(anahtar);
        if (!sonuc.ok) {
          console.error(`HATA: verilen anahtar gecersiz: ${sonuc.neden}`);
          return 1;
        }
      }
      const sonuc = ikiliKontrol(ikili, anahtar);
      (sonuc.kod === 0 ? console.log : console.error)(sonuc.mesaj);
      return sonuc.kod;
    }
    kullanim();
    return komut ? 1 : 0;
  } catch (hata) {
    console.error(`HATA: ${hata.message}`);
    return 1;
  }
}

function dogrudanCalistirildiMi() {
  if (!process.argv[1]) return false;
  const a = path.resolve(fileURLToPath(import.meta.url));
  const b = path.resolve(process.argv[1]);
  return process.platform === 'win32' ? a.toLowerCase() === b.toLowerCase() : a === b;
}

if (dogrudanCalistirildiMi()) {
  process.exitCode = calistir(process.argv.slice(2));
}
