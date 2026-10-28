// Ed25519 anahtar islemleri: uretim, dosyaya yazma / dosyadan okuma, genel anahtar bicimleri, depo-ici koruma.
//
// OZEL anahtar kurallari (bu modul uygular):
//  * Yol KULLANICIDAN gelir (--ozel ya da OTA_IMZA_OZEL_ANAHTAR); varsayilan yol YOKTUR.
//  * Bir git deposunun ya da bu aracin ait oldugu proje klasorunun ICINE yazilmaz / oradan okunmaz.
//  * Var olan dosyanin uzerine ASLA yazilmaz (O_EXCL): yanlislikla anahtar ezmek sahadaki tum cihazlarin guncelleme yolunu keserdi.
//  * Dosya 0600 izinle olusur; istenirse PKCS#8 parolasiyla sifrelenir (parola yalniz ortam degiskeninden gelir, komut satirindan degil).
//  * Hicbir fonksiyon ozel anahtar baytlarini dondurmez / yazdirmaz; yalniz KeyObject ve dosya olarak elde tutulur.

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { MAKS_ANAHTAR_DOSYASI, sinirliMetinOku } from './dosya.mjs';
import { IslemHatasi, KullanimHatasi, guvenliMetin } from './hata.mjs';

// Ed25519 SubjectPublicKeyInfo DER oneki (12 bayt); ardindan 32 baytlik ham genel anahtar gelir.
const SPKI_ONEKI = Buffer.from('302a300506032b6570032100', 'hex');

// PEM basliklari bilerek PARCALI kurulur: kaynak kodda tam "BEGIN ... PRIVATE KEY" basligi gecmesin (gizli bilgi tarayicilari
// kaynak kodu ozel anahtar sanip yanlis alarm vermesin; gercek bir anahtar govdesi zaten hicbir yerde bulunmaz).
const TIRE = '-----';
export const PEM_ETIKET = Object.freeze({
  ozel: `${TIRE}BEGIN PRIVATE KEY${TIRE}`,
  ozelSifreli: `${TIRE}BEGIN ENCRYPTED PRIVATE KEY${TIRE}`,
  genel: `${TIRE}BEGIN PUBLIC KEY${TIRE}`,
});
export const EN_AZ_PAROLA_UZUNLUGU = 8;

const burasi = path.dirname(fileURLToPath(import.meta.url));

/**
 * Bu araca ait proje kokleri. Arac `<depo>/tools/ota_imza` altinda calisiyorsa `<depo>` (".git klasoru olmayan" kopyalar icin ek
 * koruma); bagimsiz bir kopyadaysa bos liste (korunacak bir proje kokunden soz edilemez).
 */
export function projeKokleri() {
  const aracKlasoru = path.resolve(burasi, '..');
  const ust = path.dirname(aracKlasoru);
  return path.basename(ust) === 'tools' ? [path.dirname(ust)] : [];
}

/**
 * Var olan en derin atanin GERCEK yolunu (sembolik baglar / baglantilar cozulmus, Windows kisa adlari acilmis) bulur; var olmayan
 * kalan parcalari sona ekler. Boylece henuz yazilmamis bir dosyanin yolu da sembolik baglantiyla depoya yonlendirilemez.
 */
export function gercekYol(mutlakYol) {
  const kalan = [];
  let simdiki = path.resolve(mutlakYol);
  for (;;) {
    try {
      return path.join(fs.realpathSync.native(simdiki), ...kalan.reverse());
    } catch (hata) {
      if (hata.code !== 'ENOENT' && hata.code !== 'ENOTDIR') {
        throw hata;
      }
      const ust = path.dirname(simdiki);
      if (ust === simdiki) {
        throw hata;
      }
      kalan.push(path.basename(simdiki));
      simdiki = ust;
    }
  }
}

function icindeMi(kok, hedef) {
  const goreli = path.relative(kok, hedef);
  return goreli === '' || (goreli !== '..' && !goreli.startsWith(`..${path.sep}`) && !path.isAbsolute(goreli));
}

