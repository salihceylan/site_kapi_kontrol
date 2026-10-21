import 'package:site_kapi_kontrol/models/finance.dart' show AccountParty;
import 'package:site_kapi_kontrol/models/finance_4b.dart';

/// İcra dökümü (F8; sunucu `GET finance/reports/enforcement`): hesap (ev sahibi / kiracı) bazında vadesi geçmiş ödenmemiş kalemler.
/// Tutarlar tamsayı kuruştur. Döküm bilgi amaçlıdır; avukat kontrolünden geçirilmelidir.
class EnforcementItem {
  const EnforcementItem({
    required this.name,
    this.dueDate,
    this.period,
    this.description = '',
    this.isLateFee = false,
    required this.remainingMinor,
    this.daysOverdue = 0,
  });

  final String name;
  final DateTime? dueDate;
  final DateTime? period;
  final String description;
  final bool isLateFee;
  final int remainingMinor;
  final int daysOverdue;

  factory EnforcementItem.fromJson(Map<String, dynamic> json) => EnforcementItem(
    name: f4Str(json['name'], 'Borç'),
    dueDate: f4Date(json['due_date']),
    period: f4Date(json['period']),
    description: f4Str(json['description']),
    isLateFee: f4Bool(json['is_late_fee']),
    remainingMinor: f4Minor(json, 'remaining_minor'),
    daysOverdue: f4Int(json['days_overdue']),
  );
}

class EnforcementAccount {
  const EnforcementAccount({
    required this.apartmentId,
    required this.label,
    this.blockName,
    required this.accountParty,
    this.personName,
    this.items = const <EnforcementItem>[],
    required this.principalMinor,
    required this.lateFeeMinor,
    required this.totalMinor,
  });

  final int apartmentId;
  final String label;
  final String? blockName;
  final AccountParty accountParty;
  final String? personName;
  final List<EnforcementItem> items;
  final int principalMinor;
  final int lateFeeMinor;
  final int totalMinor;

  /// Sunucudaki seçim anahtarı (`accounts=` sorgusu): "12:owner".
  String get key => '$apartmentId:${accountParty.apiValue}';

  factory EnforcementAccount.fromJson(Map<String, dynamic> json) => EnforcementAccount(
    apartmentId: f4Int(json['apartment_id']),
    label: f4Str(json['label']),
    blockName: f4Text(json['block_name']),
    accountParty: AccountParty.tryParse(json['account_party']) ?? AccountParty.owner,
    personName: f4Text(json['person_name']),
    items: f4List(json['items'], EnforcementItem.fromJson),
    principalMinor: f4Minor(json, 'principal_minor'),
    lateFeeMinor: f4Minor(json, 'late_fee_minor'),
    totalMinor: f4Minor(json, 'total_minor'),
  );
}

class EnforcementReport {
  const EnforcementReport({
    required this.siteName,
    this.asOf,
    this.note = '',
    this.accounts = const <EnforcementAccount>[],
  });

  final String siteName;
  final DateTime? asOf;
  final String note;
  final List<EnforcementAccount> accounts;

  factory EnforcementReport.fromJson(Map<String, dynamic> json) => EnforcementReport(
    siteName: f4Str(f4Map(json['site'])['name']),
    asOf: f4Date(json['as_of']),
    note: f4Str(json['note']),
    accounts: f4List(json['accounts'], EnforcementAccount.fromJson),
  );

  /// Yalnız seçilen hesaplarla (PDF ve Excel aynı seçimi kullanır).
  EnforcementReport only(Set<String> keys) =>
      EnforcementReport(siteName: siteName, asOf: asOf, note: note, accounts: [for (final a in accounts) if (keys.contains(a.key)) a]);
}
