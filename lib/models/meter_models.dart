// Sayaç Okuma ve Faturalandırma (`metering`) modeli. Sunucu sözleşmesi: docs/PLATFORM_SAYAC.md.
// Para tamsayı kuruş; okuma değeri en çok 3 ondalıklı METİN olarak taşınır (kayan nokta yuvarlama hatası olmasın).
import 'package:flutter/foundation.dart';

/// Sayaç türleri (`kind`).
enum MeterKind {
  water('water', 'Su'),
  electricity('electricity', 'Elektrik'),
  heat('heat', 'Isı'),
  hotWater('hot_water', 'Sıcak su');

  const MeterKind(this.api, this.label);

  final String api;
  final String label;

  static MeterKind? tryParse(Object? value) {
    for (final kind in MeterKind.values) {
      if (kind.api == value) return kind;
    }
    return null;
  }
}

/// Dağıtım yöntemleri (`method`).
enum MeterMethod {
  unitPrice('unit_price', 'Birim fiyat'),
  invoice('invoice', 'Fatura tutarı'),
  heat('heat', 'Isı payı (ölçüm + m²)');

  const MeterMethod(this.api, this.label);

  final String api;
  final String label;
}

/// Sakin/yönetici sayaç ekranının siteleri (`metering` açık siteler).
@immutable
class MeterSite {
  const MeterSite({required this.code, required this.name, this.canWrite = true});

  final int code;
  final String name;

  /// Yalnız yönetici yazar; kurul üyesi salt okur.
  final bool canWrite;

  String get label => name.trim().isEmpty ? 'İsimsiz site' : name.trim();

  @override
  bool operator ==(Object other) =>
      other is MeterSite && other.code == code && other.name == name && other.canWrite == canWrite;

  @override
  int get hashCode => Object.hash(code, name, canWrite);
}

Map<String, dynamic> _map(Object? raw) => raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
List<Map<String, dynamic>> _list(Object? raw) =>
    raw is List ? <Map<String, dynamic>>[for (final e in raw) if (e is Map) Map<String, dynamic>.from(e)] : const <Map<String, dynamic>>[];
int _int(Object? raw) => raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
String _str(Object? raw) => raw == null ? '' : '$raw';

@immutable
class MeterApartment {
  const MeterApartment({required this.id, required this.label, this.areaM2});

  final int id;
  final String label;
  final String? areaM2;

  factory MeterApartment.fromJson(Map<String, dynamic> json) =>
      MeterApartment(id: _int(json['id']), label: _str(json['label']), areaM2: json['area_m2'] as String?);

  static List<MeterApartment> listFrom(Map<String, dynamic> body) =>
      <MeterApartment>[for (final m in _list(body['items'])) MeterApartment.fromJson(m)];
}

@immutable
class Meter {
  const Meter({
    required this.id,
    required this.kind,
    required this.serialNo,
    required this.isActive,
    required this.apartmentId,
    required this.apartmentLabel,
    this.lastValue,
    this.lastDate,
  });

  final int id;
  final MeterKind kind;
  final String serialNo;
  final bool isActive;
  final int apartmentId;
  final String apartmentLabel;
  final String? lastValue;
  final String? lastDate;

  factory Meter.fromJson(Map<String, dynamic> json) {
    final last = json['last_reading'] is Map ? _map(json['last_reading']) : null;
    return Meter(
      id: _int(json['id']),
      kind: MeterKind.tryParse(json['kind']) ?? MeterKind.water,
      serialNo: _str(json['serial_no']),
      isActive: json['is_active'] == true,
      apartmentId: _int(json['apartment_id']),
      apartmentLabel: _str(json['apartment_label']),
      lastValue: last == null ? null : _str(last['value']),
      lastDate: last == null ? null : _str(last['date']),
    );
  }

  static List<Meter> listFrom(Map<String, dynamic> body) => <Meter>[for (final m in _list(body['items'])) Meter.fromJson(m)];
}

@immutable
class MeterReading {
  const MeterReading({required this.id, required this.date, required this.value, required this.source});

  final int id;
  final String date;
  final String value;
  final String source;

  factory MeterReading.fromJson(Map<String, dynamic> json) =>
      MeterReading(id: _int(json['id']), date: _str(json['date']), value: _str(json['value']), source: _str(json['source']));
}

/// Dosyadan içe aktarma önizlemesi/sonucu: satır başına durum (`ok`, `same`, `error`).
@immutable
class MeterImportRow {
  const MeterImportRow({required this.n, required this.code, required this.status, this.reason, this.value});

  final int n;
  final String code;
  final String status;
  final String? reason;
  final String? value;

  bool get isError => status == 'error';

  factory MeterImportRow.fromJson(Map<String, dynamic> json) => MeterImportRow(
    n: _int(json['n']),
    code: _str(json['code']),
    status: _str(json['status']),
    reason: json['reason'] as String?,
    value: json['value'] as String?,
  );

  /// Hata nedeninin düz Türkçe karşılığı.
  static String reasonText(String? reason) => switch (reason) {
    'CODE_MISSING' => 'Kod boş',
    'VALUE_INVALID' => 'Değer geçersiz (en çok 3 ondalıklı sayı)',
    'METER_NOT_FOUND' => 'Bu koda uyan etkin sayaç yok',
    'CODE_AMBIGUOUS' => 'Kod birden çok sayaca uyuyor; seri numarasını kullanın',
    'DUPLICATE_IN_FILE' => 'Dosyada bu sayaç birden çok kez geçiyor',
    'READING_EXISTS' => 'Bu tarihte farklı bir okuma zaten var',
    'READING_OUT_OF_ORDER' => 'Önceki ya da sonraki okumayla tutarsız',
    _ => 'Satır okunamadı',
  };
}

