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

class GeofenceService {
  GeofenceService._();
  static final GeofenceService instance = GeofenceService._();

  /// Calculates Haversine distance in meters between two coordinates
  double calculateDistance(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    return Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
  }

  /// Request current device location
  Future<Position?> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Checks if resident is within allowed site geofence radius
  Future<GeofenceCheckResult> verifyWithinGeofence({
    required double? targetLat,
    required double? targetLng,
    required int radiusMeters,
  }) async {
    if (targetLat == null || targetLng == null) {
      // No geofence coordinates configured on site, allow access
      return GeofenceCheckResult(
        allowed: true,
        distanceMeters: 0,
        targetRadiusMeters: radiusMeters,
      );
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return GeofenceCheckResult(
        allowed: false,
        distanceMeters: -1,
        targetRadiusMeters: radiusMeters,
        errorMessage: 'Konum servisleri kapali. Lutfen GPS konumunu acin.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return GeofenceCheckResult(
          allowed: false,
          distanceMeters: -1,
          targetRadiusMeters: radiusMeters,
          errorMessage: 'Konum izni verilmedi. Guvenlik icin konum gereklidir.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return GeofenceCheckResult(
        allowed: false,
        distanceMeters: -1,
        targetRadiusMeters: radiusMeters,
        errorMessage: 'Konum izni kalici olarak engellenmis. Ayarlardan izin verin.',
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final distance = calculateDistance(
        position.latitude,
        position.longitude,
        targetLat,
        targetLng,
      );

      if (distance <= radiusMeters) {
        return GeofenceCheckResult(
          allowed: true,
          distanceMeters: distance,
          targetRadiusMeters: radiusMeters,
        );
      } else {
        return GeofenceCheckResult(
          allowed: false,
          distanceMeters: distance,
          targetRadiusMeters: radiusMeters,
          errorMessage: 'Kapi konumunda degilsiniz (Mesafe: ~m, Izin verilen: m).',
        );
      }
    } catch (e) {
      return GeofenceCheckResult(
        allowed: false,
        distanceMeters: -1,
        targetRadiusMeters: radiusMeters,
        errorMessage: 'Anlik konum alinamadi: ',
      );
    }
  }
}
