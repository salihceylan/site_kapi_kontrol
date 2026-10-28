// Gercek surum arsivindeki (cihaz_kontrol/firmware_releases) imajlarla gerceklik denetimi:  node --test "tools/ota_imza/test/*.test.mjs"
// Sahte imajlar yalniz aracin mantigini sinar; bu dosya imaj basligi / cip kimligi / surum metni varsayimlarinin GERCEK derlemelerde de
// gecerli oldugunu gosterir. Arsiv yoksa (ornegin depo kopyasi eksikse) testler atlanir.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { describe, it } from 'node:test';
import { HEDEFLER } from '../lib/bicim.mjs';
import { genelAnahtariCoz } from '../lib/anahtar.mjs';
import { hedefUyumunuDenetle, imajBasliginiCoz, imajOku, imajdaSurumVarMi } from '../lib/imaj.mjs';
import { dogrula, imzala } from '../lib/imza.mjs';
import { DEPO_KOKU, anahtarHazirla, geciciDizin, temizle } from './yardimci.mjs';

const ARSIV = path.join(DEPO_KOKU, 'cihaz_kontrol', 'firmware_releases');

function arsivImajlari() {
  if (!fs.existsSync(ARSIV)) return [];
  return fs
    .readdirSync(ARSIV)
    .map((ad) => ({ ad, bin: path.join(ARSIV, ad, 'firmware.bin'), manifest: path.join(ARSIV, ad, 'manifest.json') }))
    .filter((girdi) => fs.existsSync(girdi.bin));
}

const imajlar = arsivImajlari();
const atla = imajlar.length === 0 ? 'cihaz_kontrol/firmware_releases bulunamadi' : false;

describe('gercek surum arsivi', { skip: atla }, () => {
  const okunan = imajlar.map((girdi) => {
    const imaj = imajOku(girdi.bin);
    return { ...girdi, imaj, baslik: imajBasliginiCoz(imaj.veri) };
  });

  it('her gercek imaj gecerli bir ESP32 uygulama basligi tasir (0xE9, segment 1-16)', () => {
    for (const { ad, baslik } of okunan) {
      assert.equal(baslik.gecerli, true, `${ad}: ${baslik.neden}`);
    }
  });

  it('C3 imajlari (chip_id 0x0005) esp32-c3 icin kabul, esp32-wroom icin RED; WROOM (0x0000) tersi', () => {
    let c3 = 0;
    let wroom = 0;
    for (const { ad, imaj, baslik } of okunan) {
      if (baslik.cipKimligi === HEDEFLER['esp32-c3'].cipKimligi) {
        c3 += 1;
        assert.equal(hedefUyumunuDenetle('esp32-c3', imaj.veri).ok, true, ad);
        assert.equal(hedefUyumunuDenetle('esp32-wroom', imaj.veri).ok, false, ad);
      } else if (baslik.cipKimligi === HEDEFLER['esp32-wroom'].cipKimligi) {
        wroom += 1;
        assert.equal(hedefUyumunuDenetle('esp32-wroom', imaj.veri).ok, true, ad);
        assert.equal(hedefUyumunuDenetle('esp32-c3', imaj.veri).ok, false, ad);
      } else {
        // arsivdeki eski (ESP32-S3 donemi) imajlar iki hedef icin de reddedilir
        assert.equal(hedefUyumunuDenetle('esp32-c3', imaj.veri).ok, false, ad);
        assert.equal(hedefUyumunuDenetle('esp32-wroom', imaj.veri).ok, false, ad);
      }
    }
    assert.ok(c3 > 0, 'arsivde en az bir C3 imaji bekleniyordu');
    assert.ok(wroom > 0, 'arsivde en az bir WROOM imaji bekleniyordu');
  });

  it('manifest.json surumu imajin icinde NUL sonlu dize olarak bulunur (surum sezgisi gercek derlemelerde calisir)', () => {
    let denetlenen = 0;
    let bulunan = 0;
    for (const { manifest, imaj } of okunan) {
      if (!fs.existsSync(manifest)) continue;
      const surum = String(JSON.parse(fs.readFileSync(manifest, 'utf8')).version ?? '');
      if (!/^\d+\.\d+\.\d+$/.test(surum)) continue;
      denetlenen += 1;
      if (imajdaSurumVarMi(imaj.veri, surum)) bulunan += 1;
    }
    assert.ok(denetlenen >= 5, `yeterli manifest bulunamadi (${denetlenen})`);
    assert.ok(bulunan / denetlenen >= 0.9, `surum metni yalniz ${bulunan}/${denetlenen} imajda bulundu`);
  });

  it('gercek bir C3 ve bir WROOM imaji imzalanir ve dogrulanir; ayri gercek imaj ve bit-bozma reddedilir', () => {
    const dizin = geciciDizin();
    try {
      const anahtar = anahtarHazirla(dizin);
      const genelAnahtarlar = [genelAnahtariCoz(anahtar.hex)];
      for (const [hedef, cip] of [['esp32-c3', 0x0005], ['esp32-wroom', 0x0000]]) {
        const girdi = okunan.find(({ baslik }) => baslik.cipKimligi === cip);
        const siradaki = okunan.find(({ baslik, imaj }) => baslik.cipKimligi === cip && imaj.sha256 !== girdi.imaj.sha256);
        const gecerliSurum = '4.3.4';
        const sonuc = imzala({ imajYolu: girdi.bin, hedef, surum: gecerliSurum, ozelAnahtar: anahtar.ozel });
        assert.equal(sonuc.ozet.sha256, girdi.imaj.sha256);
        assert.equal(sonuc.ozet.boyut, girdi.imaj.boyut);

        // imzayi gecici klasore koyup imajin kopyasi uzerinden dogrula (arsiv dosyalarina dokunulmaz)
        const kopya = path.join(dizin, `${hedef}.bin`);
        fs.copyFileSync(girdi.bin, kopya);
        const gecti = dogrula({ imajYolu: kopya, sigMetni: sonuc.metin, genelAnahtarlar });
        assert.equal(gecti.gecti, true, JSON.stringify(gecti.kontroller));

        if (siradaki !== undefined) {
          fs.copyFileSync(siradaki.bin, kopya);
          assert.equal(dogrula({ imajYolu: kopya, sigMetni: sonuc.metin, genelAnahtarlar }).gecti, false, 'baska surumun imaji reddedilmeli');
        }
        const bozuk = Buffer.from(girdi.imaj.veri);
        bozuk[Math.floor(bozuk.length / 2)] ^= 0x01;
        fs.writeFileSync(kopya, bozuk);
        assert.equal(dogrula({ imajYolu: kopya, sigMetni: sonuc.metin, genelAnahtarlar }).gecti, false, 'tek bit bozulma reddedilmeli');
      }
    } finally {
      temizle(dizin);
    }
  });
});
