import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/views/yeni_site_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/panel_site_creation_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

class MockAuthServiceForYeniSite extends AuthService {
  MockAuthServiceForYeniSite() : super(api: AuthApi(baseUrl: 'http://localhost'));
}

void main() {
  final individualSession = UserSession(
    token: 'test_token',
    id: 1,
    fullName: 'Ali Kaya',
    email: 'ali@example.com',
    loginName: 'alikaya',
    role: UserRole.individual,
    isActive: true,
  );

  final managerSession = UserSession(
    token: 'test_token_mgr',
    id: 2,
    fullName: 'Mehmet Yönetici',
    email: 'mehmet@example.com',
    loginName: 'mehmety',
    role: UserRole.siteManager,
    isActive: true,
  );

  group('YeniSiteView & PanelSiteCreationCard Tests', () {
    testWidgets('YeniSiteView renders correctly for individual user (Başvuru kipi)', (tester) async {
      final mockAuth = MockAuthServiceForYeniSite();
      bool setupStarted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: YeniSiteView(
              session: individualSession,
              authService: mockAuth,
              onStartSetup: () => setupStarted = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Yeni Site Oluştur'), findsOneWidget);
      expect(find.text('BAŞVURU'), findsOneWidget);
      expect(find.text('Site Oluşturma Başvurusu Yap'), findsOneWidget);
      expect(find.text('Site Oluşturma Süreci'), findsOneWidget);

      await tester.tap(find.text('Site Oluşturma Başvurusu Yap'));
      await tester.pump();
      expect(setupStarted, isTrue);
    });

    testWidgets('YeniSiteView renders correctly for site manager (Anlık kurulum kipi)', (tester) async {
      final mockAuth = MockAuthServiceForYeniSite();
      bool setupStarted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: YeniSiteView(
              session: managerSession,
              authService: mockAuth,
              onStartSetup: () => setupStarted = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Yeni Site Oluştur'), findsOneWidget);
      expect(find.text('ANLIK KURULUM'), findsOneWidget);
      expect(find.text('Site Kurulum Sihirbazını Başlat'), findsOneWidget);

      await tester.tap(find.text('Site Kurulum Sihirbazını Başlat'));
      await tester.pump();
      expect(setupStarted, isTrue);
    });

    testWidgets('PanelSiteCreationCard renders with zero layout overflow and triggers callback', (tester) async {
      bool setupStarted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: PanelSiteCreationCard(
                  onStartSetup: () => setupStarted = true,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Yeni Site Oluştur'), findsOneWidget);
      expect(find.text('YÖNETİCİ OLUN'), findsOneWidget);
      expect(find.text('Site Kurulumunu Başlat'), findsOneWidget);

      await tester.tap(find.text('Site Kurulumunu Başlat'));
      await tester.pump();
      expect(setupStarted, isTrue);
    });

    test('YanMenu maps yeniSite to siteHizmetleri group across roles', () {
      expect(menuGroupOf(SirketMenuItem.yeniSite), equals(SirketMenuGroup.siteHizmetleri));

      // Tüm rollerde menüde yer almalıdır
      final superItems = YanMenu.visibleItems(role: UserRole.superUser);
      expect(superItems.contains(SirketMenuItem.yeniSite), isTrue);

      final managerItems = YanMenu.visibleItems(role: UserRole.siteManager);
      expect(managerItems.contains(SirketMenuItem.yeniSite), isTrue);

      final residentItems = YanMenu.visibleItems(role: UserRole.apartmentOwner);
      expect(residentItems.contains(SirketMenuItem.yeniSite), isTrue);

      final indivItems = YanMenu.visibleItems(role: UserRole.individual);
      expect(indivItems.contains(SirketMenuItem.yeniSite), isTrue);
    });
  });
}
