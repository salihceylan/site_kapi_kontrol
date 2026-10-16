// Duyuru e-postası güvenliği (DB'siz): adres özeti (tuzlu SHA-256), tuzun sırdan türetilmesi, imzalı "abonelikten çık" belirteci, bağlantı kökü.
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {
  UNSUBSCRIBE_PATH,
  emailHashSalt,
  hashEmail,
  isEmailHash,
  normalizeAddress,
  publicLinkBase,
  signUnsubscribeToken,
  unsubscribeUrl,
  verifyUnsubscribeToken,
} from '../src/modules/announcement_email_security.js';

const saved = {};
beforeEach(() => {
  for (const name of ['ANNOUNCEMENT_EMAIL_SECRET', 'JWT_SECRET']) saved[name] = process.env[name];
  delete process.env.ANNOUNCEMENT_EMAIL_SECRET;
  process.env.JWT_SECRET = 'unit-test-secret-0123456789abcdef';
});
afterEach(() => {
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
