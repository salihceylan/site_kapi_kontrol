import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/ble_wifi_provision_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BleWifiProvisionService (masaüstü: Windows/Linux, BLE eklentisi yok)', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test(
      'kurucu FlutterReactiveBle başlatmaz: yakalanmamış asenkron UnimplementedError oluşmaz',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final uncaught = <Object>[];

        await runZonedGuarded(() async {
          final service = BleWifiProvisionService();
          // FlutterReactiveBle() yapıcısı durum akışını asenkron başlatır; hata gecikmeli gelir.
          await Future<void>.delayed(const Duration(milliseconds: 150));
          expect(service.isSupportedPlatform, isFalse);
          await service.dispose();
        }, (error, stack) => uncaught.add(error));

        expect(uncaught, isEmpty);
      },
    );

    test('ensureReady desteklenmeyen platformda anlaşılır BleProvisionException fırlatır', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final uncaught = <Object>[];

      await runZonedGuarded(() async {
        final service = BleWifiProvisionService();
        await expectLater(service.ensureReady(), throwsA(isA<BleProvisionException>()));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }, (error, stack) => uncaught.add(error));

      expect(uncaught, isEmpty);
    });
  });
}
