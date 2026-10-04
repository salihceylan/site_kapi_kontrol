// "Cilalı Safir": site yöneticisi seçici (SiteManagerPickerPage) taşma + davranış + tasarım bağları.
// Davranış (arama gecikmesi, sayfalama çağrısı, seçimle dönüş, hata -> yeniden dene) ve metinler
// değişmez; yalnız görünüm: AppCard satırları + IconOrb, iskelet, EmptyState, InlineNotice, tek zemin.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/empty_state.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/pages/site_manager_picker_page.dart';

import '../design/harness.dart';

ManagedUserAccount _m(int id, String name, String email, {String? phone}) =>
    ManagedUserAccount(
      id: id,
      fullName: name,
      email: email,
      loginName: null,
      role: UserRole.siteManager,
      isActive: true,
      phoneNumber: phone,
      createdAt: null,
    );

final List<ManagedUserAccount> _managers = <ManagedUserAccount>[
  _m(5, 'Ayşe Yılmaz', 'ayse@example.com', phone: '0532 111 22 33'),
  _m(
    6,
    'Mehmet Kaan Demirtaş Uzun Soyadlı Site Yöneticisi',
    'mehmet.kaan.demirtas.cok.uzun.bir.adres@ornek-alan-adi.com.tr',
  ),
  _m(7, 'Zeynep Kaya', 'zeynep@example.com', phone: '0555 444 33 22'),
];

class _FakeAuth extends AuthService {
  _FakeAuth({
    this.managers = const <ManagedUserAccount>[],
    this.gate,
    this.failFirst = false,
  }) : super(api: AuthApi(baseUrl: 'http://localhost'));

  final List<ManagedUserAccount> managers;
  final Completer<void>? gate;
  bool failFirst;
  final List<(int, String?)> calls = <(int, String?)>[];

  @override
  Future<ManagedUserPage> listManagedUsers({
    UserRole? role,
    UserRole? excludeRole,
    required int page,
    int pageSize = 10,
    String? search,
  }) async {
    calls.add((page, search));
    await gate?.future;
    if (failFirst) {
      failFirst = false;
      throw Exception('Sunucuya ulaşılamadı');
    }
    return ManagedUserPage(
      users: managers,
      total: managers.length,
      page: page,
      pageSize: pageSize,
    );
  }
}

Future<void> _pump(
  WidgetTester t,
  Widget page, {
  double width = 360,
  double height = 640,
  double scale = 1.0,
  bool dark = false,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(harnessApp(page, dark: dark, scale: scale));
  await t.pump(const Duration(milliseconds: 450));
  expect(t.takeException(), isNull);
}

Widget _page(_FakeAuth auth, {int? selected = 5}) =>
    SiteManagerPickerPage(authService: auth, selectedUserCode: selected);

void main() {
  for (final (w, h, s) in const <(double, double, double)>[
    (320, 640, 2.0),
    (360, 640, 1.5),
  ]) {
    for (final dark in const <bool>[false, true]) {
      final cell = '${w.toInt()}x${h.toInt()} x$s ${dark ? 'koyu' : 'açık'}';
      group('taşma matrisi ($cell)', () {
        testWidgets('liste: uzun ad/e-posta satırları taşmaz', (t) async {
          await _pump(
            t,
            _page(_FakeAuth(managers: _managers)),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          expect(find.text('Ayşe Yılmaz'), findsOneWidget);
          expect(find.byType(IconOrb), findsNWidgets(3));
        });
        testWidgets('yükleniyor (iskelet)', (t) async {
          await _pump(
            t,
            _page(_FakeAuth(gate: Completer<void>())),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          expect(find.byType(ShimmerScope), findsOneWidget);
        });
        testWidgets('boş', (t) async {
          await _pump(
            t,
            _page(_FakeAuth()),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          expect(
            find.text('Kayıtlı site yöneticisi bulunamadı.'),
            findsOneWidget,
          );
        });
        testWidgets('hata', (t) async {
          await _pump(
            t,
            _page(_FakeAuth(failFirst: true)),
            width: w,
            height: h,
            scale: s,
            dark: dark,
          );
          expect(find.byType(InlineNotice), findsOneWidget);
          expect(find.text('Tekrar Dene'), findsOneWidget);
        });
      });
    }
  }

  testWidgets(
    'tasarım bağları: AppCard satırı, tek zemin (Scaffold şeffaf), eski Card yok',
    (t) async {
      await _pump(t, _page(_FakeAuth(managers: _managers)));
      expect(find.byType(AppCard), findsNWidgets(3));
      expect(find.byType(Card), findsNothing);
      final scaffold = t.widget<Scaffold>(find.byType(Scaffold).last);
      expect(scaffold.backgroundColor, isNull);
      expect(find.text('Site Yöneticisi Seç'), findsOneWidget);
      // Seçili satır (5): AppCard seçili + onay işareti; diğerlerinde yok.
      final cards = t.widgetList<AppCard>(find.byType(AppCard)).toList();
      expect(cards.map((c) => c.selected), <bool>[true, false, false]);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      // Rozetler rol tonlu, parlak "hero" değil (ışımasız).
      for (final orb in t.widgetList<IconOrb>(find.byType(IconOrb))) {
        expect(orb.tone, UserRole.siteManager.tone);
        expect(orb.glow, isFalse);
        expect(orb.size, 40);
      }
      expect(find.byType(BackdropFilter), findsNothing);
    },
  );

  testWidgets('dokunmak seçimi sonuçla döndürür', (t) async {
    SiteManagerPickerResult? result;
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final auth = _FakeAuth(managers: _managers);
    await t.pumpWidget(
      harnessApp(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context)
                    .push<SiteManagerPickerResult>(
                      MaterialPageRoute(
                        builder: (_) => _page(auth, selected: null),
                      ),
                    );
              },
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Aç'));
    await t.pumpAndSettle();
    await t.tap(find.text('Zeynep Kaya'));
    await t.pumpAndSettle();
    expect(result?.manager?.id, 7);
  });

  testWidgets(
    'arama 300 ms gecikmeyle yeniden yükler; hata -> "Tekrar Dene" yeniden yükler',
    (t) async {
      final auth = _FakeAuth(managers: _managers, failFirst: true);
      await _pump(t, _page(auth));
      expect(auth.calls, <(int, String?)>[(1, null)]);
      expect(find.byType(InlineNotice), findsOneWidget);

      await t.tap(find.text('Tekrar Dene'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(auth.calls.length, 2);
      expect(find.byType(InlineNotice), findsNothing);
      expect(find.byType(AppCard), findsNWidgets(3));

      await t.enterText(find.byType(TextField), 'zey');
      await t.pump(const Duration(milliseconds: 100));
      expect(auth.calls.length, 2, reason: 'gecikme dolmadan istek yok');
      await t.pump(const Duration(milliseconds: 250));
      expect(auth.calls.last, (1, 'zey'));
    },
  );

  testWidgets('yükleme bitince ticker kalmaz (iskelet ağaçtan kalkar)', (
    t,
  ) async {
    await _pump(t, _page(_FakeAuth(managers: _managers)));
    expect(find.byType(ShimmerScope), findsNothing);
    await t.pumpAndSettle();
    expect(t.binding.transientCallbackCount, 0);
  });

  testWidgets('boş durum EmptyState', (t) async {
    await _pump(t, _page(_FakeAuth()));
    expect(find.byType(EmptyState), findsOneWidget);
  });
}
