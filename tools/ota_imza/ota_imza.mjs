#!/usr/bin/env node
// OTA imza araci: firmware.bin icin Ed25519 imza zinciri (anahtar uret -> imzala -> dogrula). Bagimliligi YOKTUR (yalniz Node >= 20 yerlesik crypto).
// Bicim ve guvenlik notlari: tools/ota_imza/README.md
//
//   node tools/ota_imza/ota_imza.mjs anahtar-uret --ozel <depo disi yol> [--genel <dosya>]
//   node tools/ota_imza/ota_imza.mjs genel-anahtar --ozel <yol>
//   node tools/ota_imza/ota_imza.mjs imzala <firmware.bin> --hedef esp32-c3 --surum 4.3.4 [--rollback-max <surum>] [--ozel <yol>] [--cikti <yol>]
//   node tools/ota_imza/ota_imza.mjs dogrula <firmware.bin> (--genel <dosya> | --genel-hex <64 hane>) [--sig <yol>] [--manifest <manifest.json>] [--hedef <ad>] [--surum <X.Y.Z>]
//
// Cikis kodlari: 0 basarili / dogrulama gecti, 1 islem reddedildi ya da dogrulama GECMEDI, 2 komut satiri hatasi.

import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import {
  anahtarCiftiUret,
  depoDisindaOlmali,
  genelAnahtarDosyasiOku,
  genelAnahtariCoz,
  genelBilgi,
  ozelAnahtarYoluBul,
  ozelAnahtariOku,
  ozelAnahtariSil,
  ozelAnahtariYaz,
  parolaAl,
} from './lib/anahtar.mjs';
import { FORMAT, HEDEFLER, hedefDenetle, imzaDosyasiAyristir, surumDenetle } from './lib/bicim.mjs';
import { MAKS_MANIFEST_DOSYASI, MAKS_SIG_DOSYASI, sinirliMetinOku } from './lib/dosya.mjs';
import { IslemHatasi, KullanimHatasi, guvenliMetin } from './lib/hata.mjs';
import { dogrula, imzala } from './lib/imza.mjs';

const YARDIM = `OTA imza araci (${FORMAT}, Ed25519)

Kullanim:
  node tools/ota_imza/ota_imza.mjs anahtar-uret --ozel <yol> [--genel <dosya>]
      Yeni Ed25519 anahtar cifti uretir. OZEL anahtar <yol>'a yazilir (depo DISINDA olmali; var olan dosyanin uzerine yazilmaz).
      Genel anahtar ekrana basilir (PEM, hex, C++ tanimi); --genel verilirse ayrica dosyaya yazilir.
  node tools/ota_imza/ota_imza.mjs genel-anahtar --ozel <yol>
      Ozel anahtardan genel anahtari yeniden uretip basar (firmware'e gomulecek deger).
  node tools/ota_imza/ota_imza.mjs imzala <firmware.bin> --hedef <${Object.keys(HEDEFLER).join('|')}> --surum <X.Y.Z> [--rollback-max <X.Y.Z>] [--ozel <yol>] [--cikti <yol>]
      <firmware.bin>.sig (ya da --cikti) dosyasini uretir: hedef, surum, boyut, sha256 ve Ed25519 imzasi.
      --rollback-max YALNIZ bilincli surum dusurmede kullanilir: imzaya "rollback_max" yetkisini katar (surumu bu degerde ve daha eski olan cihazlar
      --surum surumune dusurulebilir; deger --surum'den BUYUK olmali). Normal yayinda KULLANMAYIN.
  node tools/ota_imza/ota_imza.mjs dogrula <firmware.bin> (--genel <dosya> | --genel-hex <64 hane hex>) [--sig <yol>] [--manifest <manifest.json>] [--hedef <ad>] [--surum <X.Y.Z>]
      Dosya + imza + genel anahtari denetler; GECTI / GECMEDI yazar. --genel / --genel-hex birden fazla verilebilir (anahtar donusu).
      --manifest verilirse manifest.json'daki version / sha256 / target imzayla birebir ayni mi diye de bakar (yuklemeden once calistirin).
  node tools/ota_imza/ota_imza.mjs yardim

Ortam degiskenleri (degerleri .env.example'da YOKTUR; yalniz imzalama makinesinde tanimlanir, sunucuda ASLA):
  OTA_IMZA_OZEL_ANAHTAR   ozel anahtar dosyasinin yolu (--ozel verilmezse kullanilir; varsayilan yol YOKTUR)
  OTA_IMZA_PAROLA         ozel anahtar dosyasinin parolasi (anahtar-uret'te verilirse anahtar sifreli yazilir; en az 8 karakter)
                          Komut satirinda parola kabul EDILMEZ (kabuk gecmisine duser).

Cikis kodlari: 0 basarili / GECTI, 1 reddedildi / GECMEDI, 2 komut satiri hatasi.
Ayrinti ve imza bicimi: tools/ota_imza/README.md
`;

