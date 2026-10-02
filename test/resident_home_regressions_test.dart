import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/profile_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/resident_door_remote_card.dart';

DoorRecord _door({String? siteName = 'Güneş Sitesi'}) => DoorRecord(
      id: 7,
      siteCode: 101,
      siteName: siteName,
      doorName: 'Ana Giriş',
      doorIndex: 1,
      isActive: true,
      assignedDeviceId: 1,
      assignedDeviceUid: 'ESP32_C3_TEST',
      mqttSiteId: 101,
      createdAt: DateTime(2026, 1, 1),
    );

const _residentSession = UserSession(
  id: 81,
  fullName: 'Ali Veli',
  email: 'a1.sakin.1.101@ahbu.local',
  loginName: 'a1.sakin',
  role: UserRole.apartmentOwner,
  isActive: true,
  token: 'tok',
  phoneNumber: '+90 532 000 00 01',
);

class _ResidentAuth extends AuthService {
  _ResidentAuth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  @override
  UserSession? get session => _residentSession;

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[], null);

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({required int doorId}) async => (null, null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;
}

Widget _card({DoorRecord? door}) {
  final d = door ?? _door();
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ResidentDoorRemoteCard(
          selectedSite: null, // daire sakini site listesini göremez
          selectedDoor: d,
          doors: <DoorRecord>[d],
          runtimeStatus: null,
          isLoadingStatus: false,
          isOpeningDoor: false,
          onSelectDoor: (_) {},
          onOpenDoor: () {},
          onCreateGuestPass: () {},
          roleColor: Colors.purple,
        ),
      ),
    ),
  );
}

void main() {
  group('Daire sakini kumandası: site adı (E2E bulgusu: başlıkta kapı adı iki kez yazıyordu)', () {
    testWidgets('selectedSite yokken başlık, kapı kaydındaki site adını gösterir', (tester) async {
      await tester.pumpWidget(_card());
      await tester.pump();

      expect(find.text('Güneş Sitesi'), findsOneWidget);
      // Kapı adı yalnızca alt satırda ("🚪 Ana Giriş") görünür, başlıkta tekrar etmez.
      expect(find.text('Ana Giriş'), findsNothing);
      expect(find.text('🚪 Ana Giriş'), findsOneWidget);
    });

    testWidgets('kapı kaydında site adı da yoksa eski davranış (kapı adı) korunur', (tester) async {
      await tester.pumpWidget(_card(door: _door(siteName: null)));
      await tester.pump();

      expect(find.text('Ana Giriş'), findsOneWidget);
    });
  });

  group('Daire sakini Profilim (E2E bulgusu: boş sayfa)', () {
    testWidgets('ResidentProfileView salt okunur hesap bilgilerini gösterir, taşmaz', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ResidentProfileView(session: _residentSession)),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Hesap Bilgilerim'), findsOneWidget);
      expect(find.text('Ali Veli'), findsOneWidget);
      expect(find.text('a1.sakin'), findsOneWidget);
      expect(find.text('+90 532 000 00 01'), findsOneWidget);
      expect(find.textContaining('site yöneticiniz'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('HomePage: daire sakini menüden Profilim açınca sayfa boş değildir', (tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: HomePage(authService: _ResidentAuth())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Profilim'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ResidentProfileView), findsOneWidget);
      expect(find.text('Hesap Bilgilerim'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Periyodik zamanlayıcıları temizle.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
