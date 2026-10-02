import 'dart:async';

import 'package:geolocator/geolocator.dart';

class GeofenceCheckResult {
  const GeofenceCheckResult({
    required this.allowed,
    required this.distanceMeters,
    required this.targetRadiusMeters,
    this.errorMessage,
  });

  final bool allowed;
  final double distanceMeters;
  final int targetRadiusMeters;
  final String? errorMessage;
}

/// Konumun neden reddedildiğini belirtir (saf doğrulama sonucu).
enum LocationFixIssue { mocked, inaccurate, stale }

/// Konum alma sonucu: ya doğrulanmış bir konum ya da kullanıcıya gösterilecek anlaşılır hata.
class LocationFixResult {
  const LocationFixResult.success(Position this.position) : errorMessage = null;
  const LocationFixResult.failure(String this.errorMessage) : position = null;

  final Position? position;
  final String? errorMessage;

  bool get isOk => position != null;
}

class GeofenceService {
  GeofenceService._();
  static final GeofenceService instance = GeofenceService._();

  /// Sunucu sözleşmesi (C3): varsayılan çember yarıçapı tek sabittir.
  static const int defaultRadiusMeters = 100;

  /// İstemci tarafı kabul sınırları (sunucu: accuracy <= 100 m, yaş <= 60 sn).
  static const double maxAccuracyMeters = 50;
  static const int maxFixAgeSeconds = 30;

  /// `getLastKnownPosition` yalnızca bu kadar taze ise GPS beklenmeden kullanılır.
  static const int maxLastKnownAgeSeconds = 10;

  static const Duration _fixTimeLimit = Duration(seconds: 10);

