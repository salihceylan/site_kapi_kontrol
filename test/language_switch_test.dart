import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/l10n/gen/app_localizations.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/locale_service.dart';
import 'package:site_kapi_kontrol/ui/views/profile_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

void main() {
  group('Language Switch (Dil Seçimi) Testleri', () {
    final session = UserSession(
      id: 1,
      fullName: 'Cenk GÜDE',
      email: 'cenk@example.com',
      loginName: 'cenk.gude',
      role: UserRole.siteManager,
      isActive: true,
      token: 'token123',
    );

    testWidgets('Türkçe ve İngilizce dil değişimi anında arayüze yansır', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final localeService = LocaleService();
      final formKey = GlobalKey<FormState>();
      final nameController = TextEditingController(text: session.fullName);
      final emailController = TextEditingController(text: session.email);
      final phoneController = TextEditingController();
      final passwordController = TextEditingController();
      final currentPasswordController = TextEditingController();

      Widget buildApp() {
        return LocaleScope(
          service: localeService,
          child: AnimatedBuilder(
            animation: localeService,
            builder: (context, _) {
              return MaterialApp(
                locale: localeService.locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        Builder(
                          builder: (ctx) => Text(
                            YanMenu.titleFor(SirketMenuItem.profilim, session.role, ctx),
                            key: const ValueKey('appbar_title'),
                          ),
                        ),
                        ProfileView(
                          session: session,
                          formKey: formKey,
                          fullNameController: nameController,
                          emailController: emailController,
                          phoneController: phoneController,
                          passwordController: passwordController,
                          currentPasswordController: currentPasswordController,
                          isSaving: false,
                          onSave: () {},
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      }

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // 1. Varsayılan olarak Türkçe olmalı
      expect(find.byKey(const ValueKey('appbar_title')), findsOneWidget);
      expect(find.text('Profilim'), findsWidgets);
      expect(find.text('Kendi Bilgilerini Düzenle'), findsOneWidget);
      expect(find.text('Profili Kaydet'), findsOneWidget);
      expect(find.text('Site Yöneticisi'), findsOneWidget);
      expect(find.text('Dil'), findsOneWidget);

      // 2. Dil seçiciden İngilizce'ye geç
      await tester.ensureVisible(find.byKey(const ValueKey<String>('dil_secici')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      // 3. Anında İngilizce olmalı (uygulamayı kapatıp açmadan)
      expect(localeService.locale.languageCode, 'en');
      expect(find.text('My Profile'), findsWidgets);
      expect(find.text('Edit Personal Information'), findsOneWidget);
      expect(find.text('Save Profile'), findsOneWidget);
      expect(find.text('Site Manager'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);

      // 4. Tekrar Türkçe'ye geç
      await tester.tap(find.text('Türkçe'));
      await tester.pumpAndSettle();

      expect(localeService.locale.languageCode, 'tr');
      expect(find.text('Profilim'), findsWidgets);
      expect(find.text('Kendi Bilgilerini Düzenle'), findsOneWidget);
      expect(find.text('Profili Kaydet'), findsOneWidget);
      expect(find.text('Site Yöneticisi'), findsOneWidget);
    });

    testWidgets('ResidentProfileView içinde dil seçici bulunur ve metinler İngilizceye döner', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final localeService = LocaleService();
      final residentSession = UserSession(
        id: 2,
        fullName: 'Ahmet Yılmaz',
        email: 'ahmet@example.com',
        loginName: 'ahmet.yilmaz',
        role: UserRole.apartmentOwner,
        isActive: true,
        token: 'token456',
      );

      Widget buildApp() {
        return LocaleScope(
          service: localeService,
          child: AnimatedBuilder(
            animation: localeService,
            builder: (context, _) {
              return MaterialApp(
                locale: localeService.locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: ResidentProfileView(
                      session: residentSession,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      }

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Türkçe görünüm
      expect(find.text('Hesap Bilgilerim'), findsOneWidget);
      expect(find.text('Daire Sakini'), findsOneWidget);

      // Dil seçici mevcut olmalı
      expect(find.byKey(const ValueKey<String>('dil_secici')), findsOneWidget);

      // English seç
      await tester.ensureVisible(find.byKey(const ValueKey<String>('dil_secici')));
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      // İngilizce görünüm
      expect(find.text('My Account Details'), findsOneWidget);
      expect(find.text('Apartment Resident'), findsOneWidget);
    });

    test('Menü ve Alt Sekmeler İngilizce ve Türkçe olarak doğru döner', () {
      final trL10n = lookupAppLocalizations(const Locale('tr'));
      final enL10n = lookupAppLocalizations(const Locale('en'));

      expect(trL10n.menuDashboard, 'Panel');
      expect(enL10n.menuDashboard, 'Dashboard');

      expect(trL10n.menuDoors, 'Kapılar');
      expect(enL10n.menuDoors, 'Doors');

      expect(trL10n.menuAnnouncements, 'Duyurular');
      expect(enL10n.menuAnnouncements, 'Announcements');

      expect(trL10n.tabSummary, 'Özet');
      expect(enL10n.tabSummary, 'Summary');

      expect(trL10n.tabDoor, 'Kapı');
      expect(enL10n.tabDoor, 'Door');
    });
  });
}
