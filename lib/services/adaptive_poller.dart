import 'dart:async';

/// Yaşam döngüsüne duyarlı yoklama (polling) zamanlayıcısı.
///
/// - Turlar ÜST ÜSTE BİNMEZ: bir tur bitmeden yenisi başlamaz; sonraki tur, önceki bittikten
///   sonra planlanır (yavaş ağda istek yığılmaz).
/// - [isActive] false iken (ekran görünür değil / uygulama arka planda) tur atlanır: ağ isteği
///   yapılmaz, kontrol [interval] sonra tekrarlanır; görünür olunca ilk turda yoklama sürer.
/// - Ardışık hatada üstel geri çekilme: gecikme `interval * 2^hata` olur, [maxDelay] (varsayılan
///   30 sn) ile sınırlanır; ilk başarıda aralık [interval]'e döner.
/// - [stop]/[dispose] zamanlayıcıyı iptal eder; sürmekte olan tur bitince yeni tur PLANLANMAZ.
///
/// Giriş sonucu: `true` başarılı, `false` başarısız (geri çekilme), `null` atlandı/yok sayılır
/// (geri çekilme durumu değişmez).
class AdaptivePoller {
  AdaptivePoller({
    required this.interval,
    required this.poll,
    this.isActive,
    this.maxDelay = const Duration(seconds: 30),
  }) : assert(interval > Duration.zero, 'interval pozitif olmalı');

  /// Sağlıklı durumdaki yoklama aralığı.
  final Duration interval;

  /// Geri çekilmenin üst sınırı.
  final Duration maxDelay;

  /// Tek bir yoklama turu. `true` başarı, `false` hata, `null` atlandı.
  final Future<bool?> Function() poll;

  /// Yoklamanın şu an gerekli olup olmadığı (görünürlük + yaşam döngüsü). Null = her zaman.
  final bool Function()? isActive;

  Timer? _timer;
  bool _running = false;
  bool _disposed = false;
  bool _inFlight = false;
  int _failures = 0;
  int _generation = 0;

  /// Zamanlayıcı kurulu mu (start edilmiş ve durdurulmamış).
  bool get isRunning => _running && !_disposed;

  /// Bir tur şu an sürüyor mu.
  bool get isInFlight => _inFlight;

  /// Ardışık başarısız tur sayısı.
  int get consecutiveFailures => _failures;

  /// Bir sonraki turdan önceki bekleme: sağlıklıyken [interval], hatada üstel (tavan [maxDelay]).
  Duration get currentDelay {
    if (_failures == 0) return interval;
    var delay = interval;
    for (var i = 0; i < _failures; i++) {
      delay *= 2;
      if (delay >= maxDelay) return maxDelay > interval ? maxDelay : interval;
    }
    return delay;
  }

  /// Yoklamayı başlatır. [immediately] true ise ilk tur hemen (bir sonraki olay döngüsü turunda)
  /// çalışır, aksi halde [interval] sonra. Zaten çalışıyorsa zamanlayıcıyı yeniden kurar.
  void start({bool immediately = false}) {
    if (_disposed) return;
    _running = true;
    _generation++;
    _schedule(immediately ? Duration.zero : currentDelay);
  }

  /// Zamanlayıcıyı iptal eder. Sürmekte olan tur tamamlanır ama sonrası planlanmaz.
  void stop() {
    _running = false;
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  /// Şimdi (sıradaki olay döngüsü turunda) bir tur çalıştırır; tur sürüyorsa bir şey yapmaz.
  /// Yoklama çalışmıyorsa (stop edilmiş) başlatmaz.
  void pollNow() {
    if (!isRunning || _inFlight) return;
    _schedule(Duration.zero);
  }

  /// Geri çekilme durumunu sıfırlar (örn. kullanıcı elle yenilediğinde).
  void resetBackoff() {
    _failures = 0;
  }

  void dispose() {
    stop();
    _disposed = true;
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (!isRunning) return;
    final generation = _generation;
    _timer = Timer(delay, () => unawaited(_tick(generation)));
  }

  Future<void> _tick(int generation) async {
    _timer = null;
    if (!isRunning || generation != _generation) return;

    // Önceki tur bitmeden yenisi başlatılmaz.
    if (_inFlight) {
      _schedule(currentDelay);
      return;
    }

    final active = isActive;
    if (active != null && !active()) {
      // Görünür/ön planda değil: ağ isteği yok; durumu bir sonraki aralıkta yeniden değerlendir.
      _schedule(interval);
      return;
    }

    _inFlight = true;
    bool? outcome;
    try {
      outcome = await poll();
    } catch (_) {
      outcome = false;
    } finally {
      _inFlight = false;
    }

    // stop()/dispose()/yeniden start() olduysa bu turun sonucu yeni döngüyü ezmez.
    if (!isRunning || generation != _generation) return;

    if (outcome == true) {
      _failures = 0;
    } else if (outcome == false) {
      if (_failures < 16) _failures++;
    }
    _schedule(currentDelay);
  }
}
