// Duyuru e-postası güvenliği (DB'siz): adres özeti (tuzlu SHA-256), tuzun sırdan türetilmesi, imzalı "abonelikten çık" belirteci, bağlantı kökü.
import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import {
  UNSUBSCRIBE_PATH,
  canonicalAddress,
  emailHashSalt,
  emailHashSalts,
  hashEmail,
  hashEmailAll,
  isEmailHash,
  normalizeAddress,
  publicLinkBase,
  resetSecretWarnings,
  signUnsubscribeToken,
  unsubscribeUrl,
  verifyUnsubscribeToken,
} from '../src/modules/announcement_email_security.js';

const saved = {};
beforeEach(() => {
  for (const name of ['ANNOUNCEMENT_EMAIL_SECRET', 'ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS', 'JWT_SECRET']) saved[name] = process.env[name];
  delete process.env.ANNOUNCEMENT_EMAIL_SECRET;
  delete process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS;
  process.env.JWT_SECRET = 'unit-test-secret-0123456789abcdef';
  resetSecretWarnings();
});
afterEach(() => {
  mock.restoreAll();
  for (const [name, value] of Object.entries(saved)) {
    if (value === undefined) delete process.env[name];
    else process.env[name] = value;
  }
});

describe('adres özeti', () => {
  it('küçük harfli, kırpılmış adres üzerinden tuzlu SHA-256 (hex 64); adres özette görünmez; aynı adres aynı özet, farklı adres farklı özet', () => {
    const hash = hashEmail('Sakin@Example.com');
    assert.match(hash, /^[0-9a-f]{64}$/);
    assert.equal(hash, hashEmail('  sakin@example.COM '));
    assert.notEqual(hash, hashEmail('baska@example.com'));
    assert.equal(hash, crypto.createHash('sha256').update(`${emailHashSalt()}:sakin@example.com`, 'utf8').digest('hex'), 'SQL ifadesiyle birebir aynı tanım');
    assert.ok(!hash.includes('sakin'));
    assert.equal(normalizeAddress(null), '');
    assert.equal(isEmailHash(hash), true);
    for (const bad of ['', 'abc', hash.toUpperCase(), `${hash}0`, null, 5]) assert.equal(isEmailHash(bad), false, String(bad));
  });

  it('tuz sunucu sırrından türetilir (ham sır değil): sır değişirse özet değişir; ANNOUNCEMENT_EMAIL_SECRET JWT_SECRET\'ı geçersiz kılar', () => {
    const salt = emailHashSalt();
    assert.match(salt, /^[0-9a-f]{64}$/);
    assert.ok(!salt.includes('unit-test-secret'));
    const before = hashEmail('a@example.com');
    process.env.ANNOUNCEMENT_EMAIL_SECRET = 'ozel-duyuru-sirri-0123456789';
    assert.notEqual(emailHashSalt(), salt);
    assert.notEqual(hashEmail('a@example.com'), before);
    delete process.env.ANNOUNCEMENT_EMAIL_SECRET;
    assert.equal(hashEmail('a@example.com'), before);
  });

  it('sır yoksa ya da kısaysa hata verir (düz/öngörülebilir tuzla sessizce çalışmaz)', () => {
    delete process.env.JWT_SECRET;
    assert.throws(() => emailHashSalt(), /tanimli degil/);
    process.env.JWT_SECRET = 'kisa';
    assert.throws(() => hashEmail('a@example.com'), /tanimli degil/);
  });
});

