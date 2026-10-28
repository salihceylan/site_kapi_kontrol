// Anahtar uretimi ve OZEL anahtar korumalari:  node --test "tools/ota_imza/test/*.test.mjs"
// Testler anahtari calisma aninda uretir (gecici klasor); depoda sabit ozel anahtar yoktur.

import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { afterEach, beforeEach, describe, it } from 'node:test';
import {
  PEM_ETIKET,
  anahtarCiftiUret,
  depoIcindeMi,
  genelAnahtariCoz,
  genelBilgi,
  ozelAnahtariOku,
  ozelAnahtariYaz,
  projeKokleri,
} from '../lib/anahtar.mjs';
import { ARAC_KLASORU, DEPO_KOKU, anahtarHazirla, calistir, geciciDizin, sahteDepoYap, temizle } from './yardimci.mjs';

const PAROLA = 'uzun-ve-guclu-test-parolasi-1';
// PEM basliklari kaynakta PARCALI kurulur (gizli bilgi tarayicilari testi ozel anahtar sanmasin); bkz. lib/anahtar.mjs
const TIRE = '-----';
const PEM_OZEL_SON = `${TIRE}END PRIVATE KEY${TIRE}`;
const PEM_GENEL_SON = `${TIRE}END PUBLIC KEY${TIRE}`;

