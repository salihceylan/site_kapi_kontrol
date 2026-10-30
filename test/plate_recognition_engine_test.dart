import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_engine.dart';

void main() {
  group('PlateRecognitionEngine Otopark & Geçiş Karar Testleri', () {
    late PlateRecognitionEngine engine;

    setUp(() {
      engine = PlateRecognitionEngine.instance;
      engine.start(
        siteCode: 101,
        cameras: <PlateCameraRow>[
          PlateCameraRow.fromJson({
            'id': 1,
            'name': 'Giriş Kamerası',
            'host': '192.168.1.100',
            'port': 80,
            'direction': 'giris',
            'is_active': true,
            'managed': true,
            'gate': {'id': 1, 'name': 'Ana Kapı'},
            'status': {'state': 'online', 'color': 'yesil'},
            'brand': 'hikvision',
            'brand_label': 'Hikvision',
          }),
          PlateCameraRow.fromJson({
            'id': 2,
            'name': 'Çıkış Kamerası',
            'host': '192.168.1.101',
            'port': 80,
            'direction': 'cikis',
            'is_active': true,
            'managed': true,
            'gate': {'id': 1, 'name': 'Ana Kapı'},
            'status': {'state': 'online', 'color': 'yesil'},
            'brand': 'hikvision',
            'brand_label': 'Hikvision',
          }),
        ],
        blacklist: <PlateBlacklistItem>[
          PlateBlacklistItem.fromJson({
            'id': 1,
            'plate': '34 KRA 99',
            'reason': 'Aidat icrası',
            'created_by_name': 'Yönetici',
          }),
        ],
        guestPermits: <PlatePermit>[
          PlatePermit.fromJson({
            'id': 1,
            'plate': '34 MSF 01',
            'apartment_id': 10,
            'apartment_label': 'A Blok D:1',
            'valid_until': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
            'status': 'active',
          }),
          PlatePermit.fromJson({
            'id': 2,
            'plate': '34 MSF 02',
            'apartment_id': 20,
            'apartment_label': 'B Blok D:2',
            'valid_until': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
            'status': 'active',
          }),
          PlatePermit.fromJson({
            'id': 3,
            'plate': '34 MSF 03',
            'apartment_id': 30,
            'apartment_label': 'C Blok D:3',
            'valid_until': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
            'status': 'active',
          }),
        ],
        vehicles: <String, Map<String, dynamic>>{
          '34SKN01': <String, dynamic>{
            'apartment_label': 'A Blok D:1',
            'person_label': 'Ahmet Yılmaz',
          },
        },
        parkingSlots: <int, int>{
          10: 1, // A Blok D:1 -> 1 park yeri
          20: 1, // B Blok D:2 -> 1 park yeri
          30: 0, // C Blok D:3 -> 0 park yeri (park hakkı yok)
        },
        insideCounts: <int, int>{
          10: 0, // A Blok D:1 -> İçeride 0 araç (BOŞ)
          20: 1, // B Blok D:2 -> İçeride 1 araç (DOLU)
          30: 0, // C Blok D:3 -> İçeride 0 araç
        },
      );
    });

    tearDown(() {
      engine.stop();
    });

    test('1. Kara listedeki araç ASLA içeri alınmaz ve kapı açılmaz', () async {
      final decision = await engine.testProcessPlate('34 KRA 99', direction: 'giris');
      expect(decision.decision, PlateDecisionType.karaListe);
      expect(decision.isGateTriggered, isFalse);
      expect(decision.reason, contains('kara listesinde'));
    });

    test('2. Sitenin kayıtlı sakin aracı onaylanır ve kapı açılır', () async {
      final decision = await engine.testProcessPlate('34 SKN 01', direction: 'giris');
      expect(decision.decision, PlateDecisionType.acildi);
      expect(decision.isGateTriggered, isTrue);
      expect(decision.apartmentLabel, 'A Blok D:1');
      expect(decision.personLabel, 'Ahmet Yılmaz');
    });

    test('3. Misafir aracı: Park hakkı olan ve park yeri BOŞ olan dairenin misafiri içeri ALINIR', () async {
      final decision = await engine.testProcessPlate('34 MSF 01', direction: 'giris');
      expect(decision.decision, PlateDecisionType.acildi);
      expect(decision.isGateTriggered, isTrue);
      expect(decision.reason, contains('kabul edildi'));
    });

    test('4. Misafir aracı: Dairenin içeride aracı varken (DOLU) misafir içeri ALINMAZ', () async {
      final decision = await engine.testProcessPlate('34 MSF 02', direction: 'giris');
      expect(decision.decision, PlateDecisionType.red);
      expect(decision.isGateTriggered, isFalse);
      expect(decision.reason, contains('park yeri dolu'));
    });

    test('5. Misafir aracı: Park yeri tanımlı OLMAYAN dairenin misafiri içeri ALINMAZ', () async {
      final decision = await engine.testProcessPlate('34 MSF 03', direction: 'giris');
      expect(decision.decision, PlateDecisionType.red);
      expect(decision.isGateTriggered, isFalse);
      expect(decision.reason, contains('otopark yeri hakkı bulunmuyor'));
    });

    test('6. Misafir aracı: Çıkış yönünde misafir aracına her zaman izin verilir', () async {
      final decision = await engine.testProcessPlate('34 MSF 02', direction: 'cikis');
      expect(decision.decision, PlateDecisionType.acildi);
      expect(decision.isGateTriggered, isTrue);
      expect(decision.reason, contains('çıkışı onaylandı'));
    });

    test('7. Tanımsız plaka: Sistemde kayıtlı olmayan araç içeri alınmaz', () async {
      final decision = await engine.testProcessPlate('06 YBN 99', direction: 'giris');
      expect(decision.decision, PlateDecisionType.tanimsiz);
      expect(decision.isGateTriggered, isFalse);
      expect(decision.reason, contains('kayıtlı değil'));
    });
  });
}
