import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/config/app_config.dart';

class NetworkService extends ChangeNotifier {
  NetworkService({this.enabled = true});

  final bool enabled;

  bool _isReady = false;
  bool _isChecking = false;
  bool _hasInternet = true;
  bool _isDisposed = false;

  bool get isReady => _isReady;
  bool get isChecking => _isChecking;
  bool get hasInternet => _hasInternet;

  Future<void> initialize() async {
    if (!enabled) {
      _isReady = true;
      _hasInternet = true;
      _notifySafely();
      return;
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (!enabled || _isChecking) {
      return;
    }

    _isChecking = true;
    _notifySafely();

    final hasInternet = await _probeInternet();
    _hasInternet = hasInternet;
    _isChecking = false;
    _isReady = true;
    _notifySafely();
  }

  /// Yedek adres, birinci adres bu sürede yanıt vermezse eşzamanlı başlar.
  static const Duration _fallbackStagger = Duration(milliseconds: 1500);

  /// İnternet var mı? Önce API `/health`; hata verirse yedek adres HEMEN, yanıt gecikirse
  /// [_fallbackStagger] sonra eşzamanlı denenir. Biri başarılı olunca beklemeden true; ikisi de
  /// başarısızsa false. (Eskiden ardışıktı: yanıtsız bir ağda en kötü 5+5 = 10 sn, şimdi ~6,5 sn;
  /// sağlıklı ağda yine tek istek.)
  Future<bool> _probeInternet() async {
    if (kIsWeb) {
      return true;
    }
    final urls = <Uri>[
      Uri.parse('$apiBaseUrl/health'),
      Uri.parse('https://clients3.google.com/generate_204'),
    ];

    final first = _probeOnce(urls[0]);
    final startFallback = Completer<void>();
    final stagger = Timer(_fallbackStagger, () {
      if (!startFallback.isCompleted) startFallback.complete();
    });
    unawaited(first.then((ok) {
      if (!ok && !startFallback.isCompleted) startFallback.complete();
    }));

    final firstOutcome = await Future.any<bool?>(<Future<bool?>>[
      first,
      startFallback.future.then<bool?>((_) => null),
    ]);
    stagger.cancel();
    if (firstOutcome == true) {
      return true;
    }

    final second = _probeOnce(urls[1]);
    final outcome = Completer<bool>();
    var pending = 2;
    void settle(bool ok) {
      if (outcome.isCompleted) return;
      if (ok) {
        outcome.complete(true);
      } else if (--pending == 0) {
        outcome.complete(false);
      }
    }

    unawaited(first.then(settle));
    unawaited(second.then(settle));
    return outcome.future;
  }

  Future<bool> _probeOnce(Uri uri) async {
    try {
      final response = await http
          .get(uri, headers: const {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  void _notifySafely() {
    if (_isDisposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