describe('anahtar-uret', () => {
  let dizin;
  beforeEach(() => {
    dizin = geciciDizin();
  });
  afterEach(() => temizle(dizin));

  it('yol verilmezse REDDEDER (cikis 2), varsayilan yol YOKTUR ve hicbir dosya olusmaz', () => {
    const sonuc = calistir(['anahtar-uret'], { cwd: dizin });
    assert.equal(sonuc.kod, 2);
    assert.match(sonuc.err, /varsayilan bir yol YOKTUR/);
    assert.deepEqual(fs.readdirSync(dizin), []);
    assert.equal(sonuc.out, '');
  });

  it('bos OTA_IMZA_OZEL_ANAHTAR yol verilmemis sayilir', () => {
    for (const bos of ['', '   ']) {
      const sonuc = calistir(['anahtar-uret'], { cwd: dizin, env: { OTA_IMZA_OZEL_ANAHTAR: bos } });
      assert.equal(sonuc.kod, 2, JSON.stringify(bos));
    }
    assert.deepEqual(fs.readdirSync(dizin), []);
  });

  it('yol OTA_IMZA_OZEL_ANAHTAR ortam degiskeninden de alinir; --ozel bayragi ortam degiskeninden ustundur', () => {
    const ortamYolu = path.join(dizin, 'ortamdan.pem');
    const bayrakYolu = path.join(dizin, 'bayraktan.pem');
    assert.equal(calistir(['anahtar-uret'], { env: { OTA_IMZA_OZEL_ANAHTAR: ortamYolu } }).kod, 0);
    assert.ok(fs.existsSync(ortamYolu));
    assert.equal(calistir(['anahtar-uret', '--ozel', bayrakYolu], { env: { OTA_IMZA_OZEL_ANAHTAR: path.join(dizin, 'kullanilmamali.pem') } }).kod, 0);
    assert.ok(fs.existsSync(bayrakYolu));
    assert.ok(!fs.existsSync(path.join(dizin, 'kullanilmamali.pem')));
  });

  it('goreli --ozel yolu cwd\'ye gore cozulur', () => {
    assert.equal(calistir(['anahtar-uret', '--ozel', 'goreli.pem'], { cwd: dizin }).kod, 0);
    assert.ok(fs.existsSync(path.join(dizin, 'goreli.pem')));
  });

  it('ozel anahtar parolasiz PKCS#8 PEM olarak yazilir, Ed25519 ve (POSIX\'te) yalniz sahibi okur', () => {
    const yol = path.join(dizin, 'ozel.pem');
    const sonuc = calistir(['anahtar-uret', '--ozel', yol]);
    assert.equal(sonuc.kod, 0, sonuc.err);
    const pem = fs.readFileSync(yol, 'utf8');
    assert.ok(pem.startsWith(`${PEM_ETIKET.ozel}\n`) && pem.endsWith(`\n${PEM_OZEL_SON}\n`), 'PKCS#8 PEM (sifresiz)');
    assert.match(pem.slice(PEM_ETIKET.ozel.length, pem.length - PEM_OZEL_SON.length - 1), /^[A-Za-z0-9+/=\n]+$/);
    assert.equal(crypto.createPrivateKey(pem).asymmetricKeyType, 'ed25519');
    if (process.platform !== 'win32') {
      assert.equal(fs.statSync(yol).mode & 0o777, 0o600);
    }
    assert.match(sonuc.out, /PAROLASIZ/);
  });

  it('genel anahtar PEM, hex, key_id ve C++ tanimi olarak basilir ve diskteki anahtarla tutarlidir', () => {
    const yol = path.join(dizin, 'ozel.pem');
    const sonuc = calistir(['anahtar-uret', '--ozel', yol]);
    const beklenen = genelBilgi(crypto.createPublicKey(ozelAnahtariOku(yol).key));
    assert.ok(sonuc.out.includes(beklenen.hex));
    assert.ok(sonuc.out.includes(beklenen.kimlik));
    assert.ok(sonuc.out.includes(PEM_ETIKET.genel));
    assert.ok(sonuc.out.includes('OTA_IMZA_GENEL_ANAHTAR[32]'));
    const bayt = [...sonuc.out.matchAll(/0x([0-9a-f]{2})/g)].map((e) => e[1]).join('');
    assert.equal(bayt, beklenen.hex, 'C++ tanimindaki 32 bayt = genel anahtar');
    assert.equal(beklenen.hex.length, 64);
    assert.match(sonuc.out, /yedekleyin/i, 'yedekleme uyarisi basilir');
  });

  it('var olan dosyanin uzerine ASLA yazmaz (cikis 1, icerik degismez)', () => {
    const yol = path.join(dizin, 'ozel.pem');
    fs.writeFileSync(yol, 'MEVCUT-ICERIK');
    const sonuc = calistir(['anahtar-uret', '--ozel', yol]);
    assert.equal(sonuc.kod, 1);
    assert.match(sonuc.err, /ZATEN VAR/);
    assert.equal(fs.readFileSync(yol, 'utf8'), 'MEVCUT-ICERIK');
  });

  it('ikinci uretim ilk anahtari ezmez', () => {
    const yol = path.join(dizin, 'ozel.pem');
    assert.equal(calistir(['anahtar-uret', '--ozel', yol]).kod, 0);
    const ilk = fs.readFileSync(yol, 'utf8');
    assert.equal(calistir(['anahtar-uret', '--ozel', yol]).kod, 1);
    assert.equal(fs.readFileSync(yol, 'utf8'), ilk);
  });

  it('iki uretim farkli anahtar verir (rastgelelik)', () => {
    const a = calistir(['anahtar-uret', '--ozel', path.join(dizin, 'a.pem')]);
    const b = calistir(['anahtar-uret', '--ozel', path.join(dizin, 'b.pem')]);
    assert.notEqual(fs.readFileSync(path.join(dizin, 'a.pem'), 'utf8'), fs.readFileSync(path.join(dizin, 'b.pem'), 'utf8'));
    assert.notEqual(a.out.match(/hex\s+: ([0-9a-f]{64})/)[1], b.out.match(/hex\s+: ([0-9a-f]{64})/)[1]);
  });

  it('ust klasor yoksa reddeder (kendiliginden klasor acmaz)', () => {
    const yol = path.join(dizin, 'yok', 'ozel.pem');
    const sonuc = calistir(['anahtar-uret', '--ozel', yol]);
    assert.equal(sonuc.kod, 1);
    assert.match(sonuc.err, /klasoru yok/);
    assert.ok(!fs.existsSync(path.join(dizin, 'yok')));
  });

  it('git deposunun ICINDEKI yolu reddeder ve dosya olusturmaz (var olan ve olmayan alt klasor)', () => {
    const depo = path.join(dizin, 'depo');
    fs.mkdirSync(path.join(depo, 'alt'), { recursive: true });
    sahteDepoYap(depo);
    for (const yol of [path.join(depo, 'ozel.pem'), path.join(depo, 'alt', 'ozel.pem'), path.join(depo, 'olmayan', 'derin', 'ozel.pem')]) {
      const sonuc = calistir(['anahtar-uret', '--ozel', yol]);
      assert.equal(sonuc.kod, 1, yol);
      assert.match(sonuc.err, /ICINDE olamaz/);
      assert.ok(!fs.existsSync(yol), yol);
    }
  });

  it('".." ile depodan cikan yol depo disi sayilir; depoya giren ".." yolu reddedilir', () => {
    const depo = path.join(dizin, 'depo');
    fs.mkdirSync(depo);
    fs.mkdirSync(path.join(dizin, 'baska'));
    sahteDepoYap(depo);
    // path.join ".." parcalarini sadelestirdigi icin yollar bilerek dizge birlestirmeyle kurulur
    const disari = `${depo}${path.sep}..${path.sep}disarida.pem`;
    assert.equal(calistir(['anahtar-uret', '--ozel', disari]).kod, 0);
    assert.ok(fs.existsSync(path.join(dizin, 'disarida.pem')));
    const iceri = `${dizin}${path.sep}baska${path.sep}..${path.sep}depo${path.sep}iceride.pem`;
    assert.equal(calistir(['anahtar-uret', '--ozel', iceri]).kod, 1);
    assert.ok(!fs.existsSync(path.join(depo, 'iceride.pem')));
  });

  it('git "worktree" gibi .git DOSYASI iceren klasorun icini de reddeder', () => {
    const depo = path.join(dizin, 'worktree');
    fs.mkdirSync(depo);
    fs.writeFileSync(path.join(depo, '.git'), 'gitdir: /baska/yer\n');
    const sonuc = calistir(['anahtar-uret', '--ozel', path.join(depo, 'ozel.pem')]);
    assert.equal(sonuc.kod, 1);
    assert.ok(!fs.existsSync(path.join(depo, 'ozel.pem')));
  });

  it('bu deponun kendi klasoru icine yazmayi reddeder (arac, test ve kok dahil)', () => {
    for (const goreli of ['ozel_deneme.pem', path.join('tools', 'ota_imza', 'ozel_deneme.pem'), path.join('server', 'ozel_deneme.pem')]) {
      const yol = path.join(DEPO_KOKU, goreli);
      try {
        const sonuc = calistir(['anahtar-uret', '--ozel', yol]);
        assert.equal(sonuc.kod, 1, goreli);
        assert.ok(!fs.existsSync(yol), `${goreli} OLUSTURULMAMALI`);
      } finally {
        fs.rmSync(yol, { force: true }); // koruma bozulsa bile depoda ozel anahtar kalmasin
      }
    }
  });

  it('sembolik baglanti / baglanti noktasi ile depoya yonlendirilen yolu reddeder', (t) => {
    const depo = path.join(dizin, 'depo');
    fs.mkdirSync(depo);
    sahteDepoYap(depo);
    const baglanti = path.join(dizin, 'baglanti');
    try {
      fs.symlinkSync(depo, baglanti, process.platform === 'win32' ? 'junction' : 'dir');
    } catch (hata) {
      t.skip(`sembolik baglanti olusturulamadi (${hata.code})`);
      return;
    }
    const sonuc = calistir(['anahtar-uret', '--ozel', path.join(baglanti, 'ozel.pem')]);
    assert.equal(sonuc.kod, 1);
    assert.match(sonuc.err, /ICINDE olamaz/);
    assert.ok(!fs.existsSync(path.join(depo, 'ozel.pem')));
  });

  it('parolali uretim: anahtar sifreli yazilir, parolasiz/yanlis parolayla acilmaz, dogru parolayla acilir', () => {
    const yol = path.join(dizin, 'ozel.pem');
    const sonuc = calistir(['anahtar-uret', '--ozel', yol], { env: { OTA_IMZA_PAROLA: PAROLA } });
    assert.equal(sonuc.kod, 0, sonuc.err);
    const pem = fs.readFileSync(yol, 'utf8');
    assert.ok(pem.startsWith(PEM_ETIKET.ozelSifreli), 'sifreli PKCS#8 basligi');
    assert.ok(!pem.includes(PEM_ETIKET.ozel), 'sifresiz baslik bulunmamali');
    assert.match(sonuc.out, /parolali/);
    assert.throws(() => ozelAnahtariOku(yol), /OTA_IMZA_PAROLA/);
    assert.throws(() => ozelAnahtariOku(yol, { parola: 'yanlis-parola-123' }), /parola yanlis/);
    assert.equal(ozelAnahtariOku(yol, { parola: PAROLA }).key.asymmetricKeyType, 'ed25519');
    assert.ok(!sonuc.out.includes(PAROLA) && !sonuc.err.includes(PAROLA), 'parola ciktiya sizmaz');
  });

  it('kisa parola reddedilir ve anahtar dosyasi OLUSMAZ', () => {
    const yol = path.join(dizin, 'ozel.pem');
    const sonuc = calistir(['anahtar-uret', '--ozel', yol], { env: { OTA_IMZA_PAROLA: 'kisa' } });
    assert.equal(sonuc.kod, 2);
    assert.ok(!fs.existsSync(yol));
  });

  it('parola komut satirinda KABUL EDILMEZ (kabuk gecmisine duser)', () => {
    for (const bayrak of [['--parola', 'gizli-parola-123'], ['--parola=gizli-parola-123']]) {
      const sonuc = calistir(['anahtar-uret', '--ozel', path.join(dizin, 'ozel.pem'), ...bayrak]);
      assert.equal(sonuc.kod, 2);
      assert.match(sonuc.err, /OTA_IMZA_PAROLA/);
      assert.ok(!sonuc.err.includes('gizli-parola-123'));
    }
    assert.ok(!fs.existsSync(path.join(dizin, 'ozel.pem')));
  });

  it('--genel genel anahtari PEM dosyasina yazar; var olan dosyayi ezmez ve OZEL anahtar uretmeden once durur', () => {
    const genelYol = path.join(dizin, 'genel.pem');
    const ozelYol = path.join(dizin, 'ozel.pem');
    assert.equal(calistir(['anahtar-uret', '--ozel', ozelYol, '--genel', genelYol]).kod, 0);
    const genel = fs.readFileSync(genelYol, 'utf8');
    assert.ok(genel.startsWith(PEM_ETIKET.genel));
    assert.doesNotMatch(genel, /PRIVATE/);
    assert.equal(genelAnahtariCoz(genel).ham.length, 32);

    const ikinciOzel = path.join(dizin, 'ozel2.pem');
    const sonuc = calistir(['anahtar-uret', '--ozel', ikinciOzel, '--genel', genelYol]);
    assert.equal(sonuc.kod, 1);
    assert.match(sonuc.err, /ZATEN VAR/);
    assert.ok(!fs.existsSync(ikinciOzel), 'genel dosya engeli yuzunden ozel anahtar da uretilmemeli');
    assert.equal(fs.readFileSync(genelYol, 'utf8'), genel);
  });

  it('--genel ile --ozel ayni dosyayi gosteremez (cikis 2, hicbir dosya olusmaz)', () => {
    const yol = path.join(dizin, 'ayni.pem');
    const sonuc = calistir(['anahtar-uret', '--ozel', yol, '--genel', yol]);
    assert.equal(sonuc.kod, 2);
    assert.match(sonuc.err, /ayni dosya/);
    assert.ok(!fs.existsSync(yol));
  });

  it('bilinmeyen secenek ve fazla arguman cikis 2 ile reddedilir', () => {
    assert.equal(calistir(['anahtar-uret', '--ozel', path.join(dizin, 'o.pem'), '--zorla']).kod, 2);
    assert.equal(calistir(['anahtar-uret', 'fazla', '--ozel', path.join(dizin, 'o.pem')]).kod, 2);
    assert.equal(calistir(['anahtar-uret', '--ozel']).kod, 2);
    assert.ok(!fs.existsSync(path.join(dizin, 'o.pem')));
  });
});

