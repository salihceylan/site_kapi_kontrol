// Sayaç saha okuması (fotoğrafla okuma, çevrimdışı kuyruk) modeli. Sunucu sözleşmesi: docs/PLATFORM_SAYAC.md "Fotoğrafla okuma".
// Okuma değeri METİN taşınır (en çok 3 ondalık). Fotoğraf baytları günlüğe YAZILMAZ.
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/meter_models.dart';

/// Son 3 dönem tüketim tabanı (sunucu `jump`; karar K12): tüketim [limit]'i AŞARSA görevli uyarılır (engel değil, onaylayıp geçer).
/// Değerler en çok 3 ondalıklı METİN; [factor] sitenin eşik çarpanıdır (varsayılan 5).
@immutable
class FieldJump {
  const FieldJump({required this.median, required this.limit, required this.factor});

  final String median;
  final String limit;
  final int factor;

  static FieldJump? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final median = raw['median'];
    final limit = raw['limit'];
    final factor = raw['factor'];
    if (median == null || limit == null || factor is! num) return null;
    return FieldJump(median: '$median', limit: '$limit', factor: factor.toInt());
  }
}

/// Sahada okunacak etkin sayaç (sunucu `GET .../meter-field/meters`). Blok / önceki okuma / sıçrama tabanı alanları YENİ sunucudan gelir;
/// eski sunucuda yoktur (blok etiketten türetilir, taban null olur: uyarı yalnız sunucudan gelir).
@immutable
class FieldMeter {
  const FieldMeter({
    required this.id,
    required this.kind,
    required this.serialNo,
    required this.apartmentLabel,
    this.lastValue,
    this.lastDate,
    this.blockName,
    this.unitLabel,
    this.previousValue,
    this.previousDate,
    this.jump,
  });

  final int id;
  final MeterKind kind;
  final String serialNo;
  final String apartmentLabel;
  final String? lastValue;

  /// "2026-10-20" biçimi.
  final String? lastDate;

  /// Sunucudan gelen blok adı ("A Blok") ve daire etiketi ("13").
  final String? blockName;
  final String? unitLabel;

  /// Okuma tarihinden ÖNCEKİ son okuma (bugünkü okuma varsa ondan öncekisi: yeniden çekimin tabanı).
  final String? previousValue;
  final String? previousDate;

  /// Son 3 dönem tüketim tabanı; yeterli veri yoksa null (uyarı yok).
  final FieldJump? jump;

  /// Blok adı: sunucudan, yoksa "A Blok - 13" etiketinden; blok bilgisi yoksa boş metin.
  String get block => blockName ?? _splitLabel(apartmentLabel).$1;

  /// Blok olmadan daire adı ("13"); blok bilgisi yoksa etiketin tamamı.
  String get unit => unitLabel ?? _splitLabel(apartmentLabel).$2;

  /// Yeni okumanın dönem tüketimini hesaplayacağı önceki okuma değeri. Yeni sunucu `previous_reading` verir; eski sunucuda son okuma
  /// ([retake] değilse) ya da bilinmiyor (yeniden çekimde son okuma, değiştirilecek bugünkü okumanın kendisidir).
  String? baseValueFor({required bool retake}) => previousValue ?? (retake ? null : lastValue);

  static (String, String) _splitLabel(String label) {
    final at = label.indexOf(' - ');
    if (at <= 0) return ('', label.trim());
    return (label.substring(0, at).trim(), label.substring(at + 3).trim());
  }