@immutable
class MeterImportResult {
  const MeterImportResult({required this.dryRun, required this.okCount, required this.sameCount, required this.errorCount, required this.rows});

  final bool dryRun;
  final int okCount;
  final int sameCount;
  final int errorCount;
  final List<MeterImportRow> rows;

  factory MeterImportResult.fromJson(Map<String, dynamic> json) => MeterImportResult(
    dryRun: json['dry_run'] == true,
    okCount: _int(json['ok_count']),
    sameCount: _int(json['same_count']),
    errorCount: _int(json['error_count']),
    rows: <MeterImportRow>[for (final m in _list(json['rows'])) MeterImportRow.fromJson(m)],
  );
}

@immutable
class BillingLine {
  const BillingLine({required this.apartmentId, required this.label, required this.consumption, required this.amountMinor, required this.accountParty});

  final int apartmentId;
  final String label;
  final String consumption;
  final int amountMinor;

  /// `owner` (ev sahibi hesabı) | `tenant` (kiracı hesabı).
  final String accountParty;

  factory BillingLine.fromJson(Map<String, dynamic> json) => BillingLine(
    apartmentId: _int(json['apartment_id']),
    label: _str(json['label']),
    consumption: _str(json['consumption']),
    amountMinor: _int(json['amount_minor']),
    accountParty: _str(json['account_party']),
  );
}

@immutable
class BillingMissing {
  const BillingMissing({required this.label, required this.reason});

  final String label;
  final String reason;

  factory BillingMissing.fromJson(Map<String, dynamic> json) => BillingMissing(label: _str(json['label']), reason: _str(json['reason']));

  String get reasonText => switch (reason) {
    'no_opening' => 'başlangıç okuması yok',
    'no_closing' => 'bitiş okuması yok',
    'decreasing' => 'okuma azalmış',
    'area_missing' => 'daire alanı (m²) girilmemiş',
    _ => 'eksik',
  };
}

/// Faturalandırma önizlemesi (`POST .../meter-billings/preview`).
@immutable
class BillingPreview {
  const BillingPreview({
    required this.totalMinor,
    required this.apartmentCount,
    required this.zeroCount,
    required this.lines,
    required this.missing,
    required this.previewHash,
    required this.canPost,
    required this.params,
  });

  final int totalMinor;
  final int apartmentCount;
  final int zeroCount;
  final List<BillingLine> lines;
  final List<BillingMissing> missing;
  final String previewHash;
  final bool canPost;
  final Map<String, dynamic> params;

  factory BillingPreview.fromJson(Map<String, dynamic> json) => BillingPreview(
    totalMinor: _int(json['total_minor']),
    apartmentCount: _int(json['apartment_count']),
    zeroCount: _int(json['zero_count']),
    lines: <BillingLine>[for (final m in _list(json['lines'])) BillingLine.fromJson(m)],
    missing: <BillingMissing>[for (final m in _list(json['missing'])) BillingMissing.fromJson(m)],
    previewHash: _str(json['preview_hash']),
    canPost: json['can_post'] == true,
    params: _map(json['params']),
  );
}

@immutable
class MeterBilling {
  const MeterBilling({required this.id, required this.kind, required this.method, required this.periodFrom, required this.periodTo, required this.totalMinor, required this.apartmentCount});

  final int id;
  final MeterKind kind;
  final String method;
  final String periodFrom;
  final String periodTo;
  final int totalMinor;
  final int apartmentCount;

  factory MeterBilling.fromJson(Map<String, dynamic> json) => MeterBilling(
    id: _int(json['id']),
    kind: MeterKind.tryParse(json['kind']) ?? MeterKind.water,
    method: _str(json['method']),
    periodFrom: _str(json['period_from']),
    periodTo: _str(json['period_to']),
    totalMinor: _int(json['total_minor']),
    apartmentCount: _int(json['apartment_count']),
  );

  static List<MeterBilling> listFrom(Map<String, dynamic> body) =>
      <MeterBilling>[for (final m in _list(body['items'])) MeterBilling.fromJson(m)];
}

/// Kuruşu "1.234,56 ₺" biçiminde yazar.
String formatMinorTl(int minor) {
  final negative = minor < 0;
  final abs = minor.abs();
  final whole = (abs ~/ 100).toString();
  final cents = (abs % 100).toString().padLeft(2, '0');
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write('.');
    buffer.write(whole[i]);
  }
  return '${negative ? '-' : ''}$buffer,$cents ₺';
}

/// "12,5" / "12.5" -> kuruş (tam sayı); en çok 2 ondalık. Geçersizse null.
int? parseTlToMinor(String text) {
  final match = RegExp(r'^(\d{1,10})(?:[.,](\d{1,2}))?$').firstMatch(text.trim());
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final cents = int.parse((match.group(2) ?? '').padRight(2, '0').isEmpty ? '0' : (match.group(2) ?? '').padRight(2, '0'));
  final minor = whole * 100 + cents;
  return minor > 0 ? minor : null;
}
