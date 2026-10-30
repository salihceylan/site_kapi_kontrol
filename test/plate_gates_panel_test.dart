import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/plate_audit_label.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/ui/widgets/plate_gates_panel.dart';

class _FakeService extends Fake implements PlateRecognitionService {}

const Map<String, dynamic> _badgeGreen = <String, dynamic>{'state': 'calisiyor', 'color': 'yesil'};

PlateGatesOverview _overview() => PlateGatesOverview.fromJson(<String, dynamic>{
  'settings': <String, dynamic>{'guest_rule': 'tum_bos', 'heartbeat_warn_seconds': 180, 'heartbeat_crit_seconds': 600},
  'guest_rules': <dynamic>[
    <String, dynamic>{'code': 'tum_bos', 'label': 'Tüm park yerleri boşsa'},
    <String, dynamic>{'code': 'en_az_bir_bos', 'label': 'En az bir park yeri boşsa'},
  ],
  'direction_modes': <dynamic>[
    <String, dynamic>{'code': 'giris', 'label': 'Yalnız giriş'},
    <String, dynamic>{'code': 'cift', 'label': 'Çift yön'},
  ],
  'gates': <dynamic>[
    <String, dynamic>{
      'id': 1,
      'name': 'Ana Kapı',
      'direction_mode': 'cift',
      'direction_label': 'Çift yön',
      'is_active': true,
      'device_uid': 'SKP-1',
      'device': <String, dynamic>{'device_uid': 'SKP-1', 'status': <String, dynamic>{'state': 'hic_baglanmadi', 'color': 'gri'}},
      'status': <String, dynamic>{'state': 'koptu', 'color': 'kirmizi'},
      'cameras': <dynamic>[
        <String, dynamic>{'camera_id': 7, 'name': 'Giriş kamerası', 'direction': 'giris', 'is_active': true, 'status': _badgeGreen},
        <String, dynamic>{'camera_id': 8, 'name': 'Çıkış kamerası', 'direction': 'cikis', 'is_active': true, 'status': <String, dynamic>{'state': 'calisiyor', 'color': 'sari'}},
      ],
    },
  ],
  'unassigned_cameras': <dynamic>[
    <String, dynamic>{'id': 9, 'name': 'Boşta kamera'},
  ],
  'devices': <dynamic>[
    <String, dynamic>{'device_uid': 'SKP-1', 'gate_name': 'Ana kapı', 'status': <String, dynamic>{'state': 'hic_baglanmadi', 'color': 'gri'}},
  ],
  'edge_clients': <dynamic>[
    <String, dynamic>{'id': 3, 'name': 'Kulübe PC', 'status': _badgeGreen, 'app_version': '0.1.0'},
  ],
  'inside_total': 2,
});

PlateInside _inside() => PlateInside.fromJson(<String, dynamic>{
  'total': 2,
  'items': <dynamic>[
    <String, dynamic>{'id': 5, 'plate': '34 ABC 123', 'kind': 'resident', 'apartment_label': 'A - 1'},
  ],
  'apartments': <dynamic>[
    <String, dynamic>{'label': 'A - 1', 'parking_slots': 2, 'inside_count': 1, 'guest_admit': <String, dynamic>{'allowed': false, 'reason': 'occupied'}},
    <String, dynamic>{'label': 'A - 2', 'parking_slots': 1, 'inside_count': 0, 'guest_admit': <String, dynamic>{'allowed': true, 'reason': 'all_free'}},
  ],
});

