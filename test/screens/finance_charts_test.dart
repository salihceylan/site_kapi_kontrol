// Finans > Grafikler sekmesi: beş grafik kartı (aylık gelir-gider, aidat tahsilatı, kasa + banka seyri, gider kategorileri, geciken
// borç yaşlandırması), "Tablo olarak göster" eşdeğeri, kayıt yok durumu, hata (asla "kayıt yok / 0" demez), erişilebilirlik ve
// taşma matrisi (320 dp x 2,0 dahil, açık + koyu tema).
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/finance_charts.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/finance_charts_tab.dart';
import 'package:site_kapi_kontrol/ui/widgets/finance_charts_parts.dart';

import 'finance_4b_fixtures.dart';
import 'finance_4b_harness.dart';
import 'finance_fixtures.dart';
import 'list_fixtures.dart' show pumpList, tapFinder;
import 'dialog_layout_harness.dart' show settleFor;

PeopleScope _scope(FinanceFakeAuth auth, {bool canWrite = true}) =>
    PeopleScope(authService: auth, siteCode: 11, siteName: 'Gül Sitesi', canWrite: canWrite);

Future<void> _pump(
  WidgetTester t,
  FinanceFakeAuth auth, {
  bool canWrite = true,
  double width = 400,
  double height = 3000,
  double scale = 1.0,
  bool dark = false,
  bool reduce = false,
  GlobalKey<FinanceChartsTabState>? key,
}) async {
  await pumpList(
    t,
    FinanceChartsTab(key: key, scope: _scope(auth, canWrite: canWrite)),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
    reduce: reduce,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
}

const List<String> _ids = <String>['income_expense', 'collection', 'cash', 'categories', 'aging'];

Finder _card(String id) => find.byKey(ValueKey<String>('finance_chart_card_$id'));
Finder _chart(String id) => find.byKey(ValueKey<String>('finance_chart_$id'));
Finder _table(String id) => find.byKey(ValueKey<String>('finance_chart_table_$id'));
Finder _switch(String id) => find.byKey(ValueKey<String>('finance_chart_table_switch_$id'));
Finder _empty(String id) => find.byKey(ValueKey<String>('finance_chart_empty_$id'));

/// Yanıt gelip kartlar kurulana dek 1 ms'lik adımlarla ilerler (giriş animasyonu henüz ilk karesindedir).
Future<void> _pumpUntilCards(WidgetTester t) async {
  for (var i = 0; i < 100 && _card('aging').evaluate().isEmpty; i++) {
    await t.pump(const Duration(milliseconds: 1));
  }
  expect(_card('aging'), findsOneWidget);
}

BarChartData _barData(WidgetTester t, String id) =>
    t.widget<BarChart>(find.descendant(of: _chart(id), matching: find.byType(BarChart)).first).data;

LineChartData _lineData(WidgetTester t, String id) =>
    t.widget<LineChart>(find.descendant(of: _chart(id), matching: find.byType(LineChart)).first).data;

/// 'Eylül 2026' çubuğu (gelir): fixture'da 1.000.000 kuruş = 10.000 lira.
double _incomeBar(WidgetTester t) => _barData(t, 'income_expense').barGroups[10].barRods.first.toY;

String _agingFirstAmount(WidgetTester t) => t
    .widget<Text>(find.descendant(of: find.byKey(const ValueKey<String>('finance_chart_aging_0')), matching: find.textContaining('₺')))
    .data!;

void main() {
  group('Grafikler: giriş animasyonu', () {
    testWidgets('çubuklar alttan büyür, çizgi soldan çizilir, tutar sıfırdan sayar; bitince son değer; tablo dönüşünde yeniden oynamaz', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await pumpList(t, FinanceChartsTab(scope: _scope(auth)), width: 400, height: 3000, scale: 1.0, dark: false);
      await _pumpUntilCards(t);
      // İlk kare: her şey sıfırdan başlar.
      expect(_incomeBar(t), 0);
      expect(_barData(t, 'income_expense').maxY, greaterThan(0), reason: 'eksen son değere sabit, çubuk büyür');
      expect(_lineData(t, 'cash').lineBarsData, isEmpty, reason: 'ilk iki ay boş: çizgi henüz yok');
      expect(_lineData(t, 'collection').lineBarsData.single.spots.length, lessThan(12));
      expect(_agingFirstAmount(t), '0,00 ₺ · %0');
      // Ortada: çubuk büyümüş ama tam değil.
      await t.pump(const Duration(milliseconds: 300));
      expect(_incomeBar(t), allOf(greaterThan(0), lessThan(10000)));
      // Sonda: son değerler; sonsuz animasyon yok (pumpAndSettle biter).
      await t.pump(const Duration(milliseconds: 1500));
      await t.pumpAndSettle();
      expect(_incomeBar(t), closeTo(10000, 1e-6));
      expect(_lineData(t, 'collection').lineBarsData.single.spots, hasLength(12));
      expect(_lineData(t, 'cash').lineBarsData.single.spots, hasLength(12));
      expect(_agingFirstAmount(t), '4.000,00 ₺ · %50');
      // "Tablo olarak göster" ve geri: animasyon yeniden oynamaz (450 ms sonra hâlâ tam değer).
      await tapFinder(t, _switch('income_expense'));
      await tapFinder(t, _switch('income_expense'));
      expect(_chart('income_expense'), findsOneWidget);
      expect(_incomeBar(t), closeTo(10000, 1e-6));
    });

    testWidgets('aynı veriyle yenileme animasyonu tekrar oynatmaz; veri değişince yeniden oynar', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final key = GlobalKey<FinanceChartsTabState>();
      await pumpList(t, FinanceChartsTab(key: key, scope: _scope(auth)), width: 400, height: 3000, scale: 1.0, dark: false);
      await _pumpUntilCards(t);
      await t.pump(const Duration(milliseconds: 1500));
      await t.pumpAndSettle();
      await key.currentState!.reload();
      await settleFor(t, 100);
      expect(_incomeBar(t), closeTo(10000, 1e-6), reason: 'veri aynı: tekrar oynamadı');
      // Veri değişti: gelir çubuğu yeniden 0'dan büyür.
      final json = f4ChartsJson();
      ((json['months'] as List)[10] as Map<String, dynamic>)['collected_minor'] = 500000;
      auth.f4.chartsJson = json;
      await key.currentState!.reload();
      await t.pump();
      await t.pump(const Duration(milliseconds: 1));
      await t.pump(const Duration(milliseconds: 1));
      expect(_incomeBar(t), lessThan(5000), reason: 'yeni veri (5.000 lira) için yeniden büyüyor');
      await t.pump(const Duration(milliseconds: 1500));
      await t.pumpAndSettle();
      expect(_incomeBar(t), closeTo(5000, 1e-6));
    });

    testWidgets('hareketi azalt açıkken ilk karede son değer (animasyon yok)', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await pumpList(t, FinanceChartsTab(scope: _scope(auth)), width: 400, height: 3000, scale: 1.0, dark: false, reduce: true);
      await _pumpUntilCards(t);
      expect(_incomeBar(t), closeTo(10000, 1e-6));
      expect(_lineData(t, 'collection').lineBarsData.single.spots, hasLength(12));
      expect(_lineData(t, 'cash').lineBarsData.single.spots, hasLength(12));
      expect(_agingFirstAmount(t), '4.000,00 ₺ · %50');
    });
  });

  group('Grafikler: dolu', () {
    f4Matrix('beş kart, grafikler ve tablo anahtarları görünür', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      for (final id in _ids) {
        expect(_card(id), findsOneWidget, reason: id);
        expect(_chart(id), findsOneWidget, reason: '$id grafiği');
        expect(_empty(id), findsNothing, reason: id);
        expect(_switch(id), findsOneWidget, reason: '$id tablo anahtarı');
      }
      expect(find.text('Aylık gelir ve gider'), findsOneWidget);
      expect(find.text('Aidat tahsilatı'), findsOneWidget);
      expect(find.text('Kasa ve banka bakiyesi'), findsOneWidget);
      expect(find.text('Gider kategorileri'), findsOneWidget);
      expect(find.text('Geciken borçlar'), findsOneWidget);
    });

    f4Matrix('Tablo olarak göster: her kartta grafik yerine tablo çıkar ve geri döner', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      for (final id in _ids) {
        await tapFinder(t, _switch(id));
        expect(_table(id), findsOneWidget, reason: '$id tablosu');
        expect(_chart(id), findsNothing, reason: '$id grafiği gizlenir');
        await tapFinder(t, _switch(id));
        expect(_chart(id), findsOneWidget, reason: '$id grafiği döner');
        expect(_table(id), findsNothing, reason: id);
      }
    });

    testWidgets('tek uç, 12 ay istenir; açıklamalar yöneticinin dilinde (tahakkuk / mutabakat yok)', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      expect(auth.f4.callCount('getFinanceCharts'), 1);
      expect(auth.f4.reportCalls.where((c) => c['name'] == 'getFinanceCharts').single['months'], 12);
      for (final id in _ids) {
        final desc = find.byKey(ValueKey<String>('finance_chart_desc_$id'));
        expect(desc, findsOneWidget, reason: id);
        final text = (t.widget(desc) as Text).data!.toLowerCase();
        expect(text.contains('tahakkuk'), isFalse, reason: id);
        expect(text.contains('mutabakat'), isFalse, reason: id);
        expect(text.contains('ledger'), isFalse, reason: id);
      }
      expect(find.textContaining('Son 12 ayda 99.500,00 ₺ tahsil edildi'), findsOneWidget);
      expect(find.textContaining('toplanma oranı: %86'), findsOneWidget);
      expect(find.textContaining('Şu an toplam'), findsOneWidget);
    });

    testWidgets('tablo: ay başlıkları, gelir-gider farkı, hesap yokken "Hesap yok", borç yazılmayan ayda yüzde yok', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      await tapFinder(t, _switch('income_expense'));
      expect(find.descendant(of: _table('income_expense'), matching: find.text('Kasım 2025')), findsOneWidget);
      expect(find.descendant(of: _table('income_expense'), matching: find.text('Ekim 2026')), findsOneWidget);
      expect(find.descendant(of: _table('income_expense'), matching: find.text('Fark')), findsNWidgets(12));
      await tapFinder(t, _switch('cash'));
      expect(find.descendant(of: _table('cash'), matching: find.text('Hesap yok')), findsNWidgets(2), reason: 'ilk iki ayda hesap yok');
      await tapFinder(t, _switch('collection'));
      expect(find.descendant(of: _table('collection'), matching: find.text('Borç yazılmadı')), findsOneWidget);
    });

    testWidgets('gider kategorileri: ilk 6 + Diğer; yaşlandırma: dört kova ve toplam', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_chart_category_5')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('finance_chart_category_6')), findsOneWidget, reason: 'Diğer satırı');
      expect(find.byKey(const ValueKey<String>('finance_chart_category_7')), findsNothing);
      expect(find.text('Diğer'), findsOneWidget);
      expect(find.text('Kırtasiye'), findsNothing, reason: 'altıdan sonrası Diğer içinde');
      expect(find.text('0-30 gün'), findsOneWidget);
      expect(find.text('31-60 gün'), findsOneWidget);
      expect(find.text('61-90 gün'), findsOneWidget);
      expect(find.text('90 günden fazla'), findsOneWidget);
      expect(find.textContaining('Toplam 8.000,00 ₺, 6 daire borçlu'), findsOneWidget);
    });

    testWidgets('kurul (salt okunur) da grafikleri görür', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, canWrite: false);
      for (final id in _ids) {
        expect(_card(id), findsOneWidget, reason: id);
      }
    });

    testWidgets('ekran okuyucu: ham tutar yığını yok; grafikler özetle okunur; anahtar etiketli', (t) async {
      final handle = t.ensureSemantics();
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth);
      expect(f4RawMoneyLabels(t), isEmpty, reason: 'tutar okunuşla verilir');
      expect(find.bySemanticsLabel(RegExp('^Aylık gelir ve gider grafiği\\.')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Kasa ve banka bakiyesi grafiği\\.')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('veri yok')), findsWidgets, reason: 'hesap yokken ay "veri yok" diye okunur');
      expect(find.bySemanticsLabel('Tablo olarak göster'), findsNWidgets(5));
      handle.dispose();
    });

    testWidgets('hareketi azalt açıkken de çizilir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      await _pump(t, auth, reduce: true);
      for (final id in _ids) {
        expect(_chart(id), findsOneWidget, reason: id);
      }
    });
  });

  group('Grafikler: kayıt yok', () {
    f4Matrix('her kart "Bu dönemde kayıt yok" der; tablo anahtarı çıkmaz', (t, w, h, s, dark) async {
      final auth = FinanceFakeAuth.seeded();
      auth.f4.chartsJson = f4ChartsJson(empty: true);
      await _pump(t, auth, width: w, height: h, scale: s, dark: dark);
      for (final id in _ids) {
        expect(_card(id), findsOneWidget, reason: id);
        expect(_empty(id), findsOneWidget, reason: id);
        expect(_chart(id), findsNothing, reason: id);
        expect(_switch(id), findsNothing, reason: id);
      }
      expect(find.text('Bu dönemde kayıt yok'), findsNWidgets(5));
      expect(find.textContaining('Kasa sekmesinden hesap ekleyince'), findsOneWidget);
    });

    testWidgets('yalnız bazı seriler boşsa yalnız o kartlar boş: borç var ama kasa hesabı yok', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final json = f4ChartsJson();
      for (final m in json['months'] as List) {
        (m as Map<String, dynamic>)
          ..['cash_balance_minor'] = null
          ..['cash_account_count'] = 0;
      }
      auth.f4.chartsJson = json;
      await _pump(t, auth);
      expect(_empty('cash'), findsOneWidget);
      expect(_chart('income_expense'), findsOneWidget);
      expect(_chart('aging'), findsOneWidget);
    });
  });

  group('Grafikler: yükleme ve hata', () {
    testWidgets('yanıt gelene dek iskelet; gelince iskelet gider', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final gate = F4Gate();
      auth.f4.reportGate = gate;
      await pumpList(t, FinanceChartsTab(scope: _scope(auth)), width: 400, height: 3000, scale: 1.0, dark: false);
      await t.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey<String>('finance_charts_loading')), findsOneWidget);
      expect(_card('aging'), findsNothing);
      gate.complete();
      await settleFor(t, 100);
      expect(find.byKey(const ValueKey<String>('finance_charts_loading')), findsNothing);
      expect(_card('aging'), findsOneWidget);
    });

    testWidgets('hata: "kayıt yok / 0" DEĞİL hata bildirimi + Tekrar Dene; eski grafik kalmaz; düzelince grafikler gelir', (t) async {
      final auth = FinanceFakeAuth.seeded();
      auth.f4.reportError = ApiException('İşlem başarısız (503)', statusCode: 503, genericFallback: true);
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_charts_error')), findsOneWidget);
      expect(find.textContaining('Grafikler alınamadı'), findsOneWidget);
      expect(find.text('Bu dönemde kayıt yok'), findsNothing, reason: 'hata kayıt yok demek değildir');
      for (final id in _ids) {
        expect(_card(id), findsNothing, reason: id);
      }
      auth.f4.reportError = null;
      await tapFinder(t, find.descendant(of: find.byType(InlineNotice), matching: find.byType(TextButton)));
      await settleFor(t, 100);
      expect(find.byKey(const ValueKey<String>('finance_charts_error')), findsNothing);
      expect(_card('income_expense'), findsOneWidget);
    });

    testWidgets('yenileme hata verirse eski grafik bırakılmaz', (t) async {
      final auth = FinanceFakeAuth.seeded();
      final key = GlobalKey<FinanceChartsTabState>();
      await _pump(t, auth, key: key);
      expect(_card('aging'), findsOneWidget);
      auth.f4.reportError = ApiException('Sunucuya ulaşılamadı.', statusCode: 503);
      await key.currentState!.reload();
      await settleFor(t, 100);
      expect(find.byKey(const ValueKey<String>('finance_charts_error')), findsOneWidget);
      expect(_card('aging'), findsNothing);
    });

    testWidgets('bozuk gövde (months yok) hata olarak gösterilir, boş grafik değil', (t) async {
      final auth = FinanceFakeAuth.seeded();
      auth.f4.chartsJson = <String, dynamic>{'currency': 'TRY'};
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('finance_charts_error')), findsOneWidget);
      expect(find.text('Bu dönemde kayıt yok'), findsNothing);
    });
  });

  group('Grafikler: model ve yardımcılar', () {
    test('FinanceCharts.fromJson: eksik months / aging FormatException; null alanlar korunur', () {
      expect(() => FinanceCharts.fromJson(<String, dynamic>{}), throwsFormatException);
      expect(() => FinanceCharts.fromJson(<String, dynamic>{'months': <Object?>[]}), throwsFormatException);
      final ok = FinanceCharts.fromJson(f4ChartsJson());
      expect(ok.months, hasLength(12));
      expect(ok.months.first.cashBalanceMinor, isNull, reason: 'hesap yokken null, 0 değil');
      expect(ok.months.last.collectionRateBp, isNull);
      expect(ok.months[2].cashBalanceMinor, 1200000);
      expect(ok.hasCash && ok.hasCollection && ok.hasIncomeExpense && ok.hasCategories && ok.hasAging, isTrue);
      final empty = FinanceCharts.fromJson(f4ChartsJson(empty: true));
      expect(empty.hasCash || empty.hasCollection || empty.hasIncomeExpense || empty.hasCategories || empty.hasAging, isFalse);
    });

    test('dönem toplamları tamsayı kuruş; oran yarım yukarı; yazılan borç yoksa oran null', () {
      final ok = FinanceCharts.fromJson(f4ChartsJson());
      expect(ok.totalCollectedMinor, ok.months.fold<int>(0, (a, m) => a + m.collectedMinor));
      expect(ok.overallRateBp, isNotNull);
      expect(FinanceCharts.fromJson(f4ChartsJson(empty: true)).overallRateBp, isNull);
      const m = FinanceChartMonth(period: '2026-10', chargedMinor: 3, lateFeeMinor: 0, collectedMinor: 1, expenseMinor: 0);
      final one = FinanceCharts(months: const [m], aging: const FinanceChartAging());
      expect(one.overallRateBp, 3333, reason: '1/3 -> 33,33');
      expect(chartPercent(8650), '%87', reason: '86,5 yukarı');
      expect(chartPercent(null), '-');
    });

    test('ay etiketleri', () {
      expect(chartMonthLabel('2026-10'), 'Eki');
      expect(chartMonthLabel('2026-01'), 'Oca');
      expect(chartMonthLabel('bozuk'), 'bozuk');
      expect(monthTitleOf('2026-10'), 'Ekim 2026');
      expect(monthTitleOf('x'), 'x');
    });

    test('eksen yardımcıları: kısa tutar ve düzgün aralık', () {
      expect(compactLira(0), '0');
      expect(compactLira(950), '950');
      expect(compactLira(1250), '1.250');
      expect(compactLira(12500), '12,5 B');
      expect(compactLira(100000), '100 B');
      expect(compactLira(1500000), '1,5 Mn');
      expect(compactLira(-2500), '-2.500');
      expect(compactLira(-1500000), '-1,5 Mn');
      expect(niceInterval(0), 1);
      expect(niceInterval(0.5), 1, reason: 'en az 1 lira');
      expect(niceInterval(10000), 5000, reason: '10000 / 4 = 2500 -> 1-2-5 kuralıyla 5000');
      expect(niceInterval(4000), 1000);
      for (final v in <double>[1, 7, 99, 1234, 56789, 1500000]) {
        final iv = niceInterval(v);
        expect(iv, greaterThan(0));
        expect((v / iv).ceil(), lessThanOrEqualTo(6), reason: '$v için en çok ~5 aralık');
      }
      expect(ChartBarRows.percentOf(1, 3), 33);
      expect(ChartBarRows.percentOf(1, 0), isNull);
      expect(ChartBarRows.percentOf(500, 1000), 50);
    });
  });
}
