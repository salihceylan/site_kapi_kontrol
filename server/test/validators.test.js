import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
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
});