/**
 * Yol bir git deposunun (ya da `ekKokler` icindeki bir proje klasorunun) icinde mi?
 * @param {string} yol
 * @param {{ ekKokler?: string[] }} [secenek]
 * @returns {{ icinde: boolean, kok?: string, neden?: string }}
 */
export function depoIcindeMi(yol, { ekKokler = projeKokleri() } = {}) {
  const gercek = gercekYol(yol);
  let klasor = path.dirname(gercek);
  for (;;) {
    if (fs.existsSync(path.join(klasor, '.git'))) {
      return { icinde: true, kok: klasor, neden: 'git deposu' };
    }
    const ust = path.dirname(klasor);
    if (ust === klasor) {
      break;
    }
    klasor = ust;
  }
  for (const kok of ekKokler) {
    const gercekKok = gercekYol(kok);
    if (icindeMi(gercekKok, gercek)) {
      return { icinde: true, kok: gercekKok, neden: 'proje klasoru' };
    }
  }
  return { icinde: false };
}

/** Ozel anahtar yolu depo icindeyse reddeder. */
export function depoDisindaOlmali(yol, secenek) {
  let sonuc;
  try {
    sonuc = depoIcindeMi(yol, secenek);
  } catch (hata) {
    throw new IslemHatasi(`ozel anahtar yolu dogrulanamadi: ${guvenliMetin(yol)} (${hata.code ?? hata.message})`);
  }
  if (sonuc.icinde) {
    throw new IslemHatasi(
      `ozel anahtar ${sonuc.neden} ICINDE olamaz: ${guvenliMetin(yol)} (${guvenliMetin(sonuc.kok)} icinde). `
        + 'Anahtari depo DISINDA, tercihen sifreli bir diskte ya da cevrimdisi USB bellekte saklayin.',
    );
  }
}

/** Ozel anahtar yolu: once --ozel bayragi, yoksa OTA_IMZA_OZEL_ANAHTAR ortam degiskeni. Ikisi de bossa KullanimHatasi (varsayilan yol YOK). */
export function ozelAnahtarYoluBul({ bayrak, env, cwd }) {
  const ham = [bayrak, env?.OTA_IMZA_OZEL_ANAHTAR].find((deger) => typeof deger === 'string' && deger.trim() !== '');
  if (ham === undefined) {
    throw new KullanimHatasi(
      'ozel anahtar yolu verilmedi. --ozel <yol> ya da OTA_IMZA_OZEL_ANAHTAR ortam degiskeni gerekir; '
        + 'varsayilan bir yol YOKTUR (anahtar yanlislikla depo icine dusmesin).',
    );
  }
  return path.resolve(cwd ?? process.cwd(), ham.trim());
}

/** Ortam degiskenindeki parola (yoksa undefined). Komut satiri parolasi kabuk gecmisine dustugu icin desteklenmez. */
export function parolaAl(env) {
  const parola = env?.OTA_IMZA_PAROLA;
  return typeof parola === 'string' && parola !== '' ? parola : undefined;
}

export function anahtarCiftiUret() {
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ed25519');
  return { ozel: privateKey, genel: publicKey };
}

/**
 * Ozel anahtari PKCS#8 PEM olarak YENI bir dosyaya yazar (O_EXCL: var olan dosyanin uzerine yazilmaz, 0600).
 * `parola` verilirse PKCS#8 AES-256-CBC ile sifrelenir.
 * @returns {{ parolali: boolean }}
 */