const PAROLA_BAYRAGI = /^--?parola(?:=|$)/;

function varMi(yol) {
  try {
    fs.statSync(yol);
    return true;
  } catch {
    return false;
  }
}

/** parseArgs hatalarini Turkce KullanimHatasi'na cevirir; --parola icin ozel aciklama verir. */
function bayraklariAyikla(argv, secenekler, { konumsalAzami = 0 } = {}) {
  if (argv.some((arg) => PAROLA_BAYRAGI.test(arg))) {
    throw new KullanimHatasi('parola komut satirinda verilmez (kabuk gecmisine duser); OTA_IMZA_PAROLA ortam degiskenini kullanin');
  }
  let sonuc;
  try {
    sonuc = parseArgs({ args: argv, options: secenekler, allowPositionals: true, strict: true });
  } catch (hata) {
    const secenek = /'(--?[\w-]+)/.exec(hata.message)?.[1];
    if (hata.code === 'ERR_PARSE_ARGS_UNKNOWN_OPTION') {
      throw new KullanimHatasi(`bilinmeyen secenek: ${guvenliMetin(secenek ?? '?')} (yardim icin: yardim)`);
    }
    if (hata.code === 'ERR_PARSE_ARGS_INVALID_OPTION_VALUE') {
      throw new KullanimHatasi(`${guvenliMetin(secenek ?? '?')} secenegi bir deger ister`);
    }
    throw new KullanimHatasi(`komut satiri hatasi (${guvenliMetin(hata.code ?? hata.message)})`);
  }
  if (sonuc.positionals.length > konumsalAzami) {
    throw new KullanimHatasi(`beklenmeyen arguman: ${guvenliMetin(sonuc.positionals[konumsalAzami])}`);
  }
  return sonuc;
}

/** Ic dogrulama fonksiyonunun IslemHatasi'ni (cikis 1) komut satiri hatasina (cikis 2) cevirir. */
function kullanimOlarak(islev) {
  try {
    return islev();
  } catch (hata) {
    if (hata instanceof IslemHatasi) {
      throw new KullanimHatasi(hata.message);
    }
    throw hata;
  }
}

function klasorVarMi(yol) {
  try {
    return fs.statSync(yol).isDirectory();
  } catch {
    return false;
  }
}

/**
 * Imza dosyasi yalniz YOKSA ya da zaten gecerli bir imza dosyasiysa (onceki bir imzala calismasi) uzerine yazilabilir. Yanlis yazilmis bir
 * --cikti yolu firmware.bin'i, ozel anahtari ya da manifest'i ezmesin diye baska her var olan dosya (ya da klasor) reddedilir.
 */
function imzaUzerineYazilabilirMi(yol) {
  if (!varMi(yol)) {
    return true;
  }
  try {
    imzaDosyasiAyristir(sinirliMetinOku(yol, MAKS_SIG_DOSYASI, 'imza dosyasi').metin);
    return true;
  } catch {
    return false;
  }
}

