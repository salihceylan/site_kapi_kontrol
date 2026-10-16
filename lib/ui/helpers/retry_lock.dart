import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';

/// Hız sınırı (429) sonrası bir düğmeyi GEÇİCİ kilitler (Platform Faz 3a): sunucu "çok sık deneme" derse
/// kullanıcı aynı isteği art arda göndermesin; kilit süresi `retry_after_seconds` kadardır (en çok
/// [maxSeconds]; bildirilmemişse [fallbackSeconds]) ve süre dolunca düğme kendiliğinden açılır.
///
/// Kullanım: hata yakalandığında `_retry.lockIfRateLimited(e, () => setState(() {}))`; düğme
/// `_retry.locked ? null : ...`; `dispose` içinde `_retry.dispose()`.
class RetryLock {
  Timer? _timer;

  /// Kilit sürüyor mu?
  bool get locked => _timer != null;

  /// [error] 429 ise kilitler ve true döner; süre dolunca [onChanged] çağrılır (çağıran `setState` yapar).
  bool lockIfRateLimited(
    Object error,
    VoidCallback onChanged, {
    int fallbackSeconds = 30,
    int maxSeconds = 120,
  }) {
    if (error is! ApiException || !error.isRateLimited) return false;
    final seconds = (error.retryAfterSeconds ?? fallbackSeconds).clamp(1, maxSeconds);
    _timer?.cancel();
    _timer = Timer(Duration(seconds: seconds), () {
      _timer = null;
      onChanged();
    });
    return true;
  }

  /// 429 için kullanıcıya gösterilecek kısa Türkçe metin; başka hatada null.
  static String? messageFor(Object error) {
    if (error is! ApiException || !error.isRateLimited) return null;
    final wait = error.retryAfterSeconds;
    return wait == null
        ? 'Çok sık deneme yapıldı. Biraz sonra tekrar deneyin.'
        : 'Çok sık deneme yapıldı. ${AuthApi.formatWait(wait)} sonra tekrar deneyin.';
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
