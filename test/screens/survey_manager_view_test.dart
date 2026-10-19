// Anket ve Oylama: yönetim "Anket ve Oylama" ekranı (SurveyManagerView) + ayrıntı penceresi + yeni anket formu.
//
// Kapsam: taşma matrisi, yükleniyor / hata / boş / dolu, modül kapalı, durum süzgeci, kurul salt okur (düğme yok, oy
// verenler yok), ayrıntı: soru + sonuç çubukları (tamsayı yüzde) + oy verenler; Yayınla / Kapat / Sil onaylı; form:
// seçenek ekle / sil sınırları ve gönderim.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/survey_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/views/survey_manager_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/survey_parts.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;
import 'survey_fixtures.dart';

const List<SurveySite> _oneSite = <SurveySite>[SurveySite(code: 11, name: 'Gül Sitesi')];
const List<SurveySite> _twoSites = <SurveySite>[SurveySite(code: 11, name: 'Gül Sitesi'), SurveySite(code: 12, name: 'Mavi Park')];
const List<SurveySite> _boardSite = <SurveySite>[SurveySite(code: 11, name: 'Gül Sitesi', access: SurveySiteAccess.board)];

class _Rig {
  _Rig(this.service, this.auth);

  final FakeSurveyService service;
  final SurveyFakeAuth auth;
  final GlobalKey<SurveyManagerViewState> key = GlobalKey<SurveyManagerViewState>();

  Future<void> pump(
    WidgetTester t, {
    double width = 400,
    double height = 2400,
    double scale = 1.0,
    bool dark = false,
    List<SurveySite> sites = _oneSite,
  }) async {
    await pumpList(
      t,
      SurveyManagerView(key: key, authService: auth, service: service, sites: sites),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await settleFor(t, 100);
    await settleFor(t, 100);
  }
}

_Rig _rig({SurveySiteAccess kind = SurveySiteAccess.manager}) {
  final auth = SurveyFakeAuth();
  return _Rig(seededSurvey(auth, kind: kind), auth);
}

Future<void> _settle(WidgetTester t) async {
  await settleFor(t, 100);
  await settleFor(t, 100);
}

Future<void> _openDetail(WidgetTester t, int id) async {
  await tapFinder(t, svKey('svm_card_$id'));
  await _settle(t);
  expect(svKey('svm_detail'), findsOneWidget);
}

void main() {
  group('taşma matrisi', () {
    surveyMatrix('liste: kartlar, durum çipleri, oy sayısı, Yeni Anket', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark, sites: _twoSites);
      expect(find.byType(SurveyManagedCard), findsNWidgets(3), reason: 'site 11: 1 açık, 2 kapalı, 3 taslak');
      expect(find.text('Taslak'), findsWidgets);
      expect(find.text('20 / 40 oy · Kapanış: 31.12.2026 23:59'), findsOneWidget);
      expect(svKey('svm_new'), findsOneWidget);
      expect(find.text('Anketler (3)'), findsOneWidget);
    });

    surveyMatrix('ayrıntı: soru, sonuç çubukları, eylemler', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _openDetail(t, 1);
      expect(find.byType(SurveyResultBar), findsNWidgets(3));
      expect(find.text('%60 · 12'), findsOneWidget);
      expect(find.text('%25 · 5'), findsOneWidget);
      expect(find.text('%15 · 3'), findsOneWidget);
      expect(find.text('Toplam 20 oy · 40 kişiden %50 katılım'), findsOneWidget);
      expect(svKey('svm_action_close'), findsOneWidget);
      expect(svKey('svm_action_open'), findsNothing);
      expect(svKey('svm_action_delete'), findsNothing);
    });

