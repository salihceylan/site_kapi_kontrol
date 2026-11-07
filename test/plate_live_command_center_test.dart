import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/plate_command_center_item.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_engine.dart';
import 'package:site_kapi_kontrol/ui/dialogs/plate_live_command_center.dart';
import 'package:site_kapi_kontrol/ui/views/plate_recognition_view.dart';

import 'plate_cameras_support.dart';

class _FakeAuthService extends Fake implements AuthService {
  @override
  AuthApi get api => AuthApi(baseUrl: 'http://localhost');

  @override
  UserSession? get session => null;
}

class _FakePlateRecognitionService extends Fake implements PlateRecognitionService {
  _FakePlateRecognitionService({
    List<Map<String, dynamic>>? gateCameras,
  }) : _gateCameras = gateCameras ?? const <Map<String, dynamic>>[];

  final List<Map<String, dynamic>> _gateCameras;

  @override
  Future<PlateGatesOverview> gatesOverview(int site) async => PlateGatesOverview.fromJson(<String, dynamic>{
        'settings': <String, dynamic>{
          'guest_rule': 'tum_bos',
          'heartbeat_warn_seconds': 180,
          'heartbeat_crit_seconds': 600,
        },
        'guest_rules': <dynamic>[],
        'direction_modes': <dynamic>[],
        'gates': <dynamic>[
          <String, dynamic>{
            'id': 10,
            'name': 'Ana Giriş Kapısı',
            'direction_mode': 'cift',
            'direction_label': 'Giriş + Çıkış',
            'is_active': true,
            'status': <String, dynamic>{'state': 'online', 'label': 'Çalışıyor', 'color': 'yesil'},
            'cameras': _gateCameras,
          },
        ],
        'unassigned_cameras': <dynamic>[],
        'devices': <dynamic>[],
        'edge_clients': <dynamic>[],
        'inside_total': 2,
      });

  @override
  Future<PlateInside> inside(int site) async => PlateInside.fromJson(<String, dynamic>{
        'total': 2,
        'items': <dynamic>[
          <String, dynamic>{
            'id': 101,
            'plate': '34 NBL 304',
            'kind': 'resident',
            'apartment_id': 7,
            'apartment_label': 'A Blok D:12',
            'gate_name': 'Ana Giriş Kapısı',
            'entered_at': DateTime.now().subtract(const Duration(minutes: 25)).toUtc().toIso8601String(),
          },
          <String, dynamic>{
            'id': 102,
            'plate': '06 MSF 99',
            'kind': 'guest',
            'apartment_id': 8,
            'apartment_label': 'B Blok D:4',
            'gate_name': 'Ana Giriş Kapısı',
            'entered_at': DateTime.now().subtract(const Duration(hours: 2)).toUtc().toIso8601String(),
          },
        ],
        'apartments': <dynamic>[
          <String, dynamic>{'id': 7, 'label': 'A Blok D:12', 'parking_slots': 2, 'inside_count': 1},
          <String, dynamic>{'id': 8, 'label': 'B Blok D:4', 'parking_slots': 2, 'inside_count': 1},
        ],
      });

  @override
  Future<PlateLiveFeed> liveFeed(int site, {int? limit}) async => PlateLiveFeed.fromJson(<String, dynamic>{
        'refresh_seconds': 5,
        'events': <dynamic>[
          <String, dynamic>{
            'id': 501,
            'plate': '34 NBL 304',
            'decision': 'ALLOWED',
            'decision_kind': 'acildi',
            'reason': 'vehicle',
            'reason_label': 'Kayıtlı sakin aracı',
            'direction': 'giris',
            'door_name': 'Ana Giriş Kapısı',
            'device_name': 'Giriş Kamerası 1',
            'confidence': 0.96,
            'gate_state': 'triggered',
            'seen_at': DateTime.now().subtract(const Duration(seconds: 20)).toUtc().toIso8601String(),
            'identity': <String, dynamic>{
              'kind': 'resident',
              'apartment_label': 'A Blok D:12',
              'person_label': 'Ahmet Yılmaz',
            },
          },
          <String, dynamic>{
            'id': 502,
            'plate': '35 CK 880',
            'decision': 'ALLOWED',
            'decision_kind': 'acildi',
            'reason': 'vehicle',
            'reason_label': 'Çıkış tamamlandı',
            'direction': 'cikis',
            'door_name': 'Ana Giriş Kapısı',
            'device_name': 'Çıkış Kamerası 1',
            'confidence': 0.94,
            'gate_state': 'triggered',
            'seen_at': DateTime.now().subtract(const Duration(seconds: 35)).toUtc().toIso8601String(),
            'identity': <String, dynamic>{
              'kind': 'resident',
              'apartment_label': 'C Blok D:2',
              'person_label': 'Zeynep Kaya',
            },
          },
        ],
      });

  @override
  Future<List<PlateBlacklistItem>> blacklist(int site) async => const <PlateBlacklistItem>[];

