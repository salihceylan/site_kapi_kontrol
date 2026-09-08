import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  compareVersionParts,
  safeFirmwareTarget,
  safeFirmwareFile,
  normalizeDeviceUid,
  mqttUsernameForDevice,
  formatBlockNameSegment,
  apartmentResidentFullName,
  apartmentBaseLoginName,
  blockLabelFromIndex,
  blockNameFromIndex,
  buildBlockApartmentCounts,
} from '../src/utils/helpers.js';

describe('Server Helpers Tests', () => {
  describe('compareVersionParts', () => {
    it('correctly compares version numbers', () => {
      assert.equal(compareVersionParts('1.0.1', '1.0.0'), 1);
      assert.equal(compareVersionParts('1.0.0', '1.0.1'), -1);
      assert.equal(compareVersionParts('1.0.0', '1.0.0'), 0);
      assert.equal(compareVersionParts('3.0.3', '3.0.2'), 1);
      assert.equal(compareVersionParts('2.1.0', '2.0.9'), 1);
      assert.equal(compareVersionParts('1.0.0', '1.0.0.1'), -1);
    });
  });

  describe('safeFirmwareTarget & safeFirmwareFile', () => {
    it('validates supported target architectures', () => {
      assert.equal(safeFirmwareTarget('esp32-c3'), 'esp32-c3');
      assert.equal(safeFirmwareTarget('esp32-wroom'), 'esp32-wroom');
      assert.equal(safeFirmwareTarget('invalid/target'), null);
      assert.equal(safeFirmwareTarget('../secret'), null);
    });

    it('validates firmware binary filenames', () => {
      assert.equal(safeFirmwareFile('firmware.bin'), 'firmware.bin');
      assert.equal(safeFirmwareFile('firmware_v3.0.3.bin'), 'firmware_v3.0.3.bin');
      assert.equal(safeFirmwareFile('firmware.exe'), null);
      assert.equal(safeFirmwareFile('../firmware.bin'), null);
    });
  });

  describe('Device UID and MQTT helpers', () => {
    it('normalizes device UIDs to uppercase hex', () => {
      assert.equal(normalizeDeviceUid('aabb1122'), 'AABB1122');
      assert.equal(normalizeDeviceUid('aa:bb:11:22'), 'AABB1122');
      assert.equal(normalizeDeviceUid('  30aea4f1  '), '30AEA4F1');
    });

    it('constructs correct MQTT username for devices', () => {
      assert.equal(mqttUsernameForDevice('aabb1122'), 'device_AABB1122');
    });
  });

  describe('Block and Apartment helpers', () => {
    it('computes correct block labels from 0-based index', () => {
      assert.equal(blockLabelFromIndex(0), 'A');
      assert.equal(blockLabelFromIndex(1), 'B');
      assert.equal(blockLabelFromIndex(25), 'Z');
      assert.equal(blockLabelFromIndex(26), 'AA');
      assert.equal(blockNameFromIndex(0), 'A Blok');
      assert.equal(blockNameFromIndex(1), 'B Blok');
    });

    it('formats block name segments safely with Turkish character replacement', () => {
      assert.equal(formatBlockNameSegment('Çamlıca Blok'), 'CamlicaBlok');
      assert.equal(formatBlockNameSegment('Şafak Blok'), 'SafakBlok');
      assert.equal(formatBlockNameSegment('A Blok'), 'ABlok');
    });

    it('generates consistent apartment base login names', () => {
      const login = apartmentBaseLoginName({
        siteCode: 1234567890,
        blockName: 'A Blok',
        sortOrder: 5,
      });
      assert.equal(login, '1234567890_ABlok_Daire5');
    });

    it('constructs apartment resident full names', () => {
      const name = apartmentResidentFullName({
        blockName: 'A Blok',
        unitLabel: 'D:12',
      });
      assert.equal(name, 'A Blok D:12');
    });

    it('builds block apartment counts distribution correctly', () => {
      const counts = buildBlockApartmentCounts({
        blockCount: 3,
        apartmentCount: 10,
        blockApartmentCounts: null,
      });
      assert.deepEqual(counts, [4, 3, 3]);
    });
  });
});
