import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/device_connectivity_log.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/widgets/device_connectivity_logs_accordion.dart';

void main() {
  final testDevice = DeviceRecord(
    id: 1,
    deviceUid: 'DEV-AABB1122',
    assignedUserCode: 1001,
    siteCode: 10,
    siteName: 'Güneş Sitesi',
    assignedDoorId: 5,
    assignedDoorName: 'Ana Giriş Kapısı',
    gateName: 'Giriş',
    siteApprovalStatus: 'approved',
    mqttUsername: 'device_DEV-AABB1122',
    mqttConfigured: true,
    mqttConnected: true,
    firmwareVersion: '3.0.3',
    hardwareTarget: 'esp32-c3',
    otaStatus: null,
    otaLastVersion: null,
    wifiRssi: -58,
    wifiSignalPercent: 82,
    lastSeenAt: DateTime(2026, 1, 1),
    lastEvent: null,
    localIp: '192.168.1.105',
    createdAt: DateTime(2026, 1, 1),
  );

  test('DeviceConnectivityReport fromJson parses correctly', () {
    final json = {
      'device_uid': 'DEV-AABB1122',
      'is_online': true,
      'current_online_since': '2026-09-08T18:00:00.000Z',
      'current_online_duration_seconds': 14400,
      'current_online_duration_text': '4 saat',
      'last_offline_at': '2026-09-08T17:50:00.000Z',
      'logs': [
        {
          'id': 1,
          'device_uid': 'DEV-AABB1122',
          'event_type': 'offline',
          'online_at': '2026-09-08T12:00:00.000Z',
          'offline_at': '2026-09-08T17:50:00.000Z',
          'duration_seconds': 21000,
          'duration_text': '5 saat 50 dk',
          'reason': 'Wi-Fi / Bağlantı Kesildi (LWT)',
          'wifi_rssi': -65,
          'wifi_signal_percent': 75,
          'local_ip': '192.168.1.105',
          'created_at': '2026-09-08T17:50:02.000Z',
        }
      ],
      'pagination': {
        'page': 1,
        'pageSize': 10,
        'total': 1,
        'totalPages': 1,
      }
    };

    final report = DeviceConnectivityReport.fromJson(json);
    expect(report.deviceUid, 'DEV-AABB1122');
    expect(report.isOnline, true);
    expect(report.currentOnlineDurationText, '4 saat');
    expect(report.logs.length, 1);
    expect(report.logs.first.durationText, '5 saat 50 dk');
    expect(report.logs.first.wifiSignalPercent, 75);
    expect(report.logs.first.reason, 'Wi-Fi / Bağlantı Kesildi (LWT)');
  });

  testWidgets('DeviceConnectivityLogsAccordion renders collapsed by default', (tester) async {
    final authService = AuthService(api: AuthApi(baseUrl: 'https://test.local'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: DeviceConnectivityLogsAccordion(
              device: testDevice,
              authService: authService,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(DeviceConnectivityLogsAccordion), findsOneWidget);
    expect(find.text('Bağlantı & Kopma Geçmişi'), findsOneWidget);
    expect(find.text('Logları Gör'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
  });
}