describe('abonelikten çık belirteci', () => {
  it('imzalı belirteç "<özet>.<HMAC>" biçimindedir ve doğrulanınca özeti döner; düz adres içermez', () => {
    const hash = hashEmail('sakin@example.com');
    const token = signUnsubscribeToken(hash);
    assert.match(token, /^[0-9a-f]{64}\.[A-Za-z0-9_-]{43}$/);
    assert.equal(verifyUnsubscribeToken(token), hash);
    assert.ok(!token.includes('sakin') && !token.includes('example'));
    assert.equal(signUnsubscribeToken(hash), token, 'süresiz ve belirleyici (aynı adres aynı bağlantı)');
  });

  it('imza adresin özetine bağlıdır: imza bozulursa, başka özetle birleştirilirse, eksik / fazla parça, boş, çok uzun, dize olmayan -> null', () => {
    const hash = hashEmail('sakin@example.com');
    const other = hashEmail('baska@example.com');
    const [, sig] = signUnsubscribeToken(hash).split('.');
    const otherSig = signUnsubscribeToken(other).split('.')[1];
    const flip = `${sig.slice(0, -1)}${sig.endsWith('A') ? 'B' : 'A'}`;
    for (const bad of [`${hash}.${flip}`, `${other}.${sig}`, `${hash}.${otherSig}`, hash, `${hash}.`, `${hash}.${sig}.x`, '', 'abc', 'a'.repeat(201), null, undefined, 42, {}, `${'0'.repeat(64)}.${sig}`, `${hash.toUpperCase()}.${sig}`]) {
      assert.equal(verifyUnsubscribeToken(bad), null, String(bad).slice(0, 40));
    }
  });

  it('sır değişirse eski belirteçler geçersizleşir (imza anahtarı sırdan türetilir)', () => {
    const hash = hashEmail('sakin@example.com');
    const token = signUnsubscribeToken(hash);
    process.env.JWT_SECRET = 'baska-bir-sir-0123456789abcdef-xyz';
    assert.equal(verifyUnsubscribeToken(token), null);
  });

  it('imzalanmamış özet (geçersiz biçim) imzalanamaz', () => {
    assert.throws(() => signUnsubscribeToken('sakin@example.com'), /gecersiz/);
    assert.throws(() => signUnsubscribeToken(''), /gecersiz/);
  });
});

describe('E3 kanonik adres (takma adlarla bastırma / sınır dolanılamaz)', () => {
  it('+etiket atılır; gmail / googlemail için noktalar silinir ve alan adı gmail.com olur; küçük harf', () => {
    assert.equal(canonicalAddress('A.Li+Haber@GMail.com'), 'ali@gmail.com');
    assert.equal(canonicalAddress('a.l.i@googlemail.com'), 'ali@gmail.com');
    assert.equal(canonicalAddress('  ali+1+2@gmail.com '), 'ali@gmail.com');
    assert.equal(canonicalAddress('ali.veli+abc@example.com'), 'ali.veli@example.com', 'gmail dışında noktalar KORUNUR');
    assert.equal(canonicalAddress('ali+haber@Example.COM'), 'ali@example.com');
    assert.equal(canonicalAddress('ali@example.com'), 'ali@example.com');
  });

  it('boş kalacak yerel kısma dokunulmaz (farklı adresler tek anahtara çökmez); bozuk girdi olduğu gibi (küçük harf) kalır', () => {
    assert.equal(canonicalAddress('+etiket@example.com'), '+etiket@example.com');
    assert.equal(canonicalAddress('...@gmail.com'), '...@gmail.com');
    assert.equal(canonicalAddress('+a@gmail.com'), '+a@gmail.com');
    assert.equal(canonicalAddress('a@b@c.com'), 'a@b@c.com');
    assert.equal(canonicalAddress('@x.com'), '@x.com');
    assert.equal(canonicalAddress('x@'), 'x@');
    assert.equal(canonicalAddress('yok'), 'yok');
    assert.equal(canonicalAddress(null), '');
  });

  it('varyant adresler AYNI özeti verir; farklı kişiler farklı özet; özet kanonik adresten hesaplanır', () => {
    const reference = hashEmail('ali@gmail.com');
    for (const variant of ['a.li+1@gmail.com', 'ALI@GMAIL.COM', 'a.l.i+haber@googlemail.com', ' ali@gmail.com ']) {
      assert.equal(hashEmail(variant), reference, variant);
    }
    assert.equal(hashEmail('ali+haber@example.com'), hashEmail('ali@example.com'));
    assert.notEqual(hashEmail('a.li@example.com'), hashEmail('ali@example.com'));
    assert.notEqual(hashEmail('ali@gmail.com'), hashEmail('veli@gmail.com'));
    assert.equal(reference, crypto.createHash('sha256').update(`${emailHashSalt()}:ali@gmail.com`, 'utf8').digest('hex'));
  });

  it('abonelik belirteci kanonik özetle uyumludur: varyant adresin bağlantısı aynı özeti taşır', () => {
    const token = signUnsubscribeToken(hashEmail('a.li+1@gmail.com'));
    assert.equal(verifyUnsubscribeToken(token), hashEmail('ali@gmail.com'));
  });
});

