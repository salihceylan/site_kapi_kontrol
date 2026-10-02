class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.retryAfterSeconds,
    bool? invalidatesSession,
    this.fromIntermediary = false,
  }) : _invalidatesSession = invalidatesSession;

  final String message;
  final int? statusCode;

  /// Sunucunun döndürdüğü makine-okunur hata kodu (örn. `GEOFENCE_EXCEEDED`,
  /// `LOGIN_LOCKED`, `TOKEN_REVOKED`), yoksa null.
  final String? code;

  /// Hız sınırı (429) yanıtlarında sunucunun bildirdiği bekleme süresi (saniye).
  final int? retryAfterSeconds;

  final bool? _invalidatesSession;

  /// 401/403 yanıtı sunucumuzdan değil araya giren bir katmandan (proxy/WAF/captive portal;
  /// gövde JSON hata zarfı değil) geldi: geçici ağ hatasıdır, oturum sonu / hesap pasif sinyali
  /// DEĞİLDİR. true iken [isUnauthorized], [isForbidden] ve [invalidatesSession] false döner.
  final bool fromIntermediary;

  /// Bu hata oturumun geçersiz olduğu anlamına mı geliyor? Varsayılan: 401.
  /// Giriş / mevcut şifre doğrulama gibi kimlik bilgisi uçlarında 401 "hatalı bilgi"
  /// demektir ve oturumu KAPATMAMALIDIR (bu durumda false verilir).
  bool get invalidatesSession =>
      _invalidatesSession ?? (statusCode == 401 && !fromIntermediary);

  bool get isUnauthorized => statusCode == 401 && !fromIntermediary;
  bool get isForbidden => statusCode == 403 && !fromIntermediary;
  bool get isRateLimited => statusCode == 429;
  bool get isServerError => statusCode != null && statusCode! >= 500;

  @override
  String toString() => message;
}

class SessionExpiredException extends ApiException {
  SessionExpiredException([
    super.message = 'Oturum süreniz doldu. Lütfen tekrar giriş yapın.',
    String? code,
  ]) : super(statusCode: 401, code: code);
}