describe('anahtar yazma hatalari', () => {
  let dizin;
  beforeEach(() => {
    dizin = geciciDizin();
  });
  afterEach(() => temizle(dizin));

  it('disk yazma hatasinda yarim ozel anahtar dosyasi BIRAKILMAZ', (t) => {
    const yol = path.join(dizin, 'yarim.pem');
    t.mock.method(fs, 'writeSync', () => {
      throw Object.assign(new Error('disk dolu'), { code: 'ENOSPC' });
    });
    assert.throws(() => ozelAnahtariYaz(yol, anahtarCiftiUret().ozel), /yazilamadi.*ENOSPC/);
    assert.ok(!fs.existsSync(yol), 'yarim yazilmis dosya silinmeli');
  });

  it('yazilan anahtar geri okunup sinanamazsa dosya SILINIR ve cikis 1 olur', (t) => {
    const yol = path.join(dizin, 'sinanamayan.pem');
    t.mock.method(crypto, 'verify', () => false);
    const sonuc = calistir(['anahtar-uret', '--ozel', yol]);
    assert.equal(sonuc.kod, 1);
    assert.match(sonuc.err, /dosya silindi/);
    assert.ok(!fs.existsSync(yol));
    assert.ok(!sonuc.out.includes(PEM_ETIKET.genel), 'dogrulanamayan anahtarin genel kismi yazdirilmaz');
  });

  it('PKCS#8 dosyasi O_EXCL ile olusur: sembolik baglanti uzerinden var olan dosyaya yazilmaz', (t) => {
    const hedef = path.join(dizin, 'hedef.txt');
    fs.writeFileSync(hedef, 'DOKUNMA');
    const baglanti = path.join(dizin, 'baglanti.pem');
    try {
      fs.symlinkSync(hedef, baglanti, 'file');
    } catch (hata) {
      t.skip(`sembolik baglanti olusturulamadi (${hata.code})`);
      return;
    }
    assert.equal(calistir(['anahtar-uret', '--ozel', baglanti]).kod, 1);
    assert.equal(fs.readFileSync(hedef, 'utf8'), 'DOKUNMA');
  });
});

