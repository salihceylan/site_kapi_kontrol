// Test yardımcısı: widget yeniden kurma (rebuild) sayacı.
//
// `debugOnRebuildDirtyWidget` her Element yeniden kurulduğunda (setState, üst widget güncellemesi,
// ValueListenableBuilder vb.) çağrılır. Böylece "şu alt ağaç şu kadar kurulur" iddiaları ölçülür.

import 'package:flutter/widgets.dart';

class RebuildProbe {
  RebuildProbe._();

  static final Map<Type, int> _counts = <Type, int>{};
  static bool _installed = false;

  /// Sayaçları sıfırlayıp izlemeyi başlatır.
  static void start() {
    _counts.clear();
    _installed = true;
    debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {
      final type = element.widget.runtimeType;
      _counts[type] = (_counts[type] ?? 0) + 1;
    };
  }

  /// İzlemeyi bırakır (testin tearDown'ında çağrılmalı).
  static void stop() {
    if (_installed) {
      debugOnRebuildDirtyWidget = null;
      _installed = false;
    }
    _counts.clear();
  }

  /// Sayaçları sıfırlar (izleme sürer).
  static void reset() => _counts.clear();

  /// [type] türündeki widget'ların son [reset]/[start]'tan beri kaç kez (yeniden) kurulduğu.
  static int count(Type type) => _counts[type] ?? 0;

  /// Tüm sayaçların kopyası (tanılama).
  static Map<Type, int> snapshot() => Map<Type, int>.of(_counts);

  /// Toplam Element yeniden kurma sayısı.
  static int get total => _counts.values.fold<int>(0, (a, b) => a + b);
}
