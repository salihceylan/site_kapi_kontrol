import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  isDeviceAssignableToManagedSite,
  isDeviceVisibleToManagedSites,
} from '../src/services/site_service.js';

describe('Device Assignment and Visibility Tests', () => {
  const managedSiteCodes = new Set([101, 202]);
  const managerUser = { id: 42, user_code: 4242, role: 'site_manager' };
  const otherUser = { id: 99, user_code: 9999, role: 'site_manager' };

  describe('isDeviceAssignableToManagedSite', () => {
    it('allows any valid device for super_user (managedSiteCodes === null)', () => {
      const device = {
        site_code: null,
        assigned_door_site_code: null,
        owner_user_id: null,
      };
      assert.equal(isDeviceAssignableToManagedSite(device, null, 999), true);
    });

    it('rejects defective devices even for super_user', () => {
      const device = {
        site_code: null,
        assigned_door_site_code: null,
        is_defective: true,
      };
      assert.equal(isDeviceAssignableToManagedSite(device, null, 101), false);
      assert.equal(isDeviceAssignableToManagedSite(device, managedSiteCodes, 101), false);
    });

    it('rejects assignment if target site is not managed by the manager', () => {
      const device = {
        site_code: null,
        assigned_door_site_code: null,
      };
      assert.equal(isDeviceAssignableToManagedSite(device, managedSiteCodes, 999, managerUser), false);
    });

    it('rejects unassigned company device if manager has not claimed/added it first', () => {
      const device = {
        site_code: null,
        assigned_door_site_code: null,
        owner_user_id: null,
        assigned_user_code: null,
      };
      // Yönetici kendi eklemediği serbest envanter cihazını doğrudan kapıya atayamaz
      assert.equal(isDeviceAssignableToManagedSite(device, managedSiteCodes, 101, managerUser), false);
    });

    it('allows manager to assign a device that they personally claimed/added', () => {
      const ownedDevice = {
        site_code: null,
        assigned_door_site_code: null,
        owner_user_id: 42,
        assigned_user_code: 4242,
      };
      assert.equal(isDeviceAssignableToManagedSite(ownedDevice, managedSiteCodes, 101, managerUser), true);
      assert.equal(isDeviceAssignableToManagedSite(ownedDevice, managedSiteCodes, 202, managerUser), true);
    });

    it('rejects device claimed by another manager', () => {
      const otherManagerDevice = {
        site_code: null,
        assigned_door_site_code: null,
        owner_user_id: 99,
        assigned_user_code: 9999,
      };
      assert.equal(isDeviceAssignableToManagedSite(otherManagerDevice, managedSiteCodes, 101, managerUser), false);
    });

    it('allows device already assigned to one of manager sites to be reassigned', () => {
      const device = {
        site_code: 101,
        assigned_door_site_code: 101,
      };
      assert.equal(isDeviceAssignableToManagedSite(device, managedSiteCodes, 101, managerUser), true);
      assert.equal(isDeviceAssignableToManagedSite(device, managedSiteCodes, 202, managerUser), true);
    });

    it('rejects device that belongs to another unmanaged site', () => {
      const device = {
        site_code: 999,
        assigned_door_site_code: 999,
      };
      assert.equal(isDeviceAssignableToManagedSite(device, managedSiteCodes, 101, managerUser), false);
    });
  });

  describe('isDeviceVisibleToManagedSites', () => {
    it('allows super_user to see all devices', () => {
      const device = { site_code: 999 };
      assert.equal(isDeviceVisibleToManagedSites(device, null), true);
    });

    it('hides unassigned company devices from site manager if not claimed by them', () => {
      const device = {
        site_code: null,
        assigned_door_site_code: null,
        owner_user_id: null,
        assigned_user_code: null,
      };
      // Kural: Site yöneticisi kendi eklemediği serbest envanter cihazını göremez
      assert.equal(isDeviceVisibleToManagedSites(device, managedSiteCodes, managerUser), false);
    });

    it('allows site manager to see devices they personally claimed/added', () => {
      const ownedDevice = {
        site_code: null,
        assigned_door_site_code: null,
        owner_user_id: 42,
        assigned_user_code: 4242,
      };
      assert.equal(isDeviceVisibleToManagedSites(ownedDevice, managedSiteCodes, managerUser), true);
    });

    it('hides device claimed by another manager', () => {
      const otherManagerDevice = {
        site_code: null,
        assigned_door_site_code: null,
        owner_user_id: 99,
        assigned_user_code: 9999,
      };
      assert.equal(isDeviceVisibleToManagedSites(otherManagerDevice, managedSiteCodes, managerUser), false);
    });

    it('allows managers to see devices in their managed sites', () => {
      const device = {
        site_code: 101,
        assigned_door_site_code: null,
      };
      assert.equal(isDeviceVisibleToManagedSites(device, managedSiteCodes, managerUser), true);
    });

    it('hides devices assigned to unmanaged sites', () => {
      const unmanagedDevice = {
        site_code: 999,
        assigned_door_site_code: 999,
      };
      assert.equal(isDeviceVisibleToManagedSites(unmanagedDevice, managedSiteCodes, managerUser), false);
    });
  });
});

