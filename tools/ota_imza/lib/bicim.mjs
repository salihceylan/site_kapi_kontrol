// OTA imza bicimi KAPI-OTA-IMZA-V1: imzalanan mesajin ve .sig dosyasinin TEK tanimi (referans uygulama).
//
// Firmware (C++) ve sunucu (Node) bu kurallari bagimsiz uygular; ortak dogruluk kaynagi: README.md ve test/vektorler.json.
// Saf modul: dosya sistemi / ag yok, yalniz dogrulama ve bicimlendirme.
//
// Imzalanan sey firmware.bin'in kendisi DEGIL, onu baglayan kisa bir mesajdir (cihaz 1,8 MB'yi RAM'e alamaz; zaten akisli SHA-256 hesaplar):
//
//   KAPI-OTA-IMZA-V1<LF>
//   target=<hedef><LF>
//   version=<surum><LF>
//   size=<bayt sayisi><LF>
//   sha256=<64 hane kucuk harf hex><LF>
//   rollback_max=<surum><LF>      <- YALNIZ imzali, sinirli SURUM DUSURME yetkisinde (imzala --rollback-max); yoksa bu satir HIC olmaz
//
// Her alan sabit sirada, ASCII ve LF (0x0A) ile biter; CR, bosluk ve ek satir YOKTUR. Alanlar asagidaki desenlerle kisitlandigi icin
// satir icine satir/alan sokmak (injection) mumkun degildir. Cihaz ve sunucu ayni bicimi uygular (tek etiket: KAPI-OTA-IMZA-V1).

import { IslemHatasi, guvenliMetin } from './hata.mjs';

export const FORMAT = 'KAPI-OTA-IMZA-V1';
export const ALGORITMA = 'Ed25519';

/** Imzalanabilecek en buyuk imaj (ESP32 flash tavani). */
export const MAKS_IMAJ_BAYT = 16 * 1024 * 1024;
/** .sig dosyasi icin makul ust sinir (gercek dosya ~450 bayttir). */
export const MAKS_SIG_BAYT = 4096;

/**
 * Bilinen donanim hedefleri. `cipKimligi`: ESP32 uygulama imajinin basligindaki chip_id (bayt 12-13, little-endian):
 * ESP32 = 0x0000, ESP32-C3 = 0x0005. Hedefler asla karismaz (AGENTS.md kural 4): yeni donanim hedefi buraya eklenir.
 */
export const HEDEFLER = Object.freeze({
  'esp32-c3': Object.freeze({ cipKimligi: 0x0005, ad: 'ESP32-C3' }),
  'esp32-wroom': Object.freeze({ cipKimligi: 0x0000, ad: 'ESP32 (WROOM)' }),
});

// Surum: X.Y.Z (ya da X.Y.Z.W), her parca 0-9999, basta sifir YOK ("4.03.0" ile "4.3.0" ayni surumun iki yazimi olurdu).
const SURUM_DESENI = /^(?:0|[1-9][0-9]{0,3})(?:\.(?:0|[1-9][0-9]{0,3})){2,3}$/;
const SHA256_DESENI = /^[0-9a-f]{64}$/;
const IMZA_DESENI = /^[0-9a-f]{128}$/;
const ANAHTAR_KIMLIGI_DESENI = /^[0-9a-f]{16}$/;

export function hedefDenetle(hedef) {
  if (typeof hedef !== 'string' || !Object.hasOwn(HEDEFLER, hedef)) {
    throw new IslemHatasi(`hedef gecersiz: ${guvenliMetin(hedef)} (izinli: ${Object.keys(HEDEFLER).join(', ')})`);
  }
  return hedef;
}

export function surumDenetle(surum, ad = 'surum') {
  if (typeof surum !== 'string' || !SURUM_DESENI.test(surum)) {
    throw new IslemHatasi(`${ad} gecersiz: ${guvenliMetin(surum)} (beklenen bicim X.Y.Z, ornek 4.3.4; basta sifir olmaz)`);
  }
  return surum;
}

/** Iki GECERLI surumu sayisal karsilastirir: -1 (a < b), 0, 1 (a > b). Eksik 4. parca 0 sayilir. */
export function surumKarsilastir(a, b) {
  const parcalar = (surum) => {
    const dizi = surumDenetle(surum).split('.').map(Number);
    while (dizi.length < 4) {
      dizi.push(0);
    }
    return dizi;
  };
  const x = parcalar(a);
  const y = parcalar(b);
  for (let i = 0; i < 4; i += 1) {
    if (x[i] !== y[i]) {
      return x[i] < y[i] ? -1 : 1;
    }
  }
  return 0;
}

export function boyutDenetle(boyut) {
  if (!Number.isSafeInteger(boyut) || boyut < 1 || boyut > MAKS_IMAJ_BAYT) {
    throw new IslemHatasi(`boyut gecersiz: ${guvenliMetin(boyut)} (1 ile ${MAKS_IMAJ_BAYT} bayt arasinda tam sayi olmali)`);
  }
  return boyut;
}

export function sha256Denetle(sha256) {
  if (typeof sha256 !== 'string' || !SHA256_DESENI.test(sha256)) {
    throw new IslemHatasi(`sha256 gecersiz: ${guvenliMetin(sha256)} (64 haneli KUCUK harfli hex olmali)`);
  }
  return sha256;
}

export function anahtarKimligiDenetle(kimlik) {
  if (typeof kimlik !== 'string' || !ANAHTAR_KIMLIGI_DESENI.test(kimlik)) {
    throw new IslemHatasi(`anahtar kimligi gecersiz: ${guvenliMetin(kimlik)} (16 haneli kucuk harfli hex olmali)`);
  }
  return kimlik;
}

