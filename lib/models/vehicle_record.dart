import 'package:flutter/foundation.dart';

/// Ortak ayrıştırma yardımcıları (Platform Faz 2a modelleri): alan yok / bozuk ise güvenli varsayılan.
int crmInt(Object? raw, [int fallback = 0]) {
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? fallback;
}

int? crmIntOrNull(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString());
}

/// NUMERIC alanlar sunucudan sayı ya da metin ("120.50") olarak gelebilir.
double? crmDoubleOrNull(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString().trim().replaceAll(',', '.'));
}

String? crmText(Object? raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}

/// DATE alanı (`YYYY-AA-GG`): saat/saat dilimi uygulanmaz, takvim günü olduğu gibi okunur (saat dilimi
/// kayması bir günü değiştirmesin). Bozuk değerde null.
DateTime? crmDate(Object? raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(year, month, day);
}

/// Zaman damgası (ISO); yerel saate çevrilir. Bozuk değerde null.
DateTime? crmTimestamp(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toLocal();
}

/// Sunucuya giden `YYYY-AA-GG` biçimi.
String crmDateParam(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-$month-$day';
}

/// Araç kaydı (`vehicles`). Plaka sunucuda normalize edilir (büyük harf, boşluksuz); [plateDisplay]
/// kullanıcının yazdığı biçimdir.
@immutable
class VehicleRecord {
  const VehicleRecord({
    required this.id,
    required this.plate,
    this.plateDisplay = '',
    this.note,
    this.personId,
    this.personName,
    this.apartmentLabel,
    this.isActive = true,
  });

  final int id;
  final String plate;
  final String plateDisplay;
  final String? note;
  final int? personId;
  final String? personName;
  final String? apartmentLabel;
  final bool isActive;

  /// Notsuz kopya: sakinin kendi kayıtlarında (`/app/my-records`) araç notu gösterilmez.
  VehicleRecord withoutNote() => VehicleRecord(
    id: id,
    plate: plate,
    plateDisplay: plateDisplay,
    personId: personId,
    personName: personName,
    apartmentLabel: apartmentLabel,
    isActive: isActive,
  );

  /// Gösterilecek plaka: görüntüleme biçimi varsa o, yoksa normalize plaka.
  String get displayPlate => plateDisplay.trim().isEmpty ? plate : plateDisplay.trim();

  factory VehicleRecord.fromJson(Map<String, dynamic> json) {
    return VehicleRecord(
      id: crmInt(json['id']),
      plate: json['plate']?.toString() ?? '',
      plateDisplay: json['plate_display']?.toString() ?? '',
      note: crmText(json['note']),
      personId: crmIntOrNull(json['person_id']),
      personName: crmText(json['person_name']),
      apartmentLabel: crmText(json['apartment_label']),
      isActive: json['is_active'] is bool ? json['is_active'] as bool : true,
    );
  }

  static List<VehicleRecord> listFrom(Object? raw) {
    if (raw is! List) return const <VehicleRecord>[];
    return raw
        .whereType<Map>()
        .map((e) => VehicleRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }
}

/// `GET .../vehicles` sayfası.
@immutable
class VehiclePage {
  const VehiclePage({this.items = const <VehicleRecord>[], this.total = 0});

  final List<VehicleRecord> items;
  final int total;

  factory VehiclePage.fromJson(Map<String, dynamic> json) {
    final items = VehicleRecord.listFrom(json['items']);
    return VehiclePage(items: items, total: crmInt(json['total'], items.length));
  }
}
