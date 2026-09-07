import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/ui/widgets/door_logs_accordion.dart';

void main() {
  final testDoor = DoorRecord(
    id: 28,
    siteCode: 1,
    siteName: 'Test Sitesi',
    doorName: 'Ana Giriş Kapısı',
    doorIndex: 1,
    isActive: true,
    assignedDeviceId: 1,
    assignedDeviceUid: 'DEV-01',
    mqttSiteId: 1,
    createdAt: DateTime(2026, 1, 1),
  );

  testWidgets('DoorLogsAccordion renders collapsed by default', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: DoorLogsAccordion(
              selectedSite: null,
              selectedDoor: testDoor,
              authService: null,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(DoorLogsAccordion), findsOneWidget);
    expect(find.text('📊 Ana Giriş Kapısı Geçiş Logları'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
  });

  testWidgets('DoorLogsAccordion toggles expansion on tap', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: DoorLogsAccordion(
              selectedSite: null,
              selectedDoor: testDoor,
              authService: null,
            ),
          ),
        ),
      ),
    );

    // Tap to expand
    await tester.tap(find.text('📊 Ana Giriş Kapısı Geçiş Logları'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
    expect(find.text('Haftalık Geçiş Geçmişi'), findsOneWidget);
  });
}