export function imzaHexDenetle(imza) {
  if (typeof imza !== 'string' || !IMZA_DESENI.test(imza)) {
    throw new IslemHatasi('imza gecersiz: 128 haneli kucuk harfli hex (Ed25519, 64 bayt) olmali');
  }
  return imza;
}

/**
 * Ed25519'un imzaladigi mesaj (bayt dizisi). Alanlar once denetlenir; gecersizse IslemHatasi.
 * `rollbackMax`: verilirse (yalniz imzali surum dusurme yetkisi) mesajin SON satiri `rollback_max=<surum>` olur; verilmezse satir HIC yoktur.
 * @param {{ hedef: string, surum: string, boyut: number, sha256: string, rollbackMax?: string }} alanlar
 * @returns {Buffer}
 */
export function imzaMesajiKur({ hedef, surum, boyut, sha256, rollbackMax }) {
  hedefDenetle(hedef);
  surumDenetle(surum);
  boyutDenetle(boyut);
  sha256Denetle(sha256);
  let metin = `${FORMAT}\ntarget=${hedef}\nversion=${surum}\nsize=${boyut}\nsha256=${sha256}\n`;
  if (rollbackMax !== undefined) {
    metin += `rollback_max=${surumDenetle(rollbackMax, 'rollback_max')}\n`;
  }
  return Buffer.from(metin, 'ascii');
}

/**
 * <firmware.bin>.sig dosyasinin nesnesi (alan sirasi sabit). `key_id`: genel anahtarin SHA-256'sinin ilk 8 baytinin hex'i (ipucu;
 * imzalanan mesajin parcasi degildir, dogrulayici dogru genel anahtari secsin diye vardir).
 */
export function imzaDosyasiKur({ hedef, surum, boyut, sha256, anahtarKimligi, imzaHex, rollbackMax }) {
  hedefDenetle(hedef);
  surumDenetle(surum);
  boyutDenetle(boyut);
  sha256Denetle(sha256);
  anahtarKimligiDenetle(anahtarKimligi);
  imzaHexDenetle(imzaHex);
  return {
    format: FORMAT,
    algorithm: ALGORITMA,
    target: hedef,
    version: surum,
    size: boyut,
    sha256,
    // YALNIZ imzali surum dusurme yetkisinde (imzalanan mesajin son satiri); yoksa alan HIC yazilmaz
    ...(rollbackMax === undefined ? {} : { rollback_max: surumDenetle(rollbackMax, 'rollback_max') }),
    key_id: anahtarKimligi,
    signature: imzaHex,
  };
}

/** .sig nesnesini dosya metnine cevirir (2 bosluk girinti, sonda LF; Ed25519 deterministik oldugu icin cikti tekrarlanabilir). */
export function imzaDosyasiMetni(sig) {
  return `${JSON.stringify(sig, null, 2)}\n`;
}

/**
 * .sig dosya metnini sikica ayristirir. Bilinmeyen EK alanlar yok sayilir (ileriye uyum); bilinen alanlarin her biri denetlenir.
 * @param {string} metin
 * @returns {{ format: string, algorithm: string, target: string, version: string, size: number, sha256: string, rollback_max?: string, key_id: string, signature: string }}
 */
export function imzaDosyasiAyristir(metin) {
  if (typeof metin !== 'string' || metin.length === 0) {
    throw new IslemHatasi('imza dosyasi bos');
  }
  if (metin.length > MAKS_SIG_BAYT) {
    throw new IslemHatasi(`imza dosyasi cok buyuk (en fazla ${MAKS_SIG_BAYT} karakter)`);
  }
  let veri;
  try {
    veri = JSON.parse(metin.charCodeAt(0) === 0xfeff ? metin.slice(1) : metin); // Windows araclarinin ekledigi BOM'u tolere et
  } catch {
    throw new IslemHatasi('imza dosyasi gecerli JSON degil');
  }
  if (veri === null || typeof veri !== 'object' || Array.isArray(veri)) {
    throw new IslemHatasi('imza dosyasi bir JSON nesnesi olmali');
  }
  if (veri.format !== FORMAT) {
    throw new IslemHatasi(`imza bicimi desteklenmiyor: ${guvenliMetin(veri.format)} (beklenen ${FORMAT})`);
  }
  if (veri.algorithm !== ALGORITMA) {
    throw new IslemHatasi(`imza algoritmasi desteklenmiyor: ${guvenliMetin(veri.algorithm)} (beklenen ${ALGORITMA})`);
  }
  // Alan hatalari hangi alanin bozuk oldugunu soylesin diye tek tek denetlenir.
  const alanlar = [
    ['target', () => hedefDenetle(veri.target)],
    ['version', () => surumDenetle(veri.version)],
    ['size', () => boyutDenetle(veri.size)],
    ['sha256', () => sha256Denetle(veri.sha256)],
    // istege bagli: yalniz imzali surum dusurme yetkisinde bulunur. Varsa gecerli bir surum olmali (null / bos dize / sayi GECERSIZdir).
    ...(veri.rollback_max === undefined ? [] : [['rollback_max', () => surumDenetle(veri.rollback_max, 'rollback_max')]]),
    ['key_id', () => anahtarKimligiDenetle(veri.key_id)],
    ['signature', () => imzaHexDenetle(veri.signature)],
  ];
  for (const [ad, denetle] of alanlar) {
    try {
      denetle();
    } catch (hata) {
      throw new IslemHatasi(`imza dosyasi, "${ad}" alani: ${hata.message}`);
    }
  }
  return {
    format: veri.format,
    algorithm: veri.algorithm,
    target: veri.target,
    version: veri.version,
    size: veri.size,
    sha256: veri.sha256,
    ...(veri.rollback_max === undefined ? {} : { rollback_max: veri.rollback_max }),
    key_id: veri.key_id,
    signature: veri.signature,
  };
}