    surveyMatrix('yeni anket formu', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await tapFinder(t, svKey('svm_new'));
      await _settle(t);
      expect(svKey('survey_form_title'), findsOneWidget);
      expect(svKey('survey_form_option_1'), findsOneWidget);
      expect(svKey('survey_form_publish'), findsOneWidget);
    });
  });

  group('durumlar', () {
    testWidgets('yükleniyor -> dolu', (t) async {
      final rig = _rig();
      final gate = Completer<void>();
      rig.service.gates['listManaged'] = <Completer<void>>[gate];
      await pumpList(t, SurveyManagerView(key: rig.key, authService: rig.auth, service: rig.service, sites: _oneSite),
          width: 400, height: 2400, scale: 1.0, dark: false);
      await t.pump();
      await t.pump();
      expect(find.byType(ListSkeleton), findsOneWidget);
      gate.complete();
      await _settle(t);
      expect(find.byType(SurveyManagedCard), findsNWidgets(3));
    });

    testWidgets('hata: "anket yok" yazmaz; Tekrar Dene', (t) async {
      final rig = _rig();
      rig.service.failures['listManaged'] = <Object>[ApiException('Sunucu yanıt vermedi, tekrar deneyin.')];
      await rig.pump(t);
      expect(svKey('svm_error'), findsOneWidget);
      expect(find.text('Henüz anket yok.'), findsNothing);
      await tapFinder(t, find.text('Tekrar Dene'));
      await _settle(t);
      expect(find.byType(SurveyManagedCard), findsNWidgets(3));
    });

    testWidgets('boş liste ve modül kapalı', (t) async {
      final auth = SurveyFakeAuth();
      final rig = _Rig(FakeSurveyService(authService: auth), auth);
      await rig.pump(t);
      expect(svKey('svm_empty'), findsOneWidget);
      rig.service.failures['listManaged'] = <Object>[FakeSurveyService.moduleOff()];
      await rig.key.currentState!.reload();
      await _settle(t);
      expect(svKey('survey_module_off'), findsOneWidget);
      expect(svKey('svm_new'), findsNothing);
    });

    testWidgets('durum süzgeci sunucuya gider', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await tapFinder(t, svKey('svm_status_draft'));
      await _settle(t);
      expect(rig.service.listManagedCalls.last.status, 'draft');
      expect(find.byType(SurveyManagedCard), findsOneWidget);
    });

    testWidgets('kurul: salt okur, düğme yok, oy verenler yok', (t) async {
      final rig = _rig(kind: SurveySiteAccess.board);
      await rig.pump(t, sites: _boardSite);
      expect(svKey('survey_read_only_note'), findsOneWidget);
      expect(svKey('svm_new'), findsNothing);
      await _openDetail(t, 2);
      expect(svKey('svm_voters_load'), findsNothing, reason: 'anonim olmayan ankette bile kurul görmez');
      expect(svKey('svm_action_open'), findsNothing);
      expect(svKey('svm_action_close'), findsNothing);
      expect(svKey('svm_action_delete'), findsNothing);
    });
  });

  group('eylemler', () {
    testWidgets('Yayınla onaylı: draft -> open', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openDetail(t, 3);
      expect(svKey('svm_action_open'), findsOneWidget);
      expect(svKey('svm_action_delete'), findsOneWidget);
      await tapFinder(t, svKey('svm_action_open'));
      await _settle(t);
      expect(find.text('Anketi yayınla'), findsOneWidget);
      await tapFinder(t, find.text('Yayınla').last);
      await _settle(t);
      expect(rig.service.openCalls, <int>[3]);
      expect(find.text('Anket yayınlandı.'), findsOneWidget);
      expect(svKey('svm_action_open'), findsNothing);
      expect(svKey('svm_action_close'), findsOneWidget);
    });

    testWidgets('Kapat onaylı; vazgeçince çağrı yok', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openDetail(t, 1);
      await tapFinder(t, svKey('svm_action_close'));
      await _settle(t);
      await tapFinder(t, find.text('Vazgeç'));
      await _settle(t);
      expect(rig.service.closeCalls, isEmpty);
      await tapFinder(t, svKey('svm_action_close'));
      await _settle(t);
      await tapFinder(t, find.text('Kapat').last);
      await _settle(t);
      expect(rig.service.closeCalls, <int>[1]);
      expect(find.text('Anket kapatıldı.'), findsOneWidget);
    });

    testWidgets('Sil onaylı: pencere kapanır, liste yenilenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openDetail(t, 3);
      await tapFinder(t, svKey('svm_action_delete'));
      await _settle(t);
      await tapFinder(t, find.text('Sil').last);
      await _settle(t);
      expect(rig.service.deleteCalls, <int>[3]);
      expect(svKey('svm_detail'), findsNothing);
      expect(find.byType(SurveyManagedCard), findsNWidgets(2));
    });

    testWidgets('INVALID_STATE: hata metni, ayrıntı yeniden çekilir', (t) async {
      final rig = _rig();
      rig.service.failures['open'] = <Object>[FakeSurveyService.error(409, 'INVALID_STATE')];
      await rig.pump(t);
      await _openDetail(t, 3);
      await tapFinder(t, svKey('svm_action_open'));
      await _settle(t);
      await tapFinder(t, find.text('Yayınla').last);
      await _settle(t);
      expect(find.textContaining('bu durumda'), findsOneWidget);
      expect(rig.service.getManagedCalls, <int>[3, 3]);
    });

    testWidgets('oy verenler: anonim olmayan ankette yüklenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openDetail(t, 2);
      await tapFinder(t, svKey('svm_voters_load'));
      await _settle(t);
      expect(rig.service.votersCalls, <int>[2]);
      expect(find.textContaining('Ayşe Yılmaz (A Blok / 5) · Evet'), findsOneWidget);
      expect(find.textContaining('Silinmiş hesap'), findsOneWidget);
    });
  });

  group('form', () {
    testWidgets('seçenek ekle / sil sınırları (2-10) ve boş alan doğrulaması', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await tapFinder(t, svKey('svm_new'));
      await _settle(t);
      expect(t.widget<IconButton>(svKey('survey_form_option_remove_0')).onPressed, isNull, reason: '2 seçenek silinemez');
      for (var i = 2; i < 10; i++) {
        await tapFinder(t, svKey('survey_form_option_add'));
        await t.pump();
      }
      expect(svKey('survey_form_option_9'), findsOneWidget);
      expect(t.widget<TextButton>(svKey('survey_form_option_add')).onPressed, isNull, reason: '10 üst sınır');
      await tapFinder(t, svKey('survey_form_option_remove_9'));
      await t.pump();
      expect(svKey('survey_form_option_9'), findsNothing);
      await tapFinder(t, svKey('survey_form_draft'));
      await _settle(t);
      expect(find.text('Başlık boş olamaz.'), findsOneWidget);
      expect(rig.service.createCalls, isEmpty);
    });

    testWidgets('doldur ve Yayınla: istek publish now, liste yenilenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await tapFinder(t, svKey('svm_new'));
      await _settle(t);
      await t.enterText(svKey('survey_form_title'), 'Yeni anket');
      await t.enterText(svKey('survey_form_question'), 'Soru?');
      await t.enterText(svKey('survey_form_option_0'), 'A');
      await t.enterText(svKey('survey_form_option_1'), 'B');
      await tapFinder(t, svKey('survey_form_one_vote'));
      await tapFinder(t, svKey('survey_form_publish'));
      await _settle(t);
      final req = rig.service.createCalls.single;
      expect(req.publishNow, isTrue);
      expect(req.oneVotePerApartment, isTrue);
      expect(req.anonymous, isTrue);
      expect(req.options, <String>['A', 'B']);
      expect(find.text('Anket yayınlandı.'), findsOneWidget);
      expect(find.byType(SurveyManagedCard), findsNWidgets(4));
    });

    testWidgets('bloklar hedefi boşken hata', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await tapFinder(t, svKey('svm_new'));
      await _settle(t);
      await t.enterText(svKey('survey_form_title'), 'x');
      await t.enterText(svKey('survey_form_question'), 'y');
      await t.enterText(svKey('survey_form_option_0'), 'A');
      await t.enterText(svKey('survey_form_option_1'), 'B');
      await tapFinder(t, svKey('survey_form_target_blocks'));
      await tapFinder(t, svKey('survey_form_draft'));
      await _settle(t);
      expect(find.text('En az bir blok seçin.'), findsOneWidget);
      expect(rig.service.createCalls, isEmpty);
    });
  });
}