describe('E2 sır yönetimi', () => {
  it('kısa (< 8) ANNOUNCEMENT_EMAIL_SECRET HATA FIRLATMAZ: JWT_SECRET\'a düşer ve BİR kez uyarı loglar (sır değeri yazılmaz)', () => {
    const warn = mock.method(console, 'warn', () => {});
    const expected = emailHashSalt();
    process.env.ANNOUNCEMENT_EMAIL_SECRET = 'kisa123';
    assert.equal(emailHashSalt(), expected, 'JWT_SECRET\'tan türetilen tuz');
    assert.doesNotThrow(() => hashEmail('a@example.com'));
    assert.doesNotThrow(() => signUnsubscribeToken(hashEmail('a@example.com')));
    emailHashSalts();
    assert.equal(warn.mock.calls.length, 1, 'bir kez');
    const logged = warn.mock.calls.map((call) => call.arguments.join(' ')).join('\n');
    assert.match(logged, /ANNOUNCEMENT_EMAIL_SECRET/);
    assert.ok(!logged.includes('kisa123') && !logged.includes('unit-test-secret'));
  });

  it('boş / yalnız boşluk ANNOUNCEMENT_EMAIL_SECRET sessizce yok sayılır (uyarısız); geçerli olan kullanılır', () => {
    const warn = mock.method(console, 'warn', () => {});
    process.env.ANNOUNCEMENT_EMAIL_SECRET = '   ';
    assert.equal(emailHashSalt(), emailHashSalts()[0]);
    assert.equal(warn.mock.calls.length, 0);
    process.env.ANNOUNCEMENT_EMAIL_SECRET = 'ozel-duyuru-sirri-0123456789';
    assert.notEqual(emailHashSalt(), crypto.createHmac('sha256', 'unit-test-secret-0123456789abcdef').update('announcement-email-hash-salt-v1').digest('hex'));
  });

  it('hiç kullanılabilir sır yoksa e-posta yolları net hata verir (yalnız e-posta özetini isteyen çağrılar etkilenir)', () => {
    delete process.env.JWT_SECRET;
    assert.throws(() => emailHashSalts(), /tanimli degil/);
    process.env.ANNOUNCEMENT_EMAIL_SECRET = 'kisa';
    mock.method(console, 'warn', () => {});
    assert.throws(() => hashEmailAll('a@example.com'), /tanimli degil/);
  });

  it('ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS: eski sırlar (virgüllü, boşluk kırpılır, kısa / tekrarlı / güncel olanlar atılır) tuz listesine eklenir; ilk eleman GÜNCEL tuzdur', () => {
    process.env.ANNOUNCEMENT_EMAIL_SECRET = 'yeni-duyuru-sirri-0123456789';
    process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS = ' eski-sir-bir-0123456789 , eski-sir-iki-0123456789,kisa, eski-sir-bir-0123456789 ,yeni-duyuru-sirri-0123456789';
    const salts = emailHashSalts();
    assert.equal(salts.length, 3);
    assert.equal(salts[0], emailHashSalt());
    assert.equal(new Set(salts).size, 3);
    assert.ok(salts.every((salt) => /^[0-9a-f]{64}$/.test(salt)));
    assert.equal(hashEmailAll('a.li+1@gmail.com').length, 3);
    assert.equal(hashEmailAll('ali@gmail.com')[0], hashEmail('ali@gmail.com'));
    assert.equal(new Set(hashEmailAll('ali@gmail.com')).size, 3);
  });

  it('sır döndürme: eski sırla atılmış bağlantı PREVIOUS listesindeyken geçerli, çıkarılınca geçersiz; yeni imzalar YALNIZ güncel sırla; eski özet de aranabilir', () => {
    process.env.ANNOUNCEMENT_EMAIL_SECRET = 'eski-duyuru-sirri-0123456789';
    const oldHash = hashEmail('sakin@example.com');
    const oldToken = signUnsubscribeToken(oldHash);
    process.env.ANNOUNCEMENT_EMAIL_SECRET = 'yeni-duyuru-sirri-0123456789';
    assert.equal(verifyUnsubscribeToken(oldToken), null, 'PREVIOUS yokken eski bağlantı geçersiz');
    process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS = 'eski-duyuru-sirri-0123456789';
    assert.equal(verifyUnsubscribeToken(oldToken), oldHash, 'PREVIOUS listesindeyken geçerli');
    assert.notEqual(hashEmail('sakin@example.com'), oldHash, 'yeni özet güncel sırla');
    assert.ok(hashEmailAll('sakin@example.com').includes(oldHash), 'eski özet de hesaplanır (bastırma araması eski kayıtları bulur)');
    // yeni bağlantılar güncel sırla imzalanır: PREVIOUS kaldırılsa da geçerli kalır
    const newToken = signUnsubscribeToken(hashEmail('sakin@example.com'));
    delete process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS;
    assert.equal(verifyUnsubscribeToken(newToken), hashEmail('sakin@example.com'));
    assert.equal(verifyUnsubscribeToken(oldToken), null);
  });

  it('JWT_SECRET döndürme (özel sır yokken): eski JWT_SECRET PREVIOUS\'a yazılınca eski bağlantılar ve özetler geçerliliğini korur', () => {
    const oldHash = hashEmail('sakin@example.com');
    const oldToken = signUnsubscribeToken(oldHash);
    const previousJwt = process.env.JWT_SECRET;
    process.env.JWT_SECRET = 'rotasyon-sonrasi-jwt-0123456789abcdef';
    assert.equal(verifyUnsubscribeToken(oldToken), null);
    process.env.ANNOUNCEMENT_EMAIL_SECRET_PREVIOUS = previousJwt;
    assert.equal(verifyUnsubscribeToken(oldToken), oldHash);
    assert.ok(hashEmailAll('sakin@example.com').includes(oldHash));
  });

  it('imza karşılaştırması crypto.timingSafeEqual ile yapılır (eşit uzunlukta her anahtar için); uzunluk uyuşmazlığında çağrılmaz (Node hata verirdi)', () => {
    const spy = mock.method(crypto, 'timingSafeEqual');
    const hash = hashEmail('sakin@example.com');
    const token = signUnsubscribeToken(hash);
    assert.equal(verifyUnsubscribeToken(token), hash);
    assert.ok(spy.mock.calls.length >= 1, 'timingSafeEqual çağrıldı');
    assert.ok(spy.mock.calls.every((call) => Buffer.isBuffer(call.arguments[0]) && Buffer.isBuffer(call.arguments[1]) && call.arguments[0].length === call.arguments[1].length));
    spy.mock.resetCalls();
    assert.equal(verifyUnsubscribeToken(`${hash}.kisa`), null);
    assert.equal(spy.mock.calls.length, 0, 'uzunluk farkı ucuzca elenir');
    const source = fs.readFileSync(new URL('../src/modules/announcement_email_security.js', import.meta.url), 'utf8');
    assert.match(source, /timingSafeEqual/);
    assert.doesNotMatch(source, /expected\s*===?\s*given|given\s*===?\s*expected|expected\.toString|\bsig\s*===?\s*signature/, 'imza === ile karşılaştırılmaz');
  });
});

