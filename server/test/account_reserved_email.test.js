// R2 F-8: hesap silme tombstone alan adı (deleted.invalid) kullanıcıya KAPALI. Kayıt, davet, rol atama, yönetici kullanıcı oluşturma / güncelleme ve
// profil güncelleme e-posta doğrulamaları bu alan adını (ve alt alan adlarını) reddeder; böylece biri tombstone adresini önceden alıp silmeyi çökertemez.
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { DELETED_EMAIL_DOMAIN as ACCOUNT_DOMAIN, deletedEmailFor } from '../src/modules/account_common.js';
import { DELETED_EMAIL_DOMAIN, isReservedEmail } from '../src/utils/reserved_email.js';
import { isValidEmail as siteRulesIsValidEmail } from '../src/utils/site_rules.js';
import {
  isValidEmail,
  validateApartmentResidentInput,
  validateCreateInput,
  validateSiteManagerRegistrationInput,
  validateUpdateInput,
} from '../src/utils/validators.js';
import * as legacyHelpers from '../src/utils/helpers.js';

const RESERVED = ['deleted-12345@deleted.invalid', 'DELETED-1@DELETED.INVALID', 'x@deleted.invalid', 'a.b@sub.deleted.invalid', '  y@deleted.invalid  '];
const NORMAL = ['ada@example.com', 'ada@deleted.invalid.example.com', 'deleted@mydeleted.invalid.com', 'ada@notdeleted.invalid', 'deleted.invalid@example.com'];

describe('ayrılmış (sistem) e-posta alan adı', () => {
  it('tek kaynak: hesap modülü ve doğrulama aynı alan adını kullanır; tombstone adresi ayrılmıştır', () => {
    assert.equal(DELETED_EMAIL_DOMAIN, 'deleted.invalid');
    assert.equal(ACCOUNT_DOMAIN, DELETED_EMAIL_DOMAIN);
    assert.equal(isReservedEmail(deletedEmailFor(12345)), true);
    assert.equal(isReservedEmail(deletedEmailFor(12345, 'ab12cd34ef')), true);
  });

  it('isReservedEmail: alan adı ve alt alan adları (büyük/küçük harf, kenar boşluğu) ayrılmış; benzer adlar değil', () => {
    for (const email of RESERVED) {
      assert.equal(isReservedEmail(email), true, email);
    }
    for (const email of NORMAL) {
      assert.equal(isReservedEmail(email), false, email);
    }
    for (const bad of ['', null, undefined, 'abc', 42]) {
      assert.equal(isReservedEmail(bad), false, String(bad));
    }
  });

  it('deletedEmailFor: sonek yalnız küçük harf/rakam; geçersiz sonek yok sayılır (adres enjeksiyonu yok)', () => {
    assert.equal(deletedEmailFor(7), 'deleted-7@deleted.invalid');
    assert.equal(deletedEmailFor(7, 'a1b2'), 'deleted-7-a1b2@deleted.invalid');
    for (const bad of ['', 'A B', 'x@y', '../x', 'a'.repeat(33), null, undefined, 5]) {
      assert.equal(deletedEmailFor(7, bad), 'deleted-7@deleted.invalid', String(bad));
    }
  });

  it('validators.isValidEmail (kayıt, davet, rol atama, platform ayarı) ayrılmış alan adını REDDEDER', () => {
    assert.equal(isValidEmail('ada@example.com'), true);
    for (const email of RESERVED) {
      assert.equal(isValidEmail(email), false, email);
    }
  });

  it('site_rules.isValidEmail (site yöneticisi daveti) ayrılmış alan adını REDDEDER', () => {
    assert.equal(siteRulesIsValidEmail('ada@example.com'), true);
    for (const email of RESERVED) {
      assert.equal(siteRulesIsValidEmail(email), false, email);
    }
  });

  it('admin kullanıcı oluşturma / güncelleme, sakin ve site yöneticisi kaydı doğrulamaları ayrılmış alan adını REDDEDER', () => {
    const base = { fullName: 'Ada Lovelace', password: 'Parola-12345', role: 'individual', phoneNumber: '', isActive: true };
    assert.equal(validateCreateInput({ ...base, email: 'ada@example.com' }), null);
    assert.equal(validateCreateInput({ ...base, email: 'deleted-9@deleted.invalid' }), 'Gecerli email girin.');
    assert.equal(validateUpdateInput({ fullName: 'Ada Lovelace', email: 'ada@example.com' }), null);
    assert.equal(validateUpdateInput({ email: 'deleted-9@deleted.invalid' }), 'Gecerli email girin.');
    assert.equal(
      validateSiteManagerRegistrationInput({ fullName: 'Ada Lovelace', email: 'ada@example.com', password: 'Parola-12345', phoneNumber: '+905551112233' }),
      null,
    );
    assert.equal(
      validateSiteManagerRegistrationInput({ fullName: 'Ada Lovelace', email: 'x@deleted.invalid', password: 'Parola-12345', phoneNumber: '+905551112233' }),
      'Gecerli email girin.',
    );
    assert.equal(
      validateApartmentResidentInput({ fullName: 'Ada Lovelace', loginName: 'ada.l', password: '', email: 'x@deleted.invalid', phoneNumber: '', isActive: true }),
      'Gecerli e-posta girin.',
    );
    assert.equal(
      validateApartmentResidentInput({ fullName: 'Ada Lovelace', loginName: 'ada.l', password: '', email: 'ada@example.com', phoneNumber: '', isActive: true }),
      null,
    );
  });

  it('eski helpers.js kopyaları da aynı kuralı uygular (aynı adlı dışa aktarımlar tutarlı kalır)', () => {
    const base = { fullName: 'Ada Lovelace', password: 'Parola-12345', role: 'individual', phoneNumber: '', isActive: true };
    assert.equal(legacyHelpers.validateCreateInput({ ...base, email: 'deleted-9@deleted.invalid' }), 'Gecerli email girin.');
    assert.equal(legacyHelpers.validateCreateInput({ ...base, email: 'ada@example.com' }), null);
    assert.equal(legacyHelpers.validateUpdateInput({ email: 'deleted-9@deleted.invalid' }), 'Gecerli email girin.');
  });
});
