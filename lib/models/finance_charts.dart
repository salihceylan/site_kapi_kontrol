import 'package:flutter/foundation.dart';

/// Finans > Grafikler verisi (`GET .../finance/reports/charts?months=12`). Tutarlar tamsayı kuruş.
///
/// Sunucu başarılı sorgudan gelen sıfırı sıfır olarak döner; hata ise BÜTÜN yanıtı hata yapar. İstemci eksik / okunamayan
/// bir gövdeyi ([FormatException]) "veri yok" diye göstermez, hata olarak gösterir.
@immutable
class FinanceCharts {
  const FinanceCharts({
    required this.months,
    this.categories = const <FinanceChartCategory>[],
    required this.aging,
    this.from = '',
    this.to = '',
  });

  /// Eskiden yeniye, kesintisiz aylar (kayıtsız aylar da satırdır).
  final List<FinanceChartMonth> months;

  /// Son N ayın gider kategorileri toplamı (yalnız pozitif net), büyükten küçüğe.
  final List<FinanceChartCategory> categories;
  final FinanceChartAging aging;

  /// 'YYYY-AA'.
  final String from;
  final String to;

  /// Gelir-gider grafiğinde gösterilecek bir şey var mı (tahsilat ya da gider)?
  bool get hasIncomeExpense => months.any((m) => m.collectedMinor != 0 || m.expenseMinor != 0);

  /// Aidat grafiğinde gösterilecek bir şey var mı (yazılan borç ya da tahsilat)?
  bool get hasCollection => months.any((m) => m.writtenMinor != 0 || m.collectedMinor != 0);

  /// Kasa + banka seyri: en az bir ayda hesap tanımlı mı?
  bool get hasCash => months.any((m) => m.cashBalanceMinor != null);

  bool get hasCategories => categories.isNotEmpty;

  bool get hasAging => aging.totalOverdueMinor > 0;

  /// Dönem toplamları (aylardan; tamsayı kuruş).
  int get totalWrittenMinor => months.fold<int>(0, (a, m) => a + m.writtenMinor);
  int get totalCollectedMinor => months.fold<int>(0, (a, m) => a + m.collectedMinor);
  int get totalExpenseMinor => months.fold<int>(0, (a, m) => a + m.expenseMinor);

  /// Dönem tahsilat oranı (baz puan, yarım yukarı); yazılan borç yoksa null.
  int? get overallRateBp {
    final written = totalWrittenMinor;
    if (written <= 0) return null;
    return (totalCollectedMinor * 20000 + written) ~/ (written * 2);
  }

  factory FinanceCharts.fromJson(Map<String, dynamic> json) {
    final rawMonths = json['months'];
    final rawAging = json['aging'];
    if (rawMonths is! List || rawAging is! Map<String, dynamic>) {
      throw const FormatException('Grafik verisi okunamadı.');
    }
    final months = <FinanceChartMonth>[
      for (final item in rawMonths)
        if (item is Map<String, dynamic>) FinanceChartMonth.fromJson(item),
    ];
    final rawCategories = json['expense_by_category'];
    return FinanceCharts(
      months: List<FinanceChartMonth>.unmodifiable(months),
      categories: List<FinanceChartCategory>.unmodifiable(<FinanceChartCategory>[
        if (rawCategories is List)
          for (final item in rawCategories)
            if (item is Map<String, dynamic>) FinanceChartCategory.fromJson(item),
      ]),
      aging: FinanceChartAging.fromJson(rawAging),
      from: _text(json['from']),
      to: _text(json['to']),
    );
  }
}

int? _intOrNull(Object? v) => v is int ? v : (v is num ? v.toInt() : null);
String _text(Object? v) => v is String ? v : '';

@immutable
class FinanceChartMonth {
  const FinanceChartMonth({
    required this.period,
    required this.chargedMinor,
    required this.lateFeeMinor,
    required this.collectedMinor,
    required this.expenseMinor,
    this.collectionRateBp,
    this.cashBalanceMinor,
    this.cashAccountCount = 0,
  });

  /// 'YYYY-AA'.
  final String period;

