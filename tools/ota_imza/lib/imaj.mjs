// Firmware imaji (firmware.bin) okuma ve ESP32 imaj basligi denetimi. Yalniz okur; hicbir sey yazmaz.
//
// ESP32 uygulama imaji basligi (esp_image_header_t, 24 bayt):
//   bayt 0      magic = 0xE9
//   bayt 1      segment_count (1..16)
//   bayt 12-13  chip_id (little-endian): ESP32 = 0x0000, ESP32-S2 = 0x0002, ESP32-C3 = 0x0005, ESP32-S3 = 0x0009 ...
//   bayt 23     hash_appended (1: imajin sonuna SHA-256 eklenmis)
// Gercek surum arsivi (cihaz_kontrol/firmware_releases) ile dogrulandi: C3 imajlari 0x0005, WROOM-32E imaji 0x0000.

import crypto from 'node:crypto';
import fs from 'node:fs';
import { HEDEFLER, MAKS_IMAJ_BAYT } from './bicim.mjs';
import { IslemHatasi, guvenliMetin } from './hata.mjs';

export const BASLIK_BAYT = 24;

const CIP_ADLARI = Object.freeze({
  0x0000: 'ESP32',
  0x0002: 'ESP32-S2',
  0x0005: 'ESP32-C3',
  0x0009: 'ESP32-S3',
  0x000c: 'ESP32-C2',
  0x000d: 'ESP32-C6',
  0x0010: 'ESP32-H2',
});

/**
 * Imaji okur: boyut, SHA-256 (kucuk harf hex) ve ham baytlar. Dosya duzenli degilse, bossa ya da MAKS_IMAJ_BAYT'tan buyukse reddeder.
 * @param {string} yol
 * @returns {{ boyut: number, sha256: string, veri: Buffer }}
 */
export function imajOku(yol) {
  let bilgi;
  try {
    bilgi = fs.statSync(yol);
  } catch (hata) {
    throw new IslemHatasi(`firmware dosyasi okunamadi: ${guvenliMetin(yol)} (${hata.code ?? hata.message})`);
  }
  if (!bilgi.isFile()) {
    throw new IslemHatasi(`firmware yolu bir dosya degil: ${guvenliMetin(yol)}`);
  }
  if (bilgi.size === 0) {
    throw new IslemHatasi(`firmware dosyasi bos: ${guvenliMetin(yol)}`);
  }
  if (bilgi.size > MAKS_IMAJ_BAYT) {
    throw new IslemHatasi(`firmware dosyasi cok buyuk (${bilgi.size} bayt; en fazla ${MAKS_IMAJ_BAYT})`);
  }
  let veri;
  try {
    veri = fs.readFileSync(yol);
  } catch (hata) {
    throw new IslemHatasi(`firmware dosyasi okunamadi: ${guvenliMetin(yol)} (${hata.code ?? hata.message})`);
  }
  if (veri.length !== bilgi.size) {
    throw new IslemHatasi('firmware dosyasi okunurken degisti; islemi tekrarlayin');
  }
  return { boyut: veri.length, sha256: crypto.createHash('sha256').update(veri).digest('hex'), veri };
}

/** Imaj basligini cozer. Gecerli bir ESP32 uygulama imaji degilse `gecerli: false` ve nedeni doner. */
export function imajBasliginiCoz(veri) {
  if (veri.length < BASLIK_BAYT) {
    return { gecerli: false, neden: `imaj ${BASLIK_BAYT} bayttan kisa; ESP32 uygulama imaji degil` };
  }
  if (veri[0] !== 0xe9) {
    return {
      gecerli: false,
      neden: `ESP32 imaj taniticisi (0xE9) yok (ilk bayt 0x${veri[0].toString(16).padStart(2, '0')}); firmware.bin yerine baska bir dosya (ELF, zip ...) verilmis olabilir`,
    };
  }
  const segmentSayisi = veri[1];
  if (segmentSayisi < 1 || segmentSayisi > 16) {
    return { gecerli: false, neden: `imaj basligindaki segment sayisi gecersiz (${segmentSayisi}; 1-16 beklenir)` };
  }
  const cipKimligi = veri.readUInt16LE(12);
  return {
    gecerli: true,
    segmentSayisi,
    cipKimligi,
    cipAdi: CIP_ADLARI[cipKimligi] ?? `bilinmeyen cip (0x${cipKimligi.toString(16).padStart(4, '0')})`,
  };
}

/**
 * Imajin derlendigi cip, imzalanan hedefle uyusuyor mu? (C3 imaji yanlislikla WROOM olarak imzalanmasin.)
 * @returns {{ ok: boolean, ayrinti: string }}
 */
export function hedefUyumunuDenetle(hedef, veri) {
  const baslik = imajBasliginiCoz(veri);
  if (!baslik.gecerli) {
    return { ok: false, ayrinti: baslik.neden };
  }
  const beklenen = HEDEFLER[hedef];
  if (baslik.cipKimligi !== beklenen.cipKimligi) {
    return {
      ok: false,
      ayrinti: `imaj ${baslik.cipAdi} icin derlenmis; hedef ${hedef} (${beklenen.ad}) ile UYUSMUYOR (yanlis ortamin firmware.bin'i olabilir)`,
    };
  }
  return { ok: true, ayrinti: `${baslik.cipAdi} imaji, ${baslik.segmentSayisi} segment` };
}

/**
 * Surum metni imajin icinde (NUL sonlu dize olarak) geciyor mu? Firmware'deki OTA_VERSION_* sabiti derlenmis imajda boyle durur;
 * bulunamazsa surum numarasi artirilmadan derlenmis / yanlis bin verilmis olabilir. Sezgiseldir: yalniz UYARI uretmek icin kullanilir.
 */
export function imajdaSurumVarMi(veri, surum) {
  return veri.includes(Buffer.concat([Buffer.from(surum, 'ascii'), Buffer.from([0])]));
}