Future<void> _pump(WidgetTester tester, {required bool canWrite}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PlateGatesPanel(service: _FakeService(), siteCode: 1, canWrite: canWrite, overview: _overview(), inside: _inside(), onChanged: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('geçiş noktaları paneli', () {
    testWidgets('yönetici: kapı / kamera / cihaz / kenar PC rozetleri metinle görünür; yazma düğmeleri var', (tester) async {
      await _pump(tester, canWrite: true);
      expect(tester.takeException(), isNull);
      expect(find.text('Ana Kapı'), findsOneWidget);
      // rozet metinleri: kapı koptu (kırmızı), cihaz hiç bağlanmadı (gri), kamera gecikmeli (sarı), kenar PC / kamera çalışıyor (yeşil)
      expect(find.text('Koptu'), findsOneWidget);
      expect(find.text('Hiç bağlanmadı'), findsOneWidget);
      expect(find.text('Gecikmeli'), findsOneWidget);
      expect(find.text('Çalışıyor'), findsWidgets);
      expect(find.textContaining('SmartKeyPass: SKP-1'), findsOneWidget);
      // Kenar PC kaldırıldı
      expect(find.text('Geçiş noktası ekle'), findsNothing);
      expect(find.text('Düzenle'), findsOneWidget);
      // misafir kuralı: 2 yerli dairede 1 araç içeride -> kabul edilmez; boş dairede kabul edilir
      expect(find.text('Park yerleri dolu'), findsOneWidget);
      expect(find.text('Misafir kabul edilir'), findsOneWidget);
      expect(find.textContaining('Misafir araç kabulü: Tüm park yerleri boşsa'), findsOneWidget);
    });

    testWidgets('salt okur (kurul / görevli): hiçbir yazma düğmesi çizilmez', (tester) async {
      await _pump(tester, canWrite: false);
      expect(find.text('Ana Kapı'), findsOneWidget);
      expect(find.text('Geçiş noktası ekle'), findsNothing);
      expect(find.text('Düzenle'), findsNothing);
      expect(find.text('Sil'), findsNothing);
      expect(find.byTooltip('Kenar istemci işlemleri'), findsNothing);
    });

    testWidgets('A3: çıkışı görülmeyen girişler bölümü eşik ve saatleri sunucu verisinden gösterir; denetim başlıkları var', (tester) async {
      final inside = PlateInside.fromJson(<String, dynamic>{
        'total': 1,
        'items': <dynamic>[
          <String, dynamic>{'id': 6, 'plate': '34 OLD 111', 'kind': 'guest', 'inside_hours': 5},
        ],
        'apartments': <dynamic>[],
        'overdue': <String, dynamic>{
          'after_hours': 3,
          'timeout_hours': 8,
          'items': <dynamic>[
            <String, dynamic>{'id': 6, 'plate': '34 OLD 111', 'kind': 'guest', 'inside_hours': 5},
          ],
        },
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlateGatesPanel(service: _FakeService(), siteCode: 1, canWrite: false, overview: _overview(), inside: inside, onChanged: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Çıkışı görülmeyen girişler (1 araç, 3 saatten uzun)'), findsOneWidget);
      expect(find.textContaining('5 saattir içeride'), findsOneWidget);
      expect(find.textContaining('8 saati aşınca'), findsOneWidget);
      expect(plateActionLabel('plate.edge_disconnected'), isNotNull);
      expect(plateActionLabel('plate.inside_timeout'), isNotNull);
    });

    testWidgets('kapı penceresi: ad + kamera seçimi GateDraft gövdesi üretir (çift yönde kamera yönüyle)', (tester) async {
      GateDraft? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => result = await showDialog<GateDraft>(context: context, builder: (_) => GateEditDialog(overview: _overview())),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Yan Kapı');
      await tester.tap(find.text('Boşta kamera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.toBody(), <String, Object?>{
        'name': 'Yan Kapı',
        'direction_mode': 'cift',
        'device_uid': null,
        'cameras': <Map<String, Object?>>[
          <String, Object?>{'camera_id': 9, 'direction': 'auto'},
        ],
      });
    });
  });

  group('kural yardımcıları', () {
    test('kamera yönü kapı moduyla uyumu (sunucuyla aynı)', () {
      expect(gateCameraDirectionFits('cift', 'cikis'), isTrue);
      expect(gateCameraDirectionFits('giris', 'auto'), isTrue);
      expect(gateCameraDirectionFits('giris', 'cikis'), isFalse);
      expect(gateCameraDirectionFits('cikis', 'cikis'), isTrue);
    });

    test('denetim eylemi başlıkları (A1)', () {
      for (final a in <String>['plate.gate_created', 'plate.gate_updated', 'plate.gate_deleted', 'plate.site_settings_changed', 'plate.edge_client_created', 'plate.edge_client_rotated', 'plate.edge_client_revoked', 'plate.inside_cleared']) {
        expect(plateActionLabel(a), isNotNull, reason: a);
      }
    });
  });
}
