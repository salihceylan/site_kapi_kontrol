// Imzalama ve dogrulama cekirdegi (CLI'dan bagimsiz; test edilebilir). Ed25519, Node yerlesik crypto.
//
// Guvence: imza, (hedef, surum, boyut, sha256) dortlusunu baglar. Cihaz bu dortluyu KENDI bildigi / hesapladigi degerlerle yeniden kurar
// (hedef = derleme sabiti OTA_TARGET, boyut ve sha256 = indirdigi baytlardan); yalniz surum ve imza sunucudan gelir.

import crypto from 'node:crypto';
import { anahtarKimligi, genelHam } from './anahtar.mjs';
import {
  hedefDenetle,
  imzaDosyasiAyristir,
  imzaDosyasiKur,
  imzaDosyasiMetni,
  imzaMesajiKur,
  surumDenetle,
} from './bicim.mjs';
import { IslemHatasi } from './hata.mjs';
import { hedefUyumunuDenetle, imajOku, imajdaSurumVarMi } from './imaj.mjs';

/**
 * Imaji imzalar. Imza uretildikten sonra AYNI mesaj genel anahtarla yeniden dogrulanir; gecmezse hata verir (bozuk anahtar / hata).
 * @param {{ imajYolu: string, hedef: string, surum: string, ozelAnahtar: crypto.KeyObject }} girdi
 * @returns {{ sig: object, metin: string, ozet: { boyut: number, sha256: string }, anahtarKimligi: string, uyarilar: string[], imajKontrolu: string }}
 */
export function imzala({ imajYolu, hedef, surum, ozelAnahtar }) {
  hedefDenetle(hedef);
  surumDenetle(surum);
  const imaj = imajOku(imajYolu);
  const uyum = hedefUyumunuDenetle(hedef, imaj.veri);
  if (!uyum.ok) {
    throw new IslemHatasi(`imza URETILMEDI: ${uyum.ayrinti}`);
  }
  const uyarilar = [];
  if (!imajdaSurumVarMi(imaj.veri, surum)) {
    uyarilar.push(
      `surum metni "${surum}" imajin icinde bulunamadi: ota_guncelleme.h'deki OTA_VERSION_* artirilmadan derlenmis ya da baska bir `
        + 'derlemenin bin dosyasi verilmis olabilir (cihaz guncellemeden sonra ayni surumu tekrar tekrar indirmeye calisir).',
    );
  }

  const genel = crypto.createPublicKey(ozelAnahtar);
  const kimlik = anahtarKimligi(genelHam(genel));
  const mesaj = imzaMesajiKur({ hedef, surum, boyut: imaj.boyut, sha256: imaj.sha256 });
  const imza = crypto.sign(null, mesaj, ozelAnahtar);
  if (imza.length !== 64 || !crypto.verify(null, mesaj, genel, imza)) {
    throw new IslemHatasi('uretilen imza kendi dogrulamasindan gecmedi; imza dosyasi YAZILMADI (anahtar bozuk olabilir)');
  }
  const sig = imzaDosyasiKur({
    hedef,
    surum,
    boyut: imaj.boyut,
    sha256: imaj.sha256,
    anahtarKimligi: kimlik,
    imzaHex: imza.toString('hex'),
  });
  return {
    sig,
    metin: imzaDosyasiMetni(sig),
    ozet: { boyut: imaj.boyut, sha256: imaj.sha256 },
    anahtarKimligi: kimlik,
    uyarilar,
    imajKontrolu: uyum.ayrinti,
  };
}

/** manifest.json ile imza dosyasinin ayni surumu / ozeti / hedefi anlattigini denetler (sonuclar `ekle` ile kontrol listesine yazilir). */
function manifestiKarsilastir(manifestMetni, sig, ekle) {
  let manifest;
  try {
    manifest = JSON.parse(manifestMetni.charCodeAt(0) === 0xfeff ? manifestMetni.slice(1) : manifestMetni);
  } catch {
    ekle('manifest.json', 'hata', 'gecerli JSON degil');
    return;
  }
  if (manifest === null || typeof manifest !== 'object' || Array.isArray(manifest)) {
    ekle('manifest.json', 'hata', 'bir JSON nesnesi degil');
    return;
  }
  const surum = manifest.version === undefined || manifest.version === null ? '' : String(manifest.version);
  ekle('manifest surumu', surum === sig.version ? 'tamam' : 'hata',
    surum === sig.version ? surum : `manifest "${surum}" diyor, imza ${sig.version} surumu icin (cihaz imzayi manifest surumuyle dogrular; ikisi BIREBIR ayni olmali)`);
  const ozet = manifest.sha256 === undefined || manifest.sha256 === null ? '' : String(manifest.sha256).toLowerCase();
  ekle('manifest sha256', ozet === sig.sha256 ? 'tamam' : 'hata',
    ozet === sig.sha256 ? ozet : `manifest ozeti "${ozet || '(yok)'}", imza ${sig.sha256} diyor`);
  if (manifest.target === undefined || manifest.target === null || manifest.target === '') {
    ekle('manifest hedefi', 'uyari', 'manifestte "target" alani yok (sunucu hedefi klasor adindan turetir; yine de acikca yazin)');
  } else {
    ekle('manifest hedefi', manifest.target === sig.target ? 'tamam' : 'hata',
      manifest.target === sig.target ? sig.target : `manifest ${String(manifest.target).slice(0, 40)}, imza ${sig.target} icin`);
  }
}