  static FieldMeter? tryFromJson(Map<String, dynamic> json) {
    final kind = MeterKind.tryParse(json['kind']);
    final id = json['id'];
    if (kind == null || id is! num) return null;
    final last = json['last_reading'];
    final previous = json['previous_reading'];
    return FieldMeter(
      id: id.toInt(),
      kind: kind,
      serialNo: '${json['serial_no'] ?? ''}',
      apartmentLabel: '${json['apartment_label'] ?? ''}',
      lastValue: last is Map ? '${last['value']}' : null,
      lastDate: last is Map && last['date'] != null ? '${last['date']}'.substring(0, 10) : null,
      blockName: json['block_name'] is String ? json['block_name'] as String : null,
      unitLabel: json['unit_label'] is String ? json['unit_label'] as String : null,
      previousValue: previous is Map && previous['value'] != null ? '${previous['value']}' : null,
      previousDate: previous is Map && previous['date'] != null ? '${previous['date']}'.substring(0, 10) : null,
      jump: FieldJump.tryFromJson(json['jump']),
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

/// Sunucunun "olağan dışı tüketim" uyarısının hata kodu (409): görevli onaylarsa aynı okuma `confirm_jump` ile yeniden gönderilir.
const String kReadingJumpCode = 'READING_JUMP';

/// Cihazda bekleyen okuma. [photoPath] cihaz dosyası (web'de yok); [error] sunucunun kalıcı reddi (düzeltilene dek yeniden denenmez).
/// [replace]: yeniden çekim (o günün okuması varsa değeri değiştirir). [jumpConfirmed]: görevli olağan dışı tüketimi onayladı (sunucuya
/// `confirm_jump: true` gider). [errorCode]: reddin sunucu kodu (örn. [kReadingJumpCode]: onay bekliyor).
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
    this.errorCode,
    this.replace = false,
    this.jumpConfirmed = false,
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
  final String? errorCode;
  final bool replace;
  final bool jumpConfirmed;

  /// Sunucu olağan dışı tüketim nedeniyle durdurdu; görevlinin onayını bekliyor.
  bool get needsJumpConfirm => error != null && errorCode == kReadingJumpCode;

  PendingMeterReading copyWith({String? value, String? error, String? errorCode, bool clearError = false, bool? jumpConfirmed}) => PendingMeterReading(
    id: id,
    siteCode: siteCode,
    meterId: meterId,
    apartmentLabel: apartmentLabel,
    kindLabel: kindLabel,
    date: date,
    value: value ?? this.value,
    photoPath: photoPath,
    error: clearError ? null : (error ?? this.error),
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    replace: replace,
    jumpConfirmed: jumpConfirmed ?? this.jumpConfirmed,
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
    if (errorCode != null) 'code': errorCode,
    if (replace) 'replace': true,
    if (jumpConfirmed) 'jc': true,
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
      errorCode: raw['code'] is String ? raw['code'] as String : null,
      replace: raw['replace'] == true,
      jumpConfirmed: raw['jc'] == true,
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

/// Blok adları, listedeki (daire) sırayla; blok bilgisi olmayan sayaçlar listeye girmez.
List<String> fieldBlocks(List<FieldMeter> meters) {
  final blocks = <String>[];
  for (final meter in meters) {
    final block = meter.block;
    if (block.isNotEmpty && !blocks.contains(block)) blocks.add(block);
  }
  return blocks;
}

final RegExp _milliPattern = RegExp(r'^(\d{1,11})(?:\.(\d{1,3}))?$');

/// En çok 3 ondalıklı sayı metnini binde bir birimle tam sayıya çevirir ("12.5" -> 12500); geçersizse null. Kayan nokta kullanılmaz.
int? parseMilli(String? text) {
  if (text == null) return null;
  final match = _milliPattern.firstMatch(text.trim());
  if (match == null) return null;
  return int.parse(match.group(1)!) * 1000 + int.parse((match.group(2) ?? '').padRight(3, '0'));
}

/// Binde bir birimli tam sayıyı ekran metnine çevirir: 24000 -> "24", 1234500 -> "1234,5" (sondaki sıfırlar atılır, ayraç virgül).
String formatMilli(int milli) {
  final whole = milli ~/ 1000;
  final fraction = (milli % 1000).toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole,$fraction';
}

/// Sunucu / giriş metnini ekran metnine çevirir ("1234.500" -> "1234,5"); sayı değilse olduğu gibi.
String formatMeterNumber(String text) {
  final milli = parseMilli(text);
  return milli == null ? text : formatMilli(milli);
}

/// Cihazda saptanan olağan dışı tüketim (değerler binde bir birimle tam sayı).
@immutable
class JumpFinding {
  const JumpFinding({required this.consumption, required this.median, required this.limit, required this.factor});

  final int consumption;
  final int median;
  final int limit;
  final int factor;
}

/// [value] okunursa dönem tüketimi (değer - önceki okuma) son 3 dönem medyanının eşik katını AŞAR mı? Aşarsa bulgu; taban yoksa
/// (sunucu 3 dönemden az veride göndermez), tüketim eşiğe eşit ya da altındaysa ya da değer önceki okumadan küçükse null.
/// Karar sunucuda da verilir (`READING_JUMP`); bu kontrol görevliyi sıradaki daireye geçmeden uyarmak içindir.
JumpFinding? checkJump(FieldMeter meter, String value) {
  final jump = meter.jump;
  if (jump == null) return null;
  final now = parseMilli(value);
  final previous = parseMilli(meter.previousValue);
  final median = parseMilli(jump.median);
  final limit = parseMilli(jump.limit);
  if (now == null || previous == null || median == null || limit == null) return null;
  final consumption = now - previous;
  if (consumption < 0 || consumption <= limit) return null;
  return JumpFinding(consumption: consumption, median: median, limit: limit, factor: jump.factor);
}

/// Girilen değer önceki okumadan küçükse önceki okuma metni (sayaç geriye gitmez; sunucu da reddeder); değilse null.
/// [retake]: yeniden çekim (taban için bkz. [FieldMeter.baseValueFor]).
String? belowPreviousReading(FieldMeter meter, String value, {required bool retake}) {
  final base = meter.baseValueFor(retake: retake);
  final now = parseMilli(value);
  final previous = parseMilli(base);
  if (now == null || previous == null || now >= previous) return null;
  return base;
}
