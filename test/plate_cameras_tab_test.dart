// Plaka Tanıma > "Geçiş noktaları" sekmesi ve kapı satırındaki "Kamera ekle / ata" (kapı ön seçili). Sahte servislerle (ağ yok).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/ui/views/plate_recognition_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/plate_gates_panel.dart';

import 'plate_cameras_support.dart';

class _FakeAuth extends Fake implements AuthService {}

class _FakePlate extends Fake implements PlateRecognitionService {
  @override
  Future<List<PlateDecisionRow>> events(int site, {String? decision}) async => const <PlateDecisionRow>[];

  @override
  Future<PlateGatesOverview> gatesOverview(int site) async => PlateGatesOverview.fromJson(<String, dynamic>{
    'settings': <String, dynamic>{'guest_rule': 'tum_bos', 'heartbeat_warn_seconds': 180, 'heartbeat_crit_seconds': 600},
    'guest_rules': <dynamic>[
      <String, dynamic>{'code': 'tum_bos', 'label': 'Tüm park yerleri boşsa'},
    ],
    'direction_modes': <dynamic>[
      <String, dynamic>{'code': 'cikis', 'label': 'Yalnız çıkış'},
    ],
    'gates': <dynamic>[
      <String, dynamic>{
        'id': 8,
        'name': 'Çıkış Kapısı',
        'direction_mode': 'cikis',
        'direction_label': 'Yalnız çıkış',
        'is_active': true,
        'status': <String, dynamic>{'state': 'koptu', 'color': 'kirmizi'},
        'cameras': <dynamic>[],
      },
    ],
    'unassigned_cameras': <dynamic>[],
    'devices': <dynamic>[],
    'edge_clients': <dynamic>[],
    'inside_total': 0,
  });

  @override
  Future<PlateInside> inside(int site) async => PlateInside.fromJson(<String, dynamic>{'total': 0, 'items': <dynamic>[], 'apartments': <dynamic>[]});
}

Future<void> _pump(WidgetTester tester, FakeCamerasService cameras) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PlateRecognitionView(
            authService: _FakeAuth(),
            sites: const <PlateSite>[PlateSite(code: 1, name: 'Gül Sitesi', access: PlateAccess.manager)],
            service: _FakePlate(),
            camerasService: cameras,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Geçiş noktaları sekmesi varsayılan gelir; Kameralar sekmesi ayrı bulunmaz', (tester) async {
    final cameras = FakeCamerasService(overview: overviewJson(cameras: const <Map<String, dynamic>>[], clients: const <Map<String, dynamic>>[], edgeOnline: false));
    await _pump(tester, cameras);
    // Kameralar sekmesi ana menüden kaldırıldı
    expect(find.text('Kameralar'), findsNothing);
    // Geçiş noktaları varsayılan açık
    expect(find.text('Geçiş noktaları'), findsWidgets);
    expect(find.byType(PlateGatesPanel), findsOneWidget);
    expect(find.text('Çıkış Kapısı'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Geçiş noktaları: kapıdaki "Kamera ekle / ata" formu o kapı ön seçili açar ve kamera o kapıyla kaydedilir', (tester) async {
    final cameras = FakeCamerasService();
    await _pump(tester, cameras);
    // Geçiş noktaları varsayılan açık
    expect(find.textContaining('Bu geçiş noktasına henüz bir kamera atanmamış'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('gate_add_camera_8')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey<String>('cam_gate')), matching: find.text('Çıkış Kapısı')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey<String>('cam_name')), 'Çıkış kamerası');
    await tester.enterText(find.byKey(const ValueKey<String>('cam_host')), '192.168.1.70');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(cameras.created.single.gateId, 8);
    expect(cameras.created.single.name, 'Çıkış kamerası');
    await tester.pumpWidget(const SizedBox());
  });
}
