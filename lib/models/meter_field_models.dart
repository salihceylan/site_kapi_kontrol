// Sayaç saha okuması (fotoğrafla okuma, çevrimdışı kuyruk) modeli. Sunucu sözleşmesi: docs/PLATFORM_SAYAC.md "Fotoğrafla okuma".
// Okuma değeri METİN taşınır (en çok 3 ondalık). Fotoğraf baytları günlüğe YAZILMAZ.
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/meter_models.dart';

/// Sahada okunacak etkin sayaç (sunucu `GET .../meter-field/meters`).
@immutable
class FieldMeter {
  const FieldMeter({required this.id, required this.kind, required this.serialNo, required this.apartmentLabel, this.lastValue, this.lastDate});

  final int id;
  final MeterKind kind;
  final String serialNo;
  final String apartmentLabel;
  final String? lastValue;

  /// "2026-10-20" biçimi.
  final String? lastDate;

  static FieldMeter? tryFromJson(Map<String, dynamic> json) {
    final kind = MeterKind.tryParse(json['kind']);
    final id = json['id'];
    if (kind == null || id is! num) return null;
    final last = json['last_reading'];
    return FieldMeter(
      id: id.toInt(),
      kind: kind,
      serialNo: '${json['serial_no'] ?? ''}',
      apartmentLabel: '${json['apartment_label'] ?? ''}',
      lastValue: last is Map ? '${last['value']}' : null,
      lastDate: last is Map && last['date'] != null ? '${last['date']}'.substring(0, 10) : null,
    );
  }

  static List<FieldMeter> listFrom(Map<String, dynamic> body) => <FieldMeter>[
    for (final raw in (body['items'] as List? ?? const <Object?>[]))
      if (raw is Map) ?FieldMeter.tryFromJson(Map<String, dynamic>.from(raw)),
  ];
}

/// Sunucunun okuma yanıtı: tekrar gönderim mi, fotoğraf nereye gitti (`drive` | `server` | `none`).
@immutable
class FieldReadingResult {
  const FieldReadingResult({required this.replayed, required this.photoStorage, this.photoName});

  final bool replayed;
  final String photoStorage;
  final String? photoName;

  factory FieldReadingResult.fromJson(Map<String, dynamic> json) {
    final photo = json['photo'] is Map ? Map<String, dynamic>.from(json['photo'] as Map) : const <String, dynamic>{};
    return FieldReadingResult(
      replayed: json['replayed'] == true,
      photoStorage: '${photo['storage'] ?? 'none'}',
      photoName: photo['name'] is String ? photo['name'] as String : null,
    );
  }
}

/// Cihazda bekleyen okuma. [photoPath] cihaz dosyası (web'de yok); [error] sunucunun kalıcı reddi (düzeltilene dek yeniden denenmez).
@immutable
class PendingMeterReading {
  const PendingMeterReading({
    required this.id,
    required this.siteCode,
    required this.meterId,
    required this.apartmentLabel,
    required this.kindLabel,
    required this.date,
    required this.value,
    this.photoPath,
    this.error,
  });

  final String id;
  final int siteCode;
  final int meterId;
  final String apartmentLabel;
  final String kindLabel;
  final String date;
  final String value;
  final String? photoPath;
  final String? error;

  PendingMeterReading copyWith({String? value, String? error, bool clearError = false}) => PendingMeterReading(
    id: id,
    siteCode: siteCode,
    meterId: meterId,
    apartmentLabel: apartmentLabel,
    kindLabel: kindLabel,
    date: date,
    value: value ?? this.value,
    photoPath: photoPath,
    error: clearError ? null : (error ?? this.error),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'site': siteCode,
    'meter': meterId,
    'apt': apartmentLabel,
    'kind': kindLabel,
    'date': date,
    'value': value,
    if (photoPath != null) 'photo': photoPath,
    if (error != null) 'error': error,
  };

  static PendingMeterReading? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final site = raw['site'];
    final meter = raw['meter'];
    final date = raw['date'];
    final value = raw['value'];
    if (id is! String || site is! num || meter is! num || date is! String || value is! String) return null;
    return PendingMeterReading(
      id: id,
      siteCode: site.toInt(),
      meterId: meter.toInt(),
      apartmentLabel: '${raw['apt'] ?? ''}',
      kindLabel: '${raw['kind'] ?? ''}',
      date: date,
      value: value,
      photoPath: raw['photo'] is String ? raw['photo'] as String : null,
      error: raw['error'] is String ? raw['error'] as String : null,
    );
  }
}

final RegExp _valuePattern = RegExp(r'^\d{1,11}(\.\d{1,3})?$');

/// Elle girilen/okunan değeri sunucu biçimine çevirir ("1 234,5" -> "1234.5"); geçersizse null.
String? normalizeReadingValue(String input) {
  final text = input.trim().replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  return _valuePattern.hasMatch(text) ? text : null;
}

/// Metin tanıma çıktısından sayaç değeri adayı. Sayaç ekranında en uzun rakam dizisi endekstir; son okuma biliniyorsa ondan küçük
/// adaylar elenir (okuma geriye gitmez). Bulunamazsa null; sonucu görevli HER ZAMAN onaylar/düzeltir.
String? pickMeterValue(String recognized, {String? lastValue}) {
  final candidates = <String>[
    for (final m in RegExp(r'\d{2,9}(?:[.,]\d{1,3})?').allMatches(recognized.replaceAll(RegExp(r'(?<=\d) (?=\d{3}\b)'), '')))
      ?normalizeReadingValue(m.group(0)!),
  ];
  if (candidates.isEmpty) return null;
  final last = lastValue == null ? null : double.tryParse(lastValue);
  final usable = last == null ? candidates : candidates.where((c) => double.parse(c) >= last).toList();
  final pool = usable.isEmpty ? candidates : usable;
  pool.sort((a, b) {
    final byLength = b.replaceAll('.', '').length.compareTo(a.replaceAll('.', '').length);
    return byLength != 0 ? byLength : a.compareTo(b);
  });
  return pool.first;
}

/// Sıradaki okunacak sayaç: bugün okunmamış ve [skipped] içinde olmayan ilk sayaç (liste daire sırasındadır); yoksa null.
FieldMeter? nextFieldMeter(List<FieldMeter> meters, {required String today, Set<int> done = const <int>{}, Set<int> skipped = const <int>{}}) {
  for (final meter in meters) {
    if (meter.lastDate == today || done.contains(meter.id) || skipped.contains(meter.id)) continue;
    return meter;
  }
  return null;
}
