// "Dairem > Araçlarım" modeli: dairenin araçları, yazma yetkisi (daire yöneticisi / site yöneticisi), sınır ve sahip seçenekleri.
// Sözleşme: docs/PLATFORM_DAIRE_YONETIMI.md ("Araçlar"). Alan yoksa güvenli varsayılan (salt okunur).
import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart';

/// Ekranda gösterilen etki uyarısı (sunucudaki cümleyle aynı): kayıtlı araç plaka tanımada yetkili sayılır.
const String kPlateRecognitionNotice = 'Eklediğiniz plaka, sitede plaka tanıma açıksa yetkili araç sayılır.';

/// Aracın sahibi olarak seçilebilen dairenin aktif sakini.
@immutable
class AptVehicleOwner {
  const AptVehicleOwner({required this.personId, required this.name, this.isDefault = false});

  factory AptVehicleOwner.fromJson(Map<String, dynamic> j) => AptVehicleOwner(
    personId: crmInt(j['person_id']),
    name: crmText(j['name']) ?? 'Kayıtlı kişi',
    isDefault: j['is_default'] == true,
  );

  final int personId;
  final String name;
  final bool isDefault;
}

@immutable
class ApartmentVehicles {
  const ApartmentVehicles({
    this.items = const <VehicleRecord>[],
    this.canManage = false,
    this.limit = 4,
    this.owners = const <AptVehicleOwner>[],
    this.notice = kPlateRecognitionNotice,
  });

  factory ApartmentVehicles.fromJson(Map<String, dynamic> j) {
    final owners = j['owners'];
    return ApartmentVehicles(
      items: VehicleRecord.listFrom(j['items']),
      canManage: j['can_manage'] == true,
      limit: crmInt(j['limit'], 4),
      owners: <AptVehicleOwner>[
        if (owners is List) for (final e in owners) if (e is Map) AptVehicleOwner.fromJson(Map<String, dynamic>.from(e)),
      ],
      notice: crmText(j['notice']) ?? kPlateRecognitionNotice,
    );
  }

  final List<VehicleRecord> items;

  /// Çağıran bu dairenin aracını ekleyip değiştirebilir (daire yöneticisi ya da site yöneticisi).
  final bool canManage;

  /// Daire başına en çok aktif araç (daire yöneticisi 4, site yöneticisi 8).
  final int limit;
  final List<AptVehicleOwner> owners;
  final String notice;

  bool get isFull => items.length >= limit;
}

/// Türkiye plakası (sunucuyla aynı kural): il kodu 01-81 + 1-3 harf + 2-4 rakam. Boşluk / tire / nokta atılır, büyük harf;
/// Türkçe harfler ASCII'ye iner. Geçerliyse normalize plaka (`34ABC123`), değilse null.
String? normalizeTrPlateInput(String? text) {
  final raw = (text ?? '').trim();
  if (raw.isEmpty || raw.length > 24) return null;
  const map = <String, String>{'Ç': 'C', 'Ğ': 'G', 'İ': 'I', 'I': 'I', 'Ö': 'O', 'Ş': 'S', 'Ü': 'U', 'ç': 'C', 'ğ': 'G', 'ı': 'I', 'i': 'I', 'ö': 'O', 'ş': 'S', 'ü': 'U'};
  final plate = raw
      .replaceAll(RegExp(r'[\s\-._]'), '')
      .split('')
      .map((ch) => map[ch] ?? ch.toUpperCase())
      .join();
  return RegExp(r'^(0[1-9]|[1-7][0-9]|8[01])[A-Z]{1,3}[0-9]{2,4}$').hasMatch(plate) ? plate : null;
}
