// Gider analizi (R1): model ayrıştırma, karşılaştırma cümlesi, grafik çizimi (hareket azaltma, özet) ve PDF'te grafik.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/expense_analysis.dart';
import 'package:site_kapi_kontrol/models/expense_models.dart';
import 'package:site_kapi_kontrol/services/background_work.dart';
import 'package:site_kapi_kontrol/services/pdf_finance_service.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/widgets/expense_analysis_chart.dart';

import 'support/pdf_text_probe.dart';

Map<String, dynamic> _json({int? changeBp = 1250, bool forecast = true}) => <String, dynamic>{
  'site': <String, dynamic>{'name': 'Işık Sitesi'},
  'generated_at': '2026-10-21T10:00:00.000Z',
  'closed_through': '2026-08',
  'to': '2026-10',
  'window': 3,
  'months': <Map<String, dynamic>>[
    for (final p in <String>['2026-08', '2026-09', '2026-10'])
      <String, dynamic>{
        'period': p,
        'income_minor': 500000,
        'expense_minor': 300000,
        'routine_minor': 200000,
        'unexpected_minor': 100000,
        'by_category': <dynamic>[],
      },
  ],
  'totals': <String, dynamic>{'income_minor': 1500000, 'expense_minor': 900000, 'routine_minor': 600000, 'unexpected_minor': 300000},
  'previous': <String, dynamic>{'from': '2026-05', 'to': '2026-07', 'expense_minor': 800000, 'routine_minor': 600000, 'unexpected_minor': 200000, 'change_bp': changeBp},
  'by_category': <Map<String, dynamic>>[
    <String, dynamic>{
      'category_name': 'Elektrik',
      'routine_minor': 600000,
      'unexpected_minor': 0,
      'total_minor': 600000,
      'share_bp': 6667,
      'previous_total_minor': 500000,
      'change_bp': 2000,
    },
    <String, dynamic>{
      'category_name': 'Bakım-onarım',
      'routine_minor': 0,
      'unexpected_minor': 300000,
      'total_minor': 300000,
      'share_bp': 3333,
      'previous_total_minor': 300000,
      'change_bp': null,
    },
  ],
  'classification': <String, dynamic>{'derived_count': 4},
  'forecast': forecast
      ? <String, dynamic>{
          'base': <String, dynamic>{'from': '2025-10', 'to': '2026-09', 'months': 12},
          'increase_bp': 1000,
          'increase_source': 'request',
          'note': null,
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'category_name': 'Elektrik',
              'base_routine_minor': 2400000,
              'base_unexpected_minor': 0,
              'annual_routine_minor': 2400000,
              'annual_unexpected_minor': 0,
              'forecast_routine_minor': 2640000,
              'forecast_minor': 2640000,
            },
          ],
          'totals': <String, dynamic>{'forecast_minor': 2640000},
        }
      : null,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PdfFinanceService.debugCompress = false;
    BackgroundWork.debugRunInline = true;
  });

  tearDown(() {
    PdfFinanceService.debugCompress = true;
    BackgroundWork.debugRunInline = false;
  });

  test('rapor ayrıştırılır; karşılaştırma cümlesi ve boş tahmin', () {
    final r = ExpenseAnalysisReport.fromJson(_json());
    expect(r.months, hasLength(3));
    expect(r.expenseMinor, 900000);
    expect(r.routineMinor + r.unexpectedMinor, r.expenseMinor);
    expect(r.categories.first.name, 'Elektrik');
    expect(r.categories.last.changeBp, isNull);
    expect(r.derivedCount, 4);
    expect(r.forecast!.totalMinor, 2640000);
    expect(r.comparisonSentence, 'Önceki 3 aya göre gider %12,5 arttı.');
    expect(ExpenseAnalysisReport.fromJson(_json(changeBp: null, forecast: false)).comparisonSentence, isNull);
    expect(ExpenseAnalysisReport.fromJson(_json(forecast: false)).forecast, isNull);
    expect(ExpenseAnalysisReport.fromJson(_json(changeBp: -300)).comparisonSentence, 'Önceki 3 aya göre gider %3 azaldı.');
  });

  test('zorunlu tutar okunamazsa FormatException', () {
    final bad = _json();
    (bad['totals'] as Map<String, dynamic>).remove('expense_minor');
    expect(() => ExpenseAnalysisReport.fromJson(bad), throwsFormatException);
  });

  test('gider türü: gider okunur, öneri ayrıştırılır, istek yalnız seçilince tür taşır', () {
    final e = Expense.fromJson(<String, dynamic>{'id': 1, 'amount_minor': 100, 'nature': 'routine', 'nature_source': 'derived'});
    expect(e.nature, ExpenseNature.routine);
    expect(e.natureSource, 'derived');
    expect(Expense.fromJson(<String, dynamic>{'id': 2, 'amount_minor': 100}).nature, isNull);
    final s = NatureSuggestion.fromJson(<String, dynamic>{'nature': 'unexpected', 'reason': 'default', 'reason_text': 'x'});
    expect(s.nature, ExpenseNature.unexpected);
    expect(() => NatureSuggestion.fromJson(<String, dynamic>{'nature': 'x'}), throwsFormatException);
    ExpenseInput input({ExpenseNature? n}) => ExpenseInput(
      categoryId: 1,
      description: 'a',
      amountMinor: 100,
      expenseDate: DateTime(2026, 10, 1),
      accountId: 1,
      nature: n,
    );
    expect(input().toJson().containsKey('nature'), isFalse);
    expect(input(n: ExpenseNature.routine).toJson()['nature'], 'routine');
  });

  Future<void> pumpChart(WidgetTester tester, {required bool reduce}) async {
    final r = ExpenseAnalysisReport.fromJson(_json());
    tester.view.physicalSize = const Size(640, 1280); // 320x640 @2.0
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(size: const Size(320, 640), disableAnimations: reduce, textScaler: const TextScaler.linear(1.6)),
          child: Scaffold(body: SingleChildScrollView(child: ExpenseAnalysisChart(months: r.months))),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('grafik çizilir, efsane ve erişilebilir özet var (hareket azaltma açık)', (tester) async {
    await pumpChart(tester, reduce: true);
    expect(find.byKey(const ValueKey<String>('expense_analysis_chart')), findsOneWidget);
    expect(find.text('Rutin gider'), findsOneWidget);
    expect(find.text('Beklenmedik gider'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Aylık gider ve gelir grafiği')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grafik hareket azaltma kapalıyken de hatasız çizilir', (tester) async {
    await pumpChart(tester, reduce: false);
    expect(find.byKey(const ValueKey<String>('expense_analysis_chart')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('özet metni her ayı sayar', () {
    final r = ExpenseAnalysisReport.fromJson(_json());
    final text = ExpenseAnalysisChart.summary(r.months);
    expect('gider'.allMatches(text).length, greaterThanOrEqualTo(3));
    expect(ExpenseAnalysisChart.summary(const <AnalysisMonth>[]), 'Grafik: veri yok.');
    expect(ExpenseAnalysisChart.shortLabel('2026-09'), '09.26');
  });

  test('PDF: grafik, kategori kırılımı ve tahmin üretilir', () async {
    final text = extractPdfText(
      await PdfFinanceService.generateExpenseAnalysisPdf(report: ExpenseAnalysisReport.fromJson(_json()), printedAt: DateTime(2026, 10, 21)),
    );
    expect(text, contains('Gider Analizi'));
    expect(text, contains('Kategori kırılımı'));
    expect(text, contains('Gelecek yıl tahmini'));
    expect(text, contains('Elektrik'));
    expect(text, contains('Önceki 3 aya göre gider'));
    expect(text, contains('Bakım-onarım'));
  });
}
