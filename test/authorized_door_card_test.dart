import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/views/individual_home_view.dart';

class MockAuthServiceForDoorCard extends AuthService {
  MockAuthServiceForDoorCard() : super(api: AuthApi(baseUrl: 'http://localhost'));

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async {
    return (
      <DoorRecord>[
        DoorRecord(
          id: 1,
          siteCode: 101,
          siteName: 'Güneş Sitesi',
          doorName: 'Ana Giriş Kapısı',
          doorIndex: 0,
          isActive: true,
          accessScope: 'SITE_COMMON',
          assignedDeviceId: 1,
          assignedDeviceUid: 'ESP32_WROOM_123',
          assignedDeviceHardwareTarget: 'esp32_wroom',
          assignedDeviceIsOnline: true,
          assignedDeviceQrReaderEnabled: true,
          assignedDeviceWifiSignalPercent: 88,
          mqttSiteId: 101,
          requireGeofence: true,
          geofenceRadiusMeters: 50,
          createdAt: DateTime(2026, 1, 1),
        ),
        DoorRecord(
          id: 2,
          siteCode: 101,
          siteName: 'Güneş Sitesi',
          doorName: 'B Blok Giriş',
          doorIndex: 1,
          isActive: true,
          accessScope: 'BLOCK',
          blockName: 'B Blok',
          assignedDeviceId: 2,
          assignedDeviceUid: 'ESP32_C3_456',
          assignedDeviceHardwareTarget: 'esp32_c3',
          assignedDeviceIsOnline: false,
          mqttSiteId: 101,
          requireGeofence: false,
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
      null,
    );
  }

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async {
    return (<JoinRequestRecord>[], null);
  }

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async {
    return <Map<String, dynamic>>[];
  }

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async {
    return (<MyApartmentRecord>[], null);
  }
}

void main() {
  final session = UserSession(
    token: 'test_token',
    id: 1,
    fullName: 'Ahmet Ceylan',
    email: 'ahmet@example.com',
    loginName: 'ahmet',
    role: UserRole.individual,
    isActive: true,
  );

  testWidgets('Yetkili Kapılarım door card renders with modern elements without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockAuth = MockAuthServiceForDoorCard();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: IndividualHomeView(
              session: session,
              authService: mockAuth,
              onRefreshAll: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Yetkili Kapılarım header
    expect(find.text('Yetkili Kapılarım'), findsOneWidget);
    expect(find.text('Ana Giriş Kapısı'), findsOneWidget);
    expect(find.text('B Blok Giriş'), findsOneWidget);

    // Online and Offline statuses
    expect(find.text('Çevrimiçi'), findsOneWidget);
    expect(find.text('Çevrimdışı'), findsOneWidget);

    // Badges
    expect(find.text('Site Ortak Kapısı'), findsOneWidget);
    expect(find.text('B Blok Kapısı'), findsOneWidget);
    expect(find.text('Konum (50m)'), findsOneWidget);
    expect(find.text('Optik QR'), findsOneWidget);
    expect(find.text('%88'), findsOneWidget);

    // Actions
    expect(find.text('Kapı Ekranından QR Oku'), findsOneWidget);
    expect(find.text('Kapıya QR Göster'), findsOneWidget);
    expect(find.text('Uzaktan Aç'), findsOneWidget);
    expect(find.text('Kapıyı Aç'), findsOneWidget);
    expect(find.text('Misafir Kodu'), findsNWidgets(2));
  });
}

