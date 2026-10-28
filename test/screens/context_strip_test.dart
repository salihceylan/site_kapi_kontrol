// P2-21: bağlam şeridi ("Ay Sitesi · A Blok / 5 · Sakin").
//
// - composeContextStrip (saf mantık): ne zaman çıkar, hangi metinler, dokununca ne olur.
// - ContextStrip: çizim, ekran okuyucu, 44 dp dokunma hedefi, taşma matrisi.
// - ContextStripHost: daireleri yükler, genel yenilemede tazeler, kullanıcı değişince eskisini bırakır, site seçici açar.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart' show ShowcaseAudience;
import 'package:site_kapi_kontrol/ui/helpers/refresh_status.dart';
import 'package:site_kapi_kontrol/ui/widgets/context_strip.dart';

import '../design/harness.dart';

const ContextSite _gunes = ContextSite(code: 1, name: 'Güneş Sitesi', role: 'manager');
const ContextSite _ay = ContextSite(code: 2, name: 'Ay Sitesi', role: 'manager');
const ContextApartment _a5 = ContextApartment(siteCode: 1, label: 'A Blok / 5');
const ContextApartment _b2 = ContextApartment(siteCode: 2, label: 'B Blok / 2');
const ContextApartment _a6 = ContextApartment(siteCode: 1, label: 'A Blok / 6');

final Finder _strip = find.byKey(const ValueKey<String>('baglam_seridi'));