describe('genel-anahtar', () => {
  let dizin;
  beforeEach(() => {
    dizin = geciciDizin();
  });
  afterEach(() => temizle(dizin));

  it('ozel anahtardan ayni genel anahtari yeniden uretir', () => {
    const anahtar = anahtarHazirla(dizin);
    const sonuc = calistir(['genel-anahtar', '--ozel', anahtar.yol]);
    assert.equal(sonuc.kod, 0, sonuc.err);
    assert.ok(sonuc.out.includes(anahtar.hex));
    assert.ok(sonuc.out.includes(anahtar.kimlik));
    assert.ok(!sonuc.out.includes('PRIVATE KEY'));
  });

  it('parolali anahtar icin OTA_IMZA_PAROLA ister; yanlis parolayi reddeder', () => {
    const anahtar = anahtarHazirla(dizin, { parola: PAROLA });
    assert.equal(calistir(['genel-anahtar', '--ozel', anahtar.yol]).kod, 1);
    assert.equal(calistir(['genel-anahtar', '--ozel', anahtar.yol], { env: { OTA_IMZA_PAROLA: 'yanlis-parola-123' } }).kod, 1);
    const dogru = calistir(['genel-anahtar', '--ozel', anahtar.yol], { env: { OTA_IMZA_PAROLA: PAROLA } });
    assert.equal(dogru.kod, 0);
    assert.ok(dogru.out.includes(anahtar.hex));
  });

  it('depo icindeki ozel anahtari OKUMAYI da reddeder', () => {
    const depo = path.join(dizin, 'depo');
    fs.mkdirSync(depo);
    sahteDepoYap(depo);
    const anahtar = anahtarHazirla(depo);
    const sonuc = calistir(['genel-anahtar', '--ozel', anahtar.yol]);
    assert.equal(sonuc.kod, 1);
    assert.match(sonuc.err, /ICINDE olamaz/);
    assert.ok(!sonuc.out.includes(anahtar.hex));
  });

  it('yol verilmezse cikis 2', () => {
    assert.equal(calistir(['genel-anahtar']).kod, 2);
  });
});

