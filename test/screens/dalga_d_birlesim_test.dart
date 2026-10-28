// Dalga D birleşimi: kompakt menü ("Tüm işlemler", K8) ile Panel görünüm kipleri (kutucuk / liste / Kolay görünüm, P2-22 ve
// P2-25) ve "Yöneticiyi ara" (P2-23) ile Kolay görünüm BİRLİKTE çalışır. Her özellik kendi dalında ayrı sınandı; bu dosya
// birleşimin kesişim noktalarını sabitler:
//  - "Tüm işlemler" gizlenen iş varken üç Panel kipinde de erişilebilir (kart / satır / büyük düğme) ve aynı geri çağrıyı çağırır.
//  - Gizlenen iş yokken (kompakt menü yok) hiçbir kipte "Tüm işlemler" çizilmez.
//  - Kolay görünümde hızlı işlemler yoktur ama sakin için "Yöneticiyi ara" büyük düğme olarak vardır: telefon uygulamasını açar,
//    telefon yoksa nedenini söyler, kendi sitesinin yöneticisi olana çizilmez.
//  - 320 dp x 2,0 yazıda üç kipte taşma yok.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/manager_contact.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/easy_view_service.dart';
import 'package:site_kapi_kontrol/services/view_mode_service.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/styles/easy_view_theme.dart';
import 'package:site_kapi_kontrol/ui/design/easy_view_switch.dart';
import 'package:site_kapi_kontrol/ui/design/view_mode_toggle.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/manager_call_tile.dart';
import 'package:site_kapi_kontrol/ui/widgets/showcase_layouts.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

UserSession _session(UserRole role) => UserSession(
  id: 7,
  fullName: 'Ayşe Yılmaz',
  email: 'a@example.com',
  loginName: null,
  role: role,
  isActive: true,
  token: 't',
);

final Set<SirketMenuItem> _extras = <SirketMenuItem>{
  SirketMenuItem.kapilar,
  SirketMenuItem.duyurular,
  SirketMenuItem.finans,
  SirketMenuItem.belgeler,
  SirketMenuItem.talepler,
};

List<SirketMenuItem> _items(UserRole role, {required bool resident}) => YanMenu.visibleItems(
  role: role,
  isResidentMode: resident,
  canToggleMode: false,
  additionalItems: _extras,
  hiddenItems: const <SirketMenuItem>{},
);

/// Sahte telefon uygulaması açıcısı.
class _Phone {
  final List<Uri> calls = <Uri>[];

  Future<bool> launch(Uri uri) async {
    calls.add(uri);
    return true;
  }
}

const _contact = ManagerContact(
  siteCode: 1,
  siteName: 'Gül Sitesi',
  managerName: 'Ali Yönetici',
  phone: '0532 123 45 67',
);
const _noPhone = ManagerContact(siteCode: 1, siteName: 'Gül Sitesi', managerName: 'Ali Yönetici');
const _self = ManagerContact(
  siteCode: 1,
  siteName: 'Gül Sitesi',
  managerName: 'Ayşe Yılmaz',
  phone: '0532 123 45 67',
  isSelf: true,
);

Widget _showcase({
  required UserRole role,
  required ShowcaseAudience audience,
  Set<SirketMenuItem>? featured,
  VoidCallback? onAllActions,
  Future<List<ManagerContact>> Function()? fetch,
  Future<bool> Function(Uri uri)? launcher,
}) => ModuleShowcaseView(
  key: const ValueKey<String>('vitrin'),
  session: _session(role),
  audience: audience,
  menuItems: _items(role, resident: audience == ShowcaseAudience.resident),
  onOpen: (_) {},
  featuredItems: featured,
  onOpenAllActions: onAllActions,
  fetchManagerContacts: fetch,
  dialLauncher: launcher,
);

