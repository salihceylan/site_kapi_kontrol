// FX1 düzeltmeleri: oturum / gezinme arayüz regresyon testleri.
//
// auth-session#0 (kayıt -> doğrulama -> ana sayfa gezinmesi kök rotayı silmemeli),
// auth-session#4 (kendi hesabını düzenlerken parola alanı gizli), site-manager-admin#7 (e-posta
// doğrulandı sonucu), error-contract#9 (bireysel kullanıcı /manager/sites çağırmaz).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/site_page.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/dialogs/managed_user_dialog.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/pages/login_page.dart';
import 'package:site_kapi_kontrol/ui/pages/register_individual_page.dart';
import 'package:site_kapi_kontrol/ui/pages/verify_email_code_page.dart';

/// lib/app.dart'taki kök yapıyı taklit eden sahte servis: oturum durumu değişince
/// dinleyicilere haber verir (MaterialApp.home bu servise tepki verir).
class _FlowAuth extends AuthService {
  _FlowAuth() : super(api: AuthApi(baseUrl: 'http://localhost'));

  bool loggedIn = false;
  final List<String> verifiedCodes = <String>[];

  @override
  bool get isReady => true;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  UserSession? get session => loggedIn
      ? const UserSession(
          id: 5,
          fullName: 'Ali Veli',
          email: 'ali@example.com',
          loginName: null,
          role: UserRole.individual,
          isActive: true,
          token: 'tok',
        )
      : null;

  @override
  Future<String?> registerIndividual({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async =>
      null;

  @override
  Future<String?> verifyIndividualCode({
    required String email,
    required String code,
  }) async {
    verifiedCodes.add(code);
    loggedIn = true;
    notifyListeners();
    return null;
  }

  @override
  Future<void> logout() async {
    loggedIn = false;
    notifyListeners();
  }
}

/// Oturum durumuna göre kökü değiştiren MaterialApp (lib/app.dart ile aynı desen).
Widget _app(_FlowAuth auth) {
  return MaterialApp(
    home: AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        if (auth.isLoggedIn) {
          return const Scaffold(body: Center(child: Text('ANA SAYFA')));
        }
        return LoginPage(authService: auth);
      },
    ),
  );
}

/// Rol bazlı HomePage gözlemi: hangi site listesi çağrıları yapıldı?
class _RoleHomeAuth extends AuthService {
  _RoleHomeAuth(this._role) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final UserRole _role;
  final List<int> listSitesPageSizes = <int>[];