/**
 * Imza dosyasini ve imaji dogrular. Tum kontroller calisir (ilk hatada durmaz) ki operator butun resmi gorsun.
 * `durum`: 'tamam' | 'hata' | 'uyari'. `gecti`: hic 'hata' yoksa true.
 *
 * @param {object} girdi
 * @param {string} girdi.imajYolu
 * @param {string} girdi.sigMetni .sig dosyasinin metni
 * @param {{ key: crypto.KeyObject, kimlik: string }[]} girdi.genelAnahtarlar guvenilen genel anahtarlar (anahtar donusu icin birden fazla olabilir)
 * @param {string} [girdi.beklenenHedef] verilirse .sig'deki hedefle eslesmeli
 * @param {string} [girdi.beklenenSurum] verilirse .sig'deki surumle eslesmeli
 * @param {string} [girdi.manifestMetni] verilirse manifest.json'daki version / sha256 / target imzayla birebir ayni olmali
 *   (cihaz imza mesajini manifest surumuyle kurar; elle yazilan manifestte surum ya da ozet farkliysa cihaz guncellemeyi reddeder)
 */
export function dogrula({ imajYolu, sigMetni, genelAnahtarlar, beklenenHedef, beklenenSurum, manifestMetni }) {
  const kontroller = [];
  const ekle = (ad, durum, ayrinti = '') => kontroller.push({ ad, durum, ayrinti });
  const sonuc = () => ({ gecti: kontroller.every((kontrol) => kontrol.durum !== 'hata'), kontroller });

  let sig;
  try {
    sig = imzaDosyasiAyristir(sigMetni);
    ekle('imza dosyasi', 'tamam', `${sig.format}, ${sig.algorithm}, hedef ${sig.target}, surum ${sig.version}`);
  } catch (hata) {
    ekle('imza dosyasi', 'hata', hata.message);
    return sonuc();
  }

  let imaj;
  try {
    imaj = imajOku(imajYolu);
  } catch (hata) {
    ekle('firmware dosyasi', 'hata', hata.message);
    return sonuc();
  }

  ekle('boyut', imaj.boyut === sig.size ? 'tamam' : 'hata',
    imaj.boyut === sig.size ? `${imaj.boyut} bayt` : `dosya ${imaj.boyut} bayt, imza dosyasi ${sig.size} bayt diyor (dosya degismis ya da baska surum)`);
  ekle('sha256', imaj.sha256 === sig.sha256 ? 'tamam' : 'hata',
    imaj.sha256 === sig.sha256 ? imaj.sha256 : `dosyanin ozeti ${imaj.sha256}, imza dosyasi ${sig.sha256} diyor (dosya degismis)`);

  if (beklenenHedef !== undefined) {
    ekle('beklenen hedef', sig.target === beklenenHedef ? 'tamam' : 'hata',
      sig.target === beklenenHedef ? beklenenHedef : `imza ${sig.target} icin, beklenen ${beklenenHedef}`);
  }
  if (beklenenSurum !== undefined) {
    ekle('beklenen surum', sig.version === beklenenSurum ? 'tamam' : 'hata',
      sig.version === beklenenSurum ? beklenenSurum : `imza ${sig.version} surumu icin, beklenen ${beklenenSurum}`);
  }

  if (manifestMetni !== undefined) {
    manifestiKarsilastir(manifestMetni, sig, ekle);
  }

  const uyum = hedefUyumunuDenetle(sig.target, imaj.veri);
  ekle('imaj basligi / hedef', uyum.ok ? 'tamam' : 'hata', uyum.ayrinti);
  if (!imajdaSurumVarMi(imaj.veri, sig.version)) {
    ekle('imajdaki surum metni', 'uyari', `"${sig.version}" imajin icinde bulunamadi (surum artirilmadan derlenmis olabilir)`);
  }

  const aday = genelAnahtarlar.find((anahtar) => anahtar.kimlik === sig.key_id);
  ekle('anahtar kimligi', aday ? 'tamam' : 'hata',
    aday ? sig.key_id : `imza ${sig.key_id} kimlikli anahtarla atilmis; verilen genel anahtar(lar): ${genelAnahtarlar.map((anahtar) => anahtar.kimlik).join(', ') || '(yok)'}`);

  if (aday) {
    const mesaj = imzaMesajiKur({ hedef: sig.target, surum: sig.version, boyut: imaj.boyut, sha256: imaj.sha256 });
    const gecerli = crypto.verify(null, mesaj, aday.key, Buffer.from(sig.signature, 'hex'));
    ekle('Ed25519 imzasi', gecerli ? 'tamam' : 'hata',
      gecerli ? 'imza gecerli' : 'imza GECERSIZ (imza, bu dosya / hedef / surum icin bu anahtarla atilmamis)');
  } else {
    ekle('Ed25519 imzasi', 'hata', 'dogrulanamadi: eslesen genel anahtar yok');
  }
  return sonuc();
}