/** Ayni klasore gecici dosya yazip yeniden adlandirir (yarim yazilmis .sig kalmaz). */
function atomikYaz(hedefYol, metin) {
  const gecici = `${hedefYol}.${process.pid}.${crypto.randomBytes(4).toString('hex')}.tmp`;
  try {
    fs.writeFileSync(gecici, metin, { flag: 'wx' });
    fs.renameSync(gecici, hedefYol);
  } catch (hata) {
    fs.rmSync(gecici, { force: true });
    throw new IslemHatasi(`imza dosyasi yazilamadi: ${guvenliMetin(hedefYol)} (${hata.code ?? hata.message})`);
  }
}

/** Windows'ta dosya izinleri 0600 ile kisitlanamaz; dosyayi yalniz mevcut kullaniciya acan icacls komutu (her kabukta ayni calisir). */
function windowsIzinKomutu(yol) {
  let kullanici = '%USERNAME%';
  try {
    kullanici = os.userInfo().username;
  } catch {
    // kullanici adi okunamazsa cmd.exe degiskeni birakilir
  }
  return `icacls "${yol}" /inheritance:r /grant:r "${kullanici}:F"`;
}

function genelAnahtarSatirlari(bilgi) {
  return [
    'GENEL anahtar (Ed25519) - sir DEGILDIR; firmware\'e ve sunucuya gomulur:',
    `  key_id : ${bilgi.kimlik}`,
    `  hex    : ${bilgi.hex}`,
    '  PEM    :',
    ...bilgi.pem.trimEnd().split('\n').map((satir) => `    ${satir}`),
    '',
    'Firmware icin C++ tanimi:',
    ...bilgi.cTanimi.split('\n').map((satir) => `  ${satir}`),
  ];
}

function anahtarUret(argv, g) {
  const { values } = bayraklariAyikla(argv, { ozel: { type: 'string' }, genel: { type: 'string' } });
  const ozelYol = ozelAnahtarYoluBul({ bayrak: values.ozel, env: g.env, cwd: g.cwd });
  depoDisindaOlmali(ozelYol);
  if (!klasorVarMi(path.dirname(ozelYol))) {
    throw new IslemHatasi(`ozel anahtarin klasoru yok: ${guvenliMetin(path.dirname(ozelYol))} (once olusturun)`);
  }
  let genelYol;
  if (values.genel !== undefined) {
    genelYol = path.resolve(g.cwd, values.genel);
    if (genelYol === ozelYol) {
      throw new KullanimHatasi('--genel ile --ozel ayni dosya olamaz');
    }
    if (varMi(genelYol)) {
      throw new IslemHatasi(`genel anahtar dosyasi ZATEN VAR, uzerine yazilmaz: ${guvenliMetin(genelYol)}`);
    }
    if (!klasorVarMi(path.dirname(genelYol))) {
      throw new IslemHatasi(`genel anahtarin klasoru yok: ${guvenliMetin(path.dirname(genelYol))}`);
    }
  }
  const parola = parolaAl(g.env);

  const { ozel } = anahtarCiftiUret();
  const { parolali } = ozelAnahtariYaz(ozelYol, ozel, parola);

  // Diskteki dosyayi GERI OKUYUP bir deneme imzasi at: bozuk / okunamayan anahtar fark edilmeden birakilmasin.
  let bilgi;
  try {
    const { key } = ozelAnahtariOku(ozelYol, { parola });
    const genel = crypto.createPublicKey(key);
    const deneme = Buffer.from('ota-imza-kendi-kendine-deneme');
    if (!crypto.verify(null, deneme, genel, crypto.sign(null, deneme, key))) {
      throw new IslemHatasi('deneme imzasi dogrulanamadi');
    }
    bilgi = genelBilgi(genel);
  } catch (hata) {
    ozelAnahtariSil(ozelYol);
    throw new IslemHatasi(`yazilan ozel anahtar dogrulanamadi, dosya silindi: ${hata.message}`);
  }

  const satirlar = [
    `OZEL anahtar yazildi: ${ozelYol}`,
    parolali
      ? '  korunma : parolali (PKCS#8, AES-256-CBC)'
      : '  korunma : PAROLASIZ (onerilen: OTA_IMZA_PAROLA tanimlayip anahtari parolali uretin)',
    process.platform === 'win32'
      ? `  izinler : Windows'ta otomatik kisitlanmaz; dosyayi yalniz kendi hesabiniza acin: ${windowsIzinKomutu(ozelYol)}`
      : '  izinler : yalniz sahibi okuyup yazabilir (0600)',
    '',
    ...genelAnahtarSatirlari(bilgi),
    '',
    'SIMDI YAPIN:',
    '  1) OZEL anahtar dosyasini en az IKI ayri guvenli yere yedekleyin (sifreli USB bellek / parola yoneticisi kasasi). Kaybolursa sahadaki',
    '     cihazlara bir daha imzali OTA yollanamaz; USB ile yeni genel anahtarli firmware yuklemek gerekir.',
    '  2) Ozel anahtari ASLA depoya, sunucuya (VPS), e-postaya, sohbete ya da bulut klasorune (OneDrive/Drive/Dropbox) koymayin.',
    '  3) Yukaridaki GENEL anahtari firmware\'e ve sunucuya gomun; key_id degerini not alin.',
  ];

  if (genelYol !== undefined) {
    try {
      fs.writeFileSync(genelYol, bilgi.pem, { flag: 'wx' });
      satirlar.push('', `Genel anahtar PEM dosyasi yazildi: ${genelYol}`);
    } catch (hata) {
      satirlar.push('', `UYARI: genel anahtar dosyasi yazilamadi (${hata.code ?? hata.message}); yukaridaki degeri elle kaydedin.`);
    }
  }
  g.out(`${satirlar.join('\n')}\n`);
  return 0;
}