  @override
  UserSession? get session => UserSession(
        id: 5,
        fullName: 'Test Kullanıcı',
        email: 'test@example.com',
        loginName: null,
        role: _role,
        isActive: true,
        token: 'tok',
      );

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  Future<SitePage> listSites({
    required int page,
    int pageSize = 10,
    String? approvalStatus,
  }) async {
    listSitesPageSizes.add(pageSize);
    return SitePage(sites: const <SiteRecord>[], total: 0, page: 1, pageSize: pageSize);
  }

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async => <Map<String, dynamic>>[];

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async =>
      (<JoinRequestRecord>[], null);

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async =>
      (<MyApartmentRecord>[], null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;
}

ManagedUserAccount _user({bool emailVerified = false, UserRole role = UserRole.superUser}) {
  return ManagedUserAccount(
    id: 5,
    fullName: 'Ali Veli',
    email: 'ali@example.com',
    loginName: null,
    role: role,
    isActive: true,
    phoneNumber: null,
    createdAt: null,
    emailVerified: emailVerified,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('auth-session#0: kayıt -> doğrulama sonrası kök rota korunur', () {
    testWidgets('doğrulama başarısında yalnızca Kayıt+Doğrulama kapanır; çıkışta giriş ekranı döner',
        (tester) async {
      tester.view.physicalSize = const Size(320, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final auth = _FlowAuth();
      await tester.pumpWidget(_app(auth));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);

      // Giriş -> Yeni Hesap Oluştur
      await tester.tap(find.text('Yeni Hesap Oluştur'));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterIndividualPage), findsOneWidget);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Ali');
      await tester.enterText(fields.at(1), 'Veli');
      await tester.enterText(fields.at(2), 'ali@example.com');
      await tester.enterText(fields.at(3), 'parola123');
      await tester.enterText(fields.at(4), 'parola123');
      await tester.tap(find.text('Kayıt Ol').last);
      await tester.pumpAndSettle();
      expect(find.byType(VerifyEmailCodePage), findsOneWidget);

      // Doğru kod -> oturum kurulur (servis dinleyicileri bilgilendirir)
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Hesabımı Doğrula'));
      await tester.pumpAndSettle();

      expect(auth.verifiedCodes, ['123456']);
      expect(find.byType(VerifyEmailCodePage), findsNothing);
      expect(find.byType(RegisterIndividualPage), findsNothing);
      expect(find.text('ANA SAYFA'), findsOneWidget);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      expect(navigator.canPop(), isFalse,
          reason: 'yığında yalnızca oturuma tepki veren kök rota kalmalı');

      // Çıkış / oturum sonu (TOKEN_REVOKED, 403...) giriş ekranına dönebilmeli.
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.text('ANA SAYFA'), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('auth-session#4 / site-manager-admin#7: kullanıcı düzenleme penceresi', () {
    Future<void> openDialog(
      WidgetTester tester,
      Future<void> Function(BuildContext context) onOpen,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => onOpen(context),
                  child: const Text('aç'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
    }

    testWidgets('kendi hesabını düzenlerken parola alanı GİZLİDİR; Profilim notu gösterilir (320 px)',
        (tester) async {
      ManagedUserFormResult? result;
      await openDialog(tester, (context) async {
        result = await ManagedUserDialog.show(
          context,
          role: UserRole.superUser,
          roleTitle: 'Süper Kullanıcı',
          user: _user(emailVerified: false),
          isSelf: true,
        );
      });

      expect(find.widgetWithText(TextFormField, 'Şifre'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Yeni Şifre (opsiyonel)'), findsNothing);
      expect(find.textContaining('Profilim'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Anahtar değiştirilip kaydedilince sonuç doğrulama durumunu taşır; parola boştur.
      await tester.ensureVisible(find.text('E-Posta Doğrulandı'));
      await tester.tap(find.text('E-Posta Doğrulandı'));
      await tester.pump();
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.emailVerified, isTrue);
      expect(result!.password, isEmpty);
    });

    testWidgets('başka kullanıcıyı düzenlerken de parola alanı yok (mevcut güvenlik notu korunur)',
        (tester) async {
      await openDialog(tester, (context) async {
        await ManagedUserDialog.show(
          context,
          role: UserRole.siteManager,
          roleTitle: 'Site Yöneticisi',
          user: _user(role: UserRole.siteManager),
          isSelf: false,
        );
      });

      expect(find.widgetWithText(TextFormField, 'Şifre'), findsNothing);
      expect(
        find.text('Güvenlik gereği kullanıcı şifresini yalnızca kendi hesabından değiştirebilir.'),
        findsOneWidget,
      );
      expect(find.textContaining('Profilim'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('YENİ kullanıcı eklerken parola alanı zorunlu olarak gösterilir', (tester) async {
      ManagedUserFormResult? result;
      await openDialog(tester, (context) async {
        result = await ManagedUserDialog.show(
          context,
          role: UserRole.superUser,
          roleTitle: 'Süper Kullanıcı',
          user: null,
          isSelf: false,
        );
      });

      expect(find.widgetWithText(TextFormField, 'Şifre'), findsOneWidget);

      // Parola kısa/boşken kaydedilemez.
      await tester.tap(find.text('Kaydet'));
      await tester.pump();
      expect(find.text('Şifre en az 6 karakter olmalı.'), findsOneWidget);
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('error-contract#9: /manager/sites yalnızca yönetici rolleri için yüklenir', () {
    Future<_RoleHomeAuth> pumpHome(WidgetTester tester, UserRole role) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final auth = _RoleHomeAuth(role);
      await tester.pumpWidget(MaterialApp(home: HomePage(authService: auth)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return auth;
    }

    Future<void> disposeHome(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    testWidgets('bireysel kullanıcı açılışta listSites (/manager/sites) ÇAĞIRMAZ', (tester) async {
      final auth = await pumpHome(tester, UserRole.individual);
      expect(auth.listSitesPageSizes, isEmpty);
      await disposeHome(tester);
    });

    testWidgets('daire sakini açılışta listSites ÇAĞIRMAZ', (tester) async {
      final auth = await pumpHome(tester, UserRole.apartmentOwner);
      expect(auth.listSitesPageSizes, isEmpty);
      await disposeHome(tester);
    });

    testWidgets('site yöneticisi ve süper kullanıcı için site listesi yine yüklenir', (tester) async {
      final manager = await pumpHome(tester, UserRole.siteManager);
      expect(manager.listSitesPageSizes, contains(10),
          reason: '_loadSites varsayılan sayfa boyutu (10) ile çağrılmalı');
      await disposeHome(tester);

      final superUser = await pumpHome(tester, UserRole.superUser);
      expect(superUser.listSitesPageSizes, contains(10));
      await disposeHome(tester);
    });
  });
}
