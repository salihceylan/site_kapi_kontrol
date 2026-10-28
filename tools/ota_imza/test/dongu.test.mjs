// uret -> imzala -> dogrula dongusu ve bozuk bin / bozuk imza reddi:  node --test "tools/ota_imza/test/*.test.mjs"
// Anahtarlar calisma aninda gecici klasorde uretilir ve test bitince silinir.

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { after, before, describe, it } from 'node:test';
import { MAKS_IMAJ_BAYT, imzaDosyasiAyristir } from '../lib/bicim.mjs';
import { anahtarHazirla, calistir, geciciDizin, sahteDepoYap, sahteImaj, surecOlarakCalistir, temizle } from './yardimci.mjs';

const sha256 = (veri) => crypto.createHash('sha256').update(veri).digest('hex');

describe('uret -> imzala -> dogrula dongusu', () => {
  let kok;
  let anahtar;
  let digerAnahtar;
  let sayac = 0;

  before(() => {
    kok = geciciDizin();
    anahtar = anahtarHazirla(kok, { ad: 'ozel.pem' });
    digerAnahtar = anahtarHazirla(kok, { ad: 'diger.pem' });
  });
  after(() => temizle(kok));

  /** Yeni bir klasorde sahte imaj uretir ve CLI ile imzalar. */
  function paket({ hedef = 'esp32-c3', cip = 0x0005, surum = '4.3.4', imaj } = {}) {
    sayac += 1;
    const dizin = path.join(kok, `paket${sayac}`);
    fs.mkdirSync(dizin);
    const bin = path.join(dizin, 'firmware.bin');
    fs.writeFileSync(bin, imaj ?? sahteImaj({ cip, surumMetni: surum }));
    const imzalama = calistir(['imzala', bin, '--hedef', hedef, '--surum', surum, '--ozel', anahtar.yol]);
    assert.equal(imzalama.kod, 0, imzalama.err);
    return { dizin, bin, sig: `${bin}.sig`, imzalama };
  }

  const dogrula = (p, ekstra = [], genelYol = anahtar.genelYol) => calistir(['dogrula', p.bin, '--genel', genelYol, ...ekstra]);
  const sigOku = (p) => JSON.parse(fs.readFileSync(p.sig, 'utf8'));
  const sigDegistir = (p, degistir) => {
    const sig = sigOku(p);
    degistir(sig);
    fs.writeFileSync(p.sig, `${JSON.stringify(sig, null, 2)}\n`);
  };
  const GECMEDI = /SONUC: GECMEDI/;

  it('gercek surecler: anahtar-uret, imzala ve dogrula zinciri cikis kodlariyla calisir', () => {
    const dizin = path.join(kok, 'surec');
    fs.mkdirSync(dizin);
    const ozel = path.join(dizin, 'ozel.pem');
    const genel = path.join(dizin, 'genel.pem');
    const bin = path.join(dizin, 'firmware.bin');
    fs.writeFileSync(bin, sahteImaj({ surumMetni: '4.3.4' }));

    const uret = surecOlarakCalistir(['anahtar-uret', '--ozel', ozel, '--genel', genel]);
    assert.equal(uret.kod, 0, uret.err);
    const imzala = surecOlarakCalistir(['imzala', bin, '--hedef', 'esp32-c3', '--surum', '4.3.4', '--ozel', ozel]);
    assert.equal(imzala.kod, 0, imzala.err);
    assert.ok(fs.existsSync(`${bin}.sig`));
    const dogru = surecOlarakCalistir(['dogrula', bin, '--genel', genel]);
    assert.equal(dogru.kod, 0, dogru.out);
    assert.match(dogru.out, /SONUC: GECTI/);

    fs.appendFileSync(bin, Buffer.from([0]));
    const bozuk = surecOlarakCalistir(['dogrula', bin, '--genel', genel]);
    assert.equal(bozuk.kod, 1);
    assert.match(bozuk.out, GECMEDI);
  });

  describe('imzala', () => {
    it('.sig dosyasi imajin yaninda olusur; alanlar imajdan hesaplananlarla birebir ayni; imaj DEGISMEZ (bin sonuna blok eklenmez)', () => {
      const imaj = sahteImaj({ surumMetni: '4.3.4' });
      const p = paket({ imaj });
      assert.deepEqual(fs.readFileSync(p.bin), imaj);
      const sig = imzaDosyasiAyristir(fs.readFileSync(p.sig, 'utf8'));
      assert.equal(sig.target, 'esp32-c3');
      assert.equal(sig.version, '4.3.4');
      assert.equal(sig.size, imaj.length);
      assert.equal(sig.sha256, sha256(imaj));
      assert.equal(sig.key_id, anahtar.kimlik);
      assert.equal(sig.signature.length, 128);
      assert.ok(p.imzalama.out.includes(sig.sha256));
      assert.ok(p.imzalama.out.includes('"version": "4.3.4"'), 'manifest icin ayni degerler basilir');
    });

    it('ESP32 (WROOM) imaji esp32-wroom hedefiyle imzalanir ve dogrulanir', () => {
      const p = paket({ hedef: 'esp32-wroom', cip: 0x0000, surum: '5.2.3' });
      assert.equal(sigOku(p).target, 'esp32-wroom');
      assert.equal(sigOku(p).version, '5.2.3');
      assert.equal(dogrula(p, ['--hedef', 'esp32-wroom', '--surum', '5.2.3']).kod, 0);
      assert.equal(dogrula(p, ['--hedef', 'esp32-c3']).kod, 1);
    });

    it('imza deterministiktir: ayni girdi ayni .sig dosyasini verir', () => {
      const imaj = sahteImaj();
      const a = paket({ imaj });
      const ilk = fs.readFileSync(a.sig, 'utf8');
      const b = paket({ imaj });
      assert.equal(fs.readFileSync(b.sig, 'utf8'), ilk);
    });

    it('--cikti ile baska yola yazar; var olan ESKI imza dosyasinin yerine atomik yazar ve gecici dosya birakmaz', () => {
      const p = paket();
      const cikti = path.join(p.dizin, 'ozel-ad.sig');
      const imzalaSurum = (surum) => calistir(['imzala', p.bin, '--hedef', 'esp32-c3', '--surum', surum, '--ozel', anahtar.yol, '--cikti', cikti]);
      assert.equal(imzalaSurum('4.3.3').kod, 0);
      const eski = fs.readFileSync(cikti, 'utf8');
      const sonuc = imzalaSurum('4.3.4');
      assert.equal(sonuc.kod, 0, sonuc.err);
      assert.match(sonuc.out, /yerine yazildi/);
      assert.notEqual(fs.readFileSync(cikti, 'utf8'), eski, 'eski imza yenisiyle degisti');
      assert.equal(fs.readFileSync(cikti, 'utf8'), fs.readFileSync(p.sig, 'utf8'), '4.3.4 imzasi paket() ile ayni (deterministik)');
      assert.deepEqual(fs.readdirSync(p.dizin).filter((ad) => ad.endsWith('.tmp')), []);
      assert.equal(calistir(['dogrula', p.bin, '--sig', cikti, '--genel', anahtar.genelYol]).kod, 0);
    });

    it('--cikti, var olan baska bir dosyayi (bin, ozel anahtar, manifest, metin, klasor) ASLA ezmez', () => {
      const p = paket();
      const manifest = path.join(p.dizin, 'manifest.json');
      const notlar = path.join(p.dizin, 'notlar.txt');
      fs.writeFileSync(manifest, '{"enabled":true}');
      fs.writeFileSync(notlar, 'notlarim');
      const oncekiBin = fs.readFileSync(p.bin);
      const oncekiAnahtar = fs.readFileSync(anahtar.yol);
      for (const hedefDosya of [p.bin, anahtar.yol, manifest, notlar, p.dizin]) {
        const sonuc = calistir(['imzala', p.bin, '--hedef', 'esp32-c3', '--surum', '4.3.4', '--ozel', anahtar.yol, '--cikti', hedefDosya]);
        assert.equal(sonuc.kod, 1, hedefDosya);
        assert.match(sonuc.err, /DEGIL, uzerine yazilmaz/);
      }
      assert.deepEqual(fs.readFileSync(p.bin), oncekiBin);
      assert.deepEqual(fs.readFileSync(anahtar.yol), oncekiAnahtar);
      assert.equal(fs.readFileSync(manifest, 'utf8'), '{"enabled":true}');
      assert.equal(fs.readFileSync(notlar, 'utf8'), 'notlarim');
    });

    it('--cikti klasoru yoksa temiz hata verir ve geride gecici dosya birakmaz', () => {
      const p = paket();
      const sonuc = calistir(['imzala', p.bin, '--hedef', 'esp32-c3', '--surum', '4.3.4', '--ozel', anahtar.yol, '--cikti', path.join(p.dizin, 'yok', 'a.sig')]);
      assert.equal(sonuc.kod, 1);
      assert.match(sonuc.err, /imza dosyasi yazilamadi/);
    });

    it('C3 imaji WROOM olarak (ve tersi) imzalanamaz; imza dosyasi URETILMEZ', () => {
      for (const [cip, hedef] of [[0x0005, 'esp32-wroom'], [0x0000, 'esp32-c3']]) {
        const dizin = path.join(kok, `uyumsuz${cip}`);
        fs.mkdirSync(dizin);
        const bin = path.join(dizin, 'firmware.bin');
        fs.writeFileSync(bin, sahteImaj({ cip }));
        const sonuc = calistir(['imzala', bin, '--hedef', hedef, '--surum', '4.3.4', '--ozel', anahtar.yol]);
        assert.equal(sonuc.kod, 1, hedef);
        assert.match(sonuc.err, /UYUSMUYOR/);
        assert.ok(!fs.existsSync(`${bin}.sig`));
      }
    });

    it('ESP32 uygulama imaji olmayan dosyalar imzalanamaz (ELF, metin, kisa, bos, segment sayisi gecersiz)', () => {
      const dizin = path.join(kok, 'imajdegil');
      fs.mkdirSync(dizin);
      const ornekler = {
        'elf.bin': Buffer.concat([Buffer.from([0x7f, 0x45, 0x4c, 0x46]), crypto.randomBytes(500)]),
        'metin.bin': Buffer.from('bu bir firmware degil, duz metin dosyasi '.repeat(10)),
        'kisa.bin': Buffer.from([0xe9, 0x05, 0x00]),
        'segmentsiz.bin': Object.assign(sahteImaj(), { 1: 0 }),
        'cokSegment.bin': Object.assign(sahteImaj(), { 1: 40 }),
      };
      for (const [ad, icerik] of Object.entries(ornekler)) {
        const bin = path.join(dizin, ad);
        fs.writeFileSync(bin, icerik);
        const sonuc = calistir(['imzala', bin, '--hedef', 'esp32-c3', '--surum', '4.3.4', '--ozel', anahtar.yol]);
        assert.equal(sonuc.kod, 1, ad);
        assert.match(sonuc.err, /URETILMEDI/, ad);
        assert.ok(!fs.existsSync(`${bin}.sig`), ad);
      }
    });

    it('bos, olmayan, klasor ve cok buyuk dosya reddedilir', () => {
      const dizin = path.join(kok, 'uc-durum');
      fs.mkdirSync(dizin);
      const bos = path.join(dizin, 'bos.bin');
      fs.writeFileSync(bos, '');
      const buyuk = path.join(dizin, 'buyuk.bin');
      fs.writeFileSync(buyuk, '');
      fs.truncateSync(buyuk, MAKS_IMAJ_BAYT + 1);
      for (const yol of [bos, path.join(dizin, 'yok.bin'), dizin, buyuk]) {
        const sonuc = calistir(['imzala', yol, '--hedef', 'esp32-c3', '--surum', '4.3.4', '--ozel', anahtar.yol]);
        assert.equal(sonuc.kod, 1, yol);
        assert.ok(!fs.existsSync(`${yol}.sig`), yol);
      }
    });

    it('surum metni imajin icinde yoksa UYARI verir ama imzalar; dogrula da UYARI gosterir ve gecer', () => {
      const dizin = path.join(kok, 'surumsuz');
      fs.mkdirSync(dizin);
      const bin = path.join(dizin, 'firmware.bin');
      fs.writeFileSync(bin, sahteImaj({ surumMetni: '4.3.3' }));
      const sonuc = calistir(['imzala', bin, '--hedef', 'esp32-c3', '--surum', '4.3.4', '--ozel', anahtar.yol]);
      assert.equal(sonuc.kod, 0, sonuc.err);
      assert.match(sonuc.err, /UYARI: surum metni "4\.3\.4" imajin icinde bulunamadi/);
      const dogru = calistir(['dogrula', bin, '--genel', anahtar.genelYol]);
      assert.equal(dogru.kod, 0);
      assert.match(dogru.out, /\[UYARI\] imajdaki surum metni/);
      assert.match(dogru.out, /SONUC: GECTI/);
    });

    it('surum metni imajda varsa UYARI yoktur', () => {
      assert.equal(paket().imzalama.err, '');
    });

    it('--hedef / --surum eksik ya da gecersizse cikis 2 ve imza dosyasi yok', () => {
      const dizin = path.join(kok, 'kullanim');
      fs.mkdirSync(dizin);
      const bin = path.join(dizin, 'firmware.bin');
      fs.writeFileSync(bin, sahteImaj());
      const temel = ['imzala', bin, '--ozel', anahtar.yol];
      for (const ekstra of [
        [],
        ['--hedef', 'esp32-c3'],
        ['--surum', '4.3.4'],
        ['--hedef', 'esp32c3', '--surum', '4.3.4'],
        ['--hedef', 'esp32-c3', '--surum', '4.3'],
        ['--hedef', 'esp32-c3', '--surum', 'v4.3.4'],
        ['--hedef', 'esp32-c3', '--surum', '4.3.4\nsize=1'],
        ['--hedef', 'esp32-s3', '--surum', '4.3.4'],
      ]) {
        const sonuc = calistir([...temel, ...ekstra]);
        assert.equal(sonuc.kod, 2, JSON.stringify(ekstra));
      }
      assert.equal(calistir(['imzala', '--hedef', 'esp32-c3', '--surum', '4.3.4', '--ozel', anahtar.yol]).kod, 2, 'firmware dosyasi verilmedi');
      assert.equal(calistir(['imzala', bin, 'fazla', '--hedef', 'esp32-c3', '--surum', '4.3.4', '--ozel', anahtar.yol]).kod, 2);
      assert.ok(!fs.existsSync(`${bin}.sig`));
    });

    it('ozel anahtar yolu verilmezse cikis 2 (varsayilan yol yok); OTA_IMZA_OZEL_ANAHTAR ile imzalanir', () => {
      const dizin = path.join(kok, 'ortam');
      fs.mkdirSync(dizin);
      const bin = path.join(dizin, 'firmware.bin');
      fs.writeFileSync(bin, sahteImaj());
      const argv = ['imzala', bin, '--hedef', 'esp32-c3', '--surum', '4.3.4'];
      assert.equal(calistir(argv).kod, 2);
      assert.ok(!fs.existsSync(`${bin}.sig`));
      const sonuc = calistir(argv, { env: { OTA_IMZA_OZEL_ANAHTAR: anahtar.yol } });
      assert.equal(sonuc.kod, 0, sonuc.err);
      assert.equal(calistir(['dogrula', bin, '--genel', anahtar.genelYol]).kod, 0);
    });

    it('depo icindeki ozel anahtarla IMZALAMAYI reddeder', () => {
      const depo = path.join(kok, 'sahte-depo');
      fs.mkdirSync(depo);
      sahteDepoYap(depo);
      const icerdeki = anahtarHazirla(depo, { ad: 'sizmis.pem' });
      const bin = path.join(depo, 'firmware.bin');
      fs.writeFileSync(bin, sahteImaj());
      const sonuc = calistir(['imzala', bin, '--hedef', 'esp32-c3', '--surum', '4.3.4', '--ozel', icerdeki.yol]);
      assert.equal(sonuc.kod, 1);
      assert.match(sonuc.err, /ICINDE olamaz/);
      assert.ok(!fs.existsSync(`${bin}.sig`));
    });

    it('parolali anahtar: parola yoksa / yanlissa imzalamaz, dogruysa imzalar', () => {
      const parolali = anahtarHazirla(kok, { ad: 'parolali.pem', parola: 'uzun-ve-guclu-test-parolasi-1' });
      const dizin = path.join(kok, 'parolali');
      fs.mkdirSync(dizin);
      const bin = path.join(dizin, 'firmware.bin');
      fs.writeFileSync(bin, sahteImaj());
      const argv = ['imzala', bin, '--hedef', 'esp32-c3', '--surum', '4.3.4', '--ozel', parolali.yol];
      assert.equal(calistir(argv).kod, 1);
      assert.equal(calistir(argv, { env: { OTA_IMZA_PAROLA: 'yanlis-parola-123' } }).kod, 1);
      assert.ok(!fs.existsSync(`${bin}.sig`));
      assert.equal(calistir(argv, { env: { OTA_IMZA_PAROLA: 'uzun-ve-guclu-test-parolasi-1' } }).kod, 0);
      assert.equal(calistir(['dogrula', bin, '--genel', parolali.genelYol]).kod, 0);
    });
  });

  describe('dogrula: gecen durumlar', () => {
    it('PEM dosyasiyla, --genel-hex ile ve birden fazla anahtarla (anahtar donusu) GECER', () => {
      const p = paket();
      assert.equal(dogrula(p).kod, 0);
      const hex = calistir(['dogrula', p.bin, '--genel-hex', anahtar.hex]);
      assert.equal(hex.kod, 0, hex.out);
      assert.match(hex.out, /SONUC: GECTI/);
      const cok = calistir(['dogrula', p.bin, '--genel', digerAnahtar.genelYol, '--genel-hex', anahtar.hex.toUpperCase()]);
      assert.equal(cok.kod, 0, cok.out);
    });

    it('--hedef ve --surum capraz kontrolu uyusunca GECER, uyusmayinca GECMEZ', () => {
      const p = paket({ surum: '4.3.4' });
      assert.equal(dogrula(p, ['--hedef', 'esp32-c3', '--surum', '4.3.4']).kod, 0);
      assert.match(dogrula(p, ['--hedef', 'esp32-wroom']).out, /beklenen hedef: imza esp32-c3 icin/);
      assert.equal(dogrula(p, ['--hedef', 'esp32-wroom']).kod, 1);
      assert.match(dogrula(p, ['--surum', '4.3.5']).out, /beklenen surum: imza 4\.3\.4 surumu icin/);
      assert.equal(dogrula(p, ['--surum', '4.3.5']).kod, 1);
      assert.equal(dogrula(p, ['--surum', '4.3']).kod, 2, 'gecersiz bicim kullanim hatasi');
    });

    it('--sig ile baska yoldaki imza dosyasi kullanilir', () => {
      const p = paket();
      const tasinan = path.join(p.dizin, 'baska-yerde.sig');
      fs.renameSync(p.sig, tasinan);
      assert.equal(dogrula(p).kod, 1, 'varsayilan .sig yolu artik yok');
      assert.equal(dogrula(p, ['--sig', tasinan]).kod, 0);
    });
  });

  describe('dogrula: manifest.json capraz kontrolu (--manifest)', () => {
    const manifestYaz = (p, alanlar) => {
      const yol = path.join(p.dizin, 'manifest.json');
      fs.writeFileSync(yol, typeof alanlar === 'string' ? alanlar : JSON.stringify(alanlar, null, 2));
      return yol;
    };

    it('manifest imzayla birebir ayniysa GECER (buyuk harfli ozet de esdeger sayilir)', () => {
      const p = paket();
      const sig = sigOku(p);
      const yol = manifestYaz(p, { enabled: true, target: sig.target, version: sig.version, filename: 'firmware.bin', sha256: sig.sha256.toUpperCase() });
      const sonuc = dogrula(p, ['--manifest', yol]);
      assert.equal(sonuc.kod, 0, sonuc.out);
      for (const ad of ['manifest surumu', 'manifest sha256', 'manifest hedefi']) {
        assert.match(sonuc.out, new RegExp(`\\[TAMAM\\] ${ad}`));
      }
    });

    it('manifestteki surum, ozet ya da hedef imzadakinden farkliysa GECMEZ (cihaz da reddederdi)', () => {
      const p = paket();
      const sig = sigOku(p);
      const temel = { target: sig.target, version: sig.version, sha256: sig.sha256 };
      const farklilar = {
        'surum 4.3.5': [{ version: '4.3.5' }, /\[HATA \] manifest surumu/],
        'surum onekli v4.3.4': [{ version: 'v4.3.4' }, /\[HATA \] manifest surumu/],
        'ozet farkli': [{ sha256: 'ab'.repeat(32) }, /\[HATA \] manifest sha256/],
        'ozet yok': [{ sha256: undefined }, /\[HATA \] manifest sha256: manifest ozeti "\(yok\)"/],
        'hedef farkli': [{ target: 'esp32-wroom' }, /\[HATA \] manifest hedefi/],
      };
      for (const [ad, [degisiklik, beklenen]] of Object.entries(farklilar)) {
        const sonuc = dogrula(p, ['--manifest', manifestYaz(p, { ...temel, ...degisiklik })]);
        assert.equal(sonuc.kod, 1, ad);
        assert.match(sonuc.out, beklenen, ad);
        assert.match(sonuc.out, /\[TAMAM\] Ed25519 imzasi/, `${ad}: imza kendisi gecerli, yalniz manifest uyumsuz`);
      }
    });

    it('manifestte target alani yoksa UYARI verir ama gecer', () => {
      const p = paket();
      const sig = sigOku(p);
      const sonuc = dogrula(p, ['--manifest', manifestYaz(p, { version: sig.version, sha256: sig.sha256 })]);
      assert.equal(sonuc.kod, 0, sonuc.out);
      assert.match(sonuc.out, /\[UYARI\] manifest hedefi/);
    });

    it('manifest okunamaz, bozuk ya da nesne degilse GECMEZ', () => {
      const p = paket();
      for (const metin of ['bu json degil', '[]', 'null', '']) {
        const sonuc = dogrula(p, ['--manifest', manifestYaz(p, metin)]);
        assert.equal(sonuc.kod, 1, JSON.stringify(metin));
        assert.match(sonuc.out, /\[HATA \] manifest\.json/);
      }
      const yok = dogrula(p, ['--manifest', path.join(p.dizin, 'yok.json')]);
      assert.equal(yok.kod, 1);
      assert.match(yok.out, /\[HATA \] manifest\.json okunamadi/);
    });
  });

  describe('dogrula: BOZUK BIN reddi', () => {
    const bozucular = {
      'ortadaki bir bit': (b) => { b[5000] ^= 0x01; return b; },
      'son bayt': (b) => { b[b.length - 1] ^= 0xff; return b; },
      'ilk bayt (imaj taniticisi)': (b) => { b[0] = 0xe8; return b; },
      'sonuna 1 bayt eklenmis': (b) => Buffer.concat([b, Buffer.from([0])]),
      'son bayt kirpilmis': (b) => b.subarray(0, b.length - 1),
      'basina 1 bayt eklenmis': (b) => Buffer.concat([Buffer.from([0]), b]),
      'tamamen baska icerik (ayni boyut)': (b) => sahteImaj({ boyut: b.length - '4.3.4\0'.length, surumMetni: '4.3.4' }),
    };
    for (const [ad, boz] of Object.entries(bozucular)) {
      it(`bin degisti: ${ad}`, () => {
        const p = paket();
        fs.writeFileSync(p.bin, boz(fs.readFileSync(p.bin)));
        const sonuc = dogrula(p);
        assert.equal(sonuc.kod, 1, sonuc.out);
        assert.match(sonuc.out, GECMEDI);
        assert.match(sonuc.out, /\[HATA \] sha256: dosyanin ozeti/);
        assert.match(sonuc.out, /\[HATA \] Ed25519 imzasi: imza GECERSIZ/);
      });
    }

    it('bir imzanin baska imaja uygulanmasi (yeniden oynatma) reddedilir', () => {
      const a = paket();
      const b = paket();
      fs.copyFileSync(a.sig, b.sig);
      const sonuc = dogrula(b);
      assert.equal(sonuc.kod, 1);
      assert.match(sonuc.out, /\[HATA \] sha256/);
      assert.match(sonuc.out, /\[HATA \] Ed25519 imzasi/);
    });

    it('imza dosyasinin imaja ait olmadigi durumda ayni boyutlu farkli imaj da reddedilir', () => {
      const a = paket({ imaj: sahteImaj({ boyut: 3000 }) });
      const ayniBoyutlu = sahteImaj({ boyut: 3000 });
      assert.equal(ayniBoyutlu.length, fs.readFileSync(a.bin).length);
      fs.writeFileSync(a.bin, ayniBoyutlu);
      const sonuc = dogrula(a);
      assert.equal(sonuc.kod, 1);
      assert.match(sonuc.out, /\[TAMAM\] boyut/);
      assert.match(sonuc.out, /\[HATA \] sha256/);
    });
  });

  describe('dogrula: BOZUK IMZA reddi', () => {
    it('imza degerinin tek bir hanesi degisirse (bastan, ortadan, sondan) reddedilir', () => {
      const p = paket();
      const orijinal = sigOku(p).signature;
      for (const indeks of [0, 63, 127]) {
        const hane = orijinal[indeks] === 'a' ? 'b' : 'a';
        sigDegistir(p, (sig) => { sig.signature = orijinal.slice(0, indeks) + hane + orijinal.slice(indeks + 1); });
        const sonuc = dogrula(p);
        assert.equal(sonuc.kod, 1, `hane ${indeks}`);
        assert.match(sonuc.out, /\[HATA \] Ed25519 imzasi: imza GECERSIZ/);
        assert.match(sonuc.out, /\[TAMAM\] sha256/, 'ozet dogru, yalniz imza bozuk');
      }
    });

    it('sifir imza, baska paketin imzasi ve bos imza reddedilir', () => {
      const p = paket();
      const baska = paket();
      for (const imza of ['00'.repeat(64), sigOku(baska).signature]) {
        sigDegistir(p, (sig) => { sig.signature = imza; });
        const sonuc = dogrula(p);
        assert.equal(sonuc.kod, 1);
        assert.match(sonuc.out, /imza GECERSIZ/);
      }
      sigDegistir(p, (sig) => { sig.signature = ''; });
      const bos = dogrula(p);
      assert.equal(bos.kod, 1);
      assert.match(bos.out, /"signature" alani/);
    });

    it('imza dosyasindaki surum, hedef, boyut, ozet ya da anahtar kimligi degistirilirse reddedilir', () => {
      const degisiklikler = {
        'surum 4.3.4 -> 4.3.5 (eski bini yeni surum diye gostermek)': (sig) => { sig.version = '4.3.5'; },
        'hedef esp32-c3 -> esp32-wroom': (sig) => { sig.target = 'esp32-wroom'; },
        'boyut + 1': (sig) => { sig.size += 1; },
        'ozet degistirildi': (sig) => { sig.sha256 = 'ab'.repeat(32); },
        'anahtar kimligi degistirildi': (sig) => { sig.key_id = '0123456789abcdef'; },
      };
      for (const [ad, degistir] of Object.entries(degisiklikler)) {
        const p = paket();
        sigDegistir(p, degistir);
        const sonuc = dogrula(p);
        assert.equal(sonuc.kod, 1, ad);
        assert.match(sonuc.out, GECMEDI, ad);
      }
    });

    it('surum etiketi degistirilince imza GECERSIZ olur (eski imajin yeni surum numarasiyla yayinlanmasi)', () => {
      const p = paket({ surum: '4.3.4' });
      sigDegistir(p, (sig) => { sig.version = '9.9.9'; });
      const sonuc = dogrula(p);
      assert.equal(sonuc.kod, 1);
      assert.match(sonuc.out, /\[HATA \] Ed25519 imzasi: imza GECERSIZ/);
      assert.match(sonuc.out, /\[TAMAM\] sha256/, 'ozet dogru; yalniz surum baglantisi bozuldu');
    });

    it('imza dosyasi bozuk bicimdeyse reddedilir: cop, bos, dizi, format/algoritma, eksik alan', () => {
      const p = paket();
      const orijinal = fs.readFileSync(p.sig, 'utf8');
      const bozukMetinler = {
        cop: 'bu bir imza dosyasi degil',
        bos: '',
        dizi: '[]',
        'format V2': orijinal.replace('KAPI-OTA-IMZA-V1', 'KAPI-OTA-IMZA-V2'),
        'algoritma RSA': orijinal.replace('Ed25519', 'RSA'),
        'size alani yok': orijinal.replace(/\s*"size": \d+,/, ''),
        'yarim dosya': orijinal.slice(0, 120),
        'cok buyuk': `{"x":"${'a'.repeat(5000)}"}`,
      };
      for (const [ad, metin] of Object.entries(bozukMetinler)) {
        fs.writeFileSync(p.sig, metin);
        const sonuc = dogrula(p);
        assert.equal(sonuc.kod, 1, ad);
        assert.match(sonuc.out, /\[HATA \] imza dosyasi/, ad);
        assert.match(sonuc.out, GECMEDI, ad);
      }
    });

    it('cok buyuk imza ya da manifest dosyasi bellege alinmadan reddedilir', () => {
      const p = paket();
      const orijinal = fs.readFileSync(p.sig, 'utf8');
      fs.writeFileSync(p.sig, 'x'.repeat(100 * 1024));
      const buyukSig = dogrula(p);
      assert.equal(buyukSig.kod, 1);
      assert.match(buyukSig.out, /\[HATA \] imza dosyasi beklenenden cok buyuk/);
      const yol = path.join(p.dizin, 'manifest.json');
      fs.writeFileSync(yol, ' '.repeat(2 * 1024 * 1024));
      fs.writeFileSync(p.sig, orijinal);
      const buyukManifest = dogrula(p, ['--manifest', yol]);
      assert.equal(buyukManifest.kod, 1);
      assert.match(buyukManifest.out, /\[HATA \] manifest\.json beklenenden cok buyuk/);
    });

    it('imza dosyasi hic yoksa reddedilir (imzasiz yayin yok)', () => {
      const p = paket();
      fs.rmSync(p.sig);
      const sonuc = dogrula(p);
      assert.equal(sonuc.kod, 1);
      assert.match(sonuc.out, /\[HATA \] imza dosyasi okunamadi/);
      assert.match(sonuc.out, GECMEDI);
    });

    it('baska bir anahtarin imzasi reddedilir (yanlis genel anahtar ve anahtar kimligi uyusmazligi)', () => {
      const p = paket();
      const sonuc = dogrula(p, [], digerAnahtar.genelYol);
      assert.equal(sonuc.kod, 1);
      assert.match(sonuc.out, /\[HATA \] anahtar kimligi: imza /);
      assert.match(sonuc.out, /\[HATA \] Ed25519 imzasi: dogrulanamadi/);
      const hex = calistir(['dogrula', p.bin, '--genel-hex', digerAnahtar.hex]);
      assert.equal(hex.kod, 1);
    });

    it('saldirgan kendi anahtariyla imzalayip key_id\'yi taklit ederse reddedilir', () => {
      const p = paket();
      // saldirgan: kendi anahtariyla ayni mesaji imzalar ve key_id'yi mesru anahtarinki yapar
      const sig = sigOku(p);
      const mesaj = Buffer.from(`KAPI-OTA-IMZA-V1\ntarget=${sig.target}\nversion=${sig.version}\nsize=${sig.size}\nsha256=${sig.sha256}\n`, 'ascii');
      sig.signature = crypto.sign(null, mesaj, digerAnahtar.ozel).toString('hex');
      fs.writeFileSync(p.sig, `${JSON.stringify(sig, null, 2)}\n`);
      const sonuc = dogrula(p);
      assert.equal(sonuc.kod, 1);
      assert.match(sonuc.out, /\[HATA \] Ed25519 imzasi: imza GECERSIZ/);
    });

    it('hicbiri eslesmeyen anahtar listesi reddedilir', () => {
      const p = paket();
      const sonuc = calistir(['dogrula', p.bin, '--genel', digerAnahtar.genelYol, '--genel-hex', 'ab'.repeat(32)]);
      assert.equal(sonuc.kod, 1);
    });
  });

  describe('dogrula: komut satiri hatalari', () => {
    it('genel anahtar / dosya verilmezse cikis 2; OZEL anahtar dosyasi genel anahtar yerine verilirse reddedilir', () => {
      const p = paket();
      assert.equal(calistir(['dogrula', p.bin]).kod, 2);
      assert.equal(calistir(['dogrula']).kod, 2);
      assert.equal(calistir(['dogrula', p.bin, '--genel-hex', 'abc']).kod, 2);
      const ozelVerildi = calistir(['dogrula', p.bin, '--genel', anahtar.yol]);
      assert.equal(ozelVerildi.kod, 1);
      assert.match(ozelVerildi.err, /OZEL anahtar/);
      assert.equal(calistir(['dogrula', p.bin, '--genel', path.join(kok, 'yok.pem')]).kod, 1);
    });

    it('bilinmeyen komut / bayrak cikis 2; yardim cikis 0', () => {
      assert.equal(calistir(['bilinmeyen']).kod, 2);
      assert.equal(calistir(['constructor']).kod, 2);
      assert.equal(calistir([]).kod, 2);
      const yardim = calistir(['yardim']);
      assert.equal(yardim.kod, 0);
      assert.match(yardim.out, /anahtar-uret/);
      assert.match(yardim.out, /OTA_IMZA_OZEL_ANAHTAR/);
      assert.equal(calistir(['dogrula', 'x.bin', '--genel', 'y.pem', '--bilinmeyen']).kod, 2);
    });

    it('hata mesajlarinda kullanici girdisindeki denetim karakterleri (C0 ve C1) etkisizlestirilir', () => {
      const sonuc = calistir(['bilinmeyen\u001b[31m\u009b31mKIRMIZI']);
      assert.equal(sonuc.kod, 2);
      assert.ok(!sonuc.err.includes('\u001b'), 'ESC (C0) ciktiya girmemeli');
      assert.ok(!sonuc.err.includes('\u009b'), 'CSI (C1) ciktiya girmemeli');
      assert.match(sonuc.err, /KIRMIZI/);
    });
  });
});
