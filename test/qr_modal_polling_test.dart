// FAZ 5 / P-c, P-d: DynamicQrPassModal durum yoklaması (800 ms) yaşam döngüsü ve geri sayım
// halkasının yeniden kurma/çizim kapsamı.
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/widgets/dynamic_qr_pass_modal.dart';

import 'support/rebuild_probe.dart';

typedef _QrStatusHandler = Future<(Map<String, dynamic>?, String?)> Function(int callIndex);

class _QrAuth extends AuthService {
  _QrAuth({_QrStatusHandler? handler})
      : handler = handler ?? ((_) async => (<String, dynamic>{}, null)),
        super(api: AuthApi(baseUrl: 'http://localhost'));

  _QrStatusHandler handler;
  int statusCalls = 0;
  int tokenCalls = 0;

  @override
  Future<(Map<String, dynamic>?, String?)> requestDoorQrToken(
    int doorId, {
    Map<String, dynamic>? location,
  }) async {
    tokenCalls++;
    return (<String, dynamic>{'token': 'tok-$tokenCalls', 'expires_in_seconds': 30}, null);
  }

  @override
  Future<(Map<String, dynamic>?, String?)> getDoorQrStatus(String qrToken) {
    statusCalls++;
    return handler(statusCalls);
  }

  @override
  Future<(Map<String, dynamic>?, String?)> revokeMyDoorQr(int doorId) async => (null, null);
}

