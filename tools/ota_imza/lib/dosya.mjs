// Kucuk girdi dosyalarini (anahtar, imza, manifest) BOYUT SINIRI asilmadan okur: yanlis bir dosya (ornegin cok buyuk bir imaj) verilirse
// bellege alinmadan reddedilir.

import fs from 'node:fs';
import { IslemHatasi, guvenliMetin } from './hata.mjs';

export const MAKS_ANAHTAR_DOSYASI = 16 * 1024;
export const MAKS_SIG_DOSYASI = 16 * 1024;
export const MAKS_MANIFEST_DOSYASI = 1024 * 1024;

/**
 * Duzenli bir dosyayi UTF-8 metin olarak okur.
 * @param {string} yol
 * @param {number} azamiBayt dosya bundan buyukse okunmadan reddedilir
 * @param {string} ad hata mesajlarinda gecen ad (ornek "imza dosyasi")
 * @returns {{ metin: string, bilgi: fs.Stats }}
 */
export function sinirliMetinOku(yol, azamiBayt, ad) {
  let bilgi;
  try {
    bilgi = fs.statSync(yol);
  } catch (hata) {
    throw new IslemHatasi(`${ad} okunamadi: ${guvenliMetin(yol)} (${hata.code ?? hata.message})`);
  }
  if (!bilgi.isFile()) {
    throw new IslemHatasi(`${ad} yolu bir dosya degil: ${guvenliMetin(yol)}`);
  }
  if (bilgi.size > azamiBayt) {
    throw new IslemHatasi(`${ad} beklenenden cok buyuk (${bilgi.size} bayt; en fazla ${azamiBayt}); yanlis dosya verilmis olabilir`);
  }
  try {
    return { metin: fs.readFileSync(yol, 'utf8'), bilgi };
  } catch (hata) {
    throw new IslemHatasi(`${ad} okunamadi: ${guvenliMetin(yol)} (${hata.code ?? hata.message})`);
  }
}
