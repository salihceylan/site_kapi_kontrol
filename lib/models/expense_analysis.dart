import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/finance_4b.dart';
import 'package:site_kapi_kontrol/models/report_models.dart' show ReportMeta;

/// Gider analizi ve tahmin (R1): `GET reports/expense-analysis` (sözleşme: docs/PLATFORM_FINANS_4B.md "Gider analizi ve tahmin").
/// PARA tamsayı kuruş; zorunlu tutar okunamazsa [FormatException]. Oranlar baz puan (bp, tamsayı); null = hesaplanamadı (önceki 0).

/// Gider türü: rutin / beklenmedik.
enum ExpenseNature {
  routine('routine', 'Rutin'),
  unexpected('unexpected', 'Beklenmedik');

  const ExpenseNature(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ExpenseNature? tryParse(Object? raw) {
    for (final value in ExpenseNature.values) {
      if (value.apiValue == raw) return value;
    }
    return null;
  }
}

/// `GET expenses/nature-suggestion`.
@immutable
class NatureSuggestion {
  const NatureSuggestion({required this.nature, this.reason = '', this.reasonText = ''});

  final ExpenseNature nature;
  final String reason;
  final String reasonText;

  factory NatureSuggestion.fromJson(Map<String, dynamic> json) {
    final nature = ExpenseNature.tryParse(json['nature']);
    if (nature == null) throw const FormatException('Gider türü önerisi okunamadı.');
    return NatureSuggestion(nature: nature, reason: f4Str(json['reason']), reasonText: f4Str(json['reason_text']));
  }
}

@immutable
class AnalysisCategory {
  const AnalysisCategory({
    required this.name,
    this.routineMinor = 0,
    this.unexpectedMinor = 0,
    this.totalMinor = 0,
    this.shareBp,
    this.previousTotalMinor = 0,
    this.changeBp,
  });

  final String name;
  final int routineMinor;
  final int unexpectedMinor;
  final int totalMinor;
  final int? shareBp;
  final int previousTotalMinor;
  final int? changeBp;

  factory AnalysisCategory.fromJson(Map<String, dynamic> json) => AnalysisCategory(
    name: f4Str(json['category_name']),
    routineMinor: f4Minor(json, 'routine_minor'),
    unexpectedMinor: f4Minor(json, 'unexpected_minor'),
    totalMinor: f4Minor(json, 'total_minor'),
    shareBp: f4IntOrNull(json['share_bp']),
    previousTotalMinor: f4MinorOrNull(json, 'previous_total_minor') ?? 0,
    changeBp: f4IntOrNull(json['change_bp']),
  );
}

@immutable
class AnalysisMonth {
  const AnalysisMonth({
    required this.period,
    this.incomeMinor = 0,
    this.expenseMinor = 0,
    this.routineMinor = 0,
    this.unexpectedMinor = 0,
  });

  /// 'YYYY-MM'.
  final String period;
  final int incomeMinor;
  final int expenseMinor;
  final int routineMinor;
  final int unexpectedMinor;

  factory AnalysisMonth.fromJson(Map<String, dynamic> json) => AnalysisMonth(
    period: f4Str(json['period']),
    incomeMinor: f4Minor(json, 'income_minor'),
    expenseMinor: f4Minor(json, 'expense_minor'),
    routineMinor: f4Minor(json, 'routine_minor'),
    unexpectedMinor: f4Minor(json, 'unexpected_minor'),
  );
}

@immutable
class ForecastItem {
  const ForecastItem({
    required this.name,
    this.baseRoutineMinor = 0,
    this.forecastRoutineMinor = 0,
    this.annualUnexpectedMinor = 0,
    this.forecastMinor = 0,
  });

  final String name;
  final int baseRoutineMinor;
  final int forecastRoutineMinor;
  final int annualUnexpectedMinor;
  final int forecastMinor;

  factory ForecastItem.fromJson(Map<String, dynamic> json) => ForecastItem(
    name: f4Str(json['category_name']),
    baseRoutineMinor: f4Minor(json, 'base_routine_minor'),
    forecastRoutineMinor: f4Minor(json, 'forecast_routine_minor'),
    annualUnexpectedMinor: f4Minor(json, 'annual_unexpected_minor'),
    forecastMinor: f4Minor(json, 'forecast_minor'),
  );
}

@immutable
class ExpenseForecast {
  const ExpenseForecast({
    this.baseFrom = '',
    this.baseTo = '',
    this.baseMonths = 0,
    this.increaseBp = 0,
    this.increaseSource = 'default',
    this.note,
    this.items = const <ForecastItem>[],
    this.totalMinor = 0,
  });