describe('bağlantı', () => {
  it('kök adres PUBLIC_APP_URL, yoksa PUBLIC_BASE_URL, yoksa varsayılan; sondaki eğik çizgiler atılır', () => {
    assert.equal(publicLinkBase({}), 'https://api.gudeteknoloji.com.tr');
    assert.equal(publicLinkBase({ PUBLIC_BASE_URL: 'https://b.example.com//' }), 'https://b.example.com');
    assert.equal(publicLinkBase({ PUBLIC_APP_URL: 'https://a.example.com/', PUBLIC_BASE_URL: 'https://b.example.com' }), 'https://a.example.com');
  });

  it('unsubscribeUrl: kök + /public/announcement-unsubscribe?t=<belirteç> (belirteç URL kodlu); belirteç doğrulanır', () => {
    const hash = hashEmail('sakin@example.com');
    const url = unsubscribeUrl(hash, { PUBLIC_APP_URL: 'https://api.example.com' });
    const parsed = new URL(url);
    assert.equal(parsed.origin, 'https://api.example.com');
    assert.equal(parsed.pathname, UNSUBSCRIBE_PATH);
    assert.equal(verifyUnsubscribeToken(parsed.searchParams.get('t')), hash);
    assert.ok(!url.includes('sakin@'));
  });
});
