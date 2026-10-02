import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/voice_door_service.dart';

DoorRecord _door(
  int id,
  String name, {
  int index = 1,
  int siteCode = 1,
  String site = 'Gude Sitesi',
}) {
  return DoorRecord(
    id: id,
    siteCode: siteCode,
    siteName: site,
    doorIndex: index,
    doorName: name,
    isActive: true,
    assignedDeviceId: id,
    assignedDeviceUid: 'ESP_$id',
    mqttSiteId: siteCode,
    createdAt: null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      expect(
        VoiceDoorService.resolveDoorFromCommand('kapıyı aç', <DoorRecord>[]).status,
        DoorMatchStatus.noDoors,
      );
    });

    test('ordinal and numbered forms resolve to the right door', () {
      expect(VoiceDoorService.matchDoorFromCommand('ikinci kapıyı aç', doors)?.id, 102);
      expect(VoiceDoorService.matchDoorFromCommand('3 numaralı kapıyı aç', doors)?.id, 103);
      expect(VoiceDoorService.matchDoorFromCommand('Kapı iki aç', doors)?.id, 102);
    });

    test('Turkish dotted capital İ is normalised ("İKİNCİ KAPIYI AÇ")', () {
      expect(VoiceDoorService.matchDoorFromCommand('İKİNCİ KAPIYI AÇ', doors)?.id, 102);
    });
  });

  group('VoiceDoorService reverse-intent / safety rules', () {
    final doors = <DoorRecord>[
      _door(101, 'Site Kapısı 1', index: 1),
      _door(102, 'Otopark Giriş Kapısı', index: 2),
      _door(103, 'Garaj Kapısı', index: 3),
    ];
    final single = <DoorRecord>[_door(201, 'Ana Kapı', index: 1)];

    test('reverse intents are rejected (kapat / kilitle / kapatma / açma)', () {
      for (final cmd in [
        'kapıyı kapat',
        'garaj kapısını kapat',
        'kapıyı kilitle',
        'kapıyı kapatma',
        'kapıyı açma',
        'otoparkı açma',
        'kapıyı açmayın',
        'kapıyı açmak istemiyorum',
        'kapıyı açma iptal',
        'dur kapıyı açma',
      ]) {
        final r = VoiceDoorService.resolveDoorFromCommand(cmd, doors);
        expect(r.status, DoorMatchStatus.reverseIntent, reason: cmd);
        expect(VoiceDoorService.matchDoorFromCommand(cmd, doors), isNull, reason: cmd);
        expect(
          VoiceDoorService.matchDoorFromCommand(cmd, single),
          isNull,
          reason: '$cmd (tek kapı)',
        );
      }
    });

    test('open verb must match as a WORD, not as a substring', () {
      for (final cmd in [
        'acil durum kapısı',
        'bacak',
        'arabayı kapıya çek', // "ac" alt dizesi yok ama kapı geçiyor, fiil yok
        'garaj kapısı',
        'otopark',
        'kapı açık mı',
      ]) {
        expect(
          VoiceDoorService.matchDoorFromCommand(cmd, doors),
          isNull,
          reason: cmd,
        );
        expect(
          VoiceDoorService.matchDoorFromCommand(cmd, single),
          isNull,
          reason: '$cmd (tek kapı)',
        );
      }
      expect(
        VoiceDoorService.resolveDoorFromCommand('acil durum', doors).status,
        DoorMatchStatus.noOpenIntent,
      );
    });

    test('generic "kapıyı aç" with several doors is AMBIGUOUS (no first-door fallback)', () {
      final r = VoiceDoorService.resolveDoorFromCommand('kapıyı aç', doors);
      expect(r.status, DoorMatchStatus.ambiguous);
      expect(r.door, isNull);
      expect(r.candidates, hasLength(3));
      expect(VoiceDoorService.matchDoorFromCommand('kapıyı aç', doors), isNull);

      final bare = VoiceDoorService.resolveDoorFromCommand('aç', doors);
      expect(bare.status, DoorMatchStatus.ambiguous);
    });

    test('first-door fallback only when the user owns a SINGLE door', () {
      expect(VoiceDoorService.matchDoorFromCommand('kapıyı aç', single)?.id, 201);
      expect(VoiceDoorService.matchDoorFromCommand('lütfen aç', single)?.id, 201);
      expect(VoiceDoorService.matchDoorFromCommand('kapıyı açar mısın', single)?.id, 201);
    });

    test('unrelated things are not treated as doors', () {
      for (final cmd in ['pencereyi aç', 'ışığı aç', 'televizyonu aç']) {
        expect(
          VoiceDoorService.resolveDoorFromCommand(cmd, single).status,
          DoorMatchStatus.notFound,
          reason: cmd,
        );
        expect(
          VoiceDoorService.resolveDoorFromCommand(cmd, doors).status,
          DoorMatchStatus.notFound,
          reason: cmd,
        );
      }
    });

    test('same door index in different sites is ambiguous; name or site resolves it', () {
      final multiSite = <DoorRecord>[
        _door(1, 'Ana Kapı', index: 1, siteCode: 1, site: 'Gül Sitesi'),
        _door(2, 'Ana Kapı', index: 1, siteCode: 2, site: 'Lale Sitesi'),
      ];

      final tie = VoiceDoorService.resolveDoorFromCommand('1. kapıyı aç', multiSite);
      expect(tie.status, DoorMatchStatus.ambiguous);
      expect(tie.candidates.map((d) => d.id), [1, 2]);

      final tie2 = VoiceDoorService.resolveDoorFromCommand('ana kapıyı aç', multiSite);
      expect(tie2.status, DoorMatchStatus.ambiguous);

      expect(
        VoiceDoorService.matchDoorFromCommand('lale sitesi ana kapıyı aç', multiSite)?.id,
        2,
      );
      expect(
        VoiceDoorService.matchDoorFromCommand('gül sitesi 1. kapıyı aç', multiSite)?.id,
        1,
      );
    });

    test('"bir kapı aç" does not silently pick door #1; "ön kapı" is not door #10', () {
      expect(
        VoiceDoorService.resolveDoorFromCommand('bir kapı aç', doors).status,
        DoorMatchStatus.ambiguous,
      );

      final front = <DoorRecord>[
        _door(1, 'Ön Kapı', index: 1),
        _door(2, 'Arka Kapı', index: 2),
      ];
      expect(VoiceDoorService.matchDoorFromCommand('ön kapıyı aç', front)?.id, 1);
      expect(VoiceDoorService.matchDoorFromCommand('arka kapıyı aç', front)?.id, 2);
    });
  });

  group('VoiceDoorService.clearSession', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('clears cached candidate doors and keeps the hands-free preference', () async {
      final service = VoiceDoorService(
        authService: AuthService(api: AuthApi(baseUrl: 'http://localhost')),
      );

      final doors = <DoorRecord>[_door(1, 'Ana Kapı')];
      // Konuşma motoru test ortamında yok; yine de aday kapılar kaydedilir.
      await service.startListening(candidateDoors: doors);
      expect(service.debugLastCandidateDoors, isNotNull);
      expect(service.debugLastCandidateDoors, hasLength(1));

      await service.setHandsFreeAutoListen(false);
      expect(service.handsFreeAutoListen, isFalse);

      var notified = 0;
      service.addListener(() => notified++);

      service.clearSession();

      expect(service.debugLastCandidateDoors, isNull);
      expect(service.matchedDoor, isNull);
      expect(service.recognizedWords, isEmpty);
      expect(service.feedbackText, isEmpty);
      expect(service.status, VoiceStatus.idle);
      expect(service.handsFreeAutoListen, isFalse, reason: 'cihaz tercihi korunmalı');
      expect(notified, greaterThan(0));

      // İkinci çağrı da güvenli
      service.clearSession();
      expect(service.debugLastCandidateDoors, isNull);

      service.dispose();
    });
  });
}
