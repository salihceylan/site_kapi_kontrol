// Satışa hazırlık (F1): ana kabuk (HomePage) entegrasyonu.
//
// - Çekmece: "Platform Ayarları" ve "İstemci Hataları" YALNIZ süper kullanıcıda; seçilince ilgili ekran açılır,
//   AppBar başlığı değişir; genel yenileme ekranı tazeler.
// - Kaydedilmemiş Platform Ayarları değişikliği varken başka menüye geçmek onay ister (Düzenlemeye Dön = yerinde
//   kal, Değişiklikleri Sil = geç); temizken pencere yoktur.
// - Profil ekranları (bireysel, daire sakini) "Gizlilik ve Veri" bölümünü taşır.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/account_client_error.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/apartment_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/models/site_block_record.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/site_structure_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/account_api.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/audit_log_view.dart';
import 'package:site_kapi_kontrol/ui/views/client_errors_view.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/views/platform_settings_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/account_privacy_section.dart';

import 'account_fixtures.dart';
import 'dialog_layout_harness.dart' show settleFor;
import 'modules_fixtures.dart';
import '../support/menu_nav.dart';

class _HomeAuth extends ModulesFakeAuth {
  _HomeAuth({UserRole role = UserRole.superUser}) : _role = role, super();

  final UserRole _role;

  @override
  UserSession? get session => UserSession(
    id: 1,
    fullName: 'Ayşe Yılmaz',
    email: 'ayse@example.com',
    loginName: null,
    role: _role,
    isActive: true,
    token: 'tok',
  );

