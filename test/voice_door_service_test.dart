import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';

void main() {
  group('VoiceDoorService Natural Language Matching Tests', () {
    const door1 = DoorRecord(
      id: 101,
      siteCode: 1,
      siteName: 'Gude Sitesi',
      doorIndex: 1,
      doorName: 'Site Kapısı 1',
      isActive: true,
      assignedDeviceId: 1,
      assignedDeviceUid: 'ESP_101',
      mqttSiteId: 1,
      createdAt: null,
    );

    const door2 = DoorRecord(
      id: 102,
      siteCode: 1,
      siteName: 'Gude Sitesi',
      doorIndex: 2,
      doorName: 'Otopark Giriş Kapısı',
      isActive: true,
      assignedDeviceId: 2,
      assignedDeviceUid: 'ESP_102',
      mqttSiteId: 1,
      createdAt: null,
    );

    const door3 = DoorRecord(
      id: 103,
      siteCode: 1,
      siteName: 'Gude Sitesi',
      doorIndex: 3,
      doorName: 'Garaj Kapısı',
      isActive: true,
      assignedDeviceId: 3,
      assignedDeviceUid: 'ESP_103',
      mqttSiteId: 1,
      createdAt: null,
    );

    final doors = <DoorRecord>[door1, door2, door3];

    test('matches "Site Kapısı Bir i aç"', () {
      final matched = VoiceDoorService.matchDoorFromCommand(
        'Site Kapısı Bir i aç',
        doors,
      );
      expect(matched?.id, 101);
      expect(matched?.doorName, 'Site Kapısı 1');
    });

    test('matches "1. kapıyı aç"', () {
      final matched = VoiceDoorService.matchDoorFromCommand(
        '1. kapıyı aç',
        doors,
      );
      expect(matched?.id, 101);
    });

    test('matches "otopark kapısını aç"', () {
      final matched = VoiceDoorService.matchDoorFromCommand(
        'otopark kapısını aç',
        doors,
      );
      expect(matched?.id, 102);
      expect(matched?.doorName, 'Otopark Giriş Kapısı');
    });

    test('matches "garajı aç"', () {
      final matched = VoiceDoorService.matchDoorFromCommand(
        'garajı aç',
        doors,
      );
      expect(matched?.id, 103);
      expect(matched?.doorName, 'Garaj Kapısı');
    });

    test('matches single door when user says general "kapıyı aç"', () {
      final matched = VoiceDoorService.matchDoorFromCommand(
        'kapıyı aç',
        <DoorRecord>[door1],
      );
      expect(matched?.id, 101);
    });

    test('returns null when no doors available', () {
      final matched = VoiceDoorService.matchDoorFromCommand(
        'kapıyı aç',
        <DoorRecord>[],
      );
      expect(matched, isNull);
    });
  });
}

