// FAZ 5 / P: kare süresi ölçüm düzeneğinin (integration_test/support/perf_frames.dart) özet matematiği.
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/perf_frames.dart';

FrameSample _s(double buildMs, double rasterMs) => FrameSample(
      buildUs: (buildMs * 1000).round(),
      rasterUs: (rasterMs * 1000).round(),
      totalUs: ((buildMs + rasterMs) * 1000).round(),
    );

void main() {
  group('MetricStats (en-yakın-sıra yüzdelikleri)', () {
    test('1..100 ms için p50=50, p90=90, p99=99, max=100', () {
      final stats = MetricStats.of([for (var i = 1; i <= 100; i++) i.toDouble()]);
      expect(stats.p50, 50);
      expect(stats.p90, 90);
      expect(stats.p99, 99);
      expect(stats.max, 100);
      expect(stats.mean, closeTo(50.5, 1e-9));
    });

    test('tek örnek ve boş liste güvenlidir', () {
      final one = MetricStats.of([7.5]);
      expect([one.p50, one.p90, one.p99, one.max], [7.5, 7.5, 7.5, 7.5]);
      final none = MetricStats.of(const <double>[]);
      expect([none.p50, none.p90, none.p99, none.max, none.mean], [0, 0, 0, 0, 0]);
    });

    test('sıra bağımsızdır', () {
      final a = MetricStats.of([5, 1, 4, 2, 3].map((e) => e.toDouble()).toList());
      final b = MetricStats.of([1, 2, 3, 4, 5].map((e) => e.toDouble()).toList());
      expect(a.p50, b.p50);
      expect(a.p90, b.p90);
    });
  });

  group('PhaseStats jank sayımı (>16 ms)', () {
    test('build VEYA raster eşiği aşan kare jank sayılır; tam eşik jank değildir', () {
      final stats = PhaseStats.fromSamples([
        _s(4, 3), // iyi
        _s(16, 2), // tam eşik: jank değil
        _s(17, 2), // build jank
        _s(3, 20), // raster jank
        _s(30, 30), // ikisi de jank
      ]);
      expect(stats.frames, 5);
      expect(stats.buildOver, 2);
      expect(stats.rasterOver, 2);
      expect(stats.anyOver, 3);
      expect(stats.jankRatio, closeTo(0.6, 1e-9));
    });

    test('boş aşama: oran 0', () {
      final stats = PhaseStats.fromSamples(const <FrameSample>[]);
      expect(stats.frames, 0);
      expect(stats.jankRatio, 0);
    });
  });

  group('FramePerfRecorder', () {
    test('örnekler aktif aşamaya yazılır; aşama dışı örnekler ayrı sayılır; JSON şeması', () {
      final recorder = FramePerfRecorder();
      recorder.addSample(_s(1, 1)); // aşama yok
      recorder.beginPhase('panel');
      for (var i = 0; i < 10; i++) {
        recorder.addSample(_s(2.0 + i, 1));
      }
      recorder.beginPhase('liste');
      recorder.addSample(_s(40, 5));
      recorder.endPhase();

      final summary = recorder.summary(meta: {'label': 'deneme'});
      expect(summary['harness'], 'perf_frames_test');
      expect(summary['label'], 'deneme');
      expect(summary['unassigned_frames'], 1);

      final phases = summary['phases']! as Map<String, Object?>;
      expect(phases.keys.toList(), ['panel', 'liste'], reason: 'ekleme sırası korunur');
      final panel = phases['panel']! as Map<String, Object?>;
      expect(panel['frames'], 10);
      final panelBuild = panel['build_ms']! as Map<String, Object?>;
      expect(panelBuild['p50'], 6.0);
      expect(panelBuild['max'], 11.0);
      final liste = phases['liste']! as Map<String, Object?>;
      expect((liste['jank']! as Map<String, Object?>)['any_over'], 1);

      final overall = summary['overall']! as Map<String, Object?>;
      expect(overall['frames'], 11);
    });
  });

  testWidgets('attach/detach zamanlama geri çağrısını güvenle ekler/çıkarır (çift çağrı zararsız)', (tester) async {
    final recorder = FramePerfRecorder();
    recorder.attach();
    recorder.attach();
    recorder.beginPhase('boş');
    await tester.pump(const Duration(milliseconds: 50));
    recorder.detach();
    recorder.detach();
    final summary = recorder.summary();
    expect((summary['phases']! as Map<String, Object?>).containsKey('boş'), isTrue);
  });
}
