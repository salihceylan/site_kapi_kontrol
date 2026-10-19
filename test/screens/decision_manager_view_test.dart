// Karar Defteri: yönetim ekranı (DecisionManagerView) + ayrıntı penceresi + karar formu + kesinleştirme onayı.
//
// Kapsam: taşma matrisi (320x640 x2,0; 360x640 x1,5; yatay 640x360 x2,0; tablet 768x1024; açık / koyu), yükleniyor /
// hata / boş / dolu (HATA ASLA "karar yok" demez), modül kapalı, süzgeçler sunucuya gider, imleçli "Daha fazla",
// kurul salt okur (taslak dahil), kesinleştirme (güçlü onay), silme, düzenleme (yalnız değişen alanlar), düzeltme
// kararı (supersedes_id dolu form, kesinleşince eski karar "değiştirildi"), bağlantıdan karar açma, PDF (yalnız kesin).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/decision_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/pdf_decision_service.dart';
import 'package:site_kapi_kontrol/ui/dialogs/decision_detail_dialog.dart';
import 'package:site_kapi_kontrol/ui/views/decision_manager_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/decision_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

import 'decision_fixtures.dart';
import 'dialog_layout_harness.dart' show scrollTo, settleFor;
import 'list_fixtures.dart' show pumpList, tapFinder;

const List<DecisionSite> _oneSite = <DecisionSite>[DecisionSite(code: 11, name: 'Gül Sitesi')];
const List<DecisionSite> _twoSites = <DecisionSite>[
  DecisionSite(code: 11, name: 'Gül Sitesi'),
  DecisionSite(code: 12, name: 'Mavi Park'),
];
const List<DecisionSite> _boardSite = <DecisionSite>[
  DecisionSite(code: 11, name: 'Gül Sitesi', access: DecisionSiteAccess.board),
];

class _Rig {
  _Rig(this.service, this.auth);

  final FakeDecisionService service;
  final DecisionFakeAuth auth;
  final GlobalKey<DecisionManagerViewState> key = GlobalKey<DecisionManagerViewState>();

  Future<void> pump(
    WidgetTester t, {
    double width = 400,
    double height = 2400,
    double scale = 1.0,
    bool dark = false,
    List<DecisionSite> sites = _oneSite,
  }) async {
    await pumpList(
      t,
      DecisionManagerView(key: key, authService: auth, service: service, sites: sites, clock: decisionTestClock),
      width: width,
      height: height,
      scale: scale,
      dark: dark,
    );
    await _settle(t);
  }
}

_Rig _rig({DecisionSiteAccess kind = DecisionSiteAccess.manager}) {
  final auth = DecisionFakeAuth();
  return _Rig(seededDecisions(auth, kind: kind), auth);
}

Future<void> _settle(WidgetTester t) async {
  await settleFor(t, 100);
  await settleFor(t, 100);
}

Future<void> _openDetail(WidgetTester t, int id) async {
  await tapFinder(t, dcKey('decision_card_$id'));
  await _settle(t);
  expect(dcKey('decision_detail'), findsOneWidget);
}

/// Pencere içindeki düğmeye kaydırıp dokunur.
Future<void> _tapIn(WidgetTester t, Finder finder) async {
  await scrollTo(t, finder.first);
  await t.tap(finder.first);
  await _settle(t);
}

Future<void> _fillForm(WidgetTester t, {String title = 'Çatı onarımı', String body = 'Çatı için teklif alınacak.'}) async {
  await t.enterText(dcKey('decision_form_title'), title);
  await t.enterText(dcKey('decision_form_body'), body);
  await t.pump();
}

