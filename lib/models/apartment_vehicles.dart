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
