import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/services/geofence_service.dart';
import 'package:site_kapi_kontrol/ui/widgets/site_security_policy_dialog.dart';

Position _position({
  double latitude = 41.0082,
  double longitude = 28.9784,
  double accuracy = 8,
  bool isMocked = false,
  DateTime? timestamp,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp ?? DateTime.now(),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
    isMocked: isMocked,
  );
}

void main() {
  group('GeofenceService Distance & Proximity Tests', () {
    test('Calculates distance accurately using Haversine formula', () {
      // Taksim Square (41.0370, 28.9850) to Galata Tower (41.0256, 28.9741)
      final distance = GeofenceService.instance.calculateDistance(
        41.0370,
        28.9850,
        41.0256,
        28.9741,
      );

      // Distance should be around 1550m +- 150m
      expect(distance, greaterThan(1400));
      expect(distance, lessThan(1700));
    });

    test('Zero distance for identical coordinates', () {
      final distance = GeofenceService.instance.calculateDistance(
        41.0000,
        29.0000,
        41.0000,
        29.0000,
      );
      expect(distance, closeTo(0.0, 0.001));
    });

    test('verifyWithinGeofence is fail-closed when target coords are undefined', () async {
      final result = await GeofenceService.instance.verifyWithinGeofence(
        targetLat: null,
        targetLng: null,
        radiusMeters: 75,
      );
      expect(result.allowed, isFalse);
      expect(result.distanceMeters, -1);
      expect(result.errorMessage, isNotNull);
      expect(result.errorMessage, contains('tanımlı değil'));
    });

    test('verifyWithinGeofence rejects out-of-range or NaN target coordinates', () async {
      for (final coords in <List<double>>[
        [91.0, 29.0],
        [41.0, 181.0],
        [double.nan, 29.0],
      ]) {
        final result = await GeofenceService.instance.verifyWithinGeofence(
          targetLat: coords[0],
          targetLng: coords[1],
          radiusMeters: 100,
        );
        expect(result.allowed, isFalse, reason: 'coords $coords must be rejected');
      }
    });

    test('default radius is the single contract value (100 m)', () {
      expect(GeofenceService.defaultRadiusMeters, 100);
      expect(
        SiteRecord.fromJson({'id': 1, 'name': 'S', 'created_at': '2026-01-01T00:00:00Z'})
            .geofenceRadiusMeters,
        100,
      );
      expect(
        DoorRecord.fromJson({
          'id': 1,
          'site_code': 1,
          'door_name': 'K',
        }).geofenceRadiusMeters,
        100,
      );
    });
  });

  group('GeofenceService fix evaluation (C3 client policy)', () {
    final now = DateTime.utc(2026, 5, 1, 12, 0, 0);

    test('accepts a fresh, accurate, non-mocked fix', () {
      expect(
        GeofenceService.evaluateFix(
          accuracyMeters: 20,
          isMocked: false,
          timestamp: now.subtract(const Duration(seconds: 5)),
          now: now,
        ),
        isNull,
      );
    });

    test('rejects mocked locations before anything else', () {
      expect(
        GeofenceService.evaluateFix(
          accuracyMeters: 5,
          isMocked: true,
          timestamp: now,
          now: now,
        ),
        LocationFixIssue.mocked,
      );
    });

    test('rejects accuracy worse than 50 m (and NaN / negative accuracy)', () {
      for (final accuracy in <double>[50.1, 120, double.nan, -1]) {
        expect(
          GeofenceService.evaluateFix(
            accuracyMeters: accuracy,
            isMocked: false,
            timestamp: now,
            now: now,
          ),
          LocationFixIssue.inaccurate,
          reason: 'accuracy=$accuracy',
        );
      }
      expect(
        GeofenceService.evaluateFix(
          accuracyMeters: 50,
          isMocked: false,
          timestamp: now,
          now: now,
        ),
        isNull,
      );
    });

    test('rejects fixes older than 30 s (hard cap) and clock-skewed future stamps', () {
      expect(
        GeofenceService.evaluateFix(
          accuracyMeters: 10,
          isMocked: false,
          timestamp: now.subtract(const Duration(seconds: 31)),
          now: now,
        ),
        LocationFixIssue.stale,
      );
      expect(
        GeofenceService.evaluateFix(
          accuracyMeters: 10,
          isMocked: false,
          timestamp: now.subtract(const Duration(seconds: 30)),
          now: now,
        ),
        isNull,
      );
      expect(
        GeofenceService.evaluateFix(
          accuracyMeters: 10,
          isMocked: false,
          timestamp: now.add(const Duration(minutes: 5)),
          now: now,
        ),
        LocationFixIssue.stale,
      );
    });

    test('messages are user readable and never raw exceptions', () {
      for (final issue in LocationFixIssue.values) {
        final message = GeofenceService.messageForIssue(issue, accuracyMeters: 87.4);
        expect(message, isNotEmpty);
        expect(message.contains('Exception'), isFalse);
      }
      expect(
        GeofenceService.messageForIssue(LocationFixIssue.inaccurate, accuracyMeters: 87.4),
        contains('87'),
      );
    });

    test('request fields follow contract C3 (ISO8601 UTC timestamp, is_mocked flag)', () {
      final stamp = DateTime.utc(2026, 5, 1, 12, 34, 56, 789);
      final fields = GeofenceService.locationRequestFields(
        _position(
          latitude: 41.015,
          longitude: 28.979,
          accuracy: 12.5,
          timestamp: stamp,
        ),
      );
      expect(fields['latitude'], 41.015);
      expect(fields['longitude'], 28.979);
      expect(fields['accuracy'], 12.5);
      expect(fields['is_mocked'], false);
      expect(fields['timestamp'], '2026-05-01T12:34:56.789Z');
      expect(fields.keys.toSet(), {'latitude', 'longitude', 'accuracy', 'timestamp', 'is_mocked'});

      final local = GeofenceService.locationRequestFields(
        _position(timestamp: DateTime(2026, 5, 1, 12, 0, 0)),
      );
      expect((local['timestamp'] as String).endsWith('Z'), isTrue);
    });
  });

  group('Site security policy form validation (geofence required fields)', () {
    test('valid coordinates and radius pass (comma decimal accepted)', () {
      final v = validateGeofenceForm(
        latitudeText: '41,0082',
        longitudeText: '28.9784',
        radiusMeters: 100,
      );
      expect(v.isValid, isTrue);
      expect(v.latitude, closeTo(41.0082, 1e-9));
      expect(v.longitude, closeTo(28.9784, 1e-9));
    });

    test('empty, non numeric and out-of-range values are rejected', () {
      final empty = validateGeofenceForm(
        latitudeText: '',
        longitudeText: '   ',
        radiusMeters: 100,
      );
      expect(empty.isValid, isFalse);
      expect(empty.latitudeError, isNotNull);
      expect(empty.longitudeError, isNotNull);

      final garbage = validateGeofenceForm(
        latitudeText: 'abc',
        longitudeText: '12.3.4',
        radiusMeters: 100,
      );
      expect(garbage.latitudeError, isNotNull);
      expect(garbage.longitudeError, isNotNull);

      final range = validateGeofenceForm(
        latitudeText: '91',
        longitudeText: '-181',
        radiusMeters: 100,
      );
      expect(range.latitudeError, isNotNull);
      expect(range.longitudeError, isNotNull);
    });

    test('(0,0) is treated as undefined and radius must be within 10..2000', () {
      expect(
        validateGeofenceForm(latitudeText: '0', longitudeText: '0', radiusMeters: 100).isValid,
        isFalse,
      );
      expect(
        validateGeofenceForm(latitudeText: '41', longitudeText: '29', radiusMeters: 5).radiusError,
        isNotNull,
      );
      expect(
        validateGeofenceForm(latitudeText: '41', longitudeText: '29', radiusMeters: 2500).radiusError,
        isNotNull,
      );
      expect(
        validateGeofenceForm(latitudeText: '41', longitudeText: '29', radiusMeters: 10).isValid,
        isTrue,
      );
    });
  });

  group('DoorRecord Capability Getters Tests', () {
    test('canOpenRemote getter reflects featureRemoteOpenEnabled', () {
      final doorAllowed = DoorRecord(
        id: 1,
        siteCode: 1,
        siteName: 'Site 1',
        doorName: 'Ana Kapı',
        doorIndex: 1,
        isActive: true,
        assignedDeviceId: 1,
        assignedDeviceUid: 'DEV1',
        mqttSiteId: 1,
        createdAt: DateTime.now(),
        featureRemoteOpenEnabled: true,
      );

      final doorDisabled = DoorRecord(
        id: 2,
        siteCode: 1,
        siteName: 'Site 1',
        doorName: 'Yan Kapı',
        doorIndex: 2,
        isActive: true,
        assignedDeviceId: 2,
        assignedDeviceUid: 'DEV2',
        mqttSiteId: 1,
        createdAt: DateTime.now(),
        featureRemoteOpenEnabled: false,
      );

      expect(doorAllowed.canOpenRemote, isTrue);
      expect(doorDisabled.canOpenRemote, isFalse);
    });

    test('canOpenQr getter requires policy and physical QR scanner hardware (excludes C3)', () {
      final doorFullyActive = DoorRecord(
        id: 1,
        siteCode: 1,
        siteName: 'Site 1',
        doorName: 'Ana Kapı',
        doorIndex: 1,
        isActive: true,
        assignedDeviceId: 1,
        assignedDeviceUid: 'DEV1',
        assignedDeviceHardwareTarget: 'esp32-wroom',
        assignedDeviceQrReaderEnabled: true,
        mqttSiteId: 1,
        createdAt: DateTime.now(),
        featureQrEnabled: true,
        qrEntryActive: true,
      );

      final doorFeatureOff = DoorRecord(
        id: 2,
        siteCode: 1,
        siteName: 'Site 1',
        doorName: 'Yan Kapı',
        doorIndex: 2,
        isActive: true,
        assignedDeviceId: 2,
        assignedDeviceUid: 'DEV2',
        assignedDeviceHardwareTarget: 'esp32-wroom',
        assignedDeviceQrReaderEnabled: true,
        mqttSiteId: 1,
        createdAt: DateTime.now(),
        featureQrEnabled: false,
        qrEntryActive: true,
      );

      final doorSiteManagerOff = DoorRecord(
        id: 3,
        siteCode: 1,
        siteName: 'Site 1',
        doorName: 'Garaj Kapısı',
        doorIndex: 3,
        isActive: true,
        assignedDeviceId: 3,
        assignedDeviceUid: 'DEV3',
        assignedDeviceHardwareTarget: 'esp32-wroom',
        assignedDeviceQrReaderEnabled: true,
        mqttSiteId: 1,
        createdAt: DateTime.now(),
        featureQrEnabled: true,
        qrEntryActive: false,
      );

      final doorC3Mini = DoorRecord(
        id: 4,
        siteCode: 1,
        siteName: 'Site 1',
        doorName: 'C3 Apartman Kapısı',
        doorIndex: 4,
        isActive: true,
        assignedDeviceId: 4,
        assignedDeviceUid: 'DEV4',
        assignedDeviceHardwareTarget: 'esp32-c3',
        assignedDeviceQrReaderEnabled: true,
        mqttSiteId: 1,
        createdAt: DateTime.now(),
        featureQrEnabled: true,
        qrEntryActive: true,
      );

      final doorWroomWithoutScanner = DoorRecord(
        id: 5,
        siteCode: 1,
        siteName: 'Site 1',
        doorName: 'Kamerasız WROOM Kapısı',
        doorIndex: 5,
        isActive: true,
        assignedDeviceId: 5,
        assignedDeviceUid: 'DEV5',
        assignedDeviceHardwareTarget: 'esp32-wroom',
        assignedDeviceQrReaderEnabled: false,
        mqttSiteId: 1,
        createdAt: DateTime.now(),
        featureQrEnabled: true,
        qrEntryActive: true,
      );

      final doorWithoutDevice = DoorRecord(
        id: 6,
        siteCode: 1,
        siteName: 'Site 1',
        doorName: 'Cihaz Atanmamış Kapı',
        doorIndex: 6,
        isActive: true,
        assignedDeviceId: null,
        assignedDeviceUid: null,
        mqttSiteId: 1,
        createdAt: DateTime.now(),
        featureQrEnabled: true,
        qrEntryActive: true,
      );

      expect(doorFullyActive.canOpenQr, isTrue);
      expect(doorFeatureOff.canOpenQr, isFalse);
      expect(doorSiteManagerOff.canOpenQr, isFalse);
      expect(doorC3Mini.canOpenQr, isFalse, reason: 'ESP32-C3 Mini kapılarında QR geçiş butonu olmamalı');
      expect(doorWroomWithoutScanner.canOpenQr, isFalse, reason: 'Kamerasız cihazlarda QR geçiş butonu olmamalı');
      expect(doorWithoutDevice.canOpenQr, isFalse, reason: 'Cihaz atanmamış kapıda QR geçiş butonu olmamalı');
    });

    test('requiresLocationForQrScan: site geofence veya ekransız (C3) cihaz', () {
      DoorRecord door({
        bool geofence = false,
        String? target,
        String? uid = 'DEV',
      }) =>
          DoorRecord(
            id: 1,
            siteCode: 1,
            siteName: 'S',
            doorName: 'K',
            doorIndex: 1,
            isActive: true,
            assignedDeviceId: uid == null ? null : 1,
            assignedDeviceUid: uid,
            assignedDeviceHardwareTarget: target,
            mqttSiteId: 1,
            requireGeofence: geofence,
            createdAt: DateTime(2026, 1, 1),
          );

      expect(door(geofence: true, target: 'esp32-wroom').requiresLocationForQrScan, isTrue);
      expect(door(target: 'esp32-wroom').requiresLocationForQrScan, isFalse,
          reason: 'ekranlı cihazda site bayrağı kapalıysa konum şart değil');
      expect(door(target: 'esp32-c3').requiresLocationForQrScan, isTrue,
          reason: 'ekransız C3 cihazda sunucu konumu zorunlu tutar');
      expect(door(uid: null).requiresLocationForQrScan, isFalse);
    });

    test('canCreateGuestPass getter reflects featureGuestPassEnabled', () {
      final doorAllowed = DoorRecord(
        id: 1,
        siteCode: 1,
        siteName: 'Site 1',
        doorName: 'Ana Kapı',
        doorIndex: 1,
        isActive: true,
        assignedDeviceId: 1,
        assignedDeviceUid: 'DEV1',
        mqttSiteId: 1,
        createdAt: DateTime.now(),
        featureGuestPassEnabled: true,
      );

      final doorDisabled = DoorRecord(
        id: 2,
        siteCode: 1,
        siteName: 'Site 1',
        doorName: 'Yan Kapı',
        doorIndex: 2,
        isActive: true,
        assignedDeviceId: 2,
        assignedDeviceUid: 'DEV2',
        mqttSiteId: 1,
        createdAt: DateTime.now(),
        featureGuestPassEnabled: false,
      );

      expect(doorAllowed.canCreateGuestPass, isTrue);
      expect(doorDisabled.canCreateGuestPass, isFalse);
    });

    test('SiteRecord JSON serialization preserves new fields', () {
      final json = {
        'id': 42,
        'name': 'Güneş Sitesi',
        'address': 'Atatürk Cad.',
        'city': 'Istanbul',
        'district': 'Kadikoy',
        'block_count': 2,
        'apartment_count': 20,
        'door_count': 2,
        'approval_status': 'approved',
        'mqtt_site_id': 42,
        'manager_user_code': 1,
        'manager_name': 'Ahmet',
        'created_at': '2026-09-01T12:00:00.000Z',
        'feature_qr_enabled': true,
        'feature_remote_open_enabled': true,
        'feature_local_udp_enabled': false,
        'feature_guest_pass_enabled': true,
        'qr_entry_active': true,
        'require_geofence': true,
        'geofence_latitude': 41.012345,
        'geofence_longitude': 28.976543,
        'geofence_radius_meters': 80,
      };

      final site = SiteRecord.fromJson(json);
      expect(site.id, 42);
      expect(site.name, 'Güneş Sitesi');
      expect(site.featureQrEnabled, isTrue);
      expect(site.featureRemoteOpenEnabled, isTrue);
      expect(site.isHybrid, isTrue);
      expect(site.isAppOnly, isFalse);
      expect(site.isQrOnly, isFalse);
      expect(site.accessModeLabel, 'Hibrit (Uygulama + QR)');
      expect(site.qrRotationSeconds, 30);
      expect(site.featureLocalUdpEnabled, isFalse);
      expect(site.requireGeofence, isTrue);
      expect(site.geofenceLatitude, 41.012345);
      expect(site.geofenceLongitude, 28.976543);
      expect(site.geofenceRadiusMeters, 80);
    });

    test('SiteRecord access mode getters detect QR-only and App-only properly', () {
      final qrOnlySite = SiteRecord(
        id: 1,
        name: 'QR Only Site',
        address: null,
        city: null,
        district: null,
        blockCount: 1,
        apartmentCount: 5,
        doorCount: 1,
        approvalStatus: 'approved',
        approvedAt: null,
        mqttSiteId: 101,
        managerUserCode: null,
        managerName: null,
        featureRemoteOpenEnabled: false,
        featureQrEnabled: true,
        createdAt: DateTime.now(),
      );
      expect(qrOnlySite.isQrOnly, isTrue);
      expect(qrOnlySite.isAppOnly, isFalse);
      expect(qrOnlySite.isHybrid, isFalse);
      expect(qrOnlySite.accessModeLabel, 'Sadece QR Kod');

      final appOnlySite = SiteRecord(
        id: 2,
        name: 'App Only Site',
        address: null,
        city: null,
        district: null,
        blockCount: 1,
        apartmentCount: 5,
        doorCount: 1,
        approvalStatus: 'approved',
        approvedAt: null,
        mqttSiteId: 102,
        managerUserCode: null,
        managerName: null,
        featureRemoteOpenEnabled: true,
        featureQrEnabled: false,
        createdAt: DateTime.now(),
      );
      expect(appOnlySite.isAppOnly, isTrue);
      expect(appOnlySite.isQrOnly, isFalse);
      expect(appOnlySite.isHybrid, isFalse);
      expect(appOnlySite.accessModeLabel, 'Sadece Uygulama');
    });
  });
}
