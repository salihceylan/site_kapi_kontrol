// S-C: parola ilkesi (§1.7) birim testleri.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  PASSWORD_MAX_BYTES,
  PASSWORD_MAX_LENGTH,
  PASSWORD_MIN_LENGTH,
  WEAK_PASSWORD_CODE,
  __policyStats,
  assertStrongPassword,
  evaluatePassword,
  foldForComparison,
  isCommonPassword,
  rejectWeakPassword,
} from '../src/security/password_policy.js';

function fakeRes() {
  return {
    statusCode: 200,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

describe('password_policy: uzunluk (§1.7: 8..128, Unicode kod noktası)', () => {
  it('sınırlar sözleşmeyle aynı', () => {
    assert.equal(PASSWORD_MIN_LENGTH, 8);
    assert.equal(PASSWORD_MAX_LENGTH, 128);
  });

  it('boş -> required, 7 karakter -> too_short, 8 karakter geçer, 129 karakter -> too_long', () => {
    assert.equal(evaluatePassword('').reason, 'required');
    assert.equal(evaluatePassword(undefined).reason, 'required');
    assert.equal(evaluatePassword('Kd9!tq2').reason, 'too_short');
    assert.equal(evaluatePassword('Kd9!tq2z').ok, true);
    assert.equal(evaluatePassword(`${'Kd9!tq2z'.repeat(16)}x`).reason, 'too_long');
  });

  it('bcrypt bayt sınırı: UTF-8’de 72 bayt geçer, 73 bayt too_long (Türkçe harf 2 bayt)', () => {
    assert.equal(PASSWORD_MAX_BYTES, 72);
    assert.equal(evaluatePassword('Kd9!tq2z'.repeat(9)).ok, true, '72 ASCII bayt');
    assert.equal(evaluatePassword(`${'Kd9!tq2z'.repeat(9)}x`).reason, 'too_long', '73 ASCII bayt');
    const turkish = 'Çağlayan-Şükrü-Göğüş-'; // karışık
    assert.ok(Buffer.byteLength(turkish, 'utf8') > [...turkish].length);
    assert.equal(evaluatePassword('ş'.repeat(37)).reason, 'too_long', '37 Türkçe harf = 74 bayt');
    assert.equal(evaluatePassword('ab'.repeat(64)).reason, 'too_long', '128 karakter ama 128 bayt');
    assert.match(evaluatePassword('ş'.repeat(40)).message, /72 bayt/);
  });

  it('bcrypt gerçekten 72 bayttan sonrasını yok sayar (kuralın gerekçesi)', async () => {
    const bcrypt = (await import('bcryptjs')).default;
    const hash = bcrypt.hashSync('ş'.repeat(100), 4);
    assert.equal(bcrypt.compareSync('ş'.repeat(36), hash), true);
  });

  it('emoji tek karakter sayılır (UTF-16 birimi değil)', () => {
    // 7 kod noktası (6 harf + 1 emoji) = UTF-16'da 8 birim: yine de kısa sayılmalı.
    assert.equal(evaluatePassword('Kd9tqz\u{1F512}').reason, 'too_short');
    assert.equal(evaluatePassword('Kd9tqzw\u{1F512}').ok, true);
  });
});

describe('password_policy: kimlikle aynı olamaz', () => {
  const context = { email: 'Ayse.Yilmaz2024@Example.com', firstName: 'Ayşe', lastName: 'Yılmaz', loginName: 'ayse.y' };

  it('e-postanın tamamı ya da @ öncesi kısmı (büyük/küçük harf farkı yok)', () => {
    assert.equal(evaluatePassword('ayse.yilmaz2024@example.com', context).reason, 'same_as_email');
    assert.equal(evaluatePassword('AYSE.YILMAZ2024', context).reason, 'same_as_email');
    assert.equal(evaluatePassword('ayse-yilmaz2024', context).reason, 'same_as_email', 'ayırıcı farkı yok sayılır');
  });

  it('ad soyad (Türkçe karakter ve boşluk farkı yok sayılır), kullanıcı adı', () => {
    assert.equal(evaluatePassword('AYŞE YILMAZ', context).reason, 'same_as_name');
    assert.equal(evaluatePassword('ayseyilmaz', context).reason, 'same_as_name');
    assert.equal(evaluatePassword('Ayşe Yılmaz', { fullName: 'Ayşe Yılmaz' }).reason, 'same_as_name');
    assert.equal(evaluatePassword('mehmetkaya', { names: ['Mehmet Kaya'] }).reason, 'same_as_name');
  });

  it('kimliği yalnızca İÇEREN güçlü parola kabul edilir (sözleşme: "aynı olamaz")', () => {
    assert.equal(evaluatePassword('ayse-Mavi-Kapi-77', context).ok, true);
  });
});

describe('password_policy: yaygın parola listesi ve örüntüler', () => {
  it('liste küçük ama dolu (TR + EN)', () => {
    assert.ok(__policyStats.commonPasswords >= 100 && __policyStats.commonPasswords <= 400, String(__policyStats.commonPasswords));
    assert.ok(__policyStats.commonBases >= 30);
  });

  it('doğrudan listede olanlar (katlama ile)', () => {
    for (const value of ['12345678', '123456789', 'password', 'Password1', 'qwerty123', 'Galatasaray1905', 'FENERBAHÇE1907',
      'beşiktaş1903', 'Sifre123', 'şifre1234', 'parola123', 'İstanbul34', 'ankara06', 'iloveyou', 'seniseviyorum',
      'smartkeypass', 'kapi1234', '1q2w3e4r', 'p@ssw0rd']) {
      assert.equal(isCommonPassword(value), true, value);
      assert.equal(evaluatePassword(value).reason, 'common', value);
    }
  });

  it('örüntüler: tek karakter, dizi (ters dahil), parça tekrarı, doğum tarihi, sondaki im', () => {
    for (const value of ['aaaaaaaa', '00000000', 'abcdefghij', 'hgfedcba', 'qwertyuiop', 'zxcvbnm,', 'abcabcabc', '12121212',
      '20242024', '19051905', '01011990', '19900101', '12345678!', '87654321', 'asdfghjkl']) {
      assert.equal(isCommonPassword(value), true, value);
    }
  });

  it('yaygın kök + kısa rakam/im eki ve öndeki ek', () => {
    for (const value of ['Sifre2024!', 'parola#1', 'Password2025', '2024istanbul', 'Galatasaray!!', 'Qwerty!23', 'abcdefg1']) {
      assert.equal(isCommonPassword(value), true, value);
    }
  });

  it('güçlü / sıradan olmayan parolalar ve mevcut testlerin parolaları geçer', () => {
    for (const value of ['Dogru-Parola-1', 'Yeni-Parola-2', 'YeniParola1', 'Gecerli-Parola-123', 'abcdef12', 'mavi-kapi-77-ruzgar',
      'Kd9!tq2z', 'kirmizi bisiklet sabah', '48213759', 'Elma.Armut.Kiraz']) {
      assert.equal(evaluatePassword(value).ok, true, value);
    }
  });

  it('foldForComparison: Türkçe harfleri birleştirir', () => {
    assert.equal(foldForComparison('İĞÜŞÖÇ ığüşöç I'), 'igusoc igusoc i');
  });
});

describe('password_policy: rota ve servis yardımcıları', () => {
  it('rejectWeakPassword: ihlalde 400 {error, code: WEAK_PASSWORD, reason}; parola yanıta yazılmaz', () => {
    const res = fakeRes();
    assert.equal(rejectWeakPassword(res, 'Sifre12345'), true);
    assert.equal(res.statusCode, 400);
    assert.equal(res.body.code, WEAK_PASSWORD_CODE);
    assert.equal(res.body.reason, 'common');
    assert.equal(typeof res.body.error, 'string');
    assert.equal(JSON.stringify(res.body).includes('Sifre12345'), false);

    const ok = fakeRes();
    assert.equal(rejectWeakPassword(ok, 'mavi-kapi-77-ruzgar'), false);
    assert.equal(ok.body, undefined);
  });

  it('assertStrongPassword: tipli 400 hata (expose, code, reason)', () => {
    assert.throws(
      () => assertStrongPassword('kisa'),
      (error) => error.statusCode === 400 && error.expose === true && error.code === 'WEAK_PASSWORD' && error.reason === 'too_short',
    );
    assert.doesNotThrow(() => assertStrongPassword('mavi-kapi-77-ruzgar'));
  });
});
