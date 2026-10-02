// FAZ 5 / P: kare süresi ölçümü (build/raster yüzdelik dilimleri + jank oranı).
//
// `SchedulerBinding.addTimingsCallback` motorun gerçek kare zamanlarını (FrameTiming) bildirir:
// profile modda (flutter drive --profile) üretimdekine en yakın sayıları verir. Bu dosya yalnız
// toplama + özetleme mantığını içerir; gezinti `perf_frames_test.dart`, çıktı yazımı
// `test_driver/perf_driver.dart` içindedir. Özet matematiği `test/perf_frame_stats_test.dart` ile
// birim testlidir (FrameTiming oluşturmadan, düz örneklerle).

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Tek karenin süreleri (mikrosaniye).
class FrameSample {
  const FrameSample({required this.buildUs, required this.rasterUs, required this.totalUs});

  /// UI iş parçacığı: build + layout + paint.
  final int buildUs;

  /// Raster iş parçacığı.
  final int rasterUs;

  /// vsync'ten raster bitişine toplam süre.
  final int totalUs;
}

/// Bir ölçünün yüzdelik dilimleri (milisaniye).
class MetricStats {
  const MetricStats({
    required this.p50,
    required this.p90,
    required this.p99,
    required this.max,
    required this.mean,
  });

  final double p50;
  final double p90;
  final double p99;
  final double max;
  final double mean;

  Map<String, Object?> toJson() => <String, Object?>{
        'p50': _round(p50),
        'p90': _round(p90),
        'p99': _round(p99),
        'max': _round(max),
        'mean': _round(mean),
      };

  /// [valuesMs] üzerinde en-yakın-sıra (nearest-rank) yüzdelikleri. Boşsa sıfırlar.
  factory MetricStats.of(List<double> valuesMs) {
    if (valuesMs.isEmpty) {
      return const MetricStats(p50: 0, p90: 0, p99: 0, max: 0, mean: 0);
    }
    final sorted = List<double>.of(valuesMs)..sort();
    double percentile(double p) {
      final rank = (p / 100 * sorted.length).ceil();
      final index = (rank < 1 ? 1 : rank) - 1;
      return sorted[index >= sorted.length ? sorted.length - 1 : index];
    }

    final sum = sorted.fold<double>(0, (a, b) => a + b);
    return MetricStats(
      p50: percentile(50),
      p90: percentile(90),
      p99: percentile(99),
      max: sorted.last,
      mean: sum / sorted.length,
    );
  }
}

double _round(double v) => (v * 1000).round() / 1000;

/// Bir gezinti aşamasının (giriş, panel, kapı kartı, günlük listesi ...) özeti.
class PhaseStats {
  const PhaseStats({
    required this.frames,
    required this.build,
    required this.raster,
    required this.total,
    required this.jankThresholdMs,
    required this.buildOver,
    required this.rasterOver,
    required this.anyOver,
  });

  final int frames;
  final MetricStats build;
  final MetricStats raster;
  final MetricStats total;
  final double jankThresholdMs;

  /// build süresi eşiği aşan kare sayısı.
  final int buildOver;

  /// raster süresi eşiği aşan kare sayısı.
  final int rasterOver;

  /// build VEYA raster eşiği aşan kare sayısı (jank).
  final int anyOver;

  double get jankRatio => frames == 0 ? 0 : anyOver / frames;

  factory PhaseStats.fromSamples(List<FrameSample> samples, {double jankThresholdMs = 16.0}) {
    final thresholdUs = (jankThresholdMs * 1000).round();
    var buildOver = 0;
    var rasterOver = 0;
    var anyOver = 0;
    for (final s in samples) {
      final b = s.buildUs > thresholdUs;
      final r = s.rasterUs > thresholdUs;
      if (b) buildOver++;
      if (r) rasterOver++;
      if (b || r) anyOver++;
    }
    return PhaseStats(
      frames: samples.length,
      build: MetricStats.of([for (final s in samples) s.buildUs / 1000.0]),
      raster: MetricStats.of([for (final s in samples) s.rasterUs / 1000.0]),
      total: MetricStats.of([for (final s in samples) s.totalUs / 1000.0]),
      jankThresholdMs: jankThresholdMs,
      buildOver: buildOver,
      rasterOver: rasterOver,
      anyOver: anyOver,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'frames': frames,
        'build_ms': build.toJson(),
        'raster_ms': raster.toJson(),
        'total_ms': total.toJson(),
        'jank': <String, Object?>{
          'threshold_ms': jankThresholdMs,
          'build_over': buildOver,
          'raster_over': rasterOver,
          'any_over': anyOver,
          'ratio': _round(jankRatio),
        },
      };
}

/// Aşama aşama kare süresi toplayıcı.
class FramePerfRecorder {
  FramePerfRecorder({this.jankThresholdMs = 16.0});

  /// Jank sayılan kare süresi eşiği (ms): 60 Hz bütçesi ≈ 16,7 ms.
  final double jankThresholdMs;

  final Map<String, List<FrameSample>> _phases = <String, List<FrameSample>>{};
  final Map<String, int> _phaseWallMs = <String, int>{};
  final List<FrameSample> _unassigned = <FrameSample>[];
  String? _current;
  Stopwatch? _phaseClock;
  bool _attached = false;

  /// Motorun kare zamanları bildirimine abone olur.
  void attach() {
    if (_attached) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    for (final t in timings) {
      addSample(
        FrameSample(
          buildUs: t.buildDuration.inMicroseconds,
          rasterUs: t.rasterDuration.inMicroseconds,
          totalUs: t.totalSpan.inMicroseconds,
        ),
      );
    }
  }

  /// Bir örnek ekler (testlerde doğrudan, üretimde zamanlama geri çağrısından).
  void addSample(FrameSample sample) {
    final name = _current;
    if (name == null) {
      _unassigned.add(sample);
    } else {
      _phases.putIfAbsent(name, () => <FrameSample>[]).add(sample);
    }
  }

  /// Yeni aşama başlatır; öncekini kapatır. Zamanlama geri çağrıları gecikmeli (toplu) gelir:
  /// çağıran, aşama sonunda kısa bir bekleme (≥ 300 ms) yapmalıdır.
  void beginPhase(String name) {
    endPhase();
    _current = name;
    _phases.putIfAbsent(name, () => <FrameSample>[]);
    _phaseClock = Stopwatch()..start();
  }

  void endPhase() {
    final name = _current;
    if (name != null) {
      _phaseWallMs[name] = (_phaseWallMs[name] ?? 0) + (_phaseClock?.elapsedMilliseconds ?? 0);
    }
    _current = null;
    _phaseClock = null;
  }

  /// Aşama özetleri (ekleme sırasıyla) + tüm aşamaların genel özeti.
  Map<String, Object?> summary({Map<String, Object?> meta = const <String, Object?>{}}) {
    endPhase();
    final phases = <String, Object?>{};
    final all = <FrameSample>[];
    _phases.forEach((name, samples) {
      all.addAll(samples);
      final stats = PhaseStats.fromSamples(samples, jankThresholdMs: jankThresholdMs).toJson();
      stats['wall_ms'] = _phaseWallMs[name] ?? 0;
      phases[name] = stats;
    });
    return <String, Object?>{
      'harness': 'perf_frames_test',
      'mode': kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug'),
      'jank_threshold_ms': jankThresholdMs,
      ...meta,
      'phases': phases,
      'overall': PhaseStats.fromSamples(all, jankThresholdMs: jankThresholdMs).toJson(),
      'unassigned_frames': _unassigned.length,
    };
  }
}
