// İşletme projesi (bütçe, `budget` modülü) modelleri. Para tamsayı kuruştur. Sözleşme: docs/PLATFORM_BUTCE.md.
import 'package:flutter/foundation.dart';

/// Ekranda listelenen site ve erişim (yönetici yazar; kurul salt okur).
@immutable
class BudgetSite {
  const BudgetSite({required this.code, required this.name, this.canWrite = true});

  final int code;
  final String name;
  final bool canWrite;

  String get label => name.trim().isEmpty ? 'İsimsiz site' : name.trim();

  @override
  bool operator ==(Object other) =>
      other is BudgetSite && other.code == code && other.name == name && other.canWrite == canWrite;

  @override
  int get hashCode => Object.hash(code, name, canWrite);
}

enum BudgetStatus {
  taslak('taslak', 'Taslak'),
  teblig('teblig', 'Tebliğ edildi'),
  kesin('kesin', 'Kesin');

  const BudgetStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static BudgetStatus parse(Object? raw) => BudgetStatus.values.firstWhere((s) => s.apiValue == raw, orElse: () => BudgetStatus.taslak);
}

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? fallback;
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString());

@immutable
class BudgetProject {
  const BudgetProject({
    required this.id,
    required this.year,
    required this.title,
    required this.status,
    this.isProvisional = false,
    this.provisionalUntil,
    this.remainingDays,
    this.notifiedAt,
    this.objectionDays,
    this.objectionEnds,
    this.note,
    this.itemCount = 0,
    this.totalMinor = 0,
  });

  factory BudgetProject.fromJson(Map<String, dynamic> j) => BudgetProject(
    id: _int(j['id']),
    year: _int(j['year']),
    title: '${j['title'] ?? ''}',
    status: BudgetStatus.parse(j['status']),
    isProvisional: j['is_provisional'] == true,
    provisionalUntil: _date(j['provisional_until']),
    remainingDays: j['provisional_remaining_days'] == null ? null : _int(j['provisional_remaining_days']),
    notifiedAt: _date(j['notified_at']),
    objectionDays: j['objection_days'] == null ? null : _int(j['objection_days']),
    objectionEnds: _date(j['objection_ends']),
    note: j['note'] as String?,
    itemCount: _int(j['item_count']),
    totalMinor: _int(j['total_minor']),
  );

  final int id;
  final int year;
  final String title;
  final BudgetStatus status;
  final bool isProvisional;
  final DateTime? provisionalUntil;

  /// Yalnız açık (kesin olmayan) geçici projede dolu: geçici sürenin kalan günü.
  final int? remainingDays;
  final DateTime? notifiedAt;
  final int? objectionDays;
  final DateTime? objectionEnds;
  final String? note;
  final int itemCount;
  final int totalMinor;
}

@immutable
class BudgetItem {
  const BudgetItem({required this.categoryId, required this.categoryName, required this.annualMinor});

  factory BudgetItem.fromJson(Map<String, dynamic> j) =>
      BudgetItem(categoryId: _int(j['category_id']), categoryName: '${j['category_name'] ?? ''}', annualMinor: _int(j['annual_minor']));

  final int categoryId;
  final String categoryName;
  final int annualMinor;
}

@immutable
class BudgetDetail {
  const BudgetDetail({required this.project, required this.items});

  factory BudgetDetail.fromJson(Map<String, dynamic> j) => BudgetDetail(
    project: BudgetProject.fromJson(Map<String, dynamic>.from(j['project'] as Map)),
    items: <BudgetItem>[for (final e in (j['items'] as List? ?? const <Object>[])) BudgetItem.fromJson(Map<String, dynamic>.from(e as Map))],
  );

  final BudgetProject project;
  final List<BudgetItem> items;
}

@immutable
class BudgetListResult {
  const BudgetListResult({required this.projects, this.provisionalRemainingDays, this.provisionalTitle});

  factory BudgetListResult.fromJson(Map<String, dynamic> j) {
    final attention = j['attention'] is Map ? (j['attention'] as Map)['provisional'] : null;
    return BudgetListResult(
      projects: <BudgetProject>[for (final e in (j['items'] as List? ?? const <Object>[])) BudgetProject.fromJson(Map<String, dynamic>.from(e as Map))],
      provisionalRemainingDays: attention is Map ? _int(attention['remaining_days']) : null,
      provisionalTitle: attention is Map ? '${attention['title'] ?? ''}' : null,
    );
  }

  final List<BudgetProject> projects;

  /// Açık geçici proje varsa kalan gün (dikkat özeti sayacı); yoksa null.
  final int? provisionalRemainingDays;
  final String? provisionalTitle;
}

@immutable
class BudgetCompareRow {
  const BudgetCompareRow({required this.categoryName, required this.plannedMinor, required this.actualMinor, required this.varianceMinor, this.usedPct});

  factory BudgetCompareRow.fromJson(Map<String, dynamic> j) => BudgetCompareRow(
    categoryName: '${j['category_name'] ?? ''}',
    plannedMinor: _int(j['planned_minor']),
    actualMinor: _int(j['actual_minor']),
    varianceMinor: _int(j['variance_minor']),
    usedPct: j['used_pct'] is num ? (j['used_pct'] as num).toDouble() : null,
  );

  final String categoryName;
  final int plannedMinor;
  final int actualMinor;

  /// Gerçekleşen - planlanan (pozitif = bütçe aşımı).
  final int varianceMinor;
  final double? usedPct;
}

@immutable
class BudgetComparison {
  const BudgetComparison({required this.project, required this.rows, required this.totals});

  factory BudgetComparison.fromJson(Map<String, dynamic> j) => BudgetComparison(
    project: BudgetProject.fromJson(Map<String, dynamic>.from(j['project'] as Map)),
    rows: <BudgetCompareRow>[for (final e in (j['rows'] as List? ?? const <Object>[])) BudgetCompareRow.fromJson(Map<String, dynamic>.from(e as Map))],
    totals: BudgetCompareRow.fromJson(Map<String, dynamic>.from(j['totals'] as Map)),
  );

  final BudgetProject project;
  final List<BudgetCompareRow> rows;
  final BudgetCompareRow totals;
}