describe('depoIcindeMi / projeKokleri', () => {
  let dizin;
  beforeEach(() => {
    dizin = geciciDizin();
  });
  afterEach(() => temizle(dizin));

  it('gecici klasor (depo disi) icin false doner; var olmayan derin yol da cozulur', () => {
    assert.equal(depoIcindeMi(path.join(dizin, 'a.pem')).icinde, false);
    assert.equal(depoIcindeMi(path.join(dizin, 'yok', 'daha', 'derin', 'a.pem')).icinde, false);
  });

  it('.git klasoru ya da dosyasi bulunan bir atanin altindaki her yol depo icindedir', () => {
    const depo = path.join(dizin, 'depo');
    fs.mkdirSync(path.join(depo, 'a', 'b'), { recursive: true });
    sahteDepoYap(depo);
    const sonuc = depoIcindeMi(path.join(depo, 'a', 'b', 'x.pem'));
    assert.equal(sonuc.icinde, true);
    assert.equal(sonuc.neden, 'git deposu');
  });

  it('.git klasoru olmayan kopyalar icin ekKokler korumasi calisir', () => {
    const kok = path.join(dizin, 'proje');
    fs.mkdirSync(path.join(kok, 'tools'), { recursive: true });
    const sonuc = depoIcindeMi(path.join(kok, 'tools', 'x.pem'), { ekKokler: [kok] });
    assert.deepEqual({ icinde: sonuc.icinde, neden: sonuc.neden }, { icinde: true, neden: 'proje klasoru' });
    assert.equal(depoIcindeMi(path.join(dizin, 'baska.pem'), { ekKokler: [kok] }).icinde, false);
    // "proje" ile baslayan kardes klasor proje klasorunun ICINDE sayilmaz
    fs.mkdirSync(path.join(dizin, 'proje-yedek'));
    assert.equal(depoIcindeMi(path.join(dizin, 'proje-yedek', 'x.pem'), { ekKokler: [kok] }).icinde, false);
  });

  it('arac depo icinde calisirken proje koku bulunur (tools/ota_imza -> depo koku)', () => {
    const kokler = projeKokleri();
    assert.equal(kokler.length, 1);
    assert.equal(fs.realpathSync.native(kokler[0]), fs.realpathSync.native(DEPO_KOKU));
    assert.equal(fs.realpathSync.native(path.dirname(path.dirname(ARAC_KLASORU))), fs.realpathSync.native(DEPO_KOKU));
  });
});

