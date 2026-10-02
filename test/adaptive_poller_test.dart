// FAZ 5 / P-c: AdaptivePoller (yoklama zamanlayıcısı) birim testleri.
// Sanal zaman: testWidgets + tester.pump(duration) Timer'ları ilerletir.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/adaptive_poller.dart';

void main() {
  group('currentDelay (üstel geri çekilme)', () {
    test('başlangıçta gecikme interval ve hata sayısı sıfırdır', () {
      final poller = AdaptivePoller(
        interval: const Duration(seconds: 3),
        poll: () async => true,
      );
      expect(poller.currentDelay, const Duration(seconds: 3));
      expect(poller.consecutiveFailures, 0);
      expect(poller.isRunning, isFalse);
      poller.dispose();
    });

    testWidgets('3 sn taban, 30 sn tavan: 3, 6, 12, 24, 30, 30; başarı 3 sn\'ye döndürür', (tester) async {
      var succeed = false;
      final delays = <Duration>[];
      late final AdaptivePoller poller;
      poller = AdaptivePoller(
        interval: const Duration(seconds: 3),
        poll: () async {
          final ok = succeed;
          return ok;
        },
      );
      poller.start();

      // Her turdan sonraki bekleme süresini, turun sonunda okuruz.
      for (var i = 0; i < 6; i++) {
        await tester.pump(poller.currentDelay);
        await tester.pump(); // tur tamamlanır
        delays.add(poller.currentDelay);
      }
      expect(delays.map((d) => d.inSeconds).toList(), [6, 12, 24, 30, 30, 30]);
      expect(poller.consecutiveFailures, 6);

      succeed = true;
      await tester.pump(poller.currentDelay);
      await tester.pump();
      expect(poller.consecutiveFailures, 0);
      expect(poller.currentDelay, const Duration(seconds: 3));
      poller.dispose();
    });

    testWidgets('null (atlandı) sonucu geri çekilme durumunu değiştirmez', (tester) async {
      final results = <bool?>[false, null, null, true];
      final poller = AdaptivePoller(
        interval: const Duration(seconds: 3),
        poll: () async => results.removeAt(0),
      );
      poller.start();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(poller.consecutiveFailures, 1);

      await tester.pump(poller.currentDelay);
      await tester.pump();
      expect(poller.consecutiveFailures, 1, reason: 'null: ne başarı ne hata');
      await tester.pump(poller.currentDelay);
      await tester.pump();
      expect(poller.consecutiveFailures, 1);

      await tester.pump(poller.currentDelay);
      await tester.pump();
      expect(poller.consecutiveFailures, 0);
      poller.dispose();
    });

    test('tavan tabandan küçükse taban kullanılır', () {
      final poller = AdaptivePoller(
        interval: const Duration(seconds: 15),
        maxDelay: const Duration(seconds: 5),
        poll: () async => false,
      );
      expect(poller.currentDelay, const Duration(seconds: 15));
      poller.dispose();
    });
  });

  group('tur yönetimi', () {
    testWidgets('önceki tur bitmeden yenisi başlamaz', (tester) async {
      var calls = 0;
      final gate = Completer<bool?>();
      final poller = AdaptivePoller(
        interval: const Duration(seconds: 1),
        poll: () {
          calls++;
          return gate.future;
        },
      );
      poller.start();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
      expect(poller.isInFlight, isTrue);

      await tester.pump(const Duration(seconds: 60));
      expect(calls, 1, reason: 'takılan tur sürerken yeni tur yok');

      gate.complete(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
      poller.dispose();
    });

    testWidgets('isActive false iken ağ turu yok; true olunca ilk tur polls (geri çekilmesiz)', (tester) async {
      var active = false;
      var calls = 0;
      final poller = AdaptivePoller(
        interval: const Duration(seconds: 3),
        isActive: () => active,
        poll: () async {
          calls++;
          return false; // hata: geri çekilme başlar
        },
      );
      poller.start();
      await tester.pump(const Duration(seconds: 60));
      expect(calls, 0);
      expect(poller.consecutiveFailures, 0, reason: 'atlanan turlar hata sayılmaz');

      active = true;
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(calls, 1, reason: 'görünür olunca bir sonraki aralıkta yoklar');
      poller.dispose();
    });

    testWidgets('stop(): sürmekte olan tur bitse de yeni tur planlanmaz; yeniden start çalışır', (tester) async {
      var calls = 0;
      final gate = Completer<bool?>();
      final poller = AdaptivePoller(
        interval: const Duration(seconds: 2),
        poll: () {
          calls++;
          return calls == 1 ? gate.future : Future<bool?>.value(true);
        },
      );
      poller.start();
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 1);

      poller.stop();
      gate.complete(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 1, reason: 'durdurulduktan sonra tur planlanmaz');
      expect(poller.isRunning, isFalse);

      poller.start();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(calls, 2);
      poller.dispose();
    });

    testWidgets('stop+start sırasında eski turun sonucu ikinci bir döngü başlatmaz', (tester) async {
      var calls = 0;
      final gate = Completer<bool?>();
      final poller = AdaptivePoller(
        interval: const Duration(seconds: 2),
        poll: () {
          calls++;
          return calls == 1 ? gate.future : Future<bool?>.value(true);
        },
      );
      poller.start();
      await tester.pump(const Duration(seconds: 2)); // tur 1 sürüyor (takılı)
      poller.stop();
      poller.start(); // yeni döngü (yeni nesil)

      gate.complete(true); // eski tur şimdi biter: yeni döngüyü ezmemeli/çoğaltmamalı
      await tester.pump();
      final before = calls;
      await tester.pump(const Duration(seconds: 10));
      // Tek döngü: 10 sn / 2 sn = 5 tur; iki döngü olsaydı ~10.
      expect(calls - before, inInclusiveRange(4, 5));
      poller.dispose();
    });

    testWidgets('pollNow: hemen bir tur; tur sürerken ya da durdurulmuşken etkisiz', (tester) async {
      var calls = 0;
      final gate = Completer<bool?>();
      final poller = AdaptivePoller(
        interval: const Duration(minutes: 5),
        poll: () {
          calls++;
          return calls == 1 ? gate.future : Future<bool?>.value(true);
        },
      );
      poller.pollNow();
      await tester.pump(Duration.zero);
      expect(calls, 0, reason: 'başlatılmamış yoklamada pollNow etkisiz');

      poller.start();
      poller.pollNow();
      await tester.pump(Duration.zero);
      expect(calls, 1);

      poller.pollNow();
      await tester.pump(Duration.zero);
      expect(calls, 1, reason: 'tur sürerken pollNow yeni tur başlatmaz');

      gate.complete(true);
      await tester.pump(Duration.zero);
      poller.dispose();
    });

    testWidgets('poll istisna fırlatırsa hata sayılır ve döngü sürer', (tester) async {
      var calls = 0;
      final poller = AdaptivePoller(
        interval: const Duration(seconds: 1),
        poll: () async {
          calls++;
          if (calls < 3) throw StateError('ağ hatası');
          return true;
        },
      );
      poller.start();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(poller.consecutiveFailures, 1);
      await tester.pump(poller.currentDelay);
      await tester.pump();
      expect(poller.consecutiveFailures, 2);
      await tester.pump(poller.currentDelay);
      await tester.pump();
      expect(poller.consecutiveFailures, 0);
      poller.dispose();
    });

    testWidgets('dispose sonrası zamanlayıcı kalmaz ve start etkisizdir', (tester) async {
      var calls = 0;
      final poller = AdaptivePoller(
        interval: const Duration(seconds: 1),
        poll: () async {
          calls++;
          return true;
        },
      );
      poller.start();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(calls, 1);

      poller.dispose();
      poller.start();
      await tester.pump(const Duration(minutes: 1));
      expect(calls, 1);
      expect(poller.isRunning, isFalse);
    });
  });
}