  @override
  Future<MyModulesResult> getMyModules() async => const MyModulesResult(scope: 'all');

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  Future<(SiteStructureRecord?, String?)> getSiteStructure({required int siteCode}) async {
    final site = sites.firstWhere((s) => s.id == siteCode, orElse: () => sites.first);
    return (
      SiteStructureRecord(
        site: site,
        blocks: const <SiteBlockRecord>[],
        apartments: const <ApartmentRecord>[],
        doors: const <DoorRecord>[],
      ),
      null,
    );
  }

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[], null);

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async => (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async => <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async => (<MyApartmentRecord>[], null);

  @override
  Future<MySiteApplications> getMySiteApplications() async => const MySiteApplications();

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({required int doorId}) async => (null, null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;

  @override
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {}
}

late FakeAccountApi _api;

Future<void> _pumpHome(
  WidgetTester t,
  _HomeAuth auth, {
  double width = 400,
  double height = 900,
  double scale = 1.0,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: HomePage(authService: auth),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

/// Yoklama zamanlayıcıları kalmasın.
Future<void> _disposeHome(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

Future<void> _openDrawer(WidgetTester t) async {
  t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await t.pump();
  await t.pump(const Duration(milliseconds: 450));
}

Future<void> _tapMenu(WidgetTester t, String label) async {
  // İP-1D: öğe çekmecede yoksa (ayar öğesi) sağ üstteki dişliden açılan Ayarlar panelinde aranır.
  final item = await findMenuEntry(t, label);
  await t.ensureVisible(item.first);
  await t.pump();
  await t.tap(item.first);
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Finder _inAppBar(Finder f) => find.descendant(of: find.byType(AppBar), matching: f);

/// Üst çubuktaki mod hapı (dokunulacak InkWell; [label] "Sakin Modu" ya da "Yönetici Paneli"). P1-13: iç ekranda "Ana
/// sayfa" düğmesi varken 480 dp altında yalnız ikondur (etiket yok, ipucu [label]); Panel'de ve geniş ekranda etiketlidir.
Finder _modePill([String label = 'Sakin Modu']) {
  final labeled = _inAppBar(find.text(label));
  if (labeled.evaluate().isNotEmpty) return find.ancestor(of: labeled, matching: find.byType(InkWell)).first;
  return find.descendant(of: _inAppBar(find.byTooltip(label)), matching: find.byType(InkWell));
}

Finder _tile(String title) => find.descendant(of: find.byType(Drawer), matching: find.text(title));

/// İP-1D: ayar öğeleri (Site Başvuruları, Modül Talepleri, Platform Ayarları, İstemci Hataları, Denetim Kaydı ...) sağ
/// üstteki dişliden açılan Ayarlar panelindedir; panel de bir `Drawer` olduğundan çekmece bulucuları orada da çalışır.
Future<void> _openSettings(WidgetTester t) => openSettingsPanel(t);

void main() {
  setUp(() {
    _api = FakeAccountApi()
      ..config = acConfig()
      ..pages = <ClientErrorPage>[
        ClientErrorPage(items: <ClientErrorItem>[acError(1), acError(2, fatal: true)]),
      ];
    AccountService.debugApiFactory = (_) => _api;
  });

  tearDown(() {
    AccountService.debugApiFactory = null;
  });

  group('Menü', () {
    testWidgets('süper kullanıcı: iki yeni öğe çekmecede; sırayla açılır, başlık değişir', (t) async {
      final auth = _HomeAuth();
      await _pumpHome(t, auth);

      await _openSettings(t);
      expect(_tile('Platform Ayarları'), findsOneWidget);
      expect(_tile('İstemci Hataları'), findsOneWidget);
      await t.ensureVisible(_tile('Platform Ayarları'));
      await t.pump();
      await t.tap(_tile('Platform Ayarları'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(find.byType(PlatformSettingsView), findsOneWidget);
      expect(_inAppBar(find.text('Platform Ayarları')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('platform_latest_version')), findsOneWidget);
      expect(_api.configCalls, 1);

      await _tapMenu(t, 'İstemci Hataları');
      expect(find.byType(ClientErrorsView), findsOneWidget);
      expect(find.byType(PlatformSettingsView), findsNothing);
      expect(_inAppBar(find.text('İstemci Hataları')), findsOneWidget);
      expect(_api.errorCalls, isNotEmpty);
      await _disposeHome(t);
    });

    testWidgets('site yöneticisi: iki öğe de YOK', (t) async {
      final auth = _HomeAuth(role: UserRole.siteManager);
      await _pumpHome(t, auth);
      await _openSettings(t);
      expect(_tile('Platform Ayarları'), findsNothing);
      expect(_tile('İstemci Hataları'), findsNothing);
      expect(_tile('Denetim Kaydı'), findsNothing);
      await _disposeHome(t);
    });

    testWidgets('genel yenileme (Yenile) açık ekranı tazeler', (t) async {
      final auth = _HomeAuth();
      await _pumpHome(t, auth);
      await _tapMenu(t, 'Platform Ayarları');
      expect(_api.configCalls, 1);
      await t.tap(find.byTooltip('Yenile').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(_api.configCalls, 2);

      await _tapMenu(t, 'İstemci Hataları');
      final before = _api.errorCalls.length;
      await t.tap(find.byTooltip('Yenile').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      expect(_api.errorCalls.length, greaterThan(before));
      await _disposeHome(t);
    });
  });

  group('kaydedilmemiş değişiklik uyarısı (menü geçişi)', () {
    Future<void> openSettingsAndEdit(WidgetTester t, _HomeAuth auth) async {
      await _pumpHome(t, auth);
      await _tapMenu(t, 'Platform Ayarları');
      final field = find.byKey(const ValueKey<String>('platform_latest_version'));
      await t.ensureVisible(field);
      await t.pump();
      await t.enterText(field, '1.9.0');
      await t.pump();
      expect(find.byKey(const ValueKey<String>('platform_dirty_notice')), findsOneWidget);
    }

    testWidgets('temizken başka menüye geçmek pencere açmaz', (t) async {
      final auth = _HomeAuth();
      await _pumpHome(t, auth);
      await _tapMenu(t, 'Platform Ayarları');
      await _tapMenu(t, 'Denetim Kaydı');
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(AuditLogView), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('kirliyken: Düzenlemeye Dön -> ekranda kalır, değişiklik korunur; Değişiklikleri Sil -> geçilir', (t) async {
      final auth = _HomeAuth();
      await openSettingsAndEdit(t, auth);

      await _tapMenu(t, 'Denetim Kaydı');
      expect(find.text('Kaydedilmemiş değişiklikler'), findsOneWidget);
      expect(find.byType(AuditLogView), findsNothing, reason: 'onay gelene dek geçilmez');
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Düzenlemeye Dön')));
      await settleFor(t);
      expect(find.byType(PlatformSettingsView), findsOneWidget);
      expect(find.byType(AuditLogView), findsNothing);
      expect(
        t.widget<TextField>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('platform_latest_version')),
            matching: find.byType(TextField),
          ),
        ).controller!.text,
        '1.9.0',
      );
      expect(_inAppBar(find.text('Platform Ayarları')), findsOneWidget);

      await _tapMenu(t, 'Denetim Kaydı');
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Değişiklikleri Sil')));
      await settleFor(t);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(AuditLogView), findsOneWidget);
      expect(find.byType(PlatformSettingsView), findsNothing);
      expect(_api.putPatches, isEmpty, reason: 'hiçbir şey sunucuya gitmedi');
      await _disposeHome(t);
    });

    testWidgets('aynı menüyü yeniden seçmek (Platform Ayarları) uyarı açmaz', (t) async {
      final auth = _HomeAuth();
      await openSettingsAndEdit(t, auth);
      await _tapMenu(t, 'Platform Ayarları');
      expect(find.byType(AlertDialog), findsNothing);
      await _disposeHome(t);
    });

    // P1-13: üst çubuktaki "Ana sayfa" düğmesi de menü kapısından geçer (kaydedilmemiş değişiklik sessizce atılmaz).
    testWidgets('üst çubuktaki "Ana sayfa" düğmesi de korumadan geçer: Düzenlemeye Dön ekranda bırakır, Değişiklikleri Sil Panel\'e döndürür',
        (t) async {
      final auth = _HomeAuth();
      await openSettingsAndEdit(t, auth);
      final home = _inAppBar(find.byTooltip('Ana sayfa'));
      expect(home, findsOneWidget, reason: 'iç ekranda (Platform Ayarları) düğme var');

      await t.tap(home);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Kaydedilmemiş değişiklikler'), findsOneWidget);
      expect(find.byType(ModuleShowcaseView), findsNothing, reason: 'onay gelene dek Panel açılmaz');
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Düzenlemeye Dön')));
      await settleFor(t);
      expect(find.byType(PlatformSettingsView), findsOneWidget, reason: 'Düzenlemeye Dön yerinde bırakır');
      expect(home, findsOneWidget);

      await t.tap(home);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Değişiklikleri Sil')));
      await settleFor(t);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(ModuleShowcaseView), findsOneWidget, reason: 'Panel (ana sayfa)');
      expect(find.byType(PlatformSettingsView), findsNothing);
      expect(home, findsNothing, reason: 'Panel\'de düğme yok');
      expect(_api.putPatches, isEmpty, reason: 'hiçbir şey sunucuya gitmedi');
      await _disposeHome(t);
    });

    /// Çekmeceden Yardım ve Destek'i açar, "Profilim ekranına git" düğmesine basar (menüyü programatik değiştirir).
    Future<void> helpToProfile(WidgetTester t) async {
      await _openDrawer(t);
      final help = find.descendant(of: find.byType(Drawer), matching: find.text('Yardım ve Destek'));
      await t.ensureVisible(help);
      await t.pump();
      await t.tap(help);
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
      final go = find.text('Profilim ekranına git');
      await t.scrollUntilVisible(go, 300, scrollable: find.byType(Scrollable).first);
      await t.pump();
      await t.tap(go);
      await t.pump();
      await t.pump(const Duration(milliseconds: 700));
    }

    testWidgets('Yardım -> "Profilim ekranına git" de korumadan geçer: kirliyken onay sorulur; Düzenlemeye Dön ekranda bırakır, Değişiklikleri Sil geçirir', (t) async {
      final auth = _HomeAuth();
      await openSettingsAndEdit(t, auth);

      await helpToProfile(t);
      expect(find.text('Kaydedilmemiş değişiklikler'), findsOneWidget, reason: 'menü _selectMenu dışından değişse de sorulur');
      expect(find.byType(AccountPrivacySection), findsNothing, reason: 'onay gelene dek Profilim açılmaz');
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Düzenlemeye Dön')));
      await settleFor(t);
      expect(find.byType(PlatformSettingsView), findsOneWidget);
      expect(
        t.widget<TextField>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('platform_latest_version')),
            matching: find.byType(TextField),
          ),
        ).controller!.text,
        '1.9.0',
        reason: 'yazılanlar korunur',
      );

      await helpToProfile(t);
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Değişiklikleri Sil')));
      await settleFor(t);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(PlatformSettingsView), findsNothing);
      expect(find.byType(AccountPrivacySection), findsOneWidget, reason: 'Profilim açıldı');
      expect(_api.putPatches, isEmpty);
      await _disposeHome(t);
    });

    testWidgets('Sakin Modu / Yönetici Paneli geçişi (AppBar hapı) de korumadan geçer: kirliyken sorar; içerik yeniden kurulup yazılanı sessizce SİLMEZ', (t) async {
      final auth = _HomeAuth();
      await openSettingsAndEdit(t, auth);

      final pill = _modePill();
      expect(pill, findsOneWidget);
      await t.tap(pill);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Kaydedilmemiş değişiklikler'), findsOneWidget);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Yönetici Paneli')), findsNothing, reason: 'mod henüz değişmedi');

      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Düzenlemeye Dön')));
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('platform_dirty_notice')), findsOneWidget, reason: 'yazılanlar korunur');

      await t.tap(pill);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Değişiklikleri Sil')));
      await settleFor(t);
      await t.pump(const Duration(milliseconds: 600));
      expect(_modePill('Yönetici Paneli'), findsOneWidget, reason: 'mod değişti');
      await _disposeHome(t);
    });

    testWidgets('yeniden-giriş: aynı karede iki istek TEK pencere açar; onayda mod YALNIZ BİR KEZ çevrilir (toggle iki kez çalışmaz)', (t) async {
      // Not: Navigator, push edilen bir yoldan sonra aynı karedeki ikinci İŞARETÇİYİ zaten soğurur; bu yüzden
      // ikinci istek anlamsal eylemle (erişilebilirlik "dokun") gönderilir — işaretçi değil.
      final handle = t.ensureSemantics();
      final auth = _HomeAuth();
      await openSettingsAndEdit(t, auth);

      final pill = _modePill();
      final node = t.getSemantics(pill);
      final owner = node.owner!; // düğümü yöneten anlamsal sahip (çoklu görünümde de doğru)
      owner.performAction(node.id, SemanticsAction.tap);
      owner.performAction(node.id, SemanticsAction.tap);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget, reason: 'ikinci pencere açılmaz');

      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Değişiklikleri Sil')));
      await settleFor(t);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(AlertDialog), findsNothing);
      expect(_modePill('Yönetici Paneli'), findsOneWidget,
          reason: 'bir kez çevrildi (iki kez çevrilseydi "Sakin Modu" kalırdı)');
      handle.dispose();
      await _disposeHome(t);
    });

    testWidgets('yeniden-giriş sıfırlanır: Düzenlemeye Dön sonrası kapı yeniden açılır', (t) async {
      final auth = _HomeAuth();
      await openSettingsAndEdit(t, auth);
      final pill = _modePill();
      for (var i = 0; i < 2; i++) {
        await t.tap(pill);
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Kaydedilmemiş değişiklikler'), findsOneWidget, reason: '$i. deneme: kapı açık kalmadı');
        await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Düzenlemeye Dön')));
        await settleFor(t);
      }
      expect(_modePill(), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('çekmecedeki mod geçişi ("Sakin Moduna Geç") de korumalı', (t) async {
      final auth = _HomeAuth();
      await openSettingsAndEdit(t, auth);
      await _openDrawer(t);
      final toggle = find.descendant(of: find.byType(Drawer), matching: find.text('Sakin Moduna Geç'));
      await t.tap(toggle);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Kaydedilmemiş değişiklikler'), findsOneWidget);
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Düzenlemeye Dön')));
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('platform_dirty_notice')), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('mod geçişi: değişiklik yokken pencere yok', (t) async {
      final auth = _HomeAuth();
      await _pumpHome(t, auth);
      await _tapMenu(t, 'Platform Ayarları');
      await t.tap(_modePill());
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byType(AlertDialog), findsNothing);
      expect(_modePill('Yönetici Paneli'), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('Yardım -> Profilim: değişiklik yokken pencere AÇILMAZ', (t) async {
      final auth = _HomeAuth();
      await _pumpHome(t, auth, height: 1400);
      await _tapMenu(t, 'Platform Ayarları');
      await helpToProfile(t);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(AccountPrivacySection), findsOneWidget);
      await _disposeHome(t);
    });

    testWidgets('kirliyken genel yenileme de onay ister; Düzenlemeye Dön GET yapmaz', (t) async {
      final auth = _HomeAuth();
      await openSettingsAndEdit(t, auth);
      await t.tap(find.byTooltip('Yenile').first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Kaydedilmemiş değişiklikler'), findsOneWidget);
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Düzenlemeye Dön')));
      await settleFor(t);
      expect(_api.configCalls, 1);
      await _disposeHome(t);
    });
  });

  group('Profil: Gizlilik ve Veri', () {
    for (final (role, label) in <(UserRole, String)>[
      (UserRole.individual, 'bireysel'),
      (UserRole.apartmentOwner, 'daire sakini'),
      (UserRole.siteManager, 'site yöneticisi'),
    ]) {
      testWidgets('$label: Profilim ekranında bölüm ve iki eylem görünür', (t) async {
        final auth = _HomeAuth(role: role);
        await _pumpHome(t, auth, height: 1400);
        await _tapMenu(t, 'Profilim');
        expect(find.byType(AccountPrivacySection), findsOneWidget);
        await t.ensureVisible(find.text('Gizlilik ve Veri'));
        await t.pump();
        expect(find.text('Gizlilik ve Veri'), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('account_export_button')), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('account_delete_button')), findsOneWidget);
        await _disposeHome(t);
      });
    }
  });
}
