import 'package:flutter/foundation.dart';

/// Yönetici ana sayfası "Bu ay" özeti (`GET .../finance/home`). Tutarlar kuruş.
@immutable
class FinanceHome {
  const FinanceHome({
    required this.month,
    required this.numbers,
    required this.steps,
    required this.attention,
    required this.recent,
  });

  /// 'YYYY-AA'.
  final String month;
  final FinanceHomeNumbers numbers;
  final List<FinanceHomeStep> steps;
  final List<FinanceHomeAttention> attention;
  final List<FinanceHomeMovement> recent;

  factory FinanceHome.fromJson(Map<String, dynamic> json) {
    final month = json['month'];
    final numbers = json['numbers'];
    if (month is! String || numbers is! Map<String, dynamic>) {
      throw const FormatException('Bu ayın özeti okunamadı.');
    }
    List<T> list<T>(String key, T Function(Map<String, dynamic>) map) {
      final raw = json[key];
      if (raw is! List) return <T>[];
      return <T>[
        for (final item in raw)
          if (item is Map<String, dynamic>) map(item),
      ];
    }

    return FinanceHome(
      month: month,
      numbers: FinanceHomeNumbers.fromJson(numbers),
      steps: list('steps', FinanceHomeStep.fromJson),
      attention: list('attention', FinanceHomeAttention.fromJson),
      recent: list('recent', FinanceHomeMovement.fromJson),
    );
  }
}

int? _intOrNull(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

@immutable
class FinanceHomeNumbers {
  const FinanceHomeNumbers({
    required this.chargedMinor,
    required this.lateFeeMinor,
    required this.collectedMinor,
    required this.collectionRateBp,
    required this.overdueApartmentCount,
    required this.apartmentCount,
    required this.cashTotalMinor,
    required this.cashAccountCount,
  });

  final int chargedMinor;
  final int lateFeeMinor;
  final int collectedMinor;

  /// Baz puan (10000 = %100); borçlandırma yoksa null.
  final int? collectionRateBp;
  final int overdueApartmentCount;
  final int apartmentCount;

  /// Kasa + banka toplamı; hesap tanımlı değilse null (0 gösterilmez).
  final int? cashTotalMinor;
  final int cashAccountCount;

  factory FinanceHomeNumbers.fromJson(Map<String, dynamic> json) => FinanceHomeNumbers(
        chargedMinor: _intOrNull(json['charged_minor']) ?? 0,
        lateFeeMinor: _intOrNull(json['late_fee_minor']) ?? 0,
        collectedMinor: _intOrNull(json['collected_minor']) ?? 0,
        collectionRateBp: _intOrNull(json['collection_rate_bp']),
        overdueApartmentCount: _intOrNull(json['overdue_apartment_count']) ?? 0,
        apartmentCount: _intOrNull(json['apartment_count']) ?? 0,
        cashTotalMinor: _intOrNull(json['cash_total_minor']),
        cashAccountCount: _intOrNull(json['cash_account_count']) ?? 0,
      );
}

/// Adım durumu: done, partial, todo, setup, unavailable.
@immutable
class FinanceHomeStep {
  const FinanceHomeStep({required this.key, required this.status, this.done, this.total, this.pending});

  /// charge, notify, match, expense, report.
  final String key;
  final String status;
  final int? done;
  final int? total;
  final int? pending;

  factory FinanceHomeStep.fromJson(Map<String, dynamic> json) => FinanceHomeStep(
        key: json['key'] is String ? json['key'] as String : '',
        status: json['status'] is String ? json['status'] as String : 'todo',
        done: _intOrNull(json['done']),
        total: _intOrNull(json['total']),
        pending: _intOrNull(json['pending']),
      );
}

@immutable
class FinanceHomeAttention {
  const FinanceHomeAttention({required this.key, required this.count, this.totalMinor, this.atLeast = false});

  final String key;
  final int count;
  final int? totalMinor;

  /// Sunucu sayıyı kesilmiş bir listeden çıkardıysa (`at_least`) true: sayı "en az" değeridir, tam sayı olarak yazılmaz.
  final bool atLeast;

  factory FinanceHomeAttention.fromJson(Map<String, dynamic> json) => FinanceHomeAttention(
        key: json['key'] is String ? json['key'] as String : '',
        count: _intOrNull(json['count']) ?? 0,
        totalMinor: _intOrNull(json['total_minor']),
        atLeast: json['at_least'] == true,
      );
}

/// Son para hareketi: kind payment, payment_void, expense, expense_void. Girişte +, çıkışta −.
@immutable
class FinanceHomeMovement {
  const FinanceHomeMovement({required this.kind, required this.date, required this.amountMinor, required this.label});

  final String kind;
  final String date;
  final int amountMinor;
  final String label;

  factory FinanceHomeMovement.fromJson(Map<String, dynamic> json) => FinanceHomeMovement(
        kind: json['kind'] is String ? json['kind'] as String : '',
        date: json['date'] is String ? json['date'] as String : '',
        amountMinor: _intOrNull(json['amount_minor']) ?? 0,
        label: json['label'] is String ? json['label'] as String : '',
      );
}