  /// Net yazılan borç (devir ve gecikme bedeli hariç).
  final int chargedMinor;

  /// Gecikme bedeli olarak yazılan tutar.
  final int lateFeeMinor;

  /// Net tahsilat (gelir).
  final int collectedMinor;

  /// Net gider (ay içinde iptal edilen gider düşülmüş; negatif olabilir).
  final int expenseMinor;

  /// Baz puan (10000 = %100) = tahsilat / yazılan borç; o ay borç yazılmadıysa null.
  final int? collectionRateBp;

  /// Ay sonundaki (bu ayda bugünkü) kasa + banka toplamı; o tarihte hesap yoksa null (0 gösterilmez).
  final int? cashBalanceMinor;
  final int cashAccountCount;

  /// Yazılan borç = aidat/borç + gecikme bedeli (tahsilat oranı bu tutara göre hesaplanır).
  int get writtenMinor => chargedMinor + lateFeeMinor;

  /// Kısa ay etiketi: '2026-10' -> '10.26'.
  String get shortLabel => period.length < 7 ? period : '${period.substring(5, 7)}.${period.substring(2, 4)}';

  /// Okunur ay adı: '2026-10' -> 'Ekim 2026'.
  String get title => monthTitleOf(period);

  factory FinanceChartMonth.fromJson(Map<String, dynamic> json) => FinanceChartMonth(
        period: _text(json['period']),
        chargedMinor: _intOrNull(json['charged_minor']) ?? 0,
        lateFeeMinor: _intOrNull(json['late_fee_minor']) ?? 0,
        collectedMinor: _intOrNull(json['collected_minor']) ?? 0,
        expenseMinor: _intOrNull(json['expense_minor']) ?? 0,
        collectionRateBp: _intOrNull(json['collection_rate_bp']),
        cashBalanceMinor: _intOrNull(json['cash_balance_minor']),
        cashAccountCount: _intOrNull(json['cash_account_count']) ?? 0,
      );
}

const List<String> _monthNames = <String>[
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık', //
];

/// 'YYYY-AA' -> 'Ekim 2026' (okunamazsa metin aynen döner).
String monthTitleOf(String month) {
  final parts = month.split('-');
  final m = parts.length >= 2 ? int.tryParse(parts[1]) : null;
  if (m == null || m < 1 || m > 12) return month;
  return '${_monthNames[m - 1]} ${parts[0]}';
}

@immutable
class FinanceChartCategory {
  const FinanceChartCategory({required this.name, required this.totalMinor});

  final String name;
  final int totalMinor;

  factory FinanceChartCategory.fromJson(Map<String, dynamic> json) => FinanceChartCategory(
        name: _text(json['category_name']),
        totalMinor: _intOrNull(json['total_minor']) ?? 0,
      );
}

/// Bugün itibarıyla geciken borçlar (kiracı + ev sahibi hesapları toplamı). Vadesi gelmemiş borç dahil değildir.
@immutable
class FinanceChartAging {
  const FinanceChartAging({
    this.asOf = '',
    this.d0to30Minor = 0,
    this.d31to60Minor = 0,
    this.d61to90Minor = 0,
    this.d91plusMinor = 0,
    this.totalOverdueMinor = 0,
    this.debtorCount = 0,
  });

  final String asOf;
  final int d0to30Minor;
  final int d31to60Minor;
  final int d61to90Minor;
  final int d91plusMinor;
  final int totalOverdueMinor;
  final int debtorCount;

  factory FinanceChartAging.fromJson(Map<String, dynamic> json) => FinanceChartAging(
        asOf: _text(json['as_of']),
        d0to30Minor: _intOrNull(json['d0_30_minor']) ?? 0,
        d31to60Minor: _intOrNull(json['d31_60_minor']) ?? 0,
        d61to90Minor: _intOrNull(json['d61_90_minor']) ?? 0,
        d91plusMinor: _intOrNull(json['d91_plus_minor']) ?? 0,
        totalOverdueMinor: _intOrNull(json['total_overdue_minor']) ?? 0,
        debtorCount: _intOrNull(json['debtor_count']) ?? 0,
      );
}
