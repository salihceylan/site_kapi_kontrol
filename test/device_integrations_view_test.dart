// Kamera ve Plaka ekranı (sözleşme v3): "Yakında…" kalktı, otomatik açma durumu sunucudan, ızgara + canlı akış, ağda kamera ara -> forma aktar,
// modül kapalıysa dürüst uyarı. Sahte servislerle (ağ yok).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/device_integrations_api.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/ui/views/device_integrations_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/plate_camera_grid.dart' show PlateCameraTile;

import 'plate_cameras_support.dart';

class _FakeAuth extends Fake implements AuthService {}

class _FakePlate extends Fake implements PlateRecognitionService {
  int calls = 0;

  @override
  Future<PlateLiveFeed> liveFeed(int site, {int? limit}) async {
    calls++;
    return PlateLiveFeed.fromJson(<String, dynamic>{
      'inside_count': 3,
      'refresh_seconds': 5,
      'limit': 30,
      'events': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'plate': '34 ABC 123',
          'decision': 'ALLOWED',
          'decision_kind': 'acildi',
          'direction': 'giris',
          'reason_label': 'x',
          'seen_at': DateTime.now().toUtc().toIso8601String(),
          'door_name': 'Ana Kapı',
          'identity': <String, dynamic>{'kind': 'resident', 'apartment_label': 'A - 5', 'person_label': 'Ali Y.'},
          'gate_state': 'triggered',
        },
      ],
    });
  }
}

class _FakeDevice extends Fake implements DeviceIntegrationsService {
  @override
  Future<List<CameraDevice>> cameras(int site) async => <CameraDevice>[
    CameraDevice.fromJson(<String, dynamic>{'id': 9, 'brand': 'hikvision', 'name': 'Eski kamera', 'host': '10.0.0.5', 'port': 80, 'has_password': true, 'is_active': true}),
  ];

  @override
  Future<List<PlateEventRow>> plateEvents(int site) async => const <PlateEventRow>[];
}

const DeviceSite _site = DeviceSite(code: 5, name: 'Gül Sitesi');

