// Banka dosyası modelleri (Dalga 2 / 2C). Para tamsayı kuruştur; sunucu yanıtından okunur, istemci hesaplamaz.
int _i(Object? v) => v is int ? v : (v is num ? v.toInt() : (int.tryParse('$v') ?? 0));
int? _ni(Object? v) => v == null ? null : _i(v);
String? _s(Object? v) => v is String && v.isNotEmpty ? v : null;

class BankPreviewSummary {
  const BankPreviewSummary({
    this.recognized = 0,
    this.check = 0,
    this.unmatched = 0,
    this.linkedExisting = 0,
    this.duplicates = 0,
    this.outgoing = 0,
    this.recognizedMinor = 0,
  });

  final int recognized;
  final int check;
  final int unmatched;
  final int linkedExisting;
  final int duplicates;
  final int outgoing;
  final int recognizedMinor;

  factory BankPreviewSummary.fromJson(Map<String, dynamic> j) => BankPreviewSummary(
    recognized: _i(j['recognized']),
    check: _i(j['check']),
    unmatched: _i(j['unmatched']),
    linkedExisting: _i(j['linked_existing']),
    duplicates: _i(j['duplicates']),
    outgoing: _i(j['outgoing']),
    recognizedMinor: _i(j['recognized_minor']),
  );
}

/// Önizlemede tek satırın sunucu sonucu. [outcome]: recognized | check | unmatched | linked | duplicate | outgoing.
/// [periodHint]: açıklamadaki ay/dönem ('YYYY-MM'); yalnız bilgidir, mahsup en eski vadeden yapılır.
class BankPreviewLine {
  const BankPreviewLine({required this.n, required this.outcome, this.matchMethod, this.apartmentLabel, this.periodHint, this.warnings = const <String>[]});

  final int n;
  final String outcome;
  final String? matchMethod;
  final String? apartmentLabel;
  final String? periodHint;
  final List<String> warnings;

  factory BankPreviewLine.fromJson(Map<String, dynamic> j) {
    final m = j['match'] is Map ? Map<String, dynamic>.from(j['match'] as Map) : const <String, dynamic>{};
    return BankPreviewLine(
      n: _i(j['n']),
      outcome: _s(j['outcome']) ?? '',
      matchMethod: _s(m['method']),
      apartmentLabel: _s(m['apartment_label']),
      periodHint: _s(j['period_hint']),
      warnings: (j['warnings'] is List ? (j['warnings'] as List) : const <Object?>[]).map((e) => '$e').toList(),
    );
  }
}

class BankPreview {
  const BankPreview({required this.hash, required this.summary, required this.warnings, this.lines = const <BankPreviewLine>[]});

  final String hash;
  final BankPreviewSummary summary;
  final List<String> warnings;
  final List<BankPreviewLine> lines;

  factory BankPreview.fromJson(Map<String, dynamic> j) => BankPreview(
    hash: _s(j['preview_hash']) ?? '',
    summary: BankPreviewSummary.fromJson(j['summary'] is Map ? Map<String, dynamic>.from(j['summary'] as Map) : <String, dynamic>{}),
    warnings: (j['warnings'] is List ? (j['warnings'] as List) : const <Object?>[]).map((e) => '$e').toList(),
    lines: (j['lines'] is List ? (j['lines'] as List) : const <Object?>[]).whereType<Map>().map((e) => BankPreviewLine.fromJson(Map<String, dynamic>.from(e))).toList(),
  );
}

/// 'YYYY-MM' -> 'Ekim 2026' (geçersizse null).
String? bankPeriodLabel(String? hint) {
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(hint ?? '');
  if (m == null) return null;
  const names = <String>['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
  final month = int.parse(m.group(2)!);
  return month < 1 || month > 12 ? null : '${names[month - 1]} ${m.group(1)}';
}

class BankLineItem {
  const BankLineItem({
    required this.id,
    this.accountId = 0,
    required this.valueDate,
    required this.amountMinor,
    required this.description,
    required this.status,
    this.counterpartyName,
    this.counterpartyIban,
    this.apartmentId,
    this.apartmentLabel,
    this.party,
    this.matchMethod,
    this.classification,
    this.note,
    this.periodHint,
  });

  final int id;
  final int accountId;
  final String valueDate;
  final int amountMinor;
  final String description;
  final String status;
  final String? counterpartyName;
  final String? counterpartyIban;
  final int? apartmentId;
  final String? apartmentLabel;
  final String? party;
  final String? matchMethod;
  final String? classification;
  final String? note;

  /// Açıklamadaki ay/dönem ipucu ('YYYY-MM'); yalnız bilgi.
  final String? periodHint;

  bool get incoming => amountMinor > 0;

  factory BankLineItem.fromJson(Map<String, dynamic> j) => BankLineItem(
    id: _i(j['id']),
    accountId: _i(j['account_id']),
    valueDate: _s(j['value_date']) ?? '',
    amountMinor: _i(j['amount_minor']),
    description: _s(j['description']) ?? '',
    status: _s(j['status']) ?? 'unmatched',
    counterpartyName: _s(j['counterparty_name']),
    counterpartyIban: _s(j['counterparty_iban']),
    apartmentId: _ni(j['apartment_id']),
    apartmentLabel: _s(j['apartment_label']),
    party: _s(j['party']),
    matchMethod: _s(j['match_method']),
    classification: _s(j['classification']),
    note: _s(j['note']),
    periodHint: _s(j['period_hint']),
  );
}

class BankImportItem {
  const BankImportItem({
    required this.id,
    required this.accountName,
    required this.fileName,
    required this.lineCount,
    required this.duplicateCount,
    required this.status,
    this.createdAt,
  });

  final int id;
  final String accountName;
  final String fileName;
  final int lineCount;
  final int duplicateCount;
  final String status;
  final String? createdAt;

  bool get isActive => status == 'active';

  factory BankImportItem.fromJson(Map<String, dynamic> j) => BankImportItem(
    id: _i(j['id']),
    accountName: _s(j['account_name']) ?? '',
    fileName: _s(j['file_name']) ?? '',
    lineCount: _i(j['line_count']),
    duplicateCount: _i(j['duplicate_count']),
    status: _s(j['status']) ?? 'active',
    createdAt: _s(j['created_at']),
  );
}

class BankIbanItem {
  const BankIbanItem({required this.iban, required this.apartmentId, required this.apartmentLabel});

  final String iban;
  final int apartmentId;
  final String apartmentLabel;

  factory BankIbanItem.fromJson(Map<String, dynamic> j) =>
      BankIbanItem(iban: _s(j['iban']) ?? '', apartmentId: _i(j['apartment_id']), apartmentLabel: _s(j['apartment_label']) ?? '');
}

/// Yükleme sonucu.
class BankCommitResult {
  const BankCommitResult({required this.posted, required this.linked, required this.attention, required this.replayed});

  final int posted;
  final int linked;
  final int attention;
  final bool replayed;

  factory BankCommitResult.fromJson(Map<String, dynamic> j) {
    final c = j['counts'] is Map ? Map<String, dynamic>.from(j['counts'] as Map) : <String, dynamic>{};
    return BankCommitResult(posted: _i(c['posted']), linked: _i(c['linked']), attention: _i(c['attention']), replayed: j['replayed'] == true);
  }
}