  /// Calculates Haversine distance in meters between two coordinates
  double calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }

  /// Bir konum örneğini politika sınırlarına göre değerlendirir.
  /// Sorun yoksa null döner. Platformdan bağımsız, saf fonksiyon (test edilebilir).
  static LocationFixIssue? evaluateFix({
    required double accuracyMeters,
    required bool isMocked,
    required DateTime timestamp,
    DateTime? now,
  }) {
    if (isMocked) return LocationFixIssue.mocked;
    if (accuracyMeters.isNaN || accuracyMeters < 0 || accuracyMeters > maxAccuracyMeters) {
      return LocationFixIssue.inaccurate;
    }
    final reference = now ?? DateTime.now();
    final ageSeconds =
        reference.difference(timestamp).inMilliseconds.abs() / 1000.0;
    if (ageSeconds > maxFixAgeSeconds) return LocationFixIssue.stale;
    return null;
  }

  static String messageForIssue(LocationFixIssue issue, {double? accuracyMeters}) {
    switch (issue) {
      case LocationFixIssue.mocked:
        return 'Sahte konum (Mock Location) tespit edildi. Güvenlik nedeniyle işlem yapılamaz.';
      case LocationFixIssue.inaccurate:
        final acc = (accuracyMeters != null && accuracyMeters.isFinite)
            ? ' (~${accuracyMeters.round()} m)'
            : '';
        return 'GPS doğruluğu yetersiz$acc. Lütfen açık alana çıkıp tekrar deneyin.';
      case LocationFixIssue.stale:
        return 'Konum bilginiz güncel değil. GPS sinyalinin yenilenmesini bekleyip tekrar deneyin.';
    }
  }

  /// Sunucuya gönderilecek konum alanları (sözleşme C3):
  /// latitude, longitude, accuracy (m), timestamp (ISO8601 UTC), is_mocked.
  static Map<String, dynamic> locationRequestFields(Position position) {
    return <String, dynamic>{
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'timestamp': position.timestamp.toUtc().toIso8601String(),
      'is_mocked': position.isMocked,
    };
  }

  /// İzin/servis durumunu denetler; sorun varsa anlaşılır hata metni döner, yoksa null.
  Future<String?> _checkServiceAndPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Konum servisleri kapalı. Lütfen telefonunuzun GPS konumunu açın.';
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return 'Konum izni verilmedi. Güvenlik için konum gereklidir.';
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return 'Konum izni kalıcı olarak engellenmiş. Ayarlardan izin verin.';
    }
    return null;
  }

  String _describeLocationError(Object error) {
    if (error is TimeoutException) {
      return 'GPS sinyali alınamadı (zaman aşımı). Açık alanda tekrar deneyin.';
    }
    if (error is LocationServiceDisabledException) {
      return 'Konum servisleri kapalı. Lütfen telefonunuzun GPS konumunu açın.';
    }
    if (error is PermissionDeniedException) {
      return 'Konum izni verilmedi. Güvenlik için konum gereklidir.';
    }
    return 'Anlık konum alınamadı. Lütfen GPS\'i kontrol edip tekrar deneyin.';
  }

  /// Politikaya uygun (doğruluk, taze, sahte değil) bir konum almaya çalışır.
  /// Başarısızlıkta neden bilgisini kullanıcıya gösterilebilir metin olarak döner.
  Future<LocationFixResult> acquireVerifiedPosition() async {
    try {
      final blocker = await _checkServiceAndPermission();
      if (blocker != null) return LocationFixResult.failure(blocker);

      // Hızlı yol: çok taze ve kaliteli son bilinen konum (yalnızca <= 10 sn).
      try {
        final lastPos = await Geolocator.getLastKnownPosition();
        if (lastPos != null) {
          final ageSeconds =
              DateTime.now().difference(lastPos.timestamp).inMilliseconds / 1000.0;
          if (ageSeconds >= 0 &&
              ageSeconds <= maxLastKnownAgeSeconds &&
              evaluateFix(
                    accuracyMeters: lastPos.accuracy,
                    isMocked: lastPos.isMocked,
                    timestamp: lastPos.timestamp,
                  ) ==
                  null) {
            return LocationFixResult.success(lastPos);
          }
        }
      } catch (_) {}

      LocationFixIssue? lastIssue;
      double? lastAccuracy;
      // En fazla iki deneme: ilk örnek yeterince doğru değilse bir kez daha dene.
      for (var attempt = 0; attempt < 2; attempt++) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: _fixTimeLimit,
          ),
        );
        final issue = evaluateFix(
          accuracyMeters: position.accuracy,
          isMocked: position.isMocked,
          timestamp: position.timestamp,
        );
        if (issue == null) {
          return LocationFixResult.success(position);
        }
        lastIssue = issue;
        lastAccuracy = position.accuracy;
        if (issue == LocationFixIssue.mocked) break;
      }
      return LocationFixResult.failure(
        messageForIssue(lastIssue ?? LocationFixIssue.inaccurate,
            accuracyMeters: lastAccuracy),
      );
    } catch (e) {
      return LocationFixResult.failure(_describeLocationError(e));
    }
  }

  /// Geriye dönük uyumlu: doğrulanmış konum, alınamazsa null.
  Future<Position?> getCurrentPosition() async {
    final result = await acquireVerifiedPosition();
    return result.position;
  }

  /// Checks if resident is within allowed site geofence radius
  Future<GeofenceCheckResult> verifyWithinGeofence({
    required double? targetLat,
    required double? targetLng,
    required int radiusMeters,
  }) async {
    final radius = radiusMeters > 0 ? radiusMeters : defaultRadiusMeters;

    final hasValidTarget = targetLat != null &&
        targetLng != null &&
        targetLat.isFinite &&
        targetLng.isFinite &&
        targetLat >= -90 &&
        targetLat <= 90 &&
        targetLng >= -180 &&
        targetLng <= 180;
    if (!hasValidTarget) {
      // Fail-closed: kapı konumu tanımsızsa mesafe doğrulanamaz, izin verilmez.
      return GeofenceCheckResult(
        allowed: false,
        distanceMeters: -1,
        targetRadiusMeters: radius,
        errorMessage:
            'Bu kapı için konum çemberi tanımlı değil. Lütfen site yöneticinize başvurun.',
      );
    }

    final fix = await acquireVerifiedPosition();
    final position = fix.position;
    if (position == null) {
      return GeofenceCheckResult(
        allowed: false,
        distanceMeters: -1,
        targetRadiusMeters: radius,
        errorMessage: fix.errorMessage ?? 'Anlık konum alınamadı.',
      );
    }

    final distance = calculateDistance(
      position.latitude,
      position.longitude,
      targetLat,
      targetLng,
    );

    if (distance <= radius) {
      return GeofenceCheckResult(
        allowed: true,
        distanceMeters: distance,
        targetRadiusMeters: radius,
      );
    }
    return GeofenceCheckResult(
      allowed: false,
      distanceMeters: distance,
      targetRadiusMeters: radius,
      errorMessage:
          'Kapı konumunda değilsiniz (Mesafe: ~${distance.round()} m, İzin verilen: $radius m).',
    );
  }
}