describe('ozelAnahtariOku', () => {
  let dizin;
  beforeEach(() => {
    dizin = geciciDizin();
  });
  afterEach(() => temizle(dizin));

  it('olmayan dosya, klasor ve PEM olmayan dosya reddedilir', () => {
    assert.throws(() => ozelAnahtariOku(path.join(dizin, 'yok.pem')), /okunamadi/);
    assert.throws(() => ozelAnahtariOku(dizin), /dosya degil/);
    const metin = path.join(dizin, 'metin.pem');
    fs.writeFileSync(metin, 'bu bir anahtar degil');
    assert.throws(() => ozelAnahtariOku(metin), /PKCS#8 PEM/);
  });

  it('cok buyuk dosya reddedilir', () => {
    const buyuk = path.join(dizin, 'buyuk.pem');
    fs.writeFileSync(buyuk, 'x'.repeat(20 * 1024));
    assert.throws(() => ozelAnahtariOku(buyuk), /cok buyuk/);
  });

  it('bozuk PEM govdesi reddedilir ve mesaj anahtar icerigi tasimaz', () => {
    const bozuk = path.join(dizin, 'bozuk.pem');
    fs.writeFileSync(bozuk, `${PEM_ETIKET.ozel}\nQUJDREVGR0hJSktMTU5PUA==\n${PEM_OZEL_SON}\n`);
    assert.throws(() => ozelAnahtariOku(bozuk), (hata) => /dosya bozuk/.test(hata.message) && !hata.message.includes('QUJDREVG'));
  });

  it('Ed25519 olmayan anahtar reddedilir', () => {
    const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    const yol = path.join(dizin, 'ec.pem');
    fs.writeFileSync(yol, privateKey.export({ type: 'pkcs8', format: 'pem' }));
    assert.throws(() => ozelAnahtariOku(yol), /Ed25519 degil/);
  });

  it('POSIX\'te gevsek izinli anahtar icin UYARI dondurur (Windows\'ta izin bitleri anlamsiz)', (t) => {
    if (process.platform === 'win32') {
      t.skip('Windows');
      return;
    }
    const anahtar = anahtarHazirla(dizin);
    assert.deepEqual(ozelAnahtariOku(anahtar.yol).uyarilar, []);
    fs.chmodSync(anahtar.yol, 0o644);
    assert.match(ozelAnahtariOku(anahtar.yol).uyarilar[0], /izinleri gevsek/);
  });
});

describe('genelAnahtariCoz', () => {
  let dizin;
  beforeEach(() => {
    dizin = geciciDizin();
  });
  afterEach(() => temizle(dizin));

  it('PEM ve hex (kucuk / buyuk harf) kabul edilir ve ayni anahtari verir', () => {
    const bilgi = anahtarHazirla(dizin);
    assert.equal(genelAnahtariCoz(bilgi.pem).ham.toString('hex'), bilgi.hex);
    assert.equal(genelAnahtariCoz(bilgi.hex).kimlik, bilgi.kimlik);
    assert.equal(genelAnahtariCoz(bilgi.hex.toUpperCase()).kimlik, bilgi.kimlik);
    assert.equal(genelAnahtariCoz(`  ${bilgi.hex}\n`).kimlik, bilgi.kimlik);
  });

  it('OZEL anahtar verilirse reddedilir', () => {
    const { ozel } = anahtarHazirla(dizin);
    assert.throws(() => genelAnahtariCoz(ozel.export({ type: 'pkcs8', format: 'pem' })), /OZEL anahtar/);
  });

  it('bozuk, kisa, uzun ve Ed25519 olmayan girdiler reddedilir', () => {
    assert.throws(() => genelAnahtariCoz(''), /taninmadi/);
    assert.throws(() => genelAnahtariCoz('abcd'), /taninmadi/);
    assert.throws(() => genelAnahtariCoz('ab'.repeat(33)), /taninmadi/);
    assert.throws(() => genelAnahtariCoz('zz'.repeat(32)), /taninmadi/);
    assert.throws(() => genelAnahtariCoz(`${PEM_ETIKET.genel}\nAAAA\n${PEM_GENEL_SON}\n`), /bozuk/);
    const { publicKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    assert.throws(() => genelAnahtariCoz(publicKey.export({ type: 'spki', format: 'pem' })), /Ed25519 degil/);
  });
});