Future<void> _pump(
  WidgetTester t,
  Widget showcase, {
  required EasyViewService easy,
  required ViewModeService modes,
  double width = 400,
  double height = 2400,
  double scale = 1.0,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    EasyViewScope(
      service: easy,
      child: ViewModeScope(
        service: modes,
        child: AnimatedBuilder(
          animation: easy,
          builder: (context, _) => MaterialApp(
            theme: easy.enabled ? easyViewLightTheme : AppTheme.light(),
            darkTheme: easy.enabled ? easyViewDarkTheme : AppTheme.dark(),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
              child: MediaQuery.withClampedTextScaling(
                minScaleFactor: easy.enabled ? EasyViewService.minTextScale : 0.0,
                maxScaleFactor: 2.0,
                child: child!,
              ),
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: showcase),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 600));
  await t.pump(const Duration(milliseconds: 600));
  expect(t.takeException(), isNull); // RenderFlex overflow dahil
}

Future<EasyViewService> _easy(bool enabled) async {
  final easy = EasyViewService();
  if (enabled) await easy.setEnabled(true);
  return easy;
}

Future<ViewModeService> _modes({required bool list}) async {
  final modes = ViewModeService();
  if (list) await modes.setMode(ViewScreen.modules, ListViewMode.list);
  return modes;
}

const _allActionsTile = ValueKey<String>('panel_kart_tumIslemler'); // kutucuk kartı ve liste satırı
const _allActionsEasy = ValueKey<String>('panel_kolay_tumIslemler');
const _managerEasy = ValueKey<String>('panel_kolay_yoneticiyiAra');
const _managerTile = ValueKey<String>('panel_hizli_yoneticiyiAra');

/// Kompakt küme: yalnız Kapılar ve Duyurular öne çıkar; Talepler, Dosya Deposu, Finans ... "Tüm işlemler"e iner.
final Set<SirketMenuItem> _compact = <SirketMenuItem>{SirketMenuItem.kapilar, SirketMenuItem.duyurular};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('"Tüm işlemler" üç Panel kipinde de erişilebilir', () {
    for (final mode in <(String, bool, bool, ValueKey<String>)>[
      ('kutucuk', false, false, _allActionsTile),
      ('liste', false, true, _allActionsTile),
      ('Kolay görünüm', true, false, _allActionsEasy),
    ]) {
      final (label, easyOn, listMode, key) = mode;

      testWidgets('$label: kompakt menü bir şeyi gizliyorsa kart / satır / düğme var ve geri çağrıyı çağırır', (t) async {
        var opened = 0;
        await _pump(
          t,
          _showcase(
            role: UserRole.siteManager,
            audience: ShowcaseAudience.admin,
            featured: _compact,
            onAllActions: () => opened++,
          ),
          easy: await _easy(easyOn),
          modes: await _modes(list: listMode),
        );
        expect(find.byKey(key), findsOneWidget);
        // Gizlenen işin kartı Panel'de yoktur (kompakt menü), "Tüm işlemler"de durur; öne çıkan iş yerindedir.
        expect(find.byKey(const ValueKey<String>('panel_kart_talepler')), findsNothing);
        expect(find.byKey(const ValueKey<String>('panel_kolay_talepler')), findsNothing);
        expect(find.byKey(ValueKey<String>(easyOn ? 'panel_kolay_duyurular' : 'panel_kart_duyurular')), findsOneWidget);
        await t.ensureVisible(find.byKey(key));
        await t.tap(find.byKey(key));
        await t.pump();
        expect(opened, 1);
      });

      testWidgets('$label: kompakt menü yoksa "Tüm işlemler" kartı çizilmez', (t) async {
        await _pump(
          t,
          _showcase(role: UserRole.siteManager, audience: ShowcaseAudience.admin, onAllActions: () {}),
          easy: await _easy(easyOn),
          modes: await _modes(list: listMode),
        );
        expect(find.byKey(key), findsNothing);
        // Önkoşul: kompakt menü yokken gizlenen iş de Panel'dedir (kart yok değil, kümeden gelen gizleme yok).
        expect(find.byKey(ValueKey<String>(easyOn ? 'panel_kolay_talepler' : 'panel_kart_talepler')), findsOneWidget);
      });
    }

    testWidgets('liste kipinde "Tüm işlemler" satırı listenin SONUNDA ve etiketi okunur', (t) async {
      await _pump(
        t,
        _showcase(
          role: UserRole.siteManager,
          audience: ShowcaseAudience.admin,
          featured: _compact,
          onAllActions: () {},
        ),
        easy: await _easy(false),
        modes: await _modes(list: true),
        height: 3000,
      );
      final rows = t.widgetList<ShowcaseModuleRow>(find.byType(ShowcaseModuleRow)).toList();
      expect(rows.length, greaterThanOrEqualTo(3)); // Kapılar, Duyurular ... + Tüm işlemler
      expect(rows.last.key, _allActionsTile);
      expect(rows.last.semanticLabel, contains('Tüm işlemler'));
      // Satır, öteki satırların altındadır (yerleşim sırası = ağaç sırası).
      final lastTop = t.getRect(find.byKey(_allActionsTile)).top;
      for (final row in rows.take(rows.length - 1)) {
        expect(t.getRect(find.byWidget(row)).bottom, lessThanOrEqualTo(lastTop + 0.01));
      }
    });
  });

  group('Kolay görünümde "Yöneticiyi ara"', () {
    testWidgets('sakin: veri gelince büyük düğme çıkar, "Tüm işlemler"den ÖNCE durur ve telefon uygulamasını açar', (t) async {
      final phone = _Phone();
      await _pump(
        t,
        _showcase(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          featured: _compact,
          onAllActions: () {},
          fetch: () async => const [_contact],
          launcher: phone.launch,
        ),
        easy: await _easy(true),
        modes: await _modes(list: false),
      );
      expect(find.byKey(_managerEasy), findsOneWidget);
      // Hızlı işlemler kutusu Kolay görünümde yoktur (aynı iş büyük düğmedir).
      expect(find.byKey(_managerTile), findsNothing);
      expect(t.getRect(find.byKey(_managerEasy)).height, greaterThanOrEqualTo(72));
      expect(t.getRect(find.byKey(_managerEasy)).top, lessThan(t.getRect(find.byKey(_allActionsEasy)).top));
      await t.ensureVisible(find.byKey(_managerEasy));
      await t.tap(find.byKey(_managerEasy));
      await t.pump();
      expect(phone.calls.map((u) => u.toString()), <String>['tel:05321234567']);
    });

    testWidgets('telefon kayıtlı değilse düğme görünür kalır, dokununca nedenini söyler ve hiçbir şey aranmaz', (t) async {
      final phone = _Phone();
      await _pump(
        t,
        _showcase(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          fetch: () async => const [_noPhone],
          launcher: phone.launch,
        ),
        easy: await _easy(true),
        modes: await _modes(list: false),
      );
      expect(find.byKey(_managerEasy), findsOneWidget);
      await t.ensureVisible(find.byKey(_managerEasy));
      await t.tap(find.byKey(_managerEasy));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text(ManagerCallTexts.noPhoneMessage), findsOneWidget);
      expect(phone.calls, isEmpty);
    });

    testWidgets('kendi sitesinin yöneticisi olana, veri yokken ve yönetici kitlesinde düğme çizilmez', (t) async {
      for (final (audience, role, fetch) in <(ShowcaseAudience, UserRole, Future<List<ManagerContact>> Function()?)>[
        (ShowcaseAudience.resident, UserRole.siteManager, () async => const [_self]),
        (ShowcaseAudience.resident, UserRole.apartmentOwner, () => Future<List<ManagerContact>>.error(StateError('ağ'))),
        (ShowcaseAudience.resident, UserRole.apartmentOwner, null),
        (ShowcaseAudience.admin, UserRole.siteManager, () async => const [_contact]),
      ]) {
        await _pump(
          t,
          _showcase(role: role, audience: audience, fetch: fetch),
          easy: await _easy(true),
          modes: await _modes(list: false),
        );
        expect(find.byKey(_managerEasy), findsNothing, reason: '$audience $role');
      }
    });

    testWidgets('Kolay görünüm KAPALIyken "Yöneticiyi ara" hızlı işlemler kutusudur (büyük düğme yok)', (t) async {
      await _pump(
        t,
        _showcase(
          role: UserRole.apartmentOwner,
          audience: ShowcaseAudience.resident,
          fetch: () async => const [_contact],
          launcher: _Phone().launch,
        ),
        easy: await _easy(false),
        modes: await _modes(list: false),
      );
      expect(find.byKey(_managerTile), findsOneWidget);
      expect(find.byKey(_managerEasy), findsNothing);
    });
  });

  group('Taşma: 320 dp x 2,0 yazı', () {
    for (final mode in <(String, bool, bool)>[
      ('kutucuk', false, false),
      ('liste', false, true),
      ('Kolay görünüm', true, false),
    ]) {
      final (label, easyOn, listMode) = mode;
      testWidgets('$label: sakin Paneli "Tüm işlemler" + "Yöneticiyi ara" ile taşmaz', (t) async {
        await _pump(
          t,
          _showcase(
            role: UserRole.apartmentOwner,
            audience: ShowcaseAudience.resident,
            featured: _compact,
            onAllActions: () {},
            fetch: () async => const [_contact],
            launcher: _Phone().launch,
          ),
          easy: await _easy(easyOn),
          modes: await _modes(list: listMode),
          width: 320,
          height: 4000,
          scale: 2.0,
        );
        expect(find.text('Tüm işlemler'), findsWidgets);
      });
    }
  });
}
