// Bilinen-cevap (known-answer) vektorleri:  node --test "tools/ota_imza/test/*.test.mjs"
//
// vektorler.json YALNIZ ACIK veri tasir (genel anahtar, mesaj, imza); OZEL ANAHTAR yoktur (vektorler atilabilir bir anahtarla uretilip
// anahtar atildi). Firmware ve sunucu testleri ayni dosyayla kendi dogrulayicilarini sinar: bicim sessizce ayrisamaz.
// Ed25519 deterministiktir (RFC 8032): ayni anahtar + mesaj hep ayni imzayi verir.

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { anahtarKimligi, genelAnahtarHamdan, genelAnahtariCoz } from '../lib/anahtar.mjs';
import { HEDEFLER, imzaDosyasiAyristir, imzaDosyasiKur, imzaDosyasiMetni, imzaMesajiKur } from '../lib/bicim.mjs';
import { dogrula } from '../lib/imza.mjs';
import { geciciDizin, sentetikImaj, temizle } from './yardimci.mjs';

const belge = JSON.parse(fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), 'vektorler.json'), 'utf8'));
const genelHam = Buffer.from(belge.genel_anahtar_hex, 'hex');
const genelKey = genelAnahtarHamdan(genelHam);

describe('test vektorleri (vektorler.json)', () => {
  it('dosya acikca TEST olarak etiketli ve ozel anahtar icermiyor', () => {
    assert.match(belge.baslik, /TEST VEKTORLERI/);
    assert.match(belge.baslik, /URETIMDE KULLANILMAZ/);
    const ham = JSON.stringify(belge);
    assert.doesNotMatch(ham, /PRIVATE KEY/);
    assert.doesNotMatch(ham, /seed|tohum|ozel_anahtar/i);
    assert.equal(belge.format, 'KAPI-OTA-IMZA-V1');
    assert.equal(genelHam.length, 32);
    assert.equal(anahtarKimligi(genelHam), belge.anahtar_kimligi);
  });

  it('en az bir vektor her bilinen hedef icin var', () => {
    const hedefler = new Set(belge.vektorler.map((v) => v.hedef));
    for (const hedef of Object.keys(HEDEFLER)) {
      assert.ok(hedefler.has(hedef), `${hedef} vektoru eksik`);
    }
  });

  for (const v of belge.vektorler) {
    describe(`vektor ${v.ad}`, () => {
      const imaj = sentetikImaj(v.boyut, v.cip_kimligi);

      it('sentetik imaj formulu: boyut ve SHA-256 vektorle ayni', () => {
        assert.equal(imaj.length, v.boyut);
        assert.equal(crypto.createHash('sha256').update(imaj).digest('hex'), v.sha256);
        assert.equal(HEDEFLER[v.hedef].cipKimligi, v.cip_kimligi);
      });

      it('imzalanan mesaj vektordekiyle bayt-bayt ayni', () => {
        const mesaj = imzaMesajiKur({ hedef: v.hedef, surum: v.surum, boyut: v.boyut, sha256: v.sha256 });
        assert.equal(mesaj.toString('ascii'), v.mesaj);
      });

      it('Ed25519 imzasi genel anahtarla dogrulanir', () => {
        assert.equal(crypto.verify(null, Buffer.from(v.mesaj, 'ascii'), genelKey, Buffer.from(v.imza_hex, 'hex')), true);
      });

      it('mesajin ya da imzanin tek bir biti degisirse dogrulama basarisiz olur', () => {
        const mesaj = Buffer.from(v.mesaj, 'ascii');
        const imza = Buffer.from(v.imza_hex, 'hex');
        for (let i = 0; i < mesaj.length; i += 7) {
          const bozuk = Buffer.from(mesaj);
          bozuk[i] ^= 0x01;
          assert.equal(crypto.verify(null, bozuk, genelKey, imza), false, `mesaj bayti ${i}`);
        }
        for (let i = 0; i < imza.length; i += 9) {
          const bozuk = Buffer.from(imza);
          bozuk[i] ^= 0x80;
          assert.equal(crypto.verify(null, mesaj, genelKey, bozuk), false, `imza bayti ${i}`);
        }
      });

      it('aracin dogrulayicisi vektoru kabul eder; hedef/surum/boyut/ozet degisirse reddeder', () => {
        const dizin = geciciDizin();
        try {
          const imajYolu = path.join(dizin, 'firmware.bin');
          fs.writeFileSync(imajYolu, imaj);
          const sigMetni = imzaDosyasiMetni(
            imzaDosyasiKur({ hedef: v.hedef, surum: v.surum, boyut: v.boyut, sha256: v.sha256, anahtarKimligi: belge.anahtar_kimligi, imzaHex: v.imza_hex }),
          );
          const genelAnahtarlar = [genelAnahtariCoz(belge.genel_anahtar_hex)];
          const sonuc = dogrula({ imajYolu, sigMetni, genelAnahtarlar, beklenenHedef: v.hedef, beklenenSurum: v.surum });
          assert.equal(sonuc.gecti, true, JSON.stringify(sonuc.kontroller));

          const digerHedef = Object.keys(HEDEFLER).find((ad) => ad !== v.hedef);
          for (const degisiklik of [{ surum: '9.9.9' }, { hedef: digerHedef }]) {
            const sig = imzaDosyasiAyristir(sigMetni);
            const bozukMetin = imzaDosyasiMetni({ ...sig, ...('surum' in degisiklik ? { version: degisiklik.surum } : { target: degisiklik.hedef }) });
            const bozuk = dogrula({ imajYolu, sigMetni: bozukMetin, genelAnahtarlar });
            assert.equal(bozuk.gecti, false, JSON.stringify(degisiklik));
            assert.equal(bozuk.kontroller.find((k) => k.ad === 'Ed25519 imzasi').durum, 'hata');
          }
        } finally {
          temizle(dizin);
        }
      });
    });
  }
});