  final String baseFrom;
  final String baseTo;
  final int baseMonths;
  final int increaseBp;

  /// request | rule | default.
  final String increaseSource;
  final String? note;
  final List<ForecastItem> items;
  final int totalMinor;

  factory ExpenseForecast.fromJson(Map<String, dynamic> json) {
    final base = f4Map(json['base']);
    return ExpenseForecast(
      baseFrom: f4Str(base['from']),
      baseTo: f4Str(base['to']),
      baseMonths: f4Int(base['months']),
      increaseBp: f4Int(json['increase_bp']),
      increaseSource: f4Str(json['increase_source'], 'default'),
      note: f4Text(json['note']),
      items: f4List(json['items'], ForecastItem.fromJson),
      totalMinor: f4Minor(f4Map(json['totals']), 'forecast_minor'),
    );
  }
}

@immutable
class ExpenseAnalysisReport {
  const ExpenseAnalysisReport({
    required this.meta,
    required this.to,
    required this.window,
    this.months = const <AnalysisMonth>[],
    this.incomeMinor = 0,
    this.expenseMinor = 0,
    this.routineMinor = 0,
    this.unexpectedMinor = 0,
    this.previousFrom = '',
    this.previousTo = '',
    this.previousExpenseMinor = 0,
    this.changeBp,
    this.categories = const <AnalysisCategory>[],
    this.derivedCount = 0,
    this.forecast,
  });

  final ReportMeta meta;
  final String to;
  final int window;
  final List<AnalysisMonth> months;
  final int incomeMinor;
  final int expenseMinor;
  final int routineMinor;
  final int unexpectedMinor;
  final String previousFrom;
  final String previousTo;
  final int previousExpenseMinor;

  /// Önceki aynı uzunluktaki döneme göre değişim (bp); önceki 0 ise null.
  final int? changeBp;
  final List<AnalysisCategory> categories;

  /// Türü kayıtlı olmayıp kategoriden türetilen gider sayısı.
  final int derivedCount;

  /// Veri yoksa null.
  final ExpenseForecast? forecast;

  factory ExpenseAnalysisReport.fromJson(Map<String, dynamic> json) {
    final totals = f4Map(json['totals']);
    final previous = f4Map(json['previous']);
    return ExpenseAnalysisReport(
      meta: ReportMeta.fromJson(json),
      to: f4Str(json['to']),
      window: f4Int(json['window'], 3),
      months: f4List(json['months'], AnalysisMonth.fromJson),
      incomeMinor: f4Minor(totals, 'income_minor'),
      expenseMinor: f4Minor(totals, 'expense_minor'),
      routineMinor: f4Minor(totals, 'routine_minor'),
      unexpectedMinor: f4Minor(totals, 'unexpected_minor'),
      previousFrom: f4Str(previous['from']),
      previousTo: f4Str(previous['to']),
      previousExpenseMinor: f4Minor(previous, 'expense_minor'),
      changeBp: f4IntOrNull(previous['change_bp']),
      categories: f4List(json['by_category'], AnalysisCategory.fromJson),
      derivedCount: f4Int(f4Map(json['classification'])['derived_count']),
      forecast: json['forecast'] is Map ? ExpenseForecast.fromJson(f4Map(json['forecast'])) : null,
    );
  }

  /// "Önceki 3 aya göre gider %12,5 arttı" cümlesi; önceki dönem 0 ise null.
  String? get comparisonSentence {
    final bp = changeBp;
    if (bp == null) return null;
    final span = window == 1 ? 'aya' : '$window aya';
    final percent = (bp.abs() / 100).toStringAsFixed(bp.abs() % 100 == 0 ? 0 : 1).replaceAll('.', ',');
    if (bp == 0) return 'Önceki $span göre gider değişmedi.';
    return 'Önceki $span göre gider %$percent ${bp > 0 ? 'arttı' : 'azaldı'}.';
  }
}
