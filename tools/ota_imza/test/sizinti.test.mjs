// "Ozel anahtar asla depoya / loga / teste girmez" guvenceleri:  node --test "tools/ota_imza/test/*.test.mjs"
//  1) hicbir komutun ciktisinda (basari ve hata yollari dahil) ozel anahtar ya da parola yok,
//  2) arac klasorundeki dosyalarda ozel anahtar govdesi yok,
//  3) .env.example yalniz AD tasir, DEGER tasimaz.

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { afterEach, beforeEach, describe, it } from 'node:test';
import { ARAC_KLASORU, calistir, geciciDizin, ozelTohum, sahteImaj, temizle } from './yardimci.mjs';

const PAROLA = 'cok-gizli-test-parolasi-9';

/** Ciktida aranmamasi gereken dizgeler: tohumun hex / base64 bicimleri, PEM govdesi ve govdenin tohuma bagli pencereleri. */
function yasakliDizgeler(pem) {
  const ozel = crypto.createPrivateKey({ key: pem, format: 'pem', passphrase: PAROLA });
  const tohum = ozelTohum(ozel);
  const der = ozel.export({ type: 'pkcs8', format: 'der' });
  const govde = der.toString('base64');
  const pencereler = [24, 28, 32, 36, 40].map((i) => govde.slice(i, i + 16));
  return {
    'tohum (hex)': tohum.toString('hex'),
    'tohum (base64)': tohum.toString('base64'),
    'tohum (base64url)': tohum.toString('base64url'),
    'DER (base64)': govde,
    'DER (hex)': der.toString('hex'),
    ...Object.fromEntries(pencereler.map((p, i) => [`DER penceresi ${i}`, p])),
  };
}

function ciktiTemiz(metin, yasaklilar, baglam) {
  assert.ok(!metin.includes('PRIVATE KEY'), `${baglam}: "PRIVATE KEY" basligi ciktida`);
  assert.ok(!metin.includes(PAROLA), `${baglam}: parola ciktida`);
  for (const [ad, deger] of Object.entries(yasaklilar)) {
    assert.ok(!metin.includes(deger), `${baglam}: ${ad} ciktida`);
  }
}

describe('ozel anahtar ve parola ciktilara sizmaz', () => {
  let dizin;
  beforeEach(() => {
    dizin = geciciDizin();
  });
  afterEach(() => temizle(dizin));

  for (const parolali of [false, true]) {
    it(`anahtar-uret, genel-anahtar, imzala ve dogrula (basari + hata yollari), ${parolali ? 'parolali' : 'parolasiz'} anahtar`, () => {
      const env = parolali ? { OTA_IMZA_PAROLA: PAROLA } : {};
      const yol = path.join(dizin, 'ozel.pem');
      const genel = path.join(dizin, 'genel.pem');
      const bin = path.join(dizin, 'firmware.bin');
      fs.writeFileSync(bin, sahteImaj());

      const ciktilar = [];
      const calis = (ad, argv, ek = env) => {
        const sonuc = calistir(argv, { env: ek });
        ciktilar.push([ad, `${sonuc.out}\n${sonuc.err}`]);
        return sonuc;
      };

      assert.equal(calis('anahtar-uret', ['anahtar-uret', '--ozel', yol, '--genel', genel]).kod, 0);
      const yasaklilar = yasakliDizgeler(fs.readFileSync(yol, 'utf8'));

      assert.equal(calis('genel-anahtar', ['genel-anahtar', '--ozel', yol]).kod, 0);
      assert.equal(calis('imzala', ['imzala', bin, '--hedef', 'esp32-c3', '--surum', '4.3.4', '--ozel', yol]).kod, 0);
      assert.equal(calis('dogrula', ['dogrula', bin, '--genel', genel]).kod, 0);

      // hata yollari
      fs.appendFileSync(bin, Buffer.from([1]));
      assert.equal(calis('dogrula (bozuk bin)', ['dogrula', bin, '--genel', genel]).kod, 1);
      assert.equal(calis('imzala (yanlis hedef)', ['imzala', bin, '--hedef', 'esp32-wroom', '--surum', '4.3.4', '--ozel', yol]).kod, 1);
      assert.equal(calis('imzala (olmayan dosya)', ['imzala', path.join(dizin, 'yok.bin'), '--hedef', 'esp32-c3', '--surum', '4.3.4', '--ozel', yol]).kod, 1);
      assert.equal(calis('dogrula (ozel anahtar genel diye verildi)', ['dogrula', bin, '--genel', yol]).kod, 1);
      if (parolali) {
        assert.equal(calis('imzala (parolasiz)', ['imzala', bin, '--hedef', 'esp32-c3', '--surum', '4.3.4', '--ozel', yol], {}).kod, 1);
        assert.equal(calis('imzala (yanlis parola)', ['imzala', bin, '--hedef', 'esp32-c3', '--surum', '4.3.4', '--ozel', yol], { OTA_IMZA_PAROLA: 'yanlis-parola-123' }).kod, 1);
      }
      // komut satiri parolasi reddi mesajinda parola tekrar basilmaz
      const ciplak = calis('parola bayragi', ['anahtar-uret', '--ozel', path.join(dizin, 'y.pem'), '--parola', PAROLA], {});
      assert.equal(ciplak.kod, 2);

      // imza dosyasi ve genel anahtar dosyasi
      const sig = fs.readFileSync(`${bin}.sig`, 'utf8');
      ciktilar.push(['.sig', sig], ['genel.pem', fs.readFileSync(genel, 'utf8')]);

      for (const [ad, metin] of ciktilar) {
        ciktiTemiz(metin, yasaklilar, ad);
      }
    });
  }

  it('parolali anahtarin dosya govdesinde tohum ve parola DUZ METIN olarak bulunmaz', () => {
    const yol = path.join(dizin, 'ozel.pem');
    assert.equal(calistir(['anahtar-uret', '--ozel', yol], { env: { OTA_IMZA_PAROLA: PAROLA } }).kod, 0);
    const pem = fs.readFileSync(yol, 'utf8');
    const ozel = crypto.createPrivateKey({ key: pem, format: 'pem', passphrase: PAROLA });
    const tohum = ozelTohum(ozel);
    assert.ok(!pem.includes(PAROLA));
    assert.ok(!Buffer.from(pem.replace(/-----[^-]+-----|\s+/g, ''), 'base64').includes(tohum), 'sifreli dosyada tohum acik bulunmamali');
  });
});