function genelAnahtar(argv, g) {
  const { values } = bayraklariAyikla(argv, { ozel: { type: 'string' } });
  const ozelYol = ozelAnahtarYoluBul({ bayrak: values.ozel, env: g.env, cwd: g.cwd });
  depoDisindaOlmali(ozelYol);
  const { key, uyarilar } = ozelAnahtariOku(ozelYol, { parola: parolaAl(g.env) });
  for (const uyari of uyarilar) {
    g.err(`UYARI: ${uyari}\n`);
  }
  g.out(`${genelAnahtarSatirlari(genelBilgi(crypto.createPublicKey(key))).join('\n')}\n`);
  return 0;
}

function imzalaKomutu(argv, g) {
  const { values, positionals } = bayraklariAyikla(
    argv,
    { ozel: { type: 'string' }, hedef: { type: 'string' }, surum: { type: 'string' }, 'rollback-max': { type: 'string' }, cikti: { type: 'string' } },
    { konumsalAzami: 1 },
  );
  if (positionals.length === 0) {
    throw new KullanimHatasi('firmware dosyasi verilmedi: imzala <firmware.bin> --hedef <ad> --surum <X.Y.Z>');
  }
  if (values.hedef === undefined) {
    throw new KullanimHatasi(`--hedef gerekli (${Object.keys(HEDEFLER).join(' | ')})`);
  }
  if (values.surum === undefined) {
    throw new KullanimHatasi('--surum gerekli (ornek 4.3.4; ota_guncelleme.h icindeki OTA_VERSION_* ile AYNI olmali)');
  }
  const hedef = kullanimOlarak(() => hedefDenetle(values.hedef));
  const surum = kullanimOlarak(() => surumDenetle(values.surum));
  const rollbackMax = values['rollback-max'] === undefined ? undefined : kullanimOlarak(() => surumDenetle(values['rollback-max'], 'rollback_max'));
  const ozelYol = ozelAnahtarYoluBul({ bayrak: values.ozel, env: g.env, cwd: g.cwd });
  depoDisindaOlmali(ozelYol);

  const imajYolu = path.resolve(g.cwd, positionals[0]);
  const sigYolu = values.cikti !== undefined ? path.resolve(g.cwd, values.cikti) : `${imajYolu}.sig`;
  if (!imzaUzerineYazilabilirMi(sigYolu)) {
    throw new IslemHatasi(
      `imza dosyasi yolu zaten var ve gecerli bir imza dosyasi DEGIL, uzerine yazilmaz: ${guvenliMetin(sigYolu)} `
        + '(firmware.bin, ozel anahtar ya da manifest olabilir; --cikti yolunu kontrol edin)',
    );
  }
  const { key, uyarilar: anahtarUyarilari } = ozelAnahtariOku(ozelYol, { parola: parolaAl(g.env) });
  const sonuc = imzala({ imajYolu, hedef, surum, ozelAnahtar: key, rollbackMax });
  const varOlan = varMi(sigYolu);
  atomikYaz(sigYolu, sonuc.metin);

  for (const uyari of [...anahtarUyarilari, ...sonuc.uyarilar]) {
    g.err(`UYARI: ${uyari}\n`);
  }
  g.out(`${[
    'IMZALANDI',
    `  firmware : ${imajYolu} (${sonuc.ozet.boyut} bayt)`,
    `  hedef    : ${hedef}  (imaj kontrolu: ${sonuc.imajKontrolu})`,
    `  surum    : ${surum}`,
    ...(rollbackMax === undefined ? [] : [`  rollback : ${rollbackMax}  (SURUM DUSURME YETKISI: surumu ${rollbackMax} ve daha eski olan cihazlar ${surum} surumune dusurulebilir)`]),
    `  sha256   : ${sonuc.ozet.sha256}`,
    `  key_id   : ${sonuc.anahtarKimligi}`,
    `  imza     : ${sigYolu}${varOlan ? '  (var olan dosyanin yerine yazildi)' : ''}`,
    '',
    'manifest.json icin AYNI degerler (bire bir):',
    `  "target": "${hedef}",`,
    `  "version": "${surum}",`,
    ...(rollbackMax === undefined ? [] : [`  "rollback_max": "${rollbackMax}",`]),
    `  "sha256": "${sonuc.ozet.sha256}"`,
    '',
    'Sonraki adim: firmware.bin ve imza dosyasini sunucuya yukleyin (docs/OTA_IMZA.md); once "dogrula" ile genel anahtarla denetleyin.',
  ].join('\n')}\n`);
  return 0;
}