void main() {
  tearDown(() => DecisionPdfActions.debugOverride = null);

  group('taşma matrisi', () {
    decisionMatrix('liste: yıl başlıkları, numara / taslak, oylama, sakinlere açık, değiştirildi, yasal not', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark, sites: _twoSites);
      expect(find.byType(DecisionCard), findsNWidgets(4));
      expect(dcKey('decision_year_header_2026'), findsOneWidget);
      expect(dcKey('decision_year_header_2025'), findsOneWidget);
      expect(find.text('Taslak'), findsWidgets);
      expect(find.text('2026/1'), findsOneWidget);
      expect(find.text('Sakinlere açık'), findsNWidgets(2));
      expect(find.text('2026/2 sayılı kararla değiştirildi'), findsOneWidget);
      expect(find.text('Ertelendi'), findsOneWidget);
      expect(dcKey('decision_legal_notice'), findsOneWidget);
      expect(find.text(kDecisionLegalNotice), findsOneWidget);
      expect(dcKey('decision_new'), findsOneWidget);
      expect(dcKey('decision_pdf'), findsOneWidget);
    });

    decisionMatrix('ayrıntı: kesin karar, oylar, katılanlar, kesinleştiren, bağlantılar', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _openDetail(t, 1);
      expect(dcKey('decision_detail_body'), findsOneWidget);
      expect(find.text('Kabul edildi · Kabul 3 · Ret 0 · Çekimser 1'), findsOneWidget);
      expect(find.text('Ayşe Yılmaz (Başkan), Mehmet Demir, Zeynep Kaya'), findsOneWidget);
      expect(find.textContaining('Kesinleştiren: Ayşe Yılmaz'), findsOneWidget);
      expect(dcKey('decision_open_ref_3'), findsOneWidget);
      expect(dcKey('decision_action_correction'), findsOneWidget);
      expect(dcKey('decision_action_finalize'), findsNothing);
      expect(dcKey('decision_action_edit'), findsNothing);
    });

    decisionMatrix('yeni karar formu', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await tapFinder(t, dcKey('decision_new'));
      await _settle(t);
      expect(dcKey('decision_form'), findsOneWidget);
      expect(dcKey('decision_form_date'), findsOneWidget);
      expect(find.text('19.10.2026'), findsOneWidget, reason: 'varsayılan gün bugün (GG.AA.YYYY)');
      expect(dcKey('decision_form_votes_for'), findsOneWidget);
      expect(dcKey('decision_form_visibility'), findsOneWidget);
      expect(find.text('Sakinler de görsün'), findsOneWidget);
    });

    decisionMatrix('kesinleştirme onayı', (t, w, h, s, dark) async {
      final rig = _rig();
      await rig.pump(t, width: w, height: h, scale: s, dark: dark);
      await _openDetail(t, 2);
      await _tapIn(t, dcKey('decision_action_finalize'));
      expect(dcKey('decision_finalize_dialog'), findsOneWidget);
      expect(find.text(kDecisionFinalizeWarning), findsOneWidget);
    });
  });

  group('durumlar', () {
    testWidgets('yükleniyor -> dolu', (t) async {
      final rig = _rig();
      final gate = Completer<void>();
      rig.service.gates['listManaged'] = <Completer<void>>[gate];
      await pumpList(
        t,
        DecisionManagerView(key: rig.key, authService: rig.auth, service: rig.service, sites: _oneSite),
        width: 400,
        height: 2400,
        scale: 1.0,
        dark: false,
      );
      await t.pump();
      expect(find.byType(ListSkeleton), findsOneWidget);
      gate.complete();
      await _settle(t);
      expect(find.byType(DecisionCard), findsNWidgets(4));
    });

    testWidgets('hata: "karar yok" yazmaz; Tekrar Dene', (t) async {
      final rig = _rig();
      rig.service.failures['listManaged'] = <Object>[ApiException('Sunucu yanıt vermedi, tekrar deneyin.')];
      await rig.pump(t);
      expect(dcKey('decision_error'), findsOneWidget);
      expect(find.text('Henüz karar yok.'), findsNothing);
      await tapFinder(t, find.text('Tekrar Dene'));
      await _settle(t);
      expect(find.byType(DecisionCard), findsNWidgets(4));
    });

    testWidgets('boş liste ve modül kapalı (Yeni Karar gizlenir)', (t) async {
      final auth = DecisionFakeAuth();
      final rig = _Rig(FakeDecisionService(authService: auth), auth);
      await rig.pump(t);
      expect(dcKey('decision_empty'), findsOneWidget);
      expect(find.text('Henüz karar yok.'), findsOneWidget);
      rig.service.failures['listManaged'] = <Object>[FakeDecisionService.moduleOff()];
      await rig.key.currentState!.reload();
      await _settle(t);
      expect(dcKey('decision_module_off'), findsOneWidget);
      expect(dcKey('decision_new'), findsNothing);
      expect(dcKey('decision_legal_notice'), findsOneWidget);
    });

    testWidgets('süzgeçler sunucuya gider: durum, toplantı türü, yıl, arama', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await tapFinder(t, dcKey('decision_status_taslak'));
      await _settle(t);
      expect(rig.service.listManagedCalls.last.status, 'taslak');
      expect(find.byType(DecisionCard), findsOneWidget);
      await tapFinder(t, dcKey('decision_status_all'));
      await tapFinder(t, dcKey('decision_type_genel_kurul'));
      await _settle(t);
      expect(rig.service.listManagedCalls.last.type, 'genel_kurul');
      expect(find.byType(DecisionCard), findsOneWidget);
      await tapFinder(t, dcKey('decision_type_all'));
      await _settle(t);
      await tapFinder(t, find.byType(DecisionYearDropdown));
      await _settle(t);
      await t.tap(find.text('2025').last);
      await _settle(t);
      expect(rig.service.listManagedCalls.last.year, 2025);
      expect(find.byType(DecisionCard), findsOneWidget);
      await t.enterText(dcKey('decision_search'), 'aidat');
      await t.pump(const Duration(milliseconds: 400));
      await _settle(t);
      expect(rig.service.listManagedCalls.last.query, 'aidat');
    });

    testWidgets('imleçli sayfalama: "Daha fazla yükle" sonraki sayfayı ekler (opak cursor)', (t) async {
      final rig = _rig();
      rig.service
        ..pageLimit = 2
        ..opaqueCursor = true;
      await rig.pump(t);
      expect(find.byType(DecisionCard), findsNWidgets(2));
      await tapFinder(t, dcKey('decision_more'));
      await _settle(t);
      expect(rig.service.listManagedCalls.last.cursor, const DecisionCursor.opaque('c2'));
      expect(find.byType(DecisionCard), findsNWidgets(4));
      expect(dcKey('decision_more'), findsNothing);
    });

    testWidgets('kurul: salt okur; taslakta bile Düzenle / Sil / Kesinleştir yok', (t) async {
      final rig = _rig(kind: DecisionSiteAccess.board);
      await rig.pump(t, sites: _boardSite);
      expect(dcKey('decision_read_only_note'), findsOneWidget);
      expect(dcKey('decision_new'), findsNothing);
      expect(dcKey('decision_pdf'), findsOneWidget, reason: 'kurul kesin kararların PDF\'ini alabilir');
      await _openDetail(t, 2);
      expect(dcKey('decision_action_finalize'), findsNothing);
      expect(dcKey('decision_action_edit'), findsNothing);
      expect(dcKey('decision_action_delete'), findsNothing);
      await tapFinder(t, dcKey('decision_detail_close'));
      await _settle(t);
      await _openDetail(t, 1);
      expect(dcKey('decision_action_correction'), findsNothing);
    });
  });

  group('kesinleştirme', () {
    testWidgets('güçlü onay: işaretlenmeden düğme kapalı; Vazgeç çağrı yapmaz; onayla numara alır', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openDetail(t, 2);
      await _tapIn(t, dcKey('decision_action_finalize'));
      expect(find.text(kDecisionFinalizeWarning), findsOneWidget);
      expect(t.widget<ElevatedButton>(dcKey('decision_finalize_confirm')).onPressed, isNull);
      await tapFinder(t, dcKey('decision_finalize_cancel'));
      await _settle(t);
      expect(rig.service.finalizeCalls, isEmpty);
      expect(dcKey('decision_finalize_dialog'), findsNothing);

      await _tapIn(t, dcKey('decision_action_finalize'));
      await tapFinder(t, dcKey('decision_finalize_ack'));
      expect(t.widget<ElevatedButton>(dcKey('decision_finalize_confirm')).onPressed, isNotNull);
      await tapFinder(t, dcKey('decision_finalize_confirm'));
      await _settle(t);
      expect(rig.service.finalizeCalls, <int>[2]);
      expect(find.text('Karar kesinleşti: 2026/3.'), findsOneWidget);
      expect(dcKey('decision_action_finalize'), findsNothing);
      expect(dcKey('decision_action_correction'), findsOneWidget);
      await tapFinder(t, dcKey('decision_detail_close'));
      await _settle(t);
      expect(find.text('2026/3'), findsOneWidget, reason: 'liste yenilenir');
    });

    testWidgets('başkası kesinleştirmişse (409 DECISION_FINAL) hata gösterilir ve ayrıntı tazelenir', (t) async {
      final rig = _rig();
      rig.service.failures['finalize'] = <Object>[FakeDecisionService.error(409, 'DECISION_FINAL')];
      await rig.pump(t);
      await _openDetail(t, 2);
      await _tapIn(t, dcKey('decision_action_finalize'));
      await tapFinder(t, dcKey('decision_finalize_ack'));
      await tapFinder(t, dcKey('decision_finalize_confirm'));
      await _settle(t);
      expect(find.textContaining('kesinleşmiş; değiştirilemez'), findsOneWidget);
      expect(rig.service.getManagedCalls, <int>[2, 2]);
    });
  });

  group('taslak işlemleri', () {
    testWidgets('Sil onaylı: pencere kapanır, liste yenilenir', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openDetail(t, 2);
      await _tapIn(t, dcKey('decision_action_delete'));
      await tapFinder(t, find.text('Sil').last);
      await _settle(t);
      expect(rig.service.deleteCalls, <int>[2]);
      expect(dcKey('decision_detail'), findsNothing);
      expect(find.byType(DecisionCard), findsNWidgets(3));
    });

    testWidgets('Düzenle: yalnız değişen alanlar PATCH ile gider', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openDetail(t, 2);
      await _tapIn(t, dcKey('decision_action_edit'));
      expect(find.text('Taslağı Düzenle'), findsOneWidget);
      await t.enterText(dcKey('decision_form_title'), 'Bahçe aydınlatması (LED)');
      await _tapIn(t, dcKey('decision_form_vote_kabul'));
      await _tapIn(t, dcKey('decision_form_visibility'));
      await _tapIn(t, dcKey('decision_form_save'));
      expect(rig.service.updateCalls.single.id, 2);
      expect(rig.service.updateCalls.single.fields, <String, Object?>{
        'title': 'Bahçe aydınlatması (LED)',
        'vote_result': 'kabul',
        'visibility': 'sakinler',
      });
      expect(find.text('Taslak güncellendi.'), findsOneWidget);
      expect(find.text('Bahçe aydınlatması (LED)'), findsWidgets);
    });

    testWidgets('form doğrulaması: boş başlık / metin, geçersiz tarih, oy sınırı; sunucu alan hatası alanın altında', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await tapFinder(t, dcKey('decision_new'));
      await _settle(t);
      await t.enterText(dcKey('decision_form_date'), '31022026');
      await t.enterText(dcKey('decision_form_votes_for'), '200000');
      await _tapIn(t, dcKey('decision_form_save'));
      expect(find.text('Başlık boş olamaz.'), findsOneWidget);
      expect(find.text('Karar metni boş olamaz.'), findsOneWidget);
      expect(find.textContaining('Geçersiz tarih'), findsOneWidget);
      expect(dcKey('decision_form_votes_error'), findsOneWidget);
      expect(rig.service.createCalls, isEmpty);

      await t.enterText(dcKey('decision_form_date'), '01102026');
      await t.enterText(dcKey('decision_form_votes_for'), '4');
      await _fillForm(t);
      rig.service.failures['create'] = <Object>[
        FakeDecisionService.error(400, 'INVALID_FIELD', field: 'title', text: 'Karar başlığı en fazla 160 karakter olabilir.'),
      ];
      await _tapIn(t, dcKey('decision_form_save'));
      expect(dcKey('decision_form_error'), findsOneWidget);
      expect(find.text('Karar başlığı en fazla 160 karakter olabilir.'), findsNWidgets(2), reason: 'üstte ve alanın altında');
      expect(dcKey('decision_form'), findsOneWidget, reason: 'metinler korunur, pencere açık kalır');
    });

    testWidgets('yeni karar: taslak olarak kaydedilir, istek gövdesi doğru', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await tapFinder(t, dcKey('decision_new'));
      await _settle(t);
      await _tapIn(t, dcKey('decision_form_type_genel_kurul'));
      await t.enterText(dcKey('decision_form_date'), '02.10.2026');
      await _fillForm(t);
      await t.enterText(dcKey('decision_form_attendees'), 'Ayşe Yılmaz');
      await t.enterText(dcKey('decision_form_votes_for'), '20');
      await t.enterText(dcKey('decision_form_votes_against'), '3');
      await _tapIn(t, dcKey('decision_form_save'));
      final input = rig.service.createCalls.single.input;
      expect(input.toJson(), <String, dynamic>{
        'meeting_type': 'genel_kurul',
        'meeting_date': '2026-10-02',
        'title': 'Çatı onarımı',
        'body': 'Çatı için teklif alınacak.',
        'attendees': 'Ayşe Yılmaz',
        'vote_result': 'kabul',
        'votes_for': 20,
        'votes_against': 3,
        'visibility': 'yonetim',
      });
      expect(find.textContaining('taslak olarak kaydedildi'), findsOneWidget);
      expect(find.byType(DecisionCard), findsNWidgets(5));
    });
  });

  group('düzeltme kararı', () {
    testWidgets('kesin kararda "Düzeltme kararı yaz": form supersedes_id dolu açılır; kesinleşince eski karar değiştirildi', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openDetail(t, 4);
      await _tapIn(t, dcKey('decision_action_correction'));
      expect(dcKey('decision_detail'), findsNothing);
      expect(dcKey('decision_form'), findsOneWidget);
      expect(find.text('Düzeltme Kararı'), findsOneWidget);
      expect(dcKey('decision_form_supersedes'), findsOneWidget);
      expect(find.textContaining('2025/1 sayılı kararı değiştirir'), findsOneWidget);
      await t.enterText(dcKey('decision_form_date'), '10.10.2026');
      await _fillForm(t, title: 'Aidat artışının yeniden görüşülmesi', body: 'Genel kurul aidat artışını yeniden görüştü.');
      await _tapIn(t, dcKey('decision_form_save'));
      final created = rig.service.createCalls.single.input;
      expect(created.supersedesId, 4);
      expect(created.toJson()['supersedes_id'], 4);
      expect(created.meetingType, DecisionMeetingType.genelKurul, reason: 'tür eski karardan gelir');

      final newId = rig.service.rows.last['id'] as int;
      await _openDetail(t, newId);
      expect(dcKey('decision_open_supersedes'), findsOneWidget);
      expect(find.text('Değiştirdiği karar: 2025/1'), findsOneWidget);
      await _tapIn(t, dcKey('decision_action_finalize'));
      await tapFinder(t, dcKey('decision_finalize_ack'));
      await tapFinder(t, dcKey('decision_finalize_confirm'));
      await _settle(t);
      expect(rig.service.finalizeCalls, <int>[newId]);
      expect(find.text('Karar 2026/3'), findsOneWidget, reason: 'pencere başlığı numarayı gösterir');
      await tapFinder(t, dcKey('decision_detail_close'));
      await _settle(t);
      expect(find.text('2026/3 sayılı kararla değiştirildi'), findsOneWidget);
    });

    testWidgets('bağlantıdan açma: "Değiştirdiği karar" ve "Kararı aç" ilgili kararı üstte açar', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openDetail(t, 3);
      await _tapIn(t, dcKey('decision_open_supersedes'));
      expect(dcKey('decision_detail'), findsNWidgets(2));
      expect(rig.service.getManagedCalls.last, 1);
      expect(dcKey('decision_open_ref_3'), findsOneWidget, reason: 'eski karar yenisine bağlanır');
      await tapFinder(t, dcKey('decision_detail_close').last);
      await _settle(t);
      expect(dcKey('decision_detail'), findsOneWidget);
    });
  });

  group('PDF', () {
    testWidgets('seçili yılın yalnız KESİN kararları teslim edilir', (t) async {
      final requests = <DecisionPdfRequest>[];
      DecisionPdfActions.debugOverride = (r) async {
        requests.add(r);
        return DecisionPdfOutcome.delivered;
      };
      final rig = _rig();
      await rig.pump(t);
      await tapFinder(t, find.byType(DecisionYearDropdown));
      await _settle(t);
      await t.tap(find.text('2026').last);
      await _settle(t);
      await tapFinder(t, dcKey('decision_pdf'));
      await _settle(t);
      final request = requests.single;
      expect(request.year, 2026);
      expect(request.siteName, 'Gül Sitesi');
      expect(request.decisions.map((d) => d.id), <int>[1, 3], reason: 'numara sırası; taslak (2) ve 2025 kararı yok');
      expect(rig.service.listManagedCalls.last.status, 'kesin');
      expect(find.textContaining('2026 yılının 2 kesin kararı PDF olarak hazırlandı.'), findsOneWidget);
    });

    testWidgets('"Tüm yıllar"da yıl sorulur; kesin karar yoksa bilgi notu, PDF üretilmez', (t) async {
      final requests = <DecisionPdfRequest>[];
      DecisionPdfActions.debugOverride = (r) async {
        requests.add(r);
        return DecisionPdfOutcome.delivered;
      };
      final rig = _rig();
      rig.service.rows.add(dcJson(9, date: '2024-05-05', title: 'Eski taslak'));
      await rig.pump(t);
      await tapFinder(t, dcKey('decision_pdf'));
      await _settle(t);
      expect(dcKey('decision_pdf_year_dialog'), findsOneWidget);
      await tapFinder(t, dcKey('decision_pdf_year_2025'));
      await _settle(t);
      expect(requests.single.year, 2025);
      expect(requests.single.decisions.single.id, 4);

      await tapFinder(t, dcKey('decision_pdf'));
      await _settle(t);
      await tapFinder(t, dcKey('decision_pdf_year_2024'));
      await _settle(t);
      expect(requests, hasLength(1));
      expect(dcKey('decision_pdf_notice'), findsOneWidget);
      expect(find.textContaining('2024 yılında kesinleşmiş karar yok'), findsOneWidget);
    });

    testWidgets('PDF hatası pencerede gösterilir', (t) async {
      DecisionPdfActions.debugOverride = (r) async => throw ApiException('Dosya kaydedilemedi.');
      final rig = _rig();
      await rig.pump(t);
      await tapFinder(t, find.byType(DecisionYearDropdown));
      await _settle(t);
      await t.tap(find.text('2025').last);
      await _settle(t);
      await tapFinder(t, dcKey('decision_pdf'));
      await _settle(t);
      expect(find.text('Dosya kaydedilemedi.'), findsOneWidget);
    });
  });

  group('form kapanışı ve uzunluk', () {
    testWidgets('kaydedilmemiş değişiklik: Vazgeç onay sorar; "Yazmaya Dön" açık tutar, "Vazgeç ve Kapat" kapatır', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await tapFinder(t, dcKey('decision_new'));
      await _settle(t);
      // Değişiklik yokken soru sorulmaz.
      await _tapIn(t, dcKey('decision_form_cancel'));
      expect(dcKey('decision_form'), findsNothing);
      expect(find.text('Değişiklikler silinsin mi?'), findsNothing);

      await tapFinder(t, dcKey('decision_new'));
      await _settle(t);
      await t.enterText(dcKey('decision_form_title'), 'Yarım kalan karar');
      await _tapIn(t, dcKey('decision_form_cancel'));
      expect(find.text('Değişiklikler silinsin mi?'), findsOneWidget);
      await tapFinder(t, dcKey('decision_form_keep'));
      await _settle(t);
      expect(dcKey('decision_form'), findsOneWidget);
      expect(find.text('Yarım kalan karar'), findsOneWidget, reason: 'yazılan korunur');

      // Geri tuşu (sistem geri) da aynı soruyu sorar.
      await t.binding.handlePopRoute();
      await _settle(t);
      expect(find.text('Değişiklikler silinsin mi?'), findsOneWidget);
      await tapFinder(t, dcKey('decision_form_discard'));
      await _settle(t);
      expect(dcKey('decision_form'), findsNothing);
      expect(rig.service.createCalls, isEmpty);
    });

    testWidgets('düzenlemede yalnız seçim değişse de sorar; değişiklik geri alınınca sormaz', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await _openDetail(t, 2);
      await _tapIn(t, dcKey('decision_action_edit'));
      await _tapIn(t, dcKey('decision_form_vote_kabul'));
      await _tapIn(t, dcKey('decision_form_cancel'));
      expect(find.text('Değişiklikler silinsin mi?'), findsOneWidget);
      await tapFinder(t, dcKey('decision_form_keep'));
      await _settle(t);
      await _tapIn(t, dcKey('decision_form_vote_ertelendi'));
      await _tapIn(t, dcKey('decision_form_cancel'));
      expect(find.text('Değişiklikler silinsin mi?'), findsNothing);
      expect(dcKey('decision_form'), findsNothing);
      expect(rig.service.updateCalls, isEmpty);
    });

    testWidgets('uzunluk kod noktasıyla sayılır: 160 emoji başlık geçer, 161 reddedilir; sessiz kırpma yok', (t) async {
      final rig = _rig();
      await rig.pump(t);
      await tapFinder(t, dcKey('decision_new'));
      await _settle(t);
      final emoji = String.fromCharCode(0x1F3E0);
      await t.enterText(dcKey('decision_form_title'), emoji * 161);
      await t.enterText(dcKey('decision_form_body'), 'Metin');
      await t.pump();
      expect(find.text('161/160'), findsOneWidget, reason: 'UTF-16 birimiyle 322 sayılırdı');
      await _tapIn(t, dcKey('decision_form_save'));
      expect(find.text('Başlık en çok 160 karakter olabilir.'), findsOneWidget);
      expect(rig.service.createCalls, isEmpty);
      await t.enterText(dcKey('decision_form_title'), emoji * 160);
      await _tapIn(t, dcKey('decision_form_save'));
      expect(rig.service.createCalls.single.input.title.runes.length, 160);
    });
  });

  group('toplantı tarihi gelmemiş taslak', () {
    testWidgets('istemci: onay açılmadan uyarır, istek gitmez', (t) async {
      final rig = _rig();
      rig.service.rows.add(dcJson(20, date: '2026-12-01', title: 'Yılbaşı toplantısı kararı'));
      await rig.pump(t);
      await _openDetail(t, 20);
      await _tapIn(t, dcKey('decision_action_finalize'));
      expect(dcKey('decision_finalize_dialog'), findsNothing);
      expect(find.textContaining('Toplantı tarihi gelmemiş karar kesinleştirilemez.'), findsOneWidget);
      expect(rig.service.finalizeCalls, isEmpty);
    });

    testWidgets('sunucu 409 DECISION_MEETING_IN_FUTURE: Türkçe metin; karar taslak kalır', (t) async {
      final rig = _rig();
      rig.service.failures['finalize'] = <Object>[FakeDecisionService.error(409, 'DECISION_MEETING_IN_FUTURE')];
      await rig.pump(t);
      await _openDetail(t, 2);
      await _tapIn(t, dcKey('decision_action_finalize'));
      await tapFinder(t, dcKey('decision_finalize_ack'));
      await tapFinder(t, dcKey('decision_finalize_confirm'));
      await _settle(t);
      expect(find.text('Toplantı tarihi gelmemiş karar kesinleştirilemez.'), findsOneWidget);
      expect(dcKey('decision_action_finalize'), findsOneWidget, reason: 'taslak eylemleri yerinde');
    });
  });
}
