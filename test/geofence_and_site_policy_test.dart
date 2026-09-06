import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/services/geofence_service.dart';

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

    test('verifyWithinGeofence returns allowed when target coords are null', () async {
      final result = await GeofenceService.instance.verifyWithinGeofence(
        targetLat: null,
        targetLng: null,
        radiusMeters: 75,
      );
      expect(result.allowed, isTrue);
      expect(result.distanceMeters, 0.0);
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

    test('canOpenQr getter requires both featureQrEnabled and qrEntryActive', () {
      final doorFullyActive = DoorRecord(
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
        mqttSiteId: 1,
        createdAt: DateTime.now(),
        featureQrEnabled: true,
        qrEntryActive: false,
      );

      expect(doorFullyActive.canOpenQr, isTrue);
      expect(doorFeatureOff.canOpenQr, isFalse);
      expect(doorSiteManagerOff.canOpenQr, isFalse);
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
      expect(site.featureLocalUdpEnabled, isFalse);
      expect(site.requireGeofence, isTrue);
      expect(site.geofenceLatitude, 41.012345);
      expect(site.geofenceLongitude, 28.976543);
      expect(site.geofenceRadiusMeters, 80);
    });
  });
}