  @override
  Future<List<PlatePermit>> permits(int site) async => const <PlatePermit>[];

  @override
  Future<List<PlateDecisionRow>> events(int site, {String? decision}) async => const <PlateDecisionRow>[];

  @override
  Future<PlateSettings> settings(int site) async => PlateSettings.fromJson(<String, dynamic>{
        'doors': <dynamic>[],
        'cameras': <dynamic>[],
        'auto_open_supported': true,
      });
}

PlateCameraRow _camRow({
  required int id,
  required String name,
  int? gateId = 10,
  String? direction,
  bool isActive = true,
}) {
  return PlateCameraRow.fromJson(<String, dynamic>{
    'id': id,
    'name': name,
    'host': '',
    'is_active': isActive,
    'managed': true,
    'direction': direction,
    if (gateId != null)
      'gate': <String, dynamic>{
        'id': gateId,
        'name': 'Ana Giriş Kapısı',
        'direction_mode': 'cift',
      },
    'status': <String, dynamic>{'state': 'online', 'label': 'Çalışıyor', 'color': 'yesil'},
    'probe': <String, dynamic>{'status': 'ok'},
    'snapshot': <String, dynamic>{'available': false},
  });
}

void main() {
  tearDown(() {
    PlateRecognitionEngine.instance.stop();
    PlateRecognitionEngine.instance.clearDecision();
  });

  group('GateCameraWallSlots ve mergeLiveStreamEvents', () {
    final gate = PlateGate.fromJson(<String, dynamic>{
      'id': 10,
      'name': 'Ana Giriş Kapısı',
      'direction_mode': 'cift',
      'direction_label': 'Giriş + Çıkış',
      'is_active': true,
      'status': <String, dynamic>{'state': 'online', 'label': 'Çalışıyor', 'color': 'yesil'},
      'cameras': <dynamic>[],
    });

    test('kamera yokken 4 yuvanın tamamı boş (yer tutucu) çözülür', () {
      final slots = GateCameraWallSlots.resolve(gate: gate, cameras: const <PlateCameraRow>[]);
      expect(slots.entry1, isNull);
      expect(slots.entry2, isNull);
      expect(slots.exit1, isNull);
      expect(slots.exit2, isNull);
      expect(slots.activeCount, 0);
    });

    test('2 giriş + 2 çıkış kamerası doğru yuvalara yerleşir ve atanmamış kamera ayrılır', () {
      final cams = <PlateCameraRow>[
        _camRow(id: 1, name: 'Giriş 1', direction: 'giris'),
        _camRow(id: 2, name: 'Çıkış 1', direction: 'cikis'),
        _camRow(id: 3, name: 'Giriş 2', direction: 'giris'),
        _camRow(id: 4, name: 'Çıkış 2', direction: 'cikis'),
        _camRow(id: 99, name: 'Boşta Kamera', gateId: null),
      ];
      final slots = GateCameraWallSlots.resolve(gate: gate, cameras: cams);
      expect(slots.entry1?.id, 1);
      expect(slots.entry2?.id, 3);
      expect(slots.exit1?.id, 2);
      expect(slots.exit2?.id, 4);
      expect(slots.activeCount, 4);
      expect(slots.unassignedCameras.map((c) => c.id), <int>[99]);
    });

    test('yerel ve sunucu olayları mükerrer üretmeden birleşir ve snapshot korunur', () {
      final now = DateTime.now();
      final snap = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final local = <PlateEngineDecision>[
        PlateEngineDecision(
          plate: '34NBL304',
          decision: PlateDecisionType.acildi,
          reason: 'Sakin aracı',
          doorId: 1,
          gateName: 'Ana Kapı',
          direction: 'giris',
          cameraId: 1,
          cameraName: 'Giriş Kamerası 1',
          confidence: 0.95,
          snapshotBytes: snap,
          timestamp: now,
        ),
      ];
      final server = <PlateDecisionRow>[
        PlateDecisionRow.fromJson(<String, dynamic>{
          'id': 77,
          'plate': '34 NBL 304',
          'decision': 'ALLOWED',
          'decision_kind': 'acildi',
          'reason_label': 'Kayıtlı sakin aracı',
          'direction': 'giris',
          'door_name': 'Ana Kapı',
          'seen_at': now.add(const Duration(seconds: 2)).toUtc().toIso8601String(),
        }),
      ];

      final merged = mergeLiveStreamEvents(localDecisions: local, serverRows: server);
      expect(merged.length, 1);
      expect(merged.single.serverId, 77);
      expect(merged.single.snapshotBytes, snap);
      expect(merged.single.confidence, 0.95);
    });
  });

  group('PlateLiveCommandCenterPage tam ekran 4 kamera komuta merkezi', () {
    const managerSite = PlateSite(code: 1, name: 'Cenk Sitesi', access: PlateAccess.manager);

    testWidgets('1920x1080 masaüstünde 4 yer tutucu kamera ve sol/sağ kartlar taşmadan çizilir, tıklanınca ayrıntı açılır',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeCams = FakeCamerasService(
        overview: overviewJson(cameras: const <Map<String, dynamic>>[]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PlateLiveCommandCenterPage(
            authService: _FakeAuthService(),
            initialSite: managerSite,
            sites: const <PlateSite>[managerSite],
            service: _FakePlateRecognitionService(),
            camerasService: fakeCams,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Sol, orta ve sağ ana başlıklar
      expect(find.text('Menüler & Diğer Bilgiler'), findsOneWidget);
      expect(find.text('Canlı Otopark Durum Bilgisi'), findsOneWidget);
      expect(find.text('Giriş Kameraları'), findsOneWidget);
      expect(find.text('Çıkış Kameraları'), findsOneWidget);
      expect(find.text('Giriş Olayları'), findsOneWidget);
      expect(find.text('Çıkış Olayları'), findsOneWidget);

      // Kamera yokken 2 giriş + 2 çıkış = 4 yer tutucu çerçeve ve ekleme butonları gösterilir
      expect(find.byKey(const ValueKey<String>('cc_placeholder_giris_1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('cc_placeholder_giris_2')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('cc_placeholder_cikis_1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('cc_placeholder_cikis_2')), findsOneWidget);
      expect(find.text('Kamera Ekle'), findsWidgets);
      expect(find.text('Ağda Ara'), findsWidgets);

      // Sağ üst Giriş Olayları kartındaki olaya tıklanınca ayrıntı modalı açılır
      await tester.tap(find.text('A Blok D:12 • Ahmet Yılmaz').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Giriş Olayı Ayrıntısı'), findsOneWidget);
      await tester.tap(find.byTooltip('Kapat').last);
      await tester.pumpAndSettle();

      // Sağ alt Çıkış Olayları kartındaki olaya tıklanınca ayrıntı modalı açılır
      await tester.tap(find.text('C Blok D:2 • Zeynep Kaya'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Çıkış Olayı Ayrıntısı'), findsOneWidget);
      await tester.tap(find.byTooltip('Kapat').last);
      await tester.pumpAndSettle();

      // Sol alt Canlı Otopark Durum Bilgisi kartına tıklanınca ayrıntı modalı açılır
      await tester.tap(find.text('Canlı Otopark Durum Bilgisi'));
      await tester.pumpAndSettle();
      expect(find.text('Canlı Otopark Durum Bilgisi • Ayrıntılar'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pumpAndSettle();
    });

    testWidgets('1 giriş ve 1 çıkış kamerası varken 2 aktif yuva + 2 yer tutucu yuva yan yana gösterilir',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeCams = FakeCamerasService(
        overview: overviewJson(
          cameras: <Map<String, dynamic>>[
            cameraJson(
              id: 1,
              name: 'Batı Giriş Cam 1',
              managed: false,
              snapshot: false,
              gate: const <String, dynamic>{'id': 10, 'name': 'Ana Giriş Kapısı', 'direction_mode': 'cift'},
              direction: 'giris',
            ),
            cameraJson(
              id: 2,
              name: 'Batı Çıkış Cam 1',
              managed: false,
              snapshot: false,
              gate: const <String, dynamic>{'id': 10, 'name': 'Ana Giriş Kapısı', 'direction_mode': 'cift'},
              direction: 'cikis',
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PlateLiveCommandCenterPage(
            authService: _FakeAuthService(),
            initialSite: managerSite,
            sites: const <PlateSite>[managerSite],
            service: _FakePlateRecognitionService(),
            camerasService: fakeCams,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey<String>('cc_active_giris_1_1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('cc_placeholder_giris_2')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('cc_active_cikis_1_2')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('cc_placeholder_cikis_2')), findsOneWidget);
    });

    testWidgets('360x800 dar ekranda dikey taşma (overflow) olmadan duyarlı (responsive) çalışır', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeCams = FakeCamerasService(
        overview: overviewJson(cameras: const <Map<String, dynamic>>[]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PlateLiveCommandCenterPage(
            authService: _FakeAuthService(),
            initialSite: managerSite,
            sites: const <PlateSite>[managerSite],
            service: _FakePlateRecognitionService(),
            camerasService: fakeCams,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Menüler & Diğer Bilgiler'), findsOneWidget);
      expect(find.text('Giriş Kameraları'), findsOneWidget);
    });

    testWidgets('Plaka Tanıma ekranında "Canlı akış" düğmesine basıldığında tam ekran pencere açılır', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeCams = FakeCamerasService(
        overview: overviewJson(cameras: const <Map<String, dynamic>>[]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlateRecognitionView(
                authService: _FakeAuthService(),
                sites: const <PlateSite>[managerSite],
                service: _FakePlateRecognitionService(),
                camerasService: fakeCams,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('plate_tab_2')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(PlateLiveCommandCenterPage), findsOneWidget);
      expect(find.text('Giriş Kameraları'), findsOneWidget);
      expect(find.text('Çıkış Kameraları'), findsOneWidget);
    });
  });
}
