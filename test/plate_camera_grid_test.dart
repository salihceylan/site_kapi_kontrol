import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/ui/widgets/plate_camera_grid.dart';

import 'plate_cameras_support.dart';

List<PlateCameraRow> _cams(List<Map<String, dynamic>> raw) => <PlateCameraRow>[for (final c in raw) PlateCameraRow.fromJson(c)];

Future<void> _pump(
  WidgetTester tester,
  FakeCamerasService service,
  List<PlateCameraRow> cameras, {
  bool edgeOnline = true,
  bool canWrite = true,
  Duration refresh = const Duration(seconds: 4),
  void Function(PlateCameraMenuAction, PlateCameraRow)? onAction,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: PlateCameraGrid(service: service, siteCode: 5, cameras: cameras, edgeOnline: edgeOnline, refresh: refresh, canWrite: canWrite, onAction: onAction),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _close(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  group('PlateCameraGrid', () {
    testWidgets('çevrimiçi / çevrimdışı / hiç bağlanmadı rozetleri, yön etiketi ve probe rozetleri; 320 dp taşmaz', (tester) async {
      tester.view.physicalSize = const Size(320, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = FakeCamerasService()..snapshotResponder = (id, etag, call) => SnapshotFetch(bytes: tinyPng, etag: '"e$id"', capturedAt: DateTime(2026, 10, 29, 14, 3, 22));
      final cameras = _cams(<Map<String, dynamic>>[
        cameraJson(id: 1, name: 'Giriş kamerası'),
        cameraJson(id: 2, name: 'Çıkış kamerası', color: 'kirmizi', state: 'koptu', direction: 'cikis', probe: const <String, dynamic>{'status': 'failed', 'message': 'kimlik doğrulanamadı'}),
        cameraJson(id: 3, name: 'Yan kapı', color: 'gri', state: 'hic_baglanmadi', gate: null, probe: const <String, dynamic>{'status': 'pending'}),
        cameraJson(id: 4, name: 'Sarı kamera', color: 'sari', direction: 'auto', probe: const <String, dynamic>{'status': 'none'}),
      ]);
      await _pump(tester, service, cameras);
      expect(tester.takeException(), isNull);

      expect(find.text('Çevrimiçi'), findsOneWidget);
      expect(find.text('Çevrimdışı'), findsOneWidget);
      expect(find.text('Hiç bağlanmadı'), findsOneWidget);
      expect(find.text('Gecikmeli'), findsOneWidget);
      // Yön / kapı etiketi
      expect(find.text('Ana Kapı · Giriş'), findsOneWidget);
      expect(find.text('Ana Kapı · Çıkış'), findsOneWidget);
      expect(find.text('Kapı yok'), findsOneWidget);
      expect(find.text('Ana Kapı · Otomatik'), findsOneWidget);
      // Probe rozetleri
      expect(find.text('RTSP sınandı 1920x1080 ✓'), findsOneWidget);
      expect(find.text('Başarısız: kimlik doğrulanamadı'), findsOneWidget);
      expect(find.text('Sınanıyor…'), findsOneWidget);
      // Görüntü baytı karoda gösterilir (Image.memory) ve çekim saati yazar.
      expect(find.byKey(const ValueKey<String>('tile_image')), findsNWidgets(4));
      expect(find.text('14:03:22'), findsNWidgets(4));
      expect(find.bySemanticsLabel(RegExp('Giriş kamerası, Ana Kapı · Giriş, Çevrimiçi, RTSP sınandı 1920x1080')), findsOneWidget);
      await _close(tester);
    });

    testWidgets('pasif kamera soluk ve "Pasif" rozetli, görüntü istenmez; eski belirteçli kamera için istek yok', (tester) async {
      final service = FakeCamerasService()..snapshotResponder = (id, etag, call) => SnapshotFetch(bytes: tinyPng, etag: '"e"');
      final cameras = _cams(<Map<String, dynamic>>[cameraJson(id: 1, active: false), cameraJson(id: 2, managed: false)]);
      await _pump(tester, service, cameras);
      expect(find.text('Pasif'), findsOneWidget);
      expect(find.text('Kamera pasif'), findsOneWidget);
      expect(find.text('Eski olay belirteçli'), findsOneWidget);
      expect(service.snapshotCalls, isEmpty, reason: 'pasif ve eski kameradan karo görüntüsü beklenmez');
      expect(tester.widget<Opacity>(find.ancestor(of: find.text('Pasif'), matching: find.byType(Opacity)).first).opacity, lessThan(1));
      await _close(tester);
    });

    testWidgets('görüntü yoksa yer tutucu: kenar çevrimdışıysa "Kenar PC çevrimdışı", değilse "Görüntü bekleniyor"', (tester) async {
      final service = FakeCamerasService(); // varsayılan: kare yok (404 NO_SNAPSHOT)
      final cameras = _cams(<Map<String, dynamic>>[cameraJson(id: 1, snapshot: false)]);
      await _pump(tester, service, cameras, edgeOnline: false);
      expect(find.text('Kenar PC çevrimdışı'), findsOneWidget);
      await _close(tester);
      await _pump(tester, service, cameras);
      expect(find.text('Görüntü bekleniyor'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('tile_image')), findsNothing);
      await _close(tester);
    });

    testWidgets('ETag ile yenilenir: 304 görüntüyü korur; sunucu hata verirse son görüntü kalır; kare silinirse görüntü kalkar', (tester) async {
      final service = FakeCamerasService();
      service.snapshotResponder = (id, etag, call) {
        switch (call) {
          case 1:
            return SnapshotFetch(bytes: tinyPng, etag: '"v1"', capturedAt: DateTime(2026, 10, 29, 9, 0, 0));
          case 2:
            return SnapshotFetch(etag: etag, notModified: true);
          case 3:
            throw ApiException('Sunucuya bağlanılamadı.');
          default:
            return const SnapshotFetch(noSnapshot: true);
        }
      };
      await _pump(tester, service, _cams(<Map<String, dynamic>>[cameraJson(id: 1)]));
      expect(service.snapshotCalls.single.etag, isNull);
      expect(find.byKey(const ValueKey<String>('tile_image')), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(service.snapshotCalls[1].etag, '"v1"', reason: 'If-None-Match için önceki ETag gönderilir');
      expect(find.byKey(const ValueKey<String>('tile_image')), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('tile_image')), findsOneWidget, reason: 'hata: son görüntü korunur');
      expect(find.textContaining('yenilenemedi'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('tile_image')), findsNothing, reason: 'sunucu kareyi sildi: istemcide kalmaz');
      await _close(tester);
    });

    testWidgets('yenileme aralığı sunucudan gelir; ekran kapanınca zamanlayıcı durur', (tester) async {
      final service = FakeCamerasService()..snapshotResponder = (id, etag, call) => SnapshotFetch(bytes: tinyPng, etag: '"v$call"');
      await _pump(tester, service, _cams(<Map<String, dynamic>>[cameraJson(id: 1)]), refresh: const Duration(seconds: 9));
      expect(service.snapshotCalls.length, 1);
      await tester.pump(const Duration(seconds: 8));
      expect(service.snapshotCalls.length, 1, reason: 'aralık 9 sn');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(service.snapshotCalls.length, 2);
      await _close(tester);
      await tester.pump(const Duration(minutes: 5));
      expect(service.snapshotCalls.length, 2, reason: 'dispose sonrası istek yok');
    });

    testWidgets('uygulama arka plana geçince istek durur, dönünce hemen yeniler', (tester) async {
      final service = FakeCamerasService()..snapshotResponder = (id, etag, call) => SnapshotFetch(bytes: tinyPng, etag: '"v$call"');
      await _pump(tester, service, _cams(<Map<String, dynamic>>[cameraJson(id: 1)]));
      expect(service.snapshotCalls.length, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 1));
      expect(service.snapshotCalls.length, 1, reason: 'arka planda istek yok');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(service.snapshotCalls.length, 2);
      await _close(tester);
    });

    testWidgets('menü yalnız yazma yetkisinde; eylemler çağırana iletilir', (tester) async {
      final service = FakeCamerasService();
      final actions = <PlateCameraMenuAction>[];
      final cameras = _cams(<Map<String, dynamic>>[cameraJson(id: 1, snapshot: false)]);
      await _pump(tester, service, cameras, canWrite: false);
      expect(find.byKey(const ValueKey<String>('tile_menu')), findsNothing);
      await _close(tester);

      await _pump(tester, service, cameras, onAction: (a, c) => actions.add(a));
      await tester.tap(find.byKey(const ValueKey<String>('tile_menu')));
      await tester.pumpAndSettle();
      expect(find.text('Düzenle'), findsOneWidget);
      expect(find.text('Yeniden sına'), findsOneWidget);
      expect(find.text('Pasifleştir'), findsOneWidget);
      await tester.tap(find.text('Yeniden sına'));
      await tester.pumpAndSettle();
      expect(actions, <PlateCameraMenuAction>[PlateCameraMenuAction.probe]);
      await _close(tester);
    });

    testWidgets('geniş ekranda birden çok sütun', (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final service = FakeCamerasService();
      await _pump(tester, service, _cams(<Map<String, dynamic>>[cameraJson(id: 1, snapshot: false), cameraJson(id: 2, snapshot: false), cameraJson(id: 3, snapshot: false)]));
      final first = tester.getTopLeft(find.byType(PlateCameraTile).at(0));
      final second = tester.getTopLeft(find.byType(PlateCameraTile).at(1));
      expect(second.dy, first.dy, reason: 'aynı satırda yan yana');
      expect(tester.takeException(), isNull);
      await _close(tester);
    });
  });
}