describe('arac klasorunde ozel anahtar bulunmaz', () => {
  const METIN_UZANTILARI = new Set(['.mjs', '.js', '.json', '.md', '.txt', '.example', '.yml', '.yaml']);

  function dosyalar(klasor) {
    const sonuc = [];
    for (const girdi of fs.readdirSync(klasor, { withFileTypes: true })) {
      const yol = path.join(klasor, girdi.name);
      if (girdi.isDirectory()) {
        if (girdi.name !== 'node_modules') sonuc.push(...dosyalar(yol));
      } else {
        sonuc.push(yol);
      }
    }
    return sonuc;
  }

  it('hicbir dosyada PEM ozel anahtar govdesi yok (BEGIN ... PRIVATE KEY basligini govde izler)', () => {
    // baslik kaynakta parcali kurulur (gizli bilgi tarayicilari bu testi ozel anahtar sanmasin)
    const desen = new RegExp(`${'-----'}BEGIN (?:ENCRYPTED |EC |RSA )?PRIVATE KEY${'-----'}\\s*[A-Za-z0-9+/=]{20,}`);
    const taranan = dosyalar(ARAC_KLASORU).filter((yol) => METIN_UZANTILARI.has(path.extname(yol)) || path.basename(yol).startsWith('.env'));
    assert.ok(taranan.length >= 8, `tarama beklenenden az dosya gordu (${taranan.length})`);
    for (const yol of taranan) {
      assert.doesNotMatch(fs.readFileSync(yol, 'utf8'), desen, `${path.relative(ARAC_KLASORU, yol)} ozel anahtar govdesi iceriyor`);
    }
  });

  it('klasorde .pem / .key / .p12 / .bin gibi anahtar ya da ikili dosya yok', () => {
    const yasakli = dosyalar(ARAC_KLASORU).filter((yol) => /\.(pem|key|p12|pfx|bin|der|sig)$/i.test(yol));
    assert.deepEqual(yasakli.map((yol) => path.relative(ARAC_KLASORU, yol)), []);
  });

  it('.env.example yalniz AD tasir: hicbir degiskenin degeri yoktur ve ozel anahtar/parola adlari tanimlidir', () => {
    const metin = fs.readFileSync(path.join(ARAC_KLASORU, '.env.example'), 'utf8');
    const atamalar = metin.split('\n').filter((satir) => /^#?\s*[A-Z][A-Z0-9_]*=/.test(satir));
    assert.ok(atamalar.length >= 2);
    for (const satir of atamalar) {
      assert.match(satir, /^#?\s*[A-Z][A-Z0-9_]*=\s*$/, `deger iceriyor: ${satir}`);
    }
    assert.match(metin, /^OTA_IMZA_OZEL_ANAHTAR=\s*$/m);
    assert.match(metin, /^#?\s*OTA_IMZA_PAROLA=\s*$/m);
  });
});