export function ozelAnahtariYaz(yol, ozel, parola) {
  if (parola !== undefined && parola.length < EN_AZ_PAROLA_UZUNLUGU) {
    throw new KullanimHatasi(`OTA_IMZA_PAROLA en az ${EN_AZ_PAROLA_UZUNLUGU} karakter olmali`);
  }
  const pem = parola === undefined
    ? ozel.export({ type: 'pkcs8', format: 'pem' })
    : ozel.export({ type: 'pkcs8', format: 'pem', cipher: 'aes-256-cbc', passphrase: parola });
  let tanimlayici;
  try {
    tanimlayici = fs.openSync(yol, 'wx', 0o600);
  } catch (hata) {
    if (hata.code === 'EEXIST') {
      throw new IslemHatasi(`ozel anahtar dosyasi ZATEN VAR, uzerine yazilmaz: ${guvenliMetin(yol)} (eskisini bilerek tasiyip yeniden deneyin)`);
    }
    throw new IslemHatasi(`ozel anahtar dosyasi olusturulamadi: ${guvenliMetin(yol)} (${hata.code ?? hata.message})`);
  }
  let yazildi = false;
  try {
    fs.writeSync(tanimlayici, pem);
    fs.fsyncSync(tanimlayici);
    yazildi = true;
  } catch (hata) {
    throw new IslemHatasi(`ozel anahtar dosyasi yazilamadi: ${guvenliMetin(yol)} (${hata.code ?? hata.message})`);
  } finally {
    fs.closeSync(tanimlayici);
    if (!yazildi) {
      ozelAnahtariSil(yol); // yarim yazilmis anahtar dosyasi birakilmaz (bu dosyayi az once biz olusturduk)
    }
  }
  return { parolali: parola !== undefined };
}

/** Az once kendimizin olusturdugu ve yazilamayan / dogrulamadan gecemeyen ozel anahtar dosyasini siler (baska hicbir dosya icin KULLANILMAZ). */
export function ozelAnahtariSil(yol) {
  try {
    fs.rmSync(yol, { force: true });
  } catch {
    // silinemezse kullanici zaten hata mesajini goruyor
  }
}

/**
 * Ozel anahtar dosyasini okur ve Ed25519 oldugunu dogrular.
 * @returns {{ key: crypto.KeyObject, uyarilar: string[] }}
 */
export function ozelAnahtariOku(yol, { parola } = {}) {
  const { metin: pem, bilgi } = sinirliMetinOku(yol, MAKS_ANAHTAR_DOSYASI, 'ozel anahtar dosyasi');
  const uyarilar = [];
  if (process.platform !== 'win32' && (bilgi.mode & 0o077) !== 0) {
    uyarilar.push(`ozel anahtar dosyasinin izinleri gevsek (0${(bilgi.mode & 0o777).toString(8)}); baskalari okuyabilir. chmod 600 uygulayin.`);
  }
  const sifreli = pem.includes(PEM_ETIKET.ozelSifreli);
  if (!sifreli && !pem.includes(PEM_ETIKET.ozel)) {
    throw new IslemHatasi('ozel anahtar dosyasi PKCS#8 PEM bicimde degil (BEGIN PRIVATE KEY ya da BEGIN ENCRYPTED PRIVATE KEY bekleniyordu)');
  }
  if (sifreli && parola === undefined) {
    throw new IslemHatasi('ozel anahtar parolali: parolayi OTA_IMZA_PAROLA ortam degiskeniyle verin (komut satirinda verilmez)');
  }
  let key;
  try {
    key = crypto.createPrivateKey(sifreli ? { key: pem, format: 'pem', passphrase: parola } : { key: pem, format: 'pem' });
  } catch {
    throw new IslemHatasi(sifreli ? 'ozel anahtar acilamadi: parola yanlis ya da dosya bozuk' : 'ozel anahtar acilamadi: dosya bozuk');
  }
  if (key.asymmetricKeyType !== 'ed25519') {
    throw new IslemHatasi(`ozel anahtar Ed25519 degil (${key.asymmetricKeyType}); bu arac yalniz Ed25519 anahtarlariyla calisir`);
  }
  return { key, uyarilar };
}

/** KeyObject (genel) -> 32 baytlik ham anahtar. */
export function genelHam(genel) {
  const der = genel.export({ type: 'spki', format: 'der' });
  if (der.length !== SPKI_ONEKI.length + 32 || !der.subarray(0, SPKI_ONEKI.length).equals(SPKI_ONEKI)) {
    throw new IslemHatasi('genel anahtar Ed25519 degil');
  }
  return Buffer.from(der.subarray(SPKI_ONEKI.length));
}

