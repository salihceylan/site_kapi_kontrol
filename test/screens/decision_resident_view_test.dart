// Karar Defteri: sakin "Kararlar" ekranı (DecisionResidentView).
//
// Kapsam: taşma matrisi (320x640 x2,0; 360x640 x1,5; yatay 640x360 x2,0; tablet 768x1024; açık / koyu), yalnız KESİN +
// sakinlere açık kararlar, yıl başlıkları, yasal not, salt okunur ayrıntı (eylem yok), yükleniyor / hata / boş / modül
// kapalı ayrımı (HATA ASLA "karar yok" demez), site ve yıl süzgeci, imleçli "Daha fazla".
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/decision_resident_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/decision_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

import 'decision_fixtures.dart';
import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;

const List<PeopleSite> _oneSite = <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')];
const List<PeopleSite> _twoSites = <PeopleSite>[
  PeopleSite(code: 11, name: 'Gül Sitesi'),
  PeopleSite(code: 12, name: 'Mavi Park'),
];

class _Rig {
  _Rig(this.service, this.auth);

  final FakeDecisionService service;
  final DecisionFakeAuth auth;
  final GlobalKey<DecisionResidentViewState> key = GlobalKey<DecisionResidentViewState>();

  Future<void> pump(
    WidgetTester t, {
    double width = 400,
    double height = 2400,
    double scale = 1.0,
    bool dark = false,
    List<PeopleSite> sites = _oneSite,
  }) async {
    await pumpList(
      t,
      DecisionResidentView(key: key, authService: auth, service: service, sites: sites),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await _settle(t);
  }
}

_Rig _rig() {
  final auth = DecisionFakeAuth();
  final service = seededDecisions(auth)
    ..rows.add(dcJson(6, no: 1, date: '2025-04-04', status: 'kesin', visibility: 'sakinler', title: 'Havuz kullanım saatleri'));
  return _Rig(service, auth);
}

Future<void> _settle(WidgetTester t) async {
  await settleFor(t, 100);
  await settleFor(t, 100);
}

void main() {
  group('taşma matrisi', () {
    decisionMatrix('liste: iki site, yıl başlıkları, site adı, değiştirildi, yasal not', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark, sites: _twoSites);
      expect(find.byType(DecisionCard), findsNWidgets(4), reason: 'kesin + sakinlere açık: 1, 3, 5 (site 12), 6');
      expect(dcKey('decision_year_header_2026'), findsOneWidget);
      expect(dcKey('decision_year_header_2025'), findsOneWidget);
      expect(find.text('Mavi Park'), findsWidgets);
      expect(find.text('2026/2 sayılı kararla değiştirildi'), findsOneWidget);
      expect(find.text('Sakinlere açık'), findsNothing, reason: 'yönetim işareti sakinde yok');
      expect(find.text('Taslak'), findsNothing);
      expect(dcKey('decision_legal_notice'), findsOneWidget);
    });

    decisionMatrix('ayrıntı: salt okunur, eylem yok, yasal not', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await tapFinder(t, dcKey('decision_card_3'));
      await _settle(t);
      expect(dcKey('decision_detail'), findsOneWidget);
      expect(rig.service.getMineCalls, <int>[3]);
      expect(dcKey('decision_detail_body'), findsOneWidget);
      expect(find.text('Değiştirdiği karar: 2026/1'), findsOneWidget);
      expect(dcKey('decision_action_finalize'), findsNothing);
      expect(dcKey('decision_action_edit'), findsNothing);
      expect(dcKey('decision_action_delete'), findsNothing);
      expect(dcKey('decision_action_correction'), findsNothing);
      expect(find.textContaining('Yazan:'), findsNothing);
      expect(find.descendant(of: dcKey('decision_detail'), matching: dcKey('decision_legal_notice')), findsOneWidget);
    });
  });

  group('durumlar', () {
    testWidgets('yalnız kesin + sakinlere açık kararlar; taslak ve yönetime özel karar görünmez', (t) async {
      final rig = _rig();
      await rig.pump(t);
      expect(find.byType(DecisionCard), findsNWidgets(3));
      expect(dcKey('decision_card_2'), findsNothing, reason: 'taslak');
      expect(dcKey('decision_card_4'), findsNothing, reason: 'yalnız yönetim');
      expect(rig.service.listMineCalls.single.site, 11, reason: 'tek sitede site açıkça istenir');
    });

    testWidgets('yükleniyor -> dolu; hata "karar yok" demez, Tekrar Dene', (t) async {
      final rig = _rig();
      final gate = Completer<void>();
      rig.service.gates['listMine'] = <Completer<void>>[gate];
      rig.service.failures['listMine'] = <Object>[ApiException('Sunucu yanıt vermedi, tekrar deneyin.')];
      await pumpList(
        t,
        DecisionResidentView(key: rig.key, authService: rig.auth, service: rig.service, sites: _oneSite),
        width: 400,
        height: 2400,
        scale: 1.0,
        dark: false,
      );
      await t.pump();
      expect(find.byType(ListSkeleton), findsOneWidget);
      gate.complete();
      await _settle(t);
      expect(dcKey('decision_error'), findsOneWidget);
      expect(find.text('Paylaşılmış karar yok.'), findsNothing);
      await tapFinder(t, find.text('Tekrar Dene'));
      await _settle(t);
      expect(find.byType(DecisionCard), findsNWidgets(3));
    });

    testWidgets('boş liste, modül kapalı ve site yok', (t) async {
      final auth = DecisionFakeAuth();
      final rig = _Rig(FakeDecisionService(authService: auth), auth);
      await rig.pump(t);
      expect(dcKey('decision_empty'), findsOneWidget);
      expect(find.text('Paylaşılmış karar yok.'), findsOneWidget);
      rig.service.failures['listMine'] = <Object>[FakeDecisionService.moduleOff()];
      await rig.key.currentState!.reload();
      await _settle(t);
      expect(dcKey('decision_module_off'), findsOneWidget);

      final none = _Rig(FakeDecisionService(authService: auth), auth);
      await none.pump(t, sites: const <PeopleSite>[]);
      expect(find.text('Karar görebileceğiniz site yok.'), findsOneWidget);
      expect(none.service.listMineCalls, isEmpty);
    });

    testWidgets('site ve yıl süzgeci sunucuya gider', (t) async {
      final rig = _rig();
      await rig.pump(t, sites: _twoSites);
      expect(rig.service.listMineCalls.single.site, isNull, reason: 'çok sitede "Tüm siteler"');
      await tapFinder(t, dcKey('decision_resident_site_0'));
      await _settle(t);
      await t.tap(find.text('Mavi Park').last);
      await _settle(t);
      expect(rig.service.listMineCalls.last.site, 12);
      expect(find.byType(DecisionCard), findsOneWidget);
      await tapFinder(t, find.byType(DecisionYearDropdown));
      await _settle(t);
      await t.tap(find.text('2026').last);
      await _settle(t);
      expect(rig.service.listMineCalls.last.year, 2026);
      expect(rig.service.listMineCalls.last.site, 12);
    });

    testWidgets('imleçli sayfalama: before_id ile "Daha fazla yükle"', (t) async {
      final rig = _rig()..service.pageLimit = 2;
      await rig.pump(t);
      expect(find.byType(DecisionCard), findsNWidgets(2));
      await tapFinder(t, dcKey('decision_more'));
      await _settle(t);
      expect(rig.service.listMineCalls.last.cursor?.param, 'before_id');
      expect(find.byType(DecisionCard), findsNWidgets(3));
    });

    testWidgets('ayrıntı 404 (artık görünmüyor): pencerede hata ve Tekrar Dene', (t) async {
      final rig = _rig();
      rig.service.failures['getMine'] = <Object>[FakeDecisionService.error(404, 'DECISION_NOT_FOUND')];
      await rig.pump(t);
      await tapFinder(t, dcKey('decision_card_1'));
      await _settle(t);
      expect(dcKey('decision_detail_error'), findsOneWidget);
      expect(find.textContaining('Karar bulunamadı'), findsOneWidget);
      expect(find.text('Asansör bakım sözleşmesinin yenilenmesi'), findsWidgets, reason: 'listedeki kayıt gösterilmeye devam eder');
    });
  });
}