DoorRecord _door() => DoorRecord(
      id: 7,
      siteCode: 101,
      siteName: 'Güneş Sitesi',
      doorName: 'A Blok Giriş Kapısı',
      doorIndex: 1,
      isActive: true,
      assignedDeviceId: 1,
      assignedDeviceUid: 'ESP32_WROOM_T1',
      mqttSiteId: 101,
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _openModal(WidgetTester tester, _QrAuth auth) async {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => DynamicQrPassModal(door: _door(), authService: auth),
            ),
            child: const Text('Aç'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Aç'));
  await tester.pump(); // diyalog
  await tester.pump(const Duration(milliseconds: 50)); // token isteği tamamlanır
}

Future<void> _closeModal(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
}

/// [totalMs] boyunca [stepMs]'lik adımlarla sanal zamanı ilerletir; durum isteği sayısının arttığı
/// sanal zamanları (ms) döndürür.
Future<List<int>> _elapse(
  WidgetTester tester,
  _QrAuth auth, {
  required int totalMs,
  int stepMs = 100,
}) async {
  final times = <int>[];
  var last = auth.statusCalls;
  for (var t = stepMs; t <= totalMs; t += stepMs) {
    await tester.pump(Duration(milliseconds: stepMs));
    while (last < auth.statusCalls) {
      times.add(t);
      last++;
    }
  }
  return times;
}

List<int> _gaps(List<int> times) => [for (var i = 1; i < times.length; i++) times[i] - times[i - 1]];

/// Boyama sayacı: `debugOnProfilePaint` her paintChild çağrısında tetiklenir; karekod
/// (QrPainter) ve halka (tasarım sistemi `CountdownRing`inin `_RingPainter`ı; eski adı
/// `_QrProgressRingPainter`) boyayıcılarının kaç kez boyandığını sayar.
class _PaintCounter {
  int qrPaints = 0;
  int ringPaints = 0;

  void start() {
    debugOnProfilePaint = (RenderObject renderObject) {
      if (renderObject is RenderCustomPaint) {
        final painter = renderObject.painter;
        if (painter is QrPainter) qrPaints++;
        final name = painter.runtimeType.toString();
        if (name == '_RingPainter' || name == '_QrProgressRingPainter') ringPaints++;
      }
    };
  }

  void stop() => debugOnProfilePaint = null;
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async => 1,
    );
  });

  tearDown(() {
    RebuildProbe.stop();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      null,
    );
  });

  group('geri sayım halkası kapsamı', () {
    testWidgets('ÖLÇÜM: 30 karede karekod yeniden kurulmaz ve yeniden boyanmaz; yalnız halka çizilir', (tester) async {
      final auth = _QrAuth();
      await _openModal(tester, auth);
      expect(find.byType(QrImageView), findsOneWidget);

      final paints = _PaintCounter()..start();
      addTearDown(paints.stop);
      RebuildProbe.start();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16)); // 480 ms: ilk yoklamadan (800 ms) önce
      }
      paints.stop();
      print(
        'ÖLÇÜM 30 kare: QrImageView yeniden kurma=${RebuildProbe.count(QrImageView)}, '
        'toplam yeniden kurma=${RebuildProbe.total}, karekod boyama=${paints.qrPaints}, halka boyama=${paints.ringPaints}',
      );

      expect(RebuildProbe.count(QrImageView), 0, reason: 'karekod her karede yeniden kurulmamalı');
      expect(paints.qrPaints, 0, reason: 'geri sayım karekodu yeniden boyatmamalı (katmanı önbellekte kalır)');
      expect(paints.ringPaints, greaterThanOrEqualTo(28), reason: 'halka her karede çizilir');
      expect(tester.takeException(), isNull);
      await _closeModal(tester);
    });
  });

  group('durum yoklaması yaşam döngüsü (QR modal)', () {
    testWidgets('800 ms aralıkla yoklar; başarılı turlarda aralık değişmez', (tester) async {
      final auth = _QrAuth();
      await _openModal(tester, auth);
      final times = await _elapse(tester, auth, totalMs: 5000);
      expect(times.length, greaterThanOrEqualTo(5));
      for (final gap in _gaps(times)) {
        expect(gap, inInclusiveRange(700, 900));
      }
      await _closeModal(tester);
    });

    testWidgets('ardışık hatada üstel geri çekilme (tavan 5 sn); başarıda 800 ms\'ye döner', (tester) async {
      var failing = true;
      final auth = _QrAuth(
        handler: (index) async => failing ? (null, 'Sunucu yanıt vermedi, tekrar deneyin.') : (<String, dynamic>{}, null),
      );
      await _openModal(tester, auth);

      // 0.8 sn sonra ilk tur; sonraki aralıklar 1.6, 3.2, 5.0 (tavan), 5.0 sn.
      final times = await _elapse(tester, auth, totalMs: 17000);
      expect(times.length, 5);
      final gaps = _gaps(times);
      expect(gaps[0], inInclusiveRange(1500, 1700));
      expect(gaps[1], inInclusiveRange(3100, 3300));
      expect(gaps[2], inInclusiveRange(4900, 5100));
      expect(gaps[3], inInclusiveRange(4900, 5100));

      // Bağlantı döndü: ilk başarılı turdan sonra aralık yine 800 ms.
      failing = false;
      final recovery = await _elapse(tester, auth, totalMs: 9000);
      expect(recovery.length, greaterThanOrEqualTo(3));
      final tail = _gaps(recovery);
      expect(tail.last, inInclusiveRange(700, 900));
      await _closeModal(tester);
    });

    testWidgets('arka plana alınınca yoklama durur; ön plana dönünce hemen yoklar', (tester) async {
      final auth = _QrAuth();
      await _openModal(tester, auth);
      await _elapse(tester, auth, totalMs: 2000);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final paused = auth.statusCalls;
      final idle = await _elapse(tester, auth, totalMs: 12000);
      expect(idle, isEmpty, reason: 'arka planda ağ isteği yok');
      expect(auth.statusCalls, paused);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(auth.statusCalls, paused + 1, reason: 'ön plana dönünce hemen yoklanır');
      final after = await _elapse(tester, auth, totalMs: 3000);
      expect(after, isNotEmpty);
      await _closeModal(tester);
    });

    testWidgets('önceki tur bitmeden yenisi başlamaz', (tester) async {
      final slow = Completer<(Map<String, dynamic>?, String?)>();
      final auth = _QrAuth(
        handler: (index) {
          if (index == 1) return slow.future;
          return Future.value((<String, dynamic>{}, null));
        },
      );
      await _openModal(tester, auth);

      final times = await _elapse(tester, auth, totalMs: 10000);
      expect(times, hasLength(1), reason: 'takılan tur 10 sn boyunca tek istektir');

      slow.complete((<String, dynamic>{}, null));
      final after = await _elapse(tester, auth, totalMs: 2000);
      expect(after, isNotEmpty);
      await _closeModal(tester);
    });

    testWidgets('karekod kullanılınca ("used") yoklama kalıcı olarak durur', (tester) async {
      final auth = _QrAuth(handler: (index) async => (<String, dynamic>{'used': true}, null));
      await _openModal(tester, auth);
      await _elapse(tester, auth, totalMs: 1200);
      expect(find.text('Geçiş Başarılı'), findsOneWidget);

      final calls = auth.statusCalls;
      final later = await _elapse(tester, auth, totalMs: 3000);
      expect(later, isEmpty);
      expect(auth.statusCalls, calls);
      // 3.2 sn sonra pencere kendiliğinden kapanır; bekleyen zamanlayıcı kalmamalı.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('kapatılınca (dispose) zamanlayıcı ve yoklama kalmaz', (tester) async {
      final auth = _QrAuth();
      await _openModal(tester, auth);
      await _elapse(tester, auth, totalMs: 2000);

      await _closeModal(tester);
      final atClose = auth.statusCalls;
      await tester.pump(const Duration(seconds: 30));
      expect(auth.statusCalls, atClose);
    });
  });
}