function dogrulaKomutu(argv, g) {
  const { values, positionals } = bayraklariAyikla(
    argv,
    {
      genel: { type: 'string', multiple: true },
      'genel-hex': { type: 'string', multiple: true },
      sig: { type: 'string' },
      hedef: { type: 'string' },
      surum: { type: 'string' },
      manifest: { type: 'string' },
    },
    { konumsalAzami: 1 },
  );
  if (positionals.length === 0) {
    throw new KullanimHatasi('firmware dosyasi verilmedi: dogrula <firmware.bin> --genel <dosya>');
  }
  const genelDosyalar = values.genel ?? [];
  const genelHexler = values['genel-hex'] ?? [];
  if (genelDosyalar.length === 0 && genelHexler.length === 0) {
    throw new KullanimHatasi('genel anahtar verilmedi: --genel <PEM dosyasi> ya da --genel-hex <64 hane>');
  }
  const beklenenHedef = values.hedef === undefined ? undefined : kullanimOlarak(() => hedefDenetle(values.hedef));
  const beklenenSurum = values.surum === undefined ? undefined : kullanimOlarak(() => surumDenetle(values.surum));
  const genelAnahtarlar = [
    ...genelDosyalar.map((yol) => genelAnahtarDosyasiOku(path.resolve(g.cwd, yol))),
    ...genelHexler.map((hex) => {
      if (!/^[0-9a-fA-F]{64}$/.test(hex.trim())) {
        throw new KullanimHatasi('--genel-hex tam 64 haneli hex olmali');
      }
      return genelAnahtariCoz(hex);
    }),
  ];

  const imajYolu = path.resolve(g.cwd, positionals[0]);
  const sigYolu = values.sig !== undefined ? path.resolve(g.cwd, values.sig) : `${imajYolu}.sig`;
  const satirlar = ['OTA imza dogrulama', `  firmware : ${imajYolu}`, `  imza     : ${sigYolu}`, ''];

  const basarisiz = (ayrinti, sonuc) => {
    satirlar.push(`[HATA ] ${ayrinti}`, '', `SONUC: GECMEDI - ${sonuc}`);
    g.out(`${satirlar.join('\n')}\n`);
    return 1;
  };
  let sigMetni;
  try {
    sigMetni = sinirliMetinOku(sigYolu, MAKS_SIG_DOSYASI, 'imza dosyasi').metin;
  } catch (hata) {
    return basarisiz(hata.message, 'imza dosyasi olmadan firmware yayinlanmamali');
  }
  let manifestMetni;
  if (values.manifest !== undefined) {
    try {
      manifestMetni = sinirliMetinOku(path.resolve(g.cwd, values.manifest), MAKS_MANIFEST_DOSYASI, 'manifest.json').metin;
    } catch (hata) {
      return basarisiz(hata.message, 'verilen manifest okunamadi');
    }
  }

  const sonuc = dogrula({ imajYolu, sigMetni, genelAnahtarlar, beklenenHedef, beklenenSurum, manifestMetni });
  const etiket = { tamam: '[TAMAM]', hata: '[HATA ]', uyari: '[UYARI]' };
  for (const kontrol of sonuc.kontroller) {
    satirlar.push(`${etiket[kontrol.durum]} ${kontrol.ad}${kontrol.ayrinti ? `: ${kontrol.ayrinti}` : ''}`);
  }
  satirlar.push('', sonuc.gecti ? 'SONUC: GECTI' : 'SONUC: GECMEDI - bu firmware yayinlanmamali / cihaza yuklenmemeli');
  g.out(`${satirlar.join('\n')}\n`);
  return sonuc.gecti ? 0 : 1;
}

