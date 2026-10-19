// Anket ve Oylama: sakin "Anketler" ekranı (SurveyResidentView).
//
// Kapsam: taşma matrisi (320x640 x2,0; 360x640 x1,5; yatay 640x360 x2,0; tablet 768x1024; açık / koyu), yükleniyor /
// hata / boş / dolu ayrımı (HATA ASLA "anket yok" demez), modül kapalı, seçenek seç + "Oy ver" onaylı, oy verince
// sonuç çubukları, kapananlar bölümü, site süzgeci.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/survey_resident_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/survey_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;
import 'survey_fixtures.dart';

const List<PeopleSite> _oneSite = <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')];
const List<PeopleSite> _twoSites = <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi'), PeopleSite(code: 12, name: 'Mavi Park')];

class _Rig {
  _Rig(this.service, this.auth);

  final FakeSurveyService service;
  final SurveyFakeAuth auth;
  final GlobalKey<SurveyResidentViewState> key = GlobalKey<SurveyResidentViewState>();

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
      SurveyResidentView(key: key, authService: auth, service: service, sites: sites),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t, 100);
    await settleFor(t, 100);
  }
}

_Rig _rig() {
  final auth = SurveyFakeAuth();
  return _Rig(seededSurvey(auth), auth);
}

Future<void> _settle(WidgetTester t) async {
  await settleFor(t, 100);
  await settleFor(t, 100);
}

void main() {
  group('taşma matrisi', () {
    surveyMatrix('açık + kapanan anketler, seçenekler ve sonuç çubukları', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark, sites: _twoSites);
      expect(find.byType(SurveyVoteCard), findsNWidgets(3), reason: 'taslak (3) sakine görünmez');
      expect(svKey('survey_option_1_0'), findsOneWidget, reason: 'oy verilmemiş açık ankette seçenekler');
      expect(svKey('survey_vote_1'), findsOneWidget);
      expect(find.byType(SurveyResultBar), findsNWidgets(6), reason: 'oy verilmiş (4) + kapalı (2) sonuç çubukları');
      expect(find.text('Kapanan anketler'), findsOneWidget);
      expect(find.text('Mavi Park'), findsWidgets, reason: 'çok siteli sakinde kartta site adı');
    });
  });

  group('durumlar', () {
    testWidgets('yükleniyor -> dolu', (t) async {
      final rig = _rig();
      final gate = Completer<void>();
      rig.service.gates['listMine'] = <Completer<void>>[gate];
      await pumpList(t, SurveyResidentView(key: rig.key, authService: rig.auth, service: rig.service, sites: _oneSite),
          width: 400, height: 2400, scale: 1.0, dark: false);
      await t.pump();
      expect(find.byType(ListSkeleton), findsOneWidget);
      gate.complete();
      await _settle(t);
      expect(find.byType(ListSkeleton), findsNothing);
      expect(find.byType(SurveyVoteCard), findsNWidgets(3));
    });

    testWidgets('hata: "anket yok" yazmaz, Tekrar Dene yeniden çeker', (t) async {
      final rig = _rig();
      rig.service.failures['listMine'] = <Object>[ApiException('Sunucu yanıt vermedi, tekrar deneyin.')];
      await rig.pump(t);
      expect(svKey('survey_error'), findsOneWidget);
      expect(find.text('Açık anket yok.'), findsNothing);
      expect(find.text('Sunucu yanıt vermedi, tekrar deneyin.'), findsOneWidget);
      await tapFinder(t, find.text('Tekrar Dene'));
      await _settle(t);
      expect(svKey('survey_error'), findsNothing);
      expect(find.byType(SurveyVoteCard), findsNWidgets(3));
    });

    testWidgets('boş liste: iki bölüm de boş kartı gösterir', (t) async {
      final auth = SurveyFakeAuth();
      final rig = _Rig(FakeSurveyService(authService: auth), auth);
      await rig.pump(t);
      expect(svKey('survey_open_empty'), findsOneWidget);
      expect(svKey('survey_closed_empty'), findsOneWidget);
    });

    testWidgets('modül kapalı kartı', (t) async {
      final rig = _rig();
      rig.service.failures['listMine'] = <Object>[FakeSurveyService.moduleOff()];
      await rig.pump(t);
      expect(svKey('survey_module_off'), findsOneWidget);
    });

    testWidgets('site yoksa açıklayıcı kart', (t) async {
      final rig = _rig();
      await rig.pump(t, sites: const <PeopleSite>[]);
      expect(find.text('Anket görebileceğiniz site yok.'), findsOneWidget);
    });
  });

  group('oy verme', () {
    testWidgets('seçenek seç -> Oy ver -> onay -> sonuç çubukları', (t) async {
      final rig = _rig();
      await rig.pump(t);
      final button = svKey('survey_vote_1');
      expect(t.widget<Widget>(button), isNotNull);
      await tapFinder(t, svKey('survey_option_1_1'));
      await tapFinder(t, button);
      await _settle(t);
      expect(find.text('Oyunuzu onaylayın'), findsOneWidget);
      await tapFinder(t, find.text('Oy ver').last);
      await _settle(t);
      expect(rig.service.voteCalls, <({int id, int option})>[(id: 1, option: 1)]);
      expect(find.text('Oyunuz alındı.'), findsOneWidget);
      expect(svKey('survey_option_1_1'), findsNothing, reason: 'oy verince seçenekler gider');
      expect(find.byType(SurveyResultBar), findsNWidgets(9), reason: '1 numaralı anketin 3 çubuğu eklendi');
      expect(find.text('%28 · 6'), findsOneWidget, reason: '6/21 tamsayı yüzde (28,57 -> 28)');
    });

    testWidgets('vazgeçince oy gitmez', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await tapFinder(t, svKey('survey_option_1_0'));
      await tapFinder(t, svKey('survey_vote_1'));
      await _settle(t);
      await tapFinder(t, find.text('Vazgeç'));
      await _settle(t);
      expect(rig.service.voteCalls, isEmpty);
      expect(svKey('survey_option_1_0'), findsOneWidget);
    });

    testWidgets('ALREADY_VOTED: hata metni ve liste yenilenir', (t) async {
      final rig = _rig();
      rig.service.failures['vote'] = <Object>[FakeSurveyService.error(409, 'ALREADY_VOTED')];
      await rig.pump(t);
      await tapFinder(t, svKey('survey_option_1_0'));
      await tapFinder(t, svKey('survey_vote_1'));
      await _settle(t);
      await tapFinder(t, find.text('Oy ver').last);
      await _settle(t);
      expect(find.textContaining('zaten oy kullandınız'), findsOneWidget);
      expect(rig.service.listMineCalls.length, 2, reason: 'ilk yükleme + yenileme');
    });
  });

  testWidgets('site süzgeci listeyi site koduyla çeker', (t) async {
    final rig = _rig();
    await rig.pump(t, sites: _twoSites);
    await tapFinder(t, find.byType(DropdownButtonFormField<int>));
    await _settle(t);
    await tapFinder(t, find.text('Mavi Park').last);
    await _settle(t);
    expect(rig.service.listMineCalls.last.site, 12);
    expect(find.byType(SurveyVoteCard), findsOneWidget);
  });
}
