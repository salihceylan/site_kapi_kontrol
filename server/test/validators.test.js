import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { LOGIN_NAME_PATTERN, normalizeLoginName } from '../src/modules/people_common.js';
import {
  validateCreateInput,
  validateStructuredSiteInput,
  validateApartmentResidentInput,
  validateDoorAssignmentInput,
  validateDeviceInput,
} from '../src/utils/validators.js';

describe('Server Validators Tests', () => {
  describe('validateCreateInput', () => {
    it('accepts valid user input', () => {
      const error = validateCreateInput({
        fullName: 'Ahmet Yilmaz',
        email: 'ahmet@example.com',
        password: 'password123',
        role: 'super_user',
        phoneNumber: '05551234567',
        isActive: true,
      });
      assert.equal(error, null);
    });

    it('rejects short names and invalid emails', () => {
      assert.ok(validateCreateInput({
        fullName: 'A',
        email: 'invalid-email',
        password: '123',
        role: 'super_user',
      }));
    });
  });

  describe('validateStructuredSiteInput', () => {
    it('accepts valid structured site parameters', () => {
      const error = validateStructuredSiteInput({
        name: 'Güneş Sitesi',
        blockCount: 2,
        apartmentCount: 10,
        doorCount: 2,
        blockApartmentCounts: [5, 5],
      });
      assert.equal(error, null);
    });

    it('rejects invalid block apartment counts', () => {
      const error = validateStructuredSiteInput({
        name: 'Güneş Sitesi',
        doorCount: 2,
        blockApartmentCounts: [4, -1],
      });
      assert.ok(error && error.includes('sifir veya pozitif'));
    });
  });

  describe('validateApartmentResidentInput', () => {
    it('accepts valid resident credentials', () => {
      const error = validateApartmentResidentInput({
        fullName: 'Mehmet Kaya',
        loginName: 'site1_ablok_d1',
        password: '1234',
        email: 'mehmet@example.com',
        phoneNumber: '05559876543',
        isActive: true,
      });
      assert.equal(error, null);
    });

    it('rejects login names with spaces or illegal characters', () => {
      const error = validateApartmentResidentInput({
        fullName: 'Mehmet Kaya',
        loginName: 'site 1 ablok d1',
        password: '1234',
      });
      assert.ok(error && error.includes('Kullanici adi'));
    });

    const residentWith = (loginName) =>
      validateApartmentResidentInput({ fullName: 'Mehmet Kaya', loginName, password: '1234', isActive: true });

    it('kullanici adi kurali people_common.normalizeLoginName ile AYNI: ayni girdi ikisinde de kabul ya da ikisinde de red', () => {
      const samples = [
        'abc', 'ab', '', '   ', 'a'.repeat(40), 'a'.repeat(41), 'ada.l', 'ada_l', 'ada-l', 'site1_ablok_d1', 'Ada.L', '  ada.l  ',
        'ali@x.com', 'ali@', 'ada l', 'ada/l', 'ada\u00e7', 'ada\u0131', '..-', 'a.b', '___', '12345', 'ADA',
      ];
      for (const sample of samples) {
        let accepted;
        try {
          accepted = normalizeLoginName(sample) !== null;
        } catch (_error) {
          accepted = false;
        }
        assert.equal(residentWith(sample) === null, accepted, `girdi: ${JSON.stringify(sample)}`);
      }
      // Yapi sabiti de ayni (3-40, yalniz a-z 0-9 . _ -)
      assert.equal(String(LOGIN_NAME_PATTERN), String(/^[a-z0-9._-]{3,40}$/));
    });

    it('kullanici adi: 40 karakterden uzun, @ iceren ve Turkce harfli adlar reddedilir; buyuk harf kucultulerek kabul edilir (normalizeLoginName gibi)', () => {
      assert.match(residentWith('a'.repeat(41)), /en fazla 40/);
      assert.match(residentWith('ali@x.com'), /@ kullanilamaz/);
      assert.match(residentWith('ada\u00e7'), /kucuk harf, rakam/);
      assert.equal(residentWith('a'.repeat(40)), null);
      assert.equal(residentWith('Ada.L'), null);
      assert.match(residentWith('ab'), /en az 3/);
      assert.match(residentWith(undefined), /en az 3/);
    });
  });

  describe('validateDoorAssignmentInput & validateDeviceInput', () => {
    it('validates device UIDs for door assignment', () => {
      assert.equal(validateDoorAssignmentInput({ deviceUid: 'AABB1122' }), null);
      assert.ok(validateDoorAssignmentInput({ deviceUid: '123' }));
    });

    it('validates device registration parameters', () => {
      assert.equal(validateDeviceInput({
        deviceUid: '30AEA4F12345',
        assignedUserCode: 10001,
        siteCode: 1234567890,
      }), null);
    });
  });

  describe('Site Access Policies', () => {
    it('ensures at least one entry method is enabled', () => {
      const validateAccessMode = (remote, qr) => {
        if (!remote && !qr) {
          return 'En az bir giris yontemi acik olmalidir.';
        }
        return null;
      };

      assert.equal(validateAccessMode(true, true), null); // Hibrit
      assert.equal(validateAccessMode(true, false), null); // Sadece Uygulama
      assert.equal(validateAccessMode(false, true), null); // Sadece QR
      assert.ok(validateAccessMode(false, false)); // Ikisi de kapaliysa gecersiz
    });
  });
});