/** 32 baytlik ham anahtar -> KeyObject (genel). */
export function genelAnahtarHamdan(ham) {
  if (!Buffer.isBuffer(ham) || ham.length !== 32) {
    throw new IslemHatasi('ham genel anahtar 32 bayt olmali');
  }
  return crypto.createPublicKey({ key: Buffer.concat([SPKI_ONEKI, ham]), format: 'der', type: 'spki' });
}

/** Anahtar kimligi: ham genel anahtarin SHA-256'sinin ilk 8 baytinin hex'i (16 hane). Yalniz ipucudur; guvenlik karari vermez. */
export function anahtarKimligi(ham) {
  return crypto.createHash('sha256').update(ham).digest('hex').slice(0, 16);
}

/** Genel anahtarin yazdirilabilir bicimleri (hepsi aciktir, sir degildir). */
export function genelBilgi(genel) {
  const ham = genelHam(genel);
  const kimlik = anahtarKimligi(ham);
  return {
    ham,
    hex: ham.toString('hex'),
    kimlik,
    pem: genel.export({ type: 'spki', format: 'pem' }),
    cTanimi: cTanimiUret(ham, kimlik),
  };
}

/** Firmware'e gomulecek C++ tanimi. */
export function cTanimiUret(ham, kimlik) {
  const satirlar = [];
  for (let i = 0; i < ham.length; i += 8) {
    satirlar.push(`  ${[...ham.subarray(i, i + 8)].map((bayt) => `0x${bayt.toString(16).padStart(2, '0')}`).join(', ')},`);
  }
  return [
    `// OTA imza genel anahtari (Ed25519, 32 bayt) - key_id: ${kimlik}`,
    'inline constexpr uint8_t OTA_IMZA_GENEL_ANAHTAR[32] = {',
    ...satirlar,
    '};',
  ].join('\n');
}

/**
 * Dogrulama icin verilen genel anahtar metnini cozer: PEM (BEGIN PUBLIC KEY) ya da 64 hane hex. Ozel anahtar dosyasi verilirse REDDEDER
 * (ozel anahtar dogrulama icin gerekmez; yanlis yerde duruyor olabilir).
 * @returns {{ key: crypto.KeyObject, ham: Buffer, kimlik: string }}
 */
export function genelAnahtariCoz(metin) {
  const temiz = String(metin ?? '').trim();
  if (/PRIVATE KEY/.test(temiz)) {
    throw new IslemHatasi('verilen dosya bir OZEL anahtar iceriyor; dogrulama icin yalniz GENEL anahtar verin (ozel anahtar baska yerde duruyorsa guvenligini gozden gecirin)');
  }
  let key;
  if (/^[0-9a-fA-F]{64}$/.test(temiz)) {
    key = genelAnahtarHamdan(Buffer.from(temiz, 'hex'));
  } else if (temiz.includes(PEM_ETIKET.genel)) {
    try {
      key = crypto.createPublicKey({ key: temiz, format: 'pem' });
    } catch {
      throw new IslemHatasi('genel anahtar PEM dosyasi okunamadi (bozuk)');
    }
    if (key.asymmetricKeyType !== 'ed25519') {
      throw new IslemHatasi(`genel anahtar Ed25519 degil (${key.asymmetricKeyType})`);
    }
  } else {
    throw new IslemHatasi('genel anahtar taninmadi: PEM (BEGIN PUBLIC KEY) ya da 64 haneli hex bekleniyordu');
  }
  const ham = genelHam(key);
  return { key, ham, kimlik: anahtarKimligi(ham) };
}

/** Genel anahtar DOSYASINI okuyup cozer. */
export function genelAnahtarDosyasiOku(yol) {
  return genelAnahtariCoz(sinirliMetinOku(yol, MAKS_ANAHTAR_DOSYASI, 'genel anahtar dosyasi').metin);
}
