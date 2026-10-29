// Imzali SURUM DUSURME yetkisi (rollback_max): mesaj, .sig dosyasi, komut satiri ve bilinen-cevap vektoru:
//   node --test "tools/ota_imza/test/*.test.mjs"
// Varsayilan imza HICBIR surum dusurmeyi yetkilendirmez; rollback_max yalniz `imzala --rollback-max` ile, bilincli olarak eklenir.
// Cihaz ve sunucu ayni bicimi uygular (tek etiket KAPI-OTA-IMZA-V1; rollback_max mesajin istege bagli SON satiridir).

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { after, before, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { genelAnahtarHamdan, genelAnahtariCoz } from '../lib/anahtar.mjs';
import { imzaDosyasiAyristir, imzaDosyasiKur, imzaDosyasiMetni, imzaMesajiKur, surumKarsilastir } from '../lib/bicim.mjs';
import { IslemHatasi } from '../lib/hata.mjs';
import { dogrula } from '../lib/imza.mjs';
import { anahtarHazirla, calistir, geciciDizin, sahteImaj, sentetikImaj, temizle } from './yardimci.mjs';

const SHA = 'ab'.repeat(32);
const IMZA = 'cd'.repeat(64);
const KIMLIK = '0123456789abcdef';
const TEMEL = { hedef: 'esp32-wroom', surum: '5.2.2', boyut: 1826304, sha256: SHA };

describe('rollback_max: imza mesaji', () => {
  it('rollback_max mesajin SON satiri olur; verilmezse mesaj eskisiyle bayt-bayt ayni kalir', () => {
    const yok = imzaMesajiKur(TEMEL);
    const var_ = imzaMesajiKur({ ...TEMEL, rollbackMax: '5.3.0' });
    assert.equal(yok.toString('latin1'), `KAPI-OTA-IMZA-V1\ntarget=esp32-wroom\nversion=5.2.2\nsize=1826304\nsha256=${SHA}\n`);
    assert.equal(var_.toString('latin1'), `${yok.toString('latin1')}rollback_max=5.3.0\n`);
    assert.equal(var_.at(-1), 0x0a, 'mesaj LF ile biter');
    assert.equal(var_.toString('ascii').split('\n').length, 7, '6 satir + son LF');
    assert.ok(!var_.includes(0x0d), 'CR yok');
    assert.equal(imzaMesajiKur({ ...TEMEL, rollbackMax: undefined }).toString('latin1'), yok.toString('latin1'), 'undefined = verilmedi');
  });

  const gecersizler = ['v5.3.0', '5.3', '', null, 5.3, '5.3.0\nsha256=x', ' 5.3.0', '5.3.0-beta', '05.3.0', ['5.3.0']];
  for (const deger of gecersizler) {
    it(`gecersiz rollback_max reddedilir: ${JSON.stringify(deger)}`, () => {
      assert.throws(() => imzaMesajiKur({ ...TEMEL, rollbackMax: deger }), IslemHatasi);
    });
  }

  it('rollback_max farkli olunca mesaj degisir; var / yok ayrimi imzayi gecersiz kilar (alan ayirma)', () => {
    const { privateKey, publicKey } = crypto.generateKeyPairSync('ed25519');
    const a = imzaMesajiKur({ ...TEMEL, rollbackMax: '5.3.0' });
    const b = imzaMesajiKur({ ...TEMEL, rollbackMax: '5.3.1' });
    const c = imzaMesajiKur(TEMEL);
    assert.notDeepEqual(a, b);
    const imza = crypto.sign(null, a, privateKey);
    assert.equal(crypto.verify(null, a, publicKey, imza), true);
    assert.equal(crypto.verify(null, b, publicKey, imza), false, 'kapsam genisletme reddedilir');
    assert.equal(crypto.verify(null, c, publicKey, imza), false, 'rollback_max kaldirilinca reddedilir');
    assert.equal(crypto.verify(null, a, publicKey, crypto.sign(null, c, privateKey)), false, 'rollback_max eklenince reddedilir');
  });
});

describe('surumKarsilastir', () => {
  const durumlar = [
    ['4.3.4', '4.3.5', -1],
    ['4.3.10', '4.3.9', 1],
    ['4.3.4', '4.3.4', 0],
    ['4.3.4', '4.3.4.0', 0],
    ['4.3.4.1', '4.3.4', 1],
    ['10.0.0', '9.9.9', 1],
    ['0.0.0', '0.0.1', -1],
    ['9999.9999.9999', '9999.9999.9998', 1],
  ];
  for (const [a, b, beklenen] of durumlar) {
    it(`${a} ? ${b} = ${beklenen}`, () => {
      assert.equal(surumKarsilastir(a, b), beklenen);
      assert.equal(surumKarsilastir(b, a), -beklenen || 0);
    });
  }

  it('gecersiz surum IslemHatasi atar', () => {
    assert.throws(() => surumKarsilastir('4.3', '4.3.4'), IslemHatasi);
    assert.throws(() => surumKarsilastir('4.3.4', 'v4.3.5'), IslemHatasi);
  });
});

describe('rollback_max: .sig dosyasi', () => {
  it('kur / metin / ayristir: rollback_max sha256 ile key_id arasinda yer alir; verilmezse alan HIC yoktur', () => {
    const ile = imzaDosyasiKur({ ...TEMEL, anahtarKimligi: KIMLIK, imzaHex: IMZA, rollbackMax: '5.3.0' });
    assert.deepEqual(Object.keys(ile), ['format', 'algorithm', 'target', 'version', 'size', 'sha256', 'rollback_max', 'key_id', 'signature']);
    assert.deepEqual(imzaDosyasiAyristir(imzaDosyasiMetni(ile)), ile);

    const yok = imzaDosyasiKur({ ...TEMEL, anahtarKimligi: KIMLIK, imzaHex: IMZA });
    assert.deepEqual(Object.keys(yok), ['format', 'algorithm', 'target', 'version', 'size', 'sha256', 'key_id', 'signature']);
    assert.ok(!Object.hasOwn(imzaDosyasiAyristir(imzaDosyasiMetni(yok)), 'rollback_max'));
  });

  for (const deger of [null, '', 5, 'v5.3.0', '5.3', '5.3.0\n', ['5.3.0'], {}]) {
    it(`ayristir: gecersiz rollback_max reddedilir (${JSON.stringify(deger)}) ve hata alan adini soyler`, () => {
      const sig = { ...imzaDosyasiKur({ ...TEMEL, anahtarKimligi: KIMLIK, imzaHex: IMZA }), rollback_max: deger };
      assert.throws(() => imzaDosyasiAyristir(JSON.stringify(sig)), (hata) => hata instanceof IslemHatasi && /"rollback_max"/.test(hata.message));
    });
  }
});

describe('rollback_max: imzala / dogrula (komut satiri)', () => {
  let kok;
  let anahtar;
  let sayac = 0;
  before(() => {
    kok = geciciDizin();
    anahtar = anahtarHazirla(kok);
  });
  after(() => temizle(kok));

  function yeniPaket({ surum = '5.2.2', hedef = 'esp32-wroom', cip = 0x0000 } = {}) {
    sayac += 1;
    const dizin = path.join(kok, `paket${sayac}`);
    fs.mkdirSync(dizin);
    const bin = path.join(dizin, 'firmware.bin');
    fs.writeFileSync(bin, sahteImaj({ cip, surumMetni: surum }));
    return { dizin, bin, sig: `${bin}.sig`, hedef, surum };
  }
  const imzala = (p, ekstra = []) => calistir(['imzala', p.bin, '--hedef', p.hedef, '--surum', p.surum, '--ozel', anahtar.yol, ...ekstra]);
  const dogrulaCli = (p, ekstra = []) => calistir(['dogrula', p.bin, '--genel', anahtar.genelYol, ...ekstra]);
  const sigOku = (p) => JSON.parse(fs.readFileSync(p.sig, 'utf8'));
  const sigYaz = (p, sig) => fs.writeFileSync(p.sig, `${JSON.stringify(sig, null, 2)}\n`);

  it('imzala --rollback-max: .sig rollback_max tasir; cikti dusurme yetkisini ve manifest satirini acikca yazar; dogrula GECTI + UYARI', () => {
    const p = yeniPaket();
    const sonuc = imzala(p, ['--rollback-max', '5.3.0']);
    assert.equal(sonuc.kod, 0, sonuc.err);
    assert.match(sonuc.out, /SURUM DUSURME YETKISI/);
    assert.match(sonuc.out, /"rollback_max": "5\.3\.0"/);
    assert.match(sonuc.err, /BU IMZA SURUM DUSURME YETKISI TASIR/);
    const sig = imzaDosyasiAyristir(fs.readFileSync(p.sig, 'utf8'));
    assert.equal(sig.rollback_max, '5.3.0');
    assert.equal(sig.version, '5.2.2');

    const d = dogrulaCli(p, ['--surum', '5.2.2']);
    assert.equal(d.kod, 0, d.out);
    assert.match(d.out, /SONUC: GECTI/);
    assert.match(d.out, /\[UYARI\] surum dusurme yetkisi: .*5\.3\.0/);
  });

  it('bayraksiz imza HICBIR dusurmeyi yetkilendirmez: .sig rollback_max tasimaz, imzasi farklidir', () => {
    const p = yeniPaket();
    assert.equal(imzala(p).kod, 0);
    const yok = sigOku(p);
    assert.ok(!Object.hasOwn(yok, 'rollback_max'));
    const d = dogrulaCli(p);
    assert.equal(d.kod, 0, d.out);
    assert.doesNotMatch(d.out, /dusurme yetkisi/);
    assert.equal(imzala(p, ['--rollback-max', '5.3.0']).kod, 0);
    assert.notEqual(sigOku(p).signature, yok.signature, 'rollback_max imzayi degistirir');
  });

  it('rollback_max, surumden BUYUK olmali; esit / kucuk ise cikis 1 ve .sig YAZILMAZ', () => {
    for (const deger of ['5.2.2', '5.2.1', '5.2.2.0', '1.0.0']) {
      const p = yeniPaket();
      const sonuc = imzala(p, ['--rollback-max', deger]);
      assert.equal(sonuc.kod, 1, deger);
      assert.match(sonuc.err, /rollback_max .* BUYUK olmali/);
      assert.ok(!fs.existsSync(p.sig), `${deger}: .sig yazilmamali`);
    }
    const buyuk = yeniPaket();
    assert.equal(imzala(buyuk, ['--rollback-max', '5.2.2.1']).kod, 0, '4. parca ile buyuk olan kabul edilir');
  });

  it('gecersiz --rollback-max komut satiri hatasidir (cikis 2); deger istemeyen kullanim da', () => {
    for (const deger of ['v5.3.0', '5.3', 'abc', '5.3.0-beta', '05.3.0']) {
      const p = yeniPaket();
      const sonuc = imzala(p, ['--rollback-max', deger]);
      assert.equal(sonuc.kod, 2, deger);
      assert.match(sonuc.err, /rollback_max gecersiz/);
      assert.ok(!fs.existsSync(p.sig));
    }
    const p = yeniPaket();
    assert.equal(imzala(p, ['--rollback-max']).kod, 2);
  });

  it('.sig uzerinde oynama: rollback_max eklemek / degistirmek / kaldirmak imzayi GECERSIZ kilar', () => {
    const p = yeniPaket();
    assert.equal(imzala(p, ['--rollback-max', '5.3.0']).kod, 0);
    const asil = sigOku(p);

    sigYaz(p, { ...asil, rollback_max: '5.9.9' });
    assert.match(dogrulaCli(p).out, /SONUC: GECMEDI/);

    const { rollback_max: _atilan, ...kaldirilmis } = asil;
    sigYaz(p, kaldirilmis);
    assert.match(dogrulaCli(p).out, /SONUC: GECMEDI/);

    sigYaz(p, asil);
    assert.match(dogrulaCli(p).out, /SONUC: GECTI/);

    // rollback_max'siz imzaya sonradan yetki eklemek
    const q = yeniPaket();
    assert.equal(imzala(q).kod, 0);
    sigYaz(q, { ...sigOku(q), rollback_max: '5.3.0' });
    const sonuc = dogrulaCli(q);
    assert.equal(sonuc.kod, 1);
    assert.match(sonuc.out, /\[HATA \] Ed25519 imzasi/);
  });

  it('--manifest: manifestteki rollback_max imzadakiyle birebir ayni olmali (cihaz degeri manifestten alir)', () => {
    const p = yeniPaket();
    assert.equal(imzala(p, ['--rollback-max', '5.3.0']).kod, 0);
    const sig = sigOku(p);
    const manifest = path.join(p.dizin, 'manifest.json');
    const yaz = (ek) => fs.writeFileSync(manifest, JSON.stringify({ version: sig.version, sha256: sig.sha256, target: sig.target, ...ek }));

    yaz({ rollback_max: '5.3.0' });
    const tamam = dogrulaCli(p, ['--manifest', manifest]);
    assert.equal(tamam.kod, 0, tamam.out);
    assert.match(tamam.out, /\[TAMAM\] manifest rollback_max: 5\.3\.0/);

    yaz({});
    const eksik = dogrulaCli(p, ['--manifest', manifest]);
    assert.equal(eksik.kod, 1);
    assert.match(eksik.out, /\[HATA \] manifest rollback_max/);

    yaz({ rollback_max: '5.4.0' });
    assert.equal(dogrulaCli(p, ['--manifest', manifest]).kod, 1);

    // imza rollback tasimiyorsa manifestte de olmamali
    const q = yeniPaket();
    assert.equal(imzala(q).kod, 0);
    const qs = sigOku(q);
    const qm = path.join(q.dizin, 'manifest.json');
    fs.writeFileSync(qm, JSON.stringify({ version: qs.version, sha256: qs.sha256, target: qs.target, rollback_max: '5.3.0' }));
    assert.equal(dogrulaCli(q, ['--manifest', qm]).kod, 1);
    fs.writeFileSync(qm, JSON.stringify({ version: qs.version, sha256: qs.sha256, target: qs.target }));
    assert.equal(dogrulaCli(q, ['--manifest', qm]).kod, 0);
  });

  it('imza dosyasi / imaj / hedef / surum alanlari rollback_max imzasinda da baglidir', () => {
    const p = yeniPaket();
    assert.equal(imzala(p, ['--rollback-max', '5.3.0']).kod, 0);
    const asil = sigOku(p);
    for (const degisiklik of [{ version: '5.2.3' }, { target: 'esp32-c3' }, { size: asil.size + 1 }, { sha256: 'ef'.repeat(32) }]) {
      sigYaz(p, { ...asil, ...degisiklik });
      assert.equal(dogrulaCli(p).kod, 1, JSON.stringify(degisiklik));
    }
    sigYaz(p, asil);
    fs.appendFileSync(p.bin, Buffer.from([0]));
    assert.equal(dogrulaCli(p).kod, 1, 'bozuk bin');
  });
});

describe('rollback_max: bilinen-cevap vektoru (vektorler.json -> rollback_vektoru)', () => {
  const belge = JSON.parse(fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), 'vektorler.json'), 'utf8'));
  const v = belge.rollback_vektoru;
  const genelKey = genelAnahtarHamdan(Buffer.from(v.genel_anahtar_hex, 'hex'));

  it('vektor acik veridir: kendi genel anahtari var, ozel anahtar / tohum yok', () => {
    assert.equal(v.rollback_max, '5.3.0');
    assert.notEqual(v.genel_anahtar_hex, belge.genel_anahtar_hex, 'ana vektorlerden AYRI anahtar');
    assert.doesNotMatch(JSON.stringify(v), /PRIVATE KEY|seed|tohum|ozel_anahtar/i);
    assert.equal(genelAnahtariCoz(v.genel_anahtar_hex).kimlik, v.anahtar_kimligi);
  });

  it('imzalanan mesaj vektordekiyle bayt-bayt ayni; Ed25519 imzasi dogrulanir', () => {
    const mesaj = imzaMesajiKur({ hedef: v.hedef, surum: v.surum, boyut: v.boyut, sha256: v.sha256, rollbackMax: v.rollback_max });
    assert.equal(mesaj.toString('ascii'), v.mesaj);
    assert.equal(crypto.verify(null, mesaj, genelKey, Buffer.from(v.imza_hex, 'hex')), true);
  });

  it('rollback_max satiri olmadan / baska degerle / tek bit bozulmus mesajla dogrulama basarisiz olur', () => {
    const imza = Buffer.from(v.imza_hex, 'hex');
    const temel = { hedef: v.hedef, surum: v.surum, boyut: v.boyut, sha256: v.sha256 };
    assert.equal(crypto.verify(null, imzaMesajiKur(temel), genelKey, imza), false);
    assert.equal(crypto.verify(null, imzaMesajiKur({ ...temel, rollbackMax: '5.3.1' }), genelKey, imza), false);
    const mesaj = Buffer.from(v.mesaj, 'ascii');
    for (let i = 0; i < mesaj.length; i += 5) {
      const bozuk = Buffer.from(mesaj);
      bozuk[i] ^= 0x01;
      assert.equal(crypto.verify(null, bozuk, genelKey, imza), false, `mesaj bayti ${i}`);
    }
  });

  it('aracin dogrulayicisi vektoru kabul eder; rollback_max kaldirilirsa reddeder', () => {
    const dizin = geciciDizin();
    try {
      const imajYolu = path.join(dizin, 'firmware.bin');
      const imaj = sentetikImaj(v.boyut, v.cip_kimligi);
      assert.equal(crypto.createHash('sha256').update(imaj).digest('hex'), v.sha256);
      fs.writeFileSync(imajYolu, imaj);
      const sig = imzaDosyasiKur({
        hedef: v.hedef, surum: v.surum, boyut: v.boyut, sha256: v.sha256, anahtarKimligi: v.anahtar_kimligi, imzaHex: v.imza_hex, rollbackMax: v.rollback_max,
      });
      const genelAnahtarlar = [genelAnahtariCoz(v.genel_anahtar_hex)];
      const kabul = dogrula({ imajYolu, sigMetni: imzaDosyasiMetni(sig), genelAnahtarlar });
      assert.equal(kabul.gecti, true, JSON.stringify(kabul.kontroller));
      assert.ok(kabul.kontroller.some((k) => k.ad === 'surum dusurme yetkisi' && k.durum === 'uyari'));

      const { rollback_max: _atilan, ...kaldirilmis } = sig;
      const red = dogrula({ imajYolu, sigMetni: imzaDosyasiMetni(kaldirilmis), genelAnahtarlar });
      assert.equal(red.gecti, false);
    } finally {
      temizle(dizin);
    }
  });
});
