// P2-26: ana kabuğun genel yenilemesinin ("Yenile" düğmesi ve aşağı çekme) durumu: sürüyor mu, en son ne zaman başarıyla
// bitti. Yenile düğmesi sürerken meşgul görünür ve ikinci dokunuş yenilemeyi katlamaz; bağlam şeridi gibi dinleyiciler
// her başarılı yenilemede [revision] ile tazelenir.
import 'dart:async';

import 'package:flutter/foundation.dart';

class RefreshStatus extends ChangeNotifier {
  RefreshStatus({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  Future<void>? _inFlight;
  DateTime? _lastRefreshedAt;
  int _revision = 0;
  bool _disposed = false;

  /// Bir yenileme sürüyor mu?
  bool get refreshing => _inFlight != null;

  /// En son BAŞARIYLA biten yenilemenin anı; hiç yenileme olmadıysa null.
  DateTime? get lastRefreshedAt => _lastRefreshedAt;

  /// Her başarılı yenilemede bir artar (dinleyiciler tazelenme anını buradan izler).
  int get revision => _revision;

  /// [task]'ı genel yenileme olarak çalıştırır. Bir yenileme sürerken çağrılırsa ikinci bir tur BAŞLATMAZ, sürmekte
  /// olanın sonucunu bekler (aşağı çekme + düğme art arda dokunuşunda sunucuya çift yük binmez). Hata fırlarsa
  /// çağırana iletilir; durum yine de "bitti"ye döner ve [lastRefreshedAt] değişmez.
  Future<void> run(Future<void> Function() task) {
    final running = _inFlight;
    if (running != null) return running;
    final done = Completer<void>();
    _inFlight = done.future;
    _notify();
    unawaited(() async {
      try {
        await task();
        _lastRefreshedAt = _clock();
        _revision++;
        _inFlight = null;
        _notify();
        done.complete();
      } catch (error, stack) {
        _inFlight = null;
        _notify();
        done.completeError(error, stack);
      }
    }());
    return done.future;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
