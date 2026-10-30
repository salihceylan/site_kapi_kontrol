// Plaka Tanıma > "Kameralar" sekmesi ve Geçiş noktaları satırındaki "Kamera ekle" (kapı ön seçili). Sahte servislerle (ağ yok).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/ui/views/device_integrations_view.dart';
import 'package:site_kapi_kontrol/ui/views/plate_recognition_view.dart';

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
  testWidgets('Kameralar sekmesi var; kamera paneli açılır, kenar istemci yoksa tek satır yönlendirme çıkar, canlı akış tekrarlanmaz', (tester) async {
    final cameras = FakeCamerasService(overview: overviewJson(cameras: const <Map<String, dynamic>>[], clients: const <Map<String, dynamic>>[], edgeOnline: false));
    await _pump(tester, cameras);
    expect(find.text('Kameralar'), findsOneWidget, reason: 'sekme düğmesi');
    await tester.tap(find.text('Kameralar'));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceIntegrationsView), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('btn_discover')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('btn_add_camera')), findsOneWidget);
    expect(find.text('Canlı akış'), findsOneWidget, reason: 'yalnız sekme düğmesi; panelde ikinci başlık yok');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Geçiş noktaları: kapıdaki "Kamera ekle" formu o kapı ön seçili açar ve kamera o kapıyla kaydedilir', (tester) async {
    final cameras = FakeCamerasService();
    await _pump(tester, cameras);
    await tester.tap(find.text('Geçiş noktaları'));
    await tester.pumpAndSettle();
    expect(find.text('Kamera bağlı değil.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('gate_add_camera_8')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey<String>('cam_gate')), matching: find.text('Çıkış Kapısı')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey<String>('cam_name')), 'Çıkış kamerası');
    await tester.enterText(find.byKey(const ValueKey<String>('cam_host')), '192.168.1.70');
    await tester.tap(find.byKey(const ValueKey<String>('cam_save')));
    await tester.pumpAndSettle();
    expect(cameras.created.single.gateId, 8);
    expect(cameras.created.single.name, 'Çıkış kamerası');
    await tester.pumpWidget(const SizedBox());
  });
}
