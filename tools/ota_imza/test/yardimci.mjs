// Test yardimcilari (test dosyasi degildir; testler bunu ice aktarir).
//
// OZEL ANAHTAR kurali: testler anahtari CALISMA ANINDA uretir (gecici klasorde, testten sonra silinir). Bu klasorde sabit
// bir ozel anahtar, PEM ya da tohum YOKTUR; vektorler.json yalniz acik veri (genel anahtar, mesaj, imza) icerir.

import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { anahtarCiftiUret, genelBilgi, ozelAnahtariYaz } from '../lib/anahtar.mjs';
import { main } from '../ota_imza.mjs';

const burasi = path.dirname(fileURLToPath(import.meta.url));
export const CLI = path.resolve(burasi, '..', 'ota_imza.mjs');
export const ARAC_KLASORU = path.resolve(burasi, '..');
export const DEPO_KOKU = path.resolve(burasi, '..', '..', '..');

/** Gecici klasor (depo DISINDA: os.tmpdir()). */
export function geciciDizin(oneki = 'ota-imza-test-') {
  return fs.mkdtempSync(path.join(os.tmpdir(), oneki));
}

export function temizle(dizin) {
  fs.rmSync(dizin, { recursive: true, force: true });
}

/**
 * Gecerli ESP32 imaj basligina sahip sahte firmware. `cip`: 0x0005 (C3) ya da 0x0000 (ESP32/WROOM).
 * `surumMetni`: verilirse govdeye NUL sonlu dize olarak eklenir (gercek imajdaki OTA_VERSION_* gibi).
 */
export function sahteImaj({ cip = 0x0005, boyut = 20000, surumMetni = '4.3.4' } = {}) {
  const govde = crypto.randomBytes(boyut);
  const imaj = surumMetni === undefined ? govde : Buffer.concat([govde, Buffer.from(`${surumMetni}\0`, 'ascii')]);
  imaj[0] = 0xe9;
  imaj[1] = 5;
  imaj.writeUInt16LE(cip, 12);
  imaj[23] = 1;
  return imaj;
}

/** vektorler.json'daki sentetik imaj formulu (README'de belgelidir). */
export function sentetikImaj(boyut, cipKimligi) {
  const imaj = Buffer.alloc(boyut);
  for (let i = 0; i < boyut; i += 1) {
    imaj[i] = (i * 31 + 7) & 0xff;
  }
  imaj[0] = 0xe9;
  imaj[1] = 0x05;
  imaj[12] = cipKimligi & 0xff;
  imaj[13] = cipKimligi >> 8;
  return imaj;
}

/** Calisma aninda anahtar cifti uretip `dizin` icine yazar (kutuphane ile; hizli). */
export function anahtarHazirla(dizin, { ad = 'ozel.pem', parola } = {}) {
  const { ozel } = anahtarCiftiUret();
  const yol = path.join(dizin, ad);
  ozelAnahtariYaz(yol, ozel, parola);
  const bilgi = genelBilgi(crypto.createPublicKey(ozel));
  const genelYol = path.join(dizin, `${ad}.genel.pem`);
  fs.writeFileSync(genelYol, bilgi.pem);
  return { yol, ozel, genelYol, ...bilgi };
}

/** Ozel anahtarin 32 baytlik tohumu (yalniz "sizinti yok" testlerinde, ciktilarda aramak icin). */
export function ozelTohum(ozel) {
  return Buffer.from(ozel.export({ type: 'pkcs8', format: 'der' }).subarray(16));
}

/** CLI'yi ayni surecte calistirir; cikti ve cikis kodunu yakalar. `env` yalniz OTA_IMZA_* degiskenlerini tasir (ana ortamdan yalitilmis). */
export function calistir(argv, { env = {}, cwd } = {}) {
  let out = '';
  let err = '';
  const kod = main(argv, {
    out: (metin) => {
      out += metin;
    },
    err: (metin) => {
      err += metin;
    },
    env,
    cwd: cwd ?? process.cwd(),
  });
  return { kod, out, err };
}

/** CLI'yi GERCEK bir surec olarak calistirir (cikis kodu, stdout/stderr). Ana ortamdaki OTA_IMZA_* degiskenleri silinir. */
export function surecOlarakCalistir(argv, { env = {}, cwd } = {}) {
  const temiz = Object.fromEntries(Object.entries(process.env).filter(([ad]) => !ad.startsWith('OTA_IMZA_')));
  const sonuc = spawnSync(process.execPath, [CLI, ...argv], { encoding: 'utf8', env: { ...temiz, ...env }, cwd });
  return { kod: sonuc.status, out: sonuc.stdout, err: sonuc.stderr };
}

/** Bir klasoru "git deposu" gibi gosterir (isaret klasoru olusturur); depo-ici koruma testleri icin. */
export function sahteDepoYap(dizin) {
  fs.mkdirSync(path.join(dizin, '.git'), { recursive: true });
}