const KOMUTLAR = {
  'anahtar-uret': anahtarUret,
  'genel-anahtar': genelAnahtar,
  imzala: imzalaKomutu,
  dogrula: dogrulaKomutu,
};

/**
 * Komut satirini calistirir ve cikis kodunu dondurur (process.exit CAGIRMAZ; testler dogrudan cagirir).
 * @param {string[]} argv komut + secenekler
 * @param {{ out?: (metin: string) => void, err?: (metin: string) => void, env?: Record<string, string|undefined>, cwd?: string }} [ortam]
 */
export function main(argv, ortam = {}) {
  const g = {
    out: ortam.out ?? ((metin) => process.stdout.write(metin)),
    err: ortam.err ?? ((metin) => process.stderr.write(metin)),
    env: ortam.env ?? process.env,
    cwd: ortam.cwd ?? process.cwd(),
  };
  try {
    const [komut, ...geri] = argv;
    if (komut === undefined) {
      g.err(YARDIM);
      return 2;
    }
    if (['yardim', '--yardim', '-h', '--help', 'help'].includes(komut)) {
      g.out(YARDIM);
      return 0;
    }
    const islev = Object.hasOwn(KOMUTLAR, komut) ? KOMUTLAR[komut] : undefined;
    if (islev === undefined) {
      throw new KullanimHatasi(`bilinmeyen komut: ${guvenliMetin(komut)} (komutlar: ${Object.keys(KOMUTLAR).join(', ')})`);
    }
    return islev(geri, g);
  } catch (hata) {
    if (hata instanceof KullanimHatasi) {
      g.err(`HATA: ${hata.message}\nYardim icin: node tools/ota_imza/ota_imza.mjs yardim\n`);
      return 2;
    }
    if (hata instanceof IslemHatasi) {
      g.err(`HATA: ${hata.message}\n`);
      return 1;
    }
    g.err(`BEKLENMEYEN HATA: ${hata?.message ?? hata}\n`);
    return 1;
  }
}

function dogrudanCalistirildiMi() {
  try {
    return process.argv[1] !== undefined && fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (dogrudanCalistirildiMi()) {
  process.exitCode = main(process.argv.slice(2));
}