void main() {
  group('composeContextStrip: ne zaman çıkar', () {
    test('tek site + tek daire (ya da dairesiz): şerit YOK (ekran eskisi gibi)', () {
      for (final audience in ShowcaseAudience.values) {
        expect(composeContextStrip(audience: audience, sites: const <ContextSite>[_gunes]), isNull, reason: audience.name);
        expect(
          composeContextStrip(audience: audience, sites: const <ContextSite>[_gunes], apartments: const <ContextApartment>[_a5]),
          isNull,
          reason: '${audience.name} tek daire',
        );
      }
    });

    test('site verisi yoksa (yüklenmedi / bağı yok) şerit yok', () {
      expect(
        composeContextStrip(
          audience: ShowcaseAudience.resident,
          sites: const <ContextSite>[],
          apartments: const <ContextApartment>[_a5, _a6],
        ),
        isNull,
      );
    });

    test('en az iki site: şerit çıkar', () {
      expect(
        composeContextStrip(audience: ShowcaseAudience.resident, sites: const <ContextSite>[_gunes, _ay]),
        isNotNull,
      );
    });

    test('tek site, iki daire (sakin): şerit çıkar; yönetici kitlesi daireleri YOK sayar', () {
      const apartments = <ContextApartment>[_a5, _a6];
      expect(
        composeContextStrip(audience: ShowcaseAudience.resident, sites: const <ContextSite>[_gunes], apartments: apartments),
        isNotNull,
      );
      expect(
        composeContextStrip(audience: ShowcaseAudience.admin, sites: const <ContextSite>[_gunes], apartments: apartments),
        isNull,
        reason: 'yönetici tek sitede: karışacak bir şey yok',
      );
    });
  });

  group('composeContextStrip: metinler', () {
    test('yönetici, kapsam yok: "Tüm siteler (2)", rol Yönetici, dokununca site seçici', () {
      final data = composeContextStrip(
        audience: ShowcaseAudience.admin,
        sites: const <ContextSite>[_gunes, _ay],
        siteSelectable: true,
      )!;
      expect(data.siteLabel, 'Tüm siteler (2)');
      expect(data.roleLabel, 'Yönetici');
      expect(data.apartmentLabel, isNull);
      expect(data.action, ContextStripAction.pickSite);
      expect(data.semanticsLabel, 'Tüm siteler (2), Yönetici olarak görüntüleniyor');
      expect(data.semanticsHint, 'Siteyi değiştirmek için dokunun');
    });

    test('yönetici, site seçili: o sitenin adı', () {
      final data = composeContextStrip(
        audience: ShowcaseAudience.admin,
        sites: const <ContextSite>[_gunes, _ay],
        scopeSiteCode: 2,
        siteSelectable: true,
      )!;
      expect(data.siteLabel, 'Ay Sitesi');
      expect(data.action, ContextStripAction.pickSite);
    });

    test('sakin, çok site: "İlk site +N site", seçici DEĞİL; "Dairem" açılabiliyorsa oraya götürür', () {
      final data = composeContextStrip(
        audience: ShowcaseAudience.resident,
        sites: const <ContextSite>[_gunes, _ay],
        canOpenApartments: true,
      )!;
      expect(data.siteLabel, 'Güneş Sitesi +1 site');
      expect(data.roleLabel, 'Sakin');
      expect(data.action, ContextStripAction.openApartments);
      expect(data.semanticsHint, 'Dairelerinizi görmek için dokunun');
      expect(
        composeContextStrip(audience: ShowcaseAudience.resident, sites: const <ContextSite>[_gunes, _ay])!.action,
        ContextStripAction.none,
        reason: 'Dairem açılamıyorsa dokunma eylemi yok',
      );
    });

    test('daire parçası: kapsamdaki tek daire adıyla, birden çoksa "N daire"', () {
      const sites = <ContextSite>[
        ContextSite(code: 1, name: 'Güneş Sitesi'),
        ContextSite(code: 2, name: 'Ay Sitesi'),
      ];
      var data = composeContextStrip(
        audience: ShowcaseAudience.resident,
        sites: sites,
        apartments: const <ContextApartment>[_a5, _b2, _a6],
      )!;
      expect(data.apartmentLabel, '3 daire');

      data = composeContextStrip(
        audience: ShowcaseAudience.resident,
        sites: sites,
        scopeSiteCode: 2,
        apartments: const <ContextApartment>[_a5, _b2, _a6],
      )!;
      expect(data.siteLabel, 'Ay Sitesi');
      expect(data.apartmentLabel, 'B Blok / 2');

      data = composeContextStrip(
        audience: ShowcaseAudience.resident,
        sites: sites,
        scopeSiteCode: 1,
        apartments: const <ContextApartment>[_a5, _b2, _a6],
      )!;
      expect(data.apartmentLabel, '2 daire');
      expect(data.semanticsLabel, 'Güneş Sitesi, 2 daire, Sakin olarak görüntüleniyor');
    });

    test('odaktaki sitedeki rol hesap rolünden önce gelir: Yönetim Kurulu, Görevli', () {
      const board = ContextSite(code: 1, name: 'Güneş Sitesi', role: 'board_member');
      const staff = ContextSite(code: 2, name: 'Ay Sitesi', role: 'staff');
      expect(
        composeContextStrip(audience: ShowcaseAudience.resident, sites: const <ContextSite>[board, staff], scopeSiteCode: 1)!
            .roleLabel,
        'Yönetim Kurulu',
      );
      expect(
        composeContextStrip(audience: ShowcaseAudience.resident, sites: const <ContextSite>[board, staff], scopeSiteCode: 2)!
            .roleLabel,
        'Görevli',
      );
      expect(
        composeContextStrip(audience: ShowcaseAudience.resident, sites: const <ContextSite>[board, staff])!.roleLabel,
        'Sakin',
        reason: 'odak yok (karışık roller): kitle rolü',
      );
    });

    test('bireysel kitle: "Bireysel"; adsız site "İsimsiz site" (teknik kod gösterilmez)', () {
      final data = composeContextStrip(
        audience: ShowcaseAudience.individual,
        sites: const <ContextSite>[ContextSite(code: 9, name: '  '), _ay],
        scopeSiteCode: 9,
      )!;
      expect(data.roleLabel, 'Bireysel');
      expect(data.siteLabel, 'İsimsiz site');
      expect(data.siteLabel, isNot(contains('9')));
    });

    test('seçici açıkken bile tek site varsa seçici eylemi yok', () {
      // Çağıran siteSelectable verse de yalnız bir site varken zaten şerit çıkmaz; iki daire varsa eylem "Dairem".
      final data = composeContextStrip(
        audience: ShowcaseAudience.resident,
        sites: const <ContextSite>[_gunes],
        apartments: const <ContextApartment>[_a5, _a6],
        siteSelectable: true,
        canOpenApartments: true,
      )!;
      expect(data.action, ContextStripAction.openApartments);
    });
  });

  group('ContextStrip: çizim', () {
    Widget wrap(ContextStripData data, {VoidCallback? onTap}) =>
        Padding(padding: const EdgeInsets.all(16), child: ContextStrip(data: data, onTap: onTap));

    testWidgets('site · daire · rol tek metinde; dokunma hedefi >= 44 dp; ok yalnız dokunulabilirken', (t) async {
      const data = ContextStripData(
        siteLabel: 'Ay Sitesi',
        apartmentLabel: 'B Blok / 2',
        roleLabel: 'Sakin',
        action: ContextStripAction.openApartments,
      );
      var taps = 0;
      await t.pumpWidget(harnessApp(wrap(data, onTap: () => taps++)));
      await t.pumpAndSettle();
      final text = t.widget<Text>(find.descendant(of: _strip, matching: find.byType(Text)));
      expect(text.textSpan!.toPlainText(), 'Ay Sitesi · B Blok / 2 · Sakin');
      expect(t.getSize(_strip).height, greaterThanOrEqualTo(44));
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      await t.tap(_strip);
      expect(taps, 1);

      await t.pumpWidget(harnessApp(wrap(data)));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      expect(find.byIcon(Icons.unfold_more_rounded), findsNothing);
      expect(t.widgetList<InkWell>(find.descendant(of: _strip, matching: find.byType(InkWell))), isEmpty);
    });

    testWidgets('site seçici şeridinde "yukarı-aşağı" oku; dairesiz şeritte daire parçası yok', (t) async {
      const data = ContextStripData(
        siteLabel: 'Tüm siteler (2)',
        roleLabel: 'Yönetici',
        action: ContextStripAction.pickSite,
      );
      await t.pumpWidget(harnessApp(wrap(data, onTap: () {})));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.unfold_more_rounded), findsOneWidget);
      final text = t.widget<Text>(find.descendant(of: _strip, matching: find.byType(Text)));
      expect(text.textSpan!.toPlainText(), 'Tüm siteler (2) · Yönetici');
    });

    testWidgets('ekran okuyucu: tek düğüm, etiket + ipucu; dokunma eylemi yalnız dokunulabilirken', (t) async {
      final handle = t.ensureSemantics();
      const data = ContextStripData(
        siteLabel: 'Ay Sitesi',
        roleLabel: 'Yönetici',
        action: ContextStripAction.pickSite,
      );
      await t.pumpWidget(harnessApp(wrap(data, onTap: () {})));
      await t.pumpAndSettle();
      expect(
        t.getSemantics(_strip),
        isSemantics(
          label: 'Ay Sitesi, Yönetici olarak görüntüleniyor',
          hint: 'Siteyi değiştirmek için dokunun',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await t.pumpWidget(
        harnessApp(wrap(const ContextStripData(siteLabel: 'Ay Sitesi', roleLabel: 'Yönetici'))),
      );
      await t.pumpAndSettle();
      expect(
        t.getSemantics(_strip),
        isSemantics(label: 'Ay Sitesi, Yönetici olarak görüntüleniyor', isButton: false, hasTapAction: false),
      );
      handle.dispose();
    });

    testWidgets('taşmaz: çok uzun site / daire adı, boyut x yazı ölçeği x tema', (t) async {
      final long = 'Çok Uzun İsimli Güzelyalı Yeşilvadi Konutları ${'Doğa ' * 12}Sitesi';
      final data = ContextStripData(
        siteLabel: long,
        apartmentLabel: 'U' * 90,
        roleLabel: 'Yönetim Kurulu',
        action: ContextStripAction.pickSite,
      );
      await forEachHarnessCell((width, scale, dark) async {
        await pumpAt(
          t,
          SizedBox(width: double.infinity, child: wrap(data, onTap: () {})),
          width: width,
          height: 640,
          scale: scale,
          dark: dark,
        );
        expect(t.getSize(_strip).height, greaterThanOrEqualTo(44));
        expect(t.getRect(_strip).right, lessThanOrEqualTo(width + 0.01));
      });
    });
  });

  group('ContextStripHost', () {
    Widget host({
      ShowcaseAudience audience = ShowcaseAudience.resident,
      List<ContextSite> sites = const <ContextSite>[_gunes, _ay],
      int? scope,
      int userId = 5,
      Future<List<ContextApartment>> Function()? load,
      RefreshStatus? refresh,
      ValueChanged<int?>? onPickSite,
      VoidCallback? onOpenApartments,
    }) =>
        ContextStripHost(
          userId: userId,
          audience: audience,
          sites: sites,
          scopeSiteCode: scope,
          loadApartments: load,
          refresh: refresh,
          onPickSite: onPickSite,
          onOpenApartments: onOpenApartments,
        );

    String stripText(WidgetTester t) =>
        t.widget<Text>(find.descendant(of: _strip, matching: find.byType(Text))).textSpan!.toPlainText();

    testWidgets('daireler yüklenince şerit "N daire" der; yükleyici verilmezse daire parçası olmaz', (t) async {
      await t.pumpWidget(harnessApp(host()));
      await t.pumpAndSettle();
      expect(stripText(t), 'Güneş Sitesi +1 site · Sakin');

      await t.pumpWidget(
        harnessApp(host(load: () async => const <ContextApartment>[_a5, _b2])),
      );
      await t.pumpAndSettle();
      expect(stripText(t), 'Güneş Sitesi +1 site · 2 daire · Sakin');
    });

    testWidgets('yönetici kitlesi daireleri HİÇ yüklemez', (t) async {
      var calls = 0;
      await t.pumpWidget(
        harnessApp(
          host(
            audience: ShowcaseAudience.admin,
            onPickSite: (_) {},
            load: () async {
              calls++;
              return const <ContextApartment>[_a5];
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(calls, 0);
      expect(stripText(t), 'Tüm siteler (2) · Yönetici');
    });

    testWidgets('yükleme hatası şeridi bozmaz: dairesiz çizilir', (t) async {
      await t.pumpWidget(harnessApp(host(load: () async => throw StateError('yok'))));
      await t.pumpAndSettle();
      expect(stripText(t), 'Güneş Sitesi +1 site · Sakin');
      expect(t.takeException(), isNull);
    });

    testWidgets('her BAŞARILI genel yenilemede daireler yeniden okunur (yenileme sürerken değil)', (t) async {
      var calls = 0;
      var apartments = const <ContextApartment>[_a5, _b2];
      final status = RefreshStatus();
      Future<List<ContextApartment>> load() async {
        calls++;
        return apartments;
      }

      await t.pumpWidget(harnessApp(host(load: load, refresh: status)));
      await t.pumpAndSettle();
      expect(calls, 1);

      final gate = Completer<void>();
      apartments = const <ContextApartment>[_a5, _b2, _a6];
      final run = status.run(() => gate.future);
      await t.pump();
      expect(calls, 1, reason: 'yenileme sürerken okunmaz');
      gate.complete();
      await run;
      await t.pumpAndSettle();
      expect(calls, 2);
      expect(stripText(t), 'Güneş Sitesi +1 site · 3 daire · Sakin');

      await expectLater(status.run(() async => throw StateError('x')), throwsStateError);
      await t.pumpAndSettle();
      expect(calls, 2, reason: 'başarısız yenileme daireleri okumaz');
    });

    testWidgets('kullanıcı değişince eski kullanıcının daireleri hemen bırakılır, yenisinin dairesi yüklenir', (t) async {
      final gate = Completer<List<ContextApartment>>();
      var call = 0;
      Future<List<ContextApartment>> load() {
        call++;
        return call == 1 ? Future.value(const <ContextApartment>[_a5, _a6]) : gate.future;
      }

      await t.pumpWidget(harnessApp(host(load: load, sites: const <ContextSite>[_gunes])));
      await t.pumpAndSettle();
      expect(stripText(t), 'Güneş Sitesi · 2 daire · Sakin');

      await t.pumpWidget(harnessApp(host(load: load, sites: const <ContextSite>[_gunes], userId: 6)));
      await t.pump();
      expect(_strip, findsNothing, reason: 'yeni kullanıcının daireleri gelene dek eski kullanıcının şeridi görünmez');
      gate.complete(const <ContextApartment>[_b2, _a6, _a5]);
      await t.pumpAndSettle();
      expect(stripText(t), 'Güneş Sitesi · 3 daire · Sakin');
    });

    testWidgets('sakin şeridine dokunmak onOpenApartments\'ı çağırır', (t) async {
      var opened = 0;
      await t.pumpWidget(harnessApp(host(onOpenApartments: () => opened++)));
      await t.pumpAndSettle();
      await t.tap(_strip);
      expect(opened, 1);
    });

    testWidgets('yönetici şeridine dokunmak site seçiciyi açar; seçim onPickSite\'a gider (Tüm siteler = null)', (t) async {
      final picked = <int?>[];
      var scope = 1;
      await t.pumpWidget(
        harnessApp(
          StatefulBuilder(
            builder: (context, setState) => host(
              audience: ShowcaseAudience.admin,
              scope: scope,
              onPickSite: (code) {
                picked.add(code);
                setState(() => scope = code ?? 0);
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(stripText(t), 'Güneş Sitesi · Yönetici');

      await t.tap(_strip);
      await t.pumpAndSettle();
      expect(find.text('Site seçin'), findsOneWidget);
      for (final key in <String>['tum', '1', '2']) {
        expect(find.byKey(ValueKey<String>('baglam_site_secenek_$key')), findsOneWidget, reason: key);
      }
      // Seçili site işaretli.
      expect(
        t.widget<ListTile>(find.byKey(const ValueKey<String>('baglam_site_secenek_1'))).selected,
        isTrue,
      );
      await t.tap(find.byKey(const ValueKey<String>('baglam_site_secenek_2')));
      await t.pumpAndSettle();
      expect(picked, <int?>[2]);
      expect(find.text('Site seçin'), findsNothing);
      expect(stripText(t), 'Ay Sitesi · Yönetici');

      await t.tap(_strip);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey<String>('baglam_site_secenek_tum')));
      await t.pumpAndSettle();
      expect(picked, <int?>[2, null]);
    });

    testWidgets('aynı siteyi yeniden seçmek onPickSite\'ı çağırmaz; pencereyi kapatmak da çağırmaz', (t) async {
      final picked = <int?>[];
      await t.pumpWidget(
        harnessApp(host(audience: ShowcaseAudience.admin, scope: 1, onPickSite: picked.add)),
      );
      await t.pumpAndSettle();
      await t.tap(_strip);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey<String>('baglam_site_secenek_1')));
      await t.pumpAndSettle();
      expect(picked, isEmpty);

      await t.tap(_strip);
      await t.pumpAndSettle();
      await t.tapAt(const Offset(10, 10)); // perde: pencere kapanır
      await t.pumpAndSettle();
      expect(picked, isEmpty);
    });

    testWidgets('kısa pencerede (yatay telefon, < 480 dp) şerit çizilmez', (t) async {
      t.view.physicalSize = const Size(800, 400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(harnessApp(host()));
      await t.pumpAndSettle();
      expect(_strip, findsNothing);
    });
  });
}