Future<void> _pump(
  WidgetTester tester,
  FakeCamerasService cameras, {
  DeviceSite site = _site,
  _FakePlate? plate,
  Size size = const Size(900, 3000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DeviceIntegrationsView(
            authService: _FakeAuth(),
            sites: <DeviceSite>[site],
            service: _FakeDevice(),
            camerasService: cameras,
            plateService: plate ?? _FakePlate(),
            refreshInterval: const Duration(minutes: 10),
            discoveryPollInterval: const Duration(seconds: 3),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

void main() {
  group('DeviceIntegrationsView (v3)', () {
    testWidgets('"Yakında…" yok; Etkin durumu sunucudan; kamera ızgarası ve canlı akış (kimlik + kapı durumu) aynı ekranda', (tester) async {
      final service = FakeCamerasService(overview: overviewJson(cameras: <Map<String, dynamic>>[cameraJson(id: 1), cameraJson(id: 2, name: 'Çıkış kamerası', direction: 'cikis')]))
        ..snapshotResponder = (id, etag, call) => SnapshotFetch(bytes: tinyPng, etag: '"e"');
      await _pump(tester, service);
      expect(find.textContaining('Yakında'), findsNothing);
      expect(find.text('Plakayla otomatik kapı açma'), findsOneWidget);
      expect(find.text('Etkin'), findsOneWidget);
      expect(find.textContaining('kapılar plakayla açılabilir'), findsOneWidget);
      expect(find.textContaining('Kulübe PC: Çevrimiçi'), findsOneWidget);
      expect(find.textContaining('okuma modeli onaylı'), findsWidgets);
      // Izgara
      expect(find.byType(PlateCameraTile), findsNWidgets(2));
      expect(find.text('Giriş kamerası'), findsOneWidget);
      expect(find.text('Çıkış kamerası'), findsOneWidget);
      // Canlı akış bileşeni (sayaç + kimlikli kart + kapı durumu rozeti)
      expect(find.text('İçeride: 3 araç', findRichText: true), findsOneWidget);
      expect(find.text('Daire A - 5 · Ali Y.'), findsOneWidget);
      expect(find.text('Kapı tetiklendi ✓'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('btn_discover')), findsOneWidget);
      await _close(tester);
    });

    testWidgets('otomatik açma etkin değilse nedeni yazılır (kenar çevrimdışı); çevrimdışı kenar satırı dürüst', (tester) async {
      final service = FakeCamerasService(
        overview: overviewJson(
          edgeOnline: false,
          autoOpen: <String, dynamic>{'state': 'inactive', 'reason': 'edge_offline', 'message': 'Kenar PC çevrimdışı: plakayla kapı açma duruyor.'},
        ),
      );
      await _pump(tester, service);
      expect(find.text('Etkin değil'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('auto_open_message')), findsOneWidget);
      expect(find.text('Kenar PC çevrimdışı: plakayla kapı açma duruyor.'), findsOneWidget);
      expect(find.textContaining('Kulübe PC: Çevrimdışı'), findsOneWidget);
      expect(find.text('Kenar PC çevrimdışı'), findsWidgets, reason: 'karoda da görüntü yerine dürüst yer tutucu');
      await _close(tester);
    });

    testWidgets('kenar istemci hiç yoksa ve kamera yoksa yönlendirme metni gösterilir', (tester) async {
      final service = FakeCamerasService(
        overview: overviewJson(
          cameras: const <Map<String, dynamic>>[],
          clients: const <Map<String, dynamic>>[],
          edgeOnline: false,
          autoOpen: <String, dynamic>{'state': 'inactive', 'reason': 'no_edge_client', 'message': 'Kenar uygulama tanımlı değil.'},
        ),
      );
      await _pump(tester, service);
      expect(find.byKey(const ValueKey<String>('no_cameras')), findsOneWidget);
      expect(find.textContaining('kenar istemci'), findsWidgets);
      await _close(tester);
    });

    testWidgets('Plaka Tanıma modülü kapalı: dürüst uyarı, ızgara / canlı akış yok, eski kamera listesi çalışır', (tester) async {
      final service = FakeCamerasService()..overviewError = ApiException('x', statusCode: 403, code: PlateCameraErrors.moduleDisabled);
      await _pump(tester, service);
      expect(find.byKey(const ValueKey<String>('module_off_notice')), findsOneWidget);
      expect(find.textContaining('Plaka Tanıma modülünün bu site için açık olması gerekir'), findsOneWidget);
      expect(find.textContaining('Yakında'), findsNothing);
      expect(find.text('Eski kamera (Hikvision)'), findsOneWidget);
      expect(find.text('Canlı akış'), findsNothing);
      await _close(tester);
    });

    testWidgets('Ağda kamera ara -> sonuç listesi -> cihaz seçilince kamera formu IP ve portla dolu açılır -> kaydedilir', (tester) async {
      final service = FakeCamerasService()
        ..startResponder = ((_) => DiscoveryStart(command: EdgeCommand.fromJson(commandJson(status: 'done', result: discoveryResultJson())), reused: false));
      await _pump(tester, service);
      await tester.tap(find.byKey(const ValueKey<String>('btn_discover')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Ağda kamera ara'), findsWidgets);
      await tester.tap(find.text('DS-2CD2043 · Hikvision'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Form
      expect(find.text('Kamera ekle'), findsWidgets);
      expect(tester.widget<TextField>(find.byKey(const ValueKey<String>('cam_host'))).controller?.text, '192.168.1.64');
      expect(tester.widget<TextField>(find.byKey(const ValueKey<String>('cam_port'))).controller?.text, '554');
      expect(find.textContaining('Boş bırakılırsa markaya göre: /Streaming/Channels/101'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey<String>('cam_name')), 'Giriş kapısı');
      await tester.enterText(find.byKey(const ValueKey<String>('cam_user')), 'admin');
      await tester.enterText(find.byKey(const ValueKey<String>('cam_pass')), 'gizli123');
      await tester.tap(find.byKey(const ValueKey<String>('cam_save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(service.created, hasLength(1));
      final draft = service.created.single;
      expect(draft.host, '192.168.1.64');
      expect(draft.brand, 'hikvision');
      final body = draft.toBody(edit: false);
      expect(body['port'], 554);
      expect(body['username'], 'admin');
      expect(body['password'], 'gizli123');
      expect(body.containsKey('gate_id'), isFalse);
      expect(find.text('Kamera kaydedildi. Kenar PC RTSP\'yi sınıyor.'), findsOneWidget);
      expect(service.overviewCalls, greaterThanOrEqualTo(2), reason: 'kayıttan sonra ızgara yenilenir');
      await _close(tester);
    });

    testWidgets('kamera formu: marka ONVIF ise kenarın bulacağı yazılır; kapı moduna uyan yönler; sunucu hatası diyalogda gösterilir', (tester) async {
      final service = FakeCamerasService()..createError = ApiException('Kamera yönü, kapının yön moduyla uyuşmuyor.', statusCode: 400, code: 'CAMERA_DIRECTION_CONFLICT');
      await _pump(tester, service);
      await tester.tap(find.byKey(const ValueKey<String>('btn_add_camera')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Marka ONVIF
      await tester.tap(find.byKey(const ValueKey<String>('cam_brand')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('ONVIF (diğer)').last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('kenar PC ONVIF ile kamerayı kendisi bulur'), findsOneWidget);
      // Çıkış kapısı seç: yön listesinde "Giriş" olmaz
      await tester.tap(find.byKey(const ValueKey<String>('cam_gate')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Çıkış Kapısı').last);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey<String>('cam_direction_8')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Giriş'), findsNothing);
      expect(find.text('Çıkış'), findsWidgets);
      await tester.tap(find.text('Otomatik').last);
      await tester.pump(const Duration(milliseconds: 400));
      // Eksik ad: yerel doğrulama
      await tester.tap(find.byKey(const ValueKey<String>('cam_save')));
      await tester.pump();
      expect(find.text('Kamera adını yazın.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey<String>('cam_name')), 'Çıkış');
      await tester.enterText(find.byKey(const ValueKey<String>('cam_host')), '192.168.1.80');
      await tester.tap(find.byKey(const ValueKey<String>('cam_save')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Kamera yönü, kapının yön moduyla uyuşmuyor.'), findsOneWidget, reason: 'sunucu mesajı diyalogda kalır');
      expect(find.byKey(const ValueKey<String>('cam_save')), findsOneWidget);
      await _close(tester);
    });

    testWidgets('dar ekran (320 dp): ızgara, kamera formu ve keşif diyaloğu taşmaz', (tester) async {
      final service = FakeCamerasService(overview: overviewJson(cameras: <Map<String, dynamic>>[cameraJson(id: 1, probe: const <String, dynamic>{'status': 'failed', 'message': 'kimlik doğrulanamadı: kullanıcı adı ya da parola hatalı olabilir'})]))
        ..snapshotResponder = ((id, etag, call) => SnapshotFetch(bytes: tinyPng, etag: '"e"'))
        ..startResponder = ((_) => DiscoveryStart(command: EdgeCommand.fromJson(commandJson(status: 'pending', waitingOffline: true)), reused: false));
      await _pump(tester, service, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey<String>('btn_add_camera')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('btn_add_camera')));
      await tester.pumpAndSettle();
      expect(find.text('Kamera ekle'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey<String>('btn_discover')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('btn_discover')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('discovery_offline')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester);
    });

    testWidgets('kurul üyesi (salt okur): ekleme / arama düğmesi yok; yazma yetkisinde menüden Pasifleştir çalışır', (tester) async {
      final service = FakeCamerasService();
      await _pump(tester, service, site: const DeviceSite(code: 5, name: 'Gül Sitesi', canWrite: false));
      expect(find.byKey(const ValueKey<String>('btn_discover')), findsNothing);
      expect(find.byKey(const ValueKey<String>('btn_add_camera')), findsNothing);
      expect(find.byKey(const ValueKey<String>('tile_menu')), findsNothing);
      await _close(tester);

      final writer = FakeCamerasService();
      await _pump(tester, writer);
      await tester.tap(find.byKey(const ValueKey<String>('tile_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pasifleştir'));
      await tester.pumpAndSettle();
      expect(writer.activeChanges, <({int id, bool active})>[(id: 1, active: false)]);
      expect(find.text('Kamera pasifleştirildi.'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('düzenleme: parola boşsa gövdeye girmez (mevcut korunur); "parolayı sil" boş parola gönderir', (tester) async {
      final service = FakeCamerasService();
      await _pump(tester, service);
      await tester.tap(find.byKey(const ValueKey<String>('tile_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Düzenle'));
      await tester.pumpAndSettle();
      expect(find.text('Kamerayı düzenle'), findsOneWidget);
      expect(find.textContaining('Boş bırakılırsa mevcut parola korunur'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('cam_save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(service.updated, hasLength(1));
      expect(service.updated.single.draft.toBody(edit: true).containsKey('password'), isFalse);
      expect(service.updated.single.draft.toBody(edit: true)['gate_id'], 7);
      expect(const PlateCameraDraft(name: 'a', brand: 'onvif', host: 'h', clearPassword: true).toBody(edit: true)['password'], '');
      await _close(tester);
    });
  });
}
