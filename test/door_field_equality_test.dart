// FAZ 5 / P-d: DoorRecord / DoorRuntimeStatus.hasSameFieldsAs — yoklama sonucu ekrandakiyle aynıysa
// arayüz yeniden kurulmaz. `==` / hashCode BİLEREK değişmedi (kimlik eşitliği).
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';

Map<String, dynamic> _doorJson() => {
      'id': 7,
      'site_code': 3,
      'site_name': 'Güneş Sitesi',
      'door_name': 'Ana Kapı',
      'door_index': 1,
      'is_active': true,
      'access_scope': 'SITE_COMMON',
      'block_id': 2,
      'block_name': 'A Blok',
      'assigned_device_id': 5,
      'assigned_device_uid': 'AABBCCDDEEFF',
      'assigned_device_hardware_target': 'esp32-wroom',
      'assigned_device_hardware_type': 'esp32-wroom',
      'assigned_device_firmware_version': '5.1.0',
      'assigned_device_is_online': true,
      'assigned_device_local_ip': '192.168.1.20',
      'assigned_device_public_ip': '88.1.2.3',
      'assigned_device_wifi_rssi': -55,
      'assigned_device_wifi_signal_percent': 80,
      'assigned_device_last_seen_at': '2026-05-01T10:00:00Z',
      'assigned_device_qr_reader_enabled': true,
      'mqtt_site_id': 3,
      'feature_qr_enabled': true,
      'feature_remote_open_enabled': true,
      'feature_local_udp_enabled': true,
      'feature_guest_pass_enabled': true,
      'qr_entry_active': true,
      'require_geofence': true,
      'geofence_latitude': 41.0,
      'geofence_longitude': 29.0,
      'geofence_radius_meters': 100,
      'qr_rotation_seconds': 30,
      'created_at': '2026-01-01T00:00:00Z',
    };

Map<String, dynamic> _statusJson({Map<String, dynamic>? door}) => {
      'door': door ?? _doorJson(),
      'device_status': {
        'device_uid': 'AABBCCDDEEFF',
        'mqtt_connected': true,
        'mqtt_bridge_connected': true,
        'door_locked': true,
        'firmware_version': '5.1.0',
        'hardware_target': 'esp32-wroom',
        'ota_status': 'guncel',
        'wifi_rssi': -55,
        'wifi_signal_percent': 80,
        'local_ip': '192.168.1.20',
        'public_ip': '88.1.2.3',
        'last_event': 'pulse',
        'last_seen_at': '2026-05-01T10:00:00Z',
        'local_control': {'ip': '192.168.1.20', 'port': 8765, 'token': 'tok', 'available': true},
      },
    };

void main() {
  group('DoorRecord.hasSameFieldsAs', () {
    test('aynı JSON iki kez ayrıştırılınca alanlar eşit, kimlik eşitliği DEĞİŞMEZ', () {
      final a = DoorRecord.fromJson(_doorJson());
      final b = DoorRecord.fromJson(_doorJson());
      expect(a.hasSameFieldsAs(b), isTrue);
      expect(a.hasSameFieldsAs(a), isTrue);
      expect(a == b, isFalse, reason: '== kimlik eşitliği olarak kalır (başka kodlar buna güvenebilir)');
    });

    test('her alandaki bir fark yakalanır (tüm alanlar karşılaştırılır)', () {
      final base = DoorRecord.fromJson(_doorJson());
      final changes = <String, Object?>{
        'id': 8,
        'site_code': 4,
        'site_name': 'Başka',
        'door_name': 'Yan Kapı',
        'door_index': 2,
        'is_active': false,
        'access_scope': 'BLOCK',
        'block_id': 3,
        'block_name': 'B Blok',
        'assigned_device_id': 6,
        'assigned_device_uid': 'FFEEDDCCBBAA',
        'assigned_device_hardware_target': 'esp32-c3',
        'assigned_device_hardware_type': 'esp32-c3',
        'assigned_device_firmware_version': '5.2.0',
        'assigned_device_is_online': false,
        'assigned_device_local_ip': '10.0.0.1',
        'assigned_device_public_ip': '1.1.1.1',
        'assigned_device_wifi_rssi': -70,
        'assigned_device_wifi_signal_percent': 40,
        'assigned_device_last_seen_at': '2026-05-01T11:00:00Z',
        'assigned_device_qr_reader_enabled': false,
        'mqtt_site_id': 9,
        'feature_qr_enabled': false,
        'feature_remote_open_enabled': false,
        'feature_local_udp_enabled': false,
        'feature_guest_pass_enabled': false,
        'qr_entry_active': false,
        'require_geofence': false,
        'geofence_latitude': 40.0,
        'geofence_longitude': 28.0,
        'geofence_radius_meters': 250,
        'qr_rotation_seconds': 60,
        'created_at': '2027-01-01T00:00:00Z',
      };
      for (final entry in changes.entries) {
        final json = _doorJson()..[entry.key] = entry.value;
        final changed = DoorRecord.fromJson(json);
        expect(base.hasSameFieldsAs(changed), isFalse, reason: 'alan ${entry.key} farkı yakalanmalı');
        expect(changed.hasSameFieldsAs(base), isFalse, reason: 'simetri: ${entry.key}');
      }
    });
  });

  group('DoorRuntimeStatus.hasSameFieldsAs', () {
    test('aynı yanıt eşit; kimlik eşitliği değişmez', () {
      final a = DoorRuntimeStatus.fromJson(_statusJson());
      final b = DoorRuntimeStatus.fromJson(_statusJson());
      expect(a.hasSameFieldsAs(b), isTrue);
      expect(a == b, isFalse);
    });

    test('cihaz durumundaki her fark yakalanır; kapı kaydındaki fark da yakalanır', () {
      final base = DoorRuntimeStatus.fromJson(_statusJson());
      final deviceChanges = <String, Object?>{
        'device_uid': 'X',
        'mqtt_connected': false,
        'mqtt_bridge_connected': false,
        'door_locked': false,
        'firmware_version': '6.0.0',
        'hardware_target': 'esp32-c3',
        'ota_status': 'hata',
        'wifi_rssi': -80,
        'wifi_signal_percent': 10,
        'public_ip': '2.2.2.2',
        'last_event': 'open',
        'last_seen_at': '2026-05-02T10:00:00Z',
      };
      for (final entry in deviceChanges.entries) {
        final json = _statusJson();
        (json['device_status'] as Map<String, dynamic>)[entry.key] = entry.value;
        final changed = DoorRuntimeStatus.fromJson(json);
        expect(base.hasSameFieldsAs(changed), isFalse, reason: 'durum alanı ${entry.key}');
      }

      // local_control içindeki alanlar (ip önceliği local_control'de).
      final localControl = <String, Object?>{'ip': '10.1.1.1', 'port': 9000, 'token': 'baska', 'available': false};
      for (final entry in localControl.entries) {
        final json = _statusJson();
        ((json['device_status'] as Map<String, dynamic>)['local_control'] as Map<String, dynamic>)[entry.key] =
            entry.value;
        expect(base.hasSameFieldsAs(DoorRuntimeStatus.fromJson(json)), isFalse, reason: 'local_control.${entry.key}');
      }

      final otherDoor = DoorRuntimeStatus.fromJson(_statusJson(door: _doorJson()..['door_name'] = 'Başka Kapı'));
      expect(base.hasSameFieldsAs(otherDoor), isFalse);
    });

    test('copyWithOffline farklı sayılır', () {
      final base = DoorRuntimeStatus.fromJson(_statusJson());
      expect(base.hasSameFieldsAs(base.copyWithOffline()), isFalse);
    });
  });
}
