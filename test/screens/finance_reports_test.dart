// Platform Faz 4b, Ö5: "Raporlar" sekmesi — yaşlandırma, gelir-gider, kasa durumu, daire ekstresi, kurul özeti.
//
// Taşma matrisi x açık-koyu; yükleniyor / hata / dolu / boş; hata asla "borç yok / 0" demez ve eski rakamı bırakmaz;
// süzgeç değişince PDF / dışa aktarma kapanır (bayat rapor yok); PDF ve dosya UYGULANMIŞ süzgeçle; kurul yalnız kurul
// özeti PDF'ini basar ve dosya dışa aktaramaz; kesinleşmemiş ay işareti; ekran okuyucu etiketleri.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart' show ExportFormat;
import 'package:site_kapi_kontrol/models/report_models.dart' show AgingItem;
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/buttons.dart' show PrimaryActionButton;
import 'package:site_kapi_kontrol/ui/helpers/finance_4b_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/finance_reports_tab.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart' show ExportSource;
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show ListSkeleton;

import 'dialog_layout_harness.dart';
import 'finance_4b_fixtures.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show pumpList;

final DateTime _now = DateTime.utc(2026, 10, 16, 9);

PeopleScope _scope(FinanceFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

final List<List<ExportSource>> _launched = <List<ExportSource>>[];
final List<FinancePdfRequest> _pdfs = <FinancePdfRequest>[];

Future<void> _pump(
  WidgetTester t,
  FinanceFakeAuth auth, {
  bool canWrite = true,
  String report = 'aging',
  double width = 400,
  double height = 3000,
  double scale = 1.0,
  bool dark = false,
}) async {
  await pumpList(
    t,
    FinanceReportsTab(
      scope: _scope(auth, canWrite: canWrite),
      now: () => _now,
      exportLauncher: (context, sources) async => _launched.add(sources),
    ),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  if (report != 'aging') {
    await f4Tap(t, 'finance_report_chip_$report');
    await settleFor(t);
  }
}

void main() {
  setUp(() {
    _launched.clear();
    _pdfs.clear();
    FinancePdfActions.debugOverride = (request) async => _pdfs.add(request);
  });

  tearDown(() => FinancePdfActions.debugOverride = null);

  group('rapor ekranları: taşma matrisi', () {
    f4Matrix('yaşlandırma: dolu', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_aging_totals')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('aging_item_301')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_report_meta')), findsOneWidget);
      for (final key in const ['finance_report_pdf_print', 'finance_report_pdf_share', 'finance_report_export']) {
        await scrollTo(t, find.byKey(ValueKey<String>(key)));
        expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
      }
    });

    f4Matrix('gelir-gider: dolu (kesinleşmiş / kesinleşmemiş ay)', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, report: 'income_expense', width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_ie_month_2026-09')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_ie_month_2026-10')), findsOneWidget);
      expect(find.text('Kapalı'), findsOneWidget);
      expect(find.text('Açık'), findsOneWidget);
      expect(find.text('Gider kategorileri'), findsOneWidget);
    });

    f4Matrix('kasa durumu: dolu + eşlenmemiş uyarısı', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      auth.f4.cashPositionJson = f4CashPositionJson(unassignedCount: 2);
      await _pump(t, auth, report: 'cash_position', width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_cash_report_unassigned')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_cash_report_1')), findsOneWidget);
      expect(find.text('Düzeltme'), findsOneWidget, reason: 'düzeltme hareketleri ayrı satır');
    });

    f4Matrix('daire ekstresi: seçim -> getir -> satırlar ve kayan bakiye', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, report: 'statement', width: w, height: h, scale: s, dark: dark);
      expect(find.textContaining('Bir daire seçip'), findsOneWidget);
      await f4Tap(t, 'finance_statement_apartment');
      await settleFor(t);
      await f4TapInDialog(t, 'A Blok - 5');
      await settleFor(t);
      await f4Tap(t, 'finance_report_fetch');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_statement_summary')), findsOneWidget);
      expect(find.textContaining('Bakiye:'), findsWidgets);
    });

    f4Matrix('kurul özeti: bölümler, uyarılar, borçlu listesi anahtarı', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, report: 'board_summary', width: w, height: h, scale: s, dark: dark);
      expect(find.byKey(const ValueKey<String>('finance_board_warnings')), findsOneWidget);
      for (final key in const ['collection', 'receivables', 'expenses', 'cash', 'late_fee', 'reminders']) {
        expect(find.byKey(ValueKey<String>('finance_board_$key')), findsOneWidget, reason: key);
      }
      expect(find.byKey(const ValueKey<String>('finance_board_debtor_list')), findsOneWidget);
    });

    f4Matrix('yükleniyor ve hata durumları (yaşlandırma)', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      auth.f4.reportGate = Completer<void>();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      expect(find.byType(ListSkeleton), findsWidgets);
      expect(find.byKey(const ValueKey<String>('finance_aging_totals')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_aging_empty')), findsNothing);
      auth.f4.reportError = ApiException('x', statusCode: 500);
      auth.f4.reportGate!.complete();
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_report_error')), findsOneWidget);
      expect(find.text('Tekrar Dene'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_aging_totals')), findsNothing, reason: 'hata asla sıfır toplam göstermez');
    });
  });

  group('yaşlandırma', () {
    testWidgets('varsayılan: bugün + yalnız borçlu; toplamlar sunucudan (kova etiketleriyle)', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      final call = auth.f4.reportCalls.first;
      expect(call['name'], 'getAgingReport');
      expect(call['as_of'], '2026-10-16');
      expect(call['status'], 'debtor');
      expect(call['limit'], 200);
      expect(find.text('Vadesi gelmemiş'), findsOneWidget);
      expect(find.text('366 gün ve üzeri'), findsOneWidget);
      expect(find.text('Vadesi geçmiş toplam'), findsOneWidget);
      expect(find.text('Daireler (2)'), findsOneWidget);
    });

    testWidgets('süzgeç değişince PDF ve Dışa Aktar KAPANIR; "Raporu Getir" sonrası açılır; yeni süzgeç sorguda', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      expect(t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('finance_report_pdf_print'))).onPressed, isNotNull);
      await f4Tap(t, 'finance_aging_status_all');
      expect(find.byKey(const ValueKey<String>('finance_report_stale')), findsOneWidget);
      for (final key in const ['finance_report_pdf_print', 'finance_report_pdf_share', 'finance_report_export']) {
        expect(t.widget<PrimaryActionButton>(find.byKey(ValueKey<String>(key))).onPressed, isNull, reason: key);
      }
      await f4Tap(t, 'finance_report_fetch');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_report_stale')), findsNothing);
      expect(auth.f4.reportCalls.last['status'], 'all');
      expect(t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('finance_report_pdf_print'))).onPressed, isNotNull);
    });

    testWidgets('tarih doğrulaması: gelecek / bozuk tarih istek göndermez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      final before = auth.f4.reportCalls.length;
      await f4Enter(t, 'finance_aging_as_of', '01.01.2099');
      await f4Tap(t, 'finance_report_fetch');
      expect(find.text('Rapor tarihi bugünden ileri olamaz.'), findsOneWidget);
      expect(auth.f4.reportCalls.length, before, reason: 'geçersiz süzgeçle istek gönderilmez');
      // Önceki (uygulanmış) rapor ekranda kalır ama "süzgeçler değişti" notuyla; PDF / dışa aktarma kapalıdır.
      expect(find.byKey(const ValueKey<String>('finance_report_stale')), findsOneWidget);
      expect(t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('finance_report_pdf_print'))).onPressed, isNull);
    });

    testWidgets('hata: eski rakamlar silinir; REPORT_BUSY bekleme süresini söyler ve düğmeyi geçici kilitler', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_aging_totals')), findsOneWidget);
      auth.f4.reportError = ApiException('x', statusCode: 503, code: 'REPORT_BUSY', retryAfterSeconds: 6);
      await f4Tap(t, 'finance_report_fetch');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_aging_totals')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_report_error')), findsOneWidget);
      // R13 P2-12: REPORT_BUSY düğmeyi bekleme süresince KİLİTLER (üstteki doküman yorumu bunu vaat ediyordu).
      expect(t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('finance_report_fetch'))).onPressed, isNull);
      auth.f4.reportError = null;
      await t.pump(const Duration(seconds: 7));
      expect(t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('finance_report_fetch'))).onPressed, isNotNull);
      await f4Tap(t, 'finance_report_fetch');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_aging_totals')), findsOneWidget);
    });

    testWidgets('429 sonrası getir düğmesi geçici kilitli, süre dolunca açılır', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      auth.f4.reportError = ApiException('x', statusCode: 429, retryAfterSeconds: 5);
      await f4Tap(t, 'finance_report_fetch');
      await settleFor(t);
      expect(find.textContaining('Çok sık deneme yapıldı'), findsOneWidget);
      expect(t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('finance_report_fetch'))).onPressed, isNull);
      auth.f4.reportError = null;
      await t.pump(const Duration(seconds: 6));
      expect(t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('finance_report_fetch'))).onPressed, isNotNull);
    });

    testWidgets('sayfalama: Daha fazla göster; PDF TÜM daireleri okur (yalnız ekrandaki sayfayı değil)', (t) async {
      final auth = FinanceFakeAuth.seeded();
      auth.f4.agingJson = f4AgingJson(items: 3);
      auth.f4.agingJson['all_items'] = <Map<String, dynamic>>[
        for (var i = 1; i <= 450; i++)
          <String, dynamic>{
            'apartment_id': 1000 + i,
            'label': 'Daire $i',
            'block_name': 'B',
            ...(f4AgingJson(items: 1)['items'] as List).first as Map<String, dynamic>,
          }..['apartment_id'] = 1000 + i,
      ];
      await _pump(t, auth);
      expect(find.text('Daireler (450)'), findsOneWidget);
      await f4Tap(t, 'finance_report_pdf_print');
      await settleFor(t);
      final aging = auth.f4.reportCalls.where((c) => c['name'] == 'getAgingReport').toList();
      expect(aging.map((c) => c['offset']), <Object?>[0, 200, 400], reason: 'PDF için eksik sayfalar tamamlandı');
      expect(_pdfs.single.kind, 'aging');
      expect(_pdfs.single.share, isFalse);
    });

    test('R13 P2-7: mergeAgingItems daire kimliğine göre tekilleştirir (kayan sayfada aynı daire iki kez gelse bile)', () {
      AgingItem item(int id) => AgingItem.fromJson(<String, dynamic>{...((f4AgingJson(items: 1)['items'] as List).first as Map<String, dynamic>), 'apartment_id': id});
      final merged = mergeAgingItems(<AgingItem>[item(1), item(2)], <AgingItem>[item(2), item(3), item(3)]);
      expect(merged.map((i) => i.apartmentId), <int>[1, 2, 3]);
    });

    testWidgets('R13 P2-7: "Daha fazla" yüklenirken "Raporu Getir" KAPALI (eski süzgeçli sayfa yeni rapora karışmaz); sayfa eklenir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      auth.f4.agingJson = f4AgingJson(items: 3);
      auth.f4.agingJson['all_items'] = <Map<String, dynamic>>[
        for (var i = 1; i <= 450; i++)
          <String, dynamic>{...(f4AgingJson(items: 1)['items'] as List).first as Map<String, dynamic>, 'apartment_id': 1000 + i, 'label': 'Daire $i'},
      ];
      await _pump(t, auth);
      auth.f4.reportGate = Completer<void>();
      await f4Tap(t, 'finance_aging_more');
      await t.pump();
      expect(t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('finance_report_fetch'))).onPressed, isNull, reason: 'sayfa yüklenirken yenileme kapalı');
      auth.f4.reportGate!.complete();
      auth.f4.reportGate = null;
      await settleFor(t);
      expect(find.text('Daha fazla göster (50)'), findsOneWidget, reason: '400 satır yüklendi, 50 kaldı');
      expect(t.widget<PrimaryActionButton>(find.byKey(const ValueKey<String>('finance_report_fetch'))).onPressed, isNotNull);
    });

    testWidgets('boş: "vadesi geçmiş borç yok" yalnız sunucu gerçekten boş dönünce', (t) async {
      final auth = FinanceFakeAuth.seeded();
      auth.f4.agingJson = f4AgingJson(items: 0);
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_aging_empty')), findsOneWidget);
    });

    testWidgets('dışa aktarma: UYGULANMIŞ süzgeçle finance_aging kaynağı; format denetim için gider', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await f4Tap(t, 'finance_report_export');
      final source = _launched.single.single;
      expect(source.label, 'Yaşlandırma');
      expect(source.filterSummary, contains('16.10.2026'));
      final envelope = await source.fetch(ExportFormat.csv);
      expect(envelope.kind, 'finance_aging');
      expect(auth.f4.exportCalls.single, <String, Object?>{
        'kind': 'finance_aging',
        'as_of': '2026-10-16',
        'status': 'debtor',
        'format': 'csv',
      });
    });

    testWidgets('kurul: rakamları okur; PDF ve dışa aktarma düğmesi YOK', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, canWrite: false);
      expect(find.byKey(const ValueKey<String>('finance_aging_totals')), findsOneWidget);
      for (final key in const ['finance_report_pdf_print', 'finance_report_pdf_share', 'finance_report_export']) {
        expect(find.byKey(ValueKey<String>(key)), findsNothing, reason: key);
      }
    });

    testWidgets('PDF hatası ekranda gösterilir; kapanış yoksa "kesinleşmemiştir" uyarısı', (t) async {
      final auth = FinanceFakeAuth.seeded();
      auth.f4.agingJson = f4AgingJson(closedThrough: null);
      FinancePdfActions.debugOverride = (_) async => throw StateError('pdf');
      await _pump(t, auth);
      expect(find.textContaining('Henüz kapatılmış ay yok.'), findsOneWidget);
      await f4Tap(t, 'finance_report_pdf_share');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_report_output_error')), findsOneWidget);
      expect(find.text('PDF hazırlanamadı. Tekrar deneyin.'), findsOneWidget);
    });

    testWidgets('ekran okuyucu: toplamlar "bin ... lira" okunuşuyla, daire kartı tek etiketle', (t) async {
      final handle = t.ensureSemantics();
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      expect(find.bySemanticsLabel(RegExp(r'Vadesi geçmiş toplam: .*lira')), findsWidgets);
      expect(
        find.bySemanticsLabel(RegExp('Daire: .*A Blok - 1.*Vadesi geçmiş toplam: .*yüz elli lira')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('gelir-gider', () {
    testWidgets('varsayılan: son 12 ay; ay düğmeleri aralığı değiştirir; sınır ve doğrulama', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, report: 'income_expense');
      expect(auth.f4.reportCalls.last['from'], '2025-11');
      expect(auth.f4.reportCalls.last['to'], '2026-10');
      expect(t.widget<IconButton>(find.byKey(const ValueKey<String>('finance_ie_to_next'))).onPressed, isNull, reason: 'gelecek ay seçilemez');
      await f4Tap(t, 'finance_ie_from_prev');
      expect(find.text('Ekim 2025'), findsOneWidget);
      await f4Tap(t, 'finance_ie_from_prev');
      await f4Tap(t, 'finance_ie_from_prev');
      await f4Tap(t, 'finance_report_fetch');
      expect(find.text('Rapor en çok 36 ay olabilir. Dönemi daraltın.'), findsNothing, reason: '15 ay');
      // 36 ayı aşan aralık
      for (var i = 0; i < 24; i++) {
        await t.tap(find.byKey(const ValueKey<String>('finance_ie_from_prev')));
        await t.pump();
      }
      await f4Tap(t, 'finance_report_fetch');
      expect(find.text('Rapor en çok 36 ay olabilir. Dönemi daraltın.'), findsOneWidget);
    });

    testWidgets('toplamlar aylardan, oranı olmayan ay "-"; dışa aktarma kaynağı finance_income_expense', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, report: 'income_expense');
      expect(find.text('Dönem toplamı'), findsOneWidget);
      expect(find.text('-'), findsOneWidget, reason: 'tahakkuku 0 olan ayın oranı');
      expect(find.text('%80,00'), findsOneWidget);
      await f4Tap(t, 'finance_report_export');
      final source = _launched.single.single;
      await source.fetch(ExportFormat.xlsx);
      expect(auth.f4.exportCalls.single['kind'], 'finance_income_expense');
      expect(auth.f4.exportCalls.single['from'], '2025-11');
      expect(auth.f4.exportCalls.single['to'], '2026-10');
    });

    testWidgets('PDF yazdır / paylaş', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, report: 'income_expense');
      await f4Tap(t, 'finance_report_pdf_print');
      await f4Tap(t, 'finance_report_pdf_share');
      expect(_pdfs.map((r) => (r.kind, r.share)), <(String, bool)>[('income_expense', false), ('income_expense', true)]);
    });
  });

  group('kasa durumu', () {
    testWidgets('tarih süzgeci sorguya yazılır; mutabakat farkı uyarı renginde; PDF + dışa aktarma', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, report: 'cash_position');
      expect(auth.f4.reportCalls.last['as_of'], '2026-10-16');
      expect(find.textContaining('Son mutabakat 01.10.2026: fark -5,00 ₺'), findsOneWidget);
      await f4Tap(t, 'finance_report_export');
      await _launched.single.single.fetch(ExportFormat.csv);
      expect(auth.f4.exportCalls.single['kind'], 'finance_cash_position');
      await f4Tap(t, 'finance_report_pdf_print');
      expect(_pdfs.single.kind, 'cash_position');
    });

    testWidgets('hata: toplam bakiye gösterilmez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      auth.f4.reportError = ApiException('x', statusCode: 500);
      await _pump(t, auth, report: 'cash_position');
      expect(find.byKey(const ValueKey<String>('finance_cash_report_total')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_report_error')), findsOneWidget);
    });
  });

  group('daire ekstresi', () {
    Future<void> pick(WidgetTester t) async {
      await f4Tap(t, 'finance_statement_apartment');
      await settleFor(t);
      await f4TapInDialog(t, 'A Blok - 5');
      await settleFor(t);
    }

    testWidgets('daire seçmeden getirilemez; seçince tarih aralığı ve daire sorguya yazılır', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, report: 'statement');
      expect(auth.f4.reportCalls.where((c) => c['name'] == 'getApartmentStatement'), isEmpty, reason: 'otomatik yükleme yok');
      await f4Tap(t, 'finance_report_fetch');
      expect(find.text('Önce bir daire seçin.'), findsOneWidget);
      expect(auth.f4.reportCalls.where((c) => c['name'] == 'getApartmentStatement'), isEmpty);
      await pick(t);
      await f4Tap(t, 'finance_report_fetch');
      await settleFor(t);
      final call = auth.f4.reportCalls.firstWhere((c) => c['name'] == 'getApartmentStatement');
      expect(call['apartment_id'], 301);
      expect(call['from'], '2026-01-01');
      expect(call['to'], '2026-10-16');
    });

    testWidgets('tarih sırası ve gelecek tarih reddedilir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, report: 'statement');
      await pick(t);
      await f4Enter(t, 'finance_statement_from', '01.12.2026');
      await f4Tap(t, 'finance_report_fetch');
      expect(find.text('Başlangıç tarihi bitiş tarihinden sonra olamaz.'), findsOneWidget);
      await f4Enter(t, 'finance_statement_from', '01.01.2026');
      await f4Enter(t, 'finance_statement_to', '01.01.2099');
      await f4Tap(t, 'finance_report_fetch');
      expect(find.text('Bitiş tarihi bugünden ileri olamaz.'), findsOneWidget);
    });

    testWidgets('STATEMENT_TOO_LARGE açık Türkçe mesaj; boş ekstre "hareket yok"', (t) async {
      final auth = FinanceFakeAuth.seeded();
      auth.f4.reportError = f4Coded('STATEMENT_TOO_LARGE', 409);
      await _pump(t, auth, report: 'statement');
      await pick(t);
      await f4Tap(t, 'finance_report_fetch');
      await settleFor(t);
      expect(find.text('Ekstre çok uzun (5.000 satırdan fazla). Tarih aralığını daraltın.'), findsOneWidget);
      auth.f4.reportError = null;
      auth.f4.statementJson = f4StatementJson(rows: 0);
      await f4Tap(t, 'finance_report_fetch');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_statement_empty')), findsOneWidget);
    });

    testWidgets('satırlar parça parça gösterilir; PDF ve dışa aktarma (finance_statement) uygulanmış süzgeçle', (t) async {
      final auth = FinanceFakeAuth.seeded();
      auth.f4.statementJson = f4StatementJson(rows: 120);
      await _pump(t, auth, report: 'statement');
      await pick(t);
      await f4Tap(t, 'finance_report_fetch');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_statement_more')), findsOneWidget);
      await f4Tap(t, 'finance_statement_more');
      await f4Tap(t, 'finance_report_export');
      final source = _launched.single.single;
      expect(source.filterSummary, contains('A Blok - 5'));
      await source.fetch(ExportFormat.xlsx);
      expect(auth.f4.exportCalls.single, <String, Object?>{
        'kind': 'finance_statement',
        'apartment_id': '301',
        'from': '2026-01-01',
        'to': '2026-10-16',
        'format': 'xlsx',
      });
      await f4Tap(t, 'finance_report_pdf_print');
      expect(_pdfs.single.kind, 'statement');
    });
  });

  group('kurul özeti', () {
    testWidgets('yönetici: borçlu listesi anahtarı kapalıyken liste istenmez; açıkken istenir ve görünür', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, report: 'board_summary');
      expect(auth.f4.reportCalls.last['debtors'], false);
      expect(find.byKey(const ValueKey<String>('finance_board_debtors')), findsNothing);
      await f4Tap(t, 'finance_board_debtor_list');
      expect(find.byKey(const ValueKey<String>('finance_report_stale')), findsOneWidget);
      await f4Tap(t, 'finance_report_fetch');
      await settleFor(t);
      expect(auth.f4.reportCalls.last['debtors'], true);
      expect(find.byKey(const ValueKey<String>('finance_board_debtors')), findsOneWidget);
      expect(find.text('A Blok - 5'), findsWidgets);
    });

    testWidgets('R13 P1-1: hesabı olan sitede kurul özeti AÇILIR (sunucu biçimi: hesap satırında yalnız bakiye); hata kutusu yok', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, report: 'board_summary');
      expect(find.byKey(const ValueKey<String>('finance_report_error')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_board_cash')), findsOneWidget);
      expect(find.text('Nakit Kasa'), findsOneWidget);
      expect(find.text('2.495,00 ₺'), findsWidgets);
    });

    testWidgets('R13 P1-2: borçlu listesi açıkken rapor düşmez; satırlar vadesi geçmiş borcu gösterir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, report: 'board_summary');
      await f4Tap(t, 'finance_board_debtor_list');
      await f4Tap(t, 'finance_report_fetch');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('finance_report_error')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_board_debtors')), findsOneWidget);
      expect(find.text('1.500,00 ₺'), findsWidgets);
    });

    testWidgets('R13 P1-3: "Toplam borç" DEĞİL "Vadesi geçmiş borç"; vadesi gelmemiş ayrı bilgi satırı; okunan adlar doğru', (t) async {
      final handle = t.ensureSemantics();
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, report: 'board_summary');
      expect(find.text('Toplam borç'), findsNothing);
      expect(find.text('Vadesi geçmiş borç'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_board_not_due')), findsOneWidget);
      expect(find.textContaining('Vadesi gelmemiş (bilgi, toplama dahil değil) (3 daire)'), findsOneWidget);
      // Vadesi geçmiş satırlar (0-30, 31-60) toplam 11.000 TL; vadesi gelmemiş 4.000 TL ayrıdır.
      expect(find.bySemanticsLabel(RegExp('Vadesi geçmiş borç: on bir bin lira')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Vadesi gelmemiş .bilgi.*: dört bin lira')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('R14: mutabakat farkı ekran okuyucuda sayı yığını değil lira olarak okunur (kurul özeti)', (t) async {
      final handle = t.ensureSemantics();
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, report: 'board_summary');
      final labels = find.bySemanticsLabel(RegExp('^Son mutabakat farkı'));
      expect(labels, findsOneWidget);
      final label = t.getSemantics(labels).label;
      expect(label, contains('lira'));
      expect(label, isNot(contains('25,00')));
      handle.dispose();
    });

    testWidgets('kurul üyesi: borçlu listesi anahtarı YOK; PDF "Yönetim Kuruluna Sun"; dışa aktarma YOK', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, canWrite: false, report: 'board_summary');
      expect(find.byKey(const ValueKey<String>('finance_board_debtor_list')), findsNothing);
      expect(auth.f4.reportCalls.last['debtors'], false);
      expect(find.text('Yönetim Kuruluna Sun (PDF)'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_report_export')), findsNothing);
      await f4Tap(t, 'finance_report_pdf_print');
      expect(_pdfs.single.kind, 'board_summary');
    });

    testWidgets('yönetici: kurul özetinde de dışa aktarma YOK (bölümlü rapor yalnız ekran + PDF)', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, report: 'board_summary');
      expect(find.byKey(const ValueKey<String>('finance_report_export')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_report_pdf_print')), findsOneWidget);
    });

    testWidgets('yanıtta olmayan bölüm ÇİZİLMEZ (uydurma sıfır yok)', (t) async {
      final auth = FinanceFakeAuth.seeded();
      auth.f4.boardJson = <String, dynamic>{...f4BoardJson()}
        ..remove('expenses')
        ..remove('cash')
        ..remove('reminders');
      await _pump(t, auth, report: 'board_summary');
      expect(find.byKey(const ValueKey<String>('finance_board_expenses')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_board_cash')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_board_collection')), findsOneWidget);
    });

    testWidgets('kurul üyesi diğer raporlarda PDF / dışa aktarma göremez', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, canWrite: false, report: 'income_expense');
      expect(find.byKey(const ValueKey<String>('finance_report_pdf_print')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_report_export')), findsNothing);
      expect(find.byKey(const ValueKey<String>('finance_ie_totals')), findsOneWidget);
    });
  });

  testWidgets('rapor türü değişince önceki raporun verisi gösterilmez; yenile düğmesi raporu yeniden yükler', (t) async {
    final auth = FinanceFakeAuth.seeded();
    await _pump(t, auth);
    expect(find.byKey(const ValueKey<String>('finance_aging_totals')), findsOneWidget);
    await f4Tap(t, 'finance_report_chip_cash_position');
    await settleFor(t);
    expect(find.byKey(const ValueKey<String>('finance_aging_totals')), findsNothing);
    final before = auth.f4.callCount('getCashPositionReport');
    await f4Tap(t, 'finance_reports_refresh');
    await settleFor(t);
    expect(auth.f4.callCount('getCashPositionReport'), before + 1);
  });

  testWidgets('hata kutusu InlineNotice kullanır ve teknik ifade sızdırmaz', (t) async {
    final auth = FinanceFakeAuth.seeded();
    auth.f4.reportError = ApiException('İşlem başarısız (502)', statusCode: 502, genericFallback: true);
    await _pump(t, auth);
    expect(find.byType(InlineNotice), findsOneWidget);
    expect(find.textContaining('502'), findsNothing);
    expect(find.text('Rapor alınamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.'), findsOneWidget);
  });
}
