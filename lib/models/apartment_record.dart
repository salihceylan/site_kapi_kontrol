class ApartmentRecord {
  const ApartmentRecord({
    required this.id,
    required this.siteCode,
    required this.blockId,
    required this.blockName,
    required this.unitLabel,
    required this.sortOrder,
    required this.isActive,
    required this.residentUserCode,
    required this.residentFullName,
    required this.residentLoginName,
    required this.residentEmail,
    required this.residentPinCode,
    required this.residentPhoneNumber,
    required this.residentIsActive,
    required this.createdAt,
    this.residentPinIssued = false,
    this.residentPinResettable = false,
    this.householdCount,
  });

  final int id;
  final int siteCode;
  final int blockId;
  final String blockName;
  final String unitLabel;
  final int sortOrder;
  final bool isActive;
  final int? residentUserCode;
  final String? residentFullName;
  final String? residentLoginName;
  final String? residentEmail;

  /// Daire PIN'i. Sunucu PIN'i SAKLAMAZ (KVKK m.12): yalnız oluşturma / sıfırlama yanıtında BİR KEZ dolu
  /// gelir; listelerde her zaman null. Ekranda saklanıp yeniden gösterilmez.
  final String? residentPinCode;
  final String? residentPhoneNumber;
  final bool? residentIsActive;
  final DateTime? createdAt;

  /// Göstergedeki hesabın parolası yönetimin verdiği PIN'dir (sakin kendi parolasını belirlemedi).
  final bool residentPinIssued;

  /// Dahili daire hesabı: yönetici PIN'i sıfırlayabilir (kendi hesabıyla giren sakinin parolası
  /// yönetici tarafından değiştirilemez).
  final bool residentPinResettable;

  /// Dairenin güncel kişi sayısı (daire satırı özeti "5 kişi"). Eski sunucuda alan yoktur: null (özet çizilmez).
  /// Eski tek-sakin alanları ([residentFullName] ...) yalnız daire HESABININ sahibini gösterir; tüm kişiler için
  /// `ApartmentManagementService.household` kullanılır.
  final int? householdCount;

  String get label => '$blockName / $unitLabel';

  factory ApartmentRecord.fromJson(Map<String, dynamic> json) {
    return ApartmentRecord(
      id: json['id'] as int,
      siteCode: json['site_code'] as int,
      blockId: json['block_id'] as int,
      blockName: json['block_name'] as String? ?? '',
      unitLabel: json['unit_label'] as String? ?? '',
      sortOrder: json['sort_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      residentUserCode: json['resident_user_code'] as int?,
      residentFullName: json['resident_full_name'] as String?,
      residentLoginName: json['resident_login_name'] as String?,
      residentEmail: json['resident_email'] as String?,
      residentPinCode: json['resident_pin_code'] as String?,
      residentPhoneNumber: json['resident_phone_number'] as String?,
      residentIsActive: json['resident_is_active'] as bool?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
      // Eski sunucu bu alanları göndermez: false (PIN notu ve sıfırlama düğmesi gösterilmez).
      residentPinIssued: json['resident_pin_issued'] == true,
      residentPinResettable: json['resident_pin_resettable'] == true,
      householdCount: json['household_count'] is num
          ? (json['household_count'] as num).toInt()
          : null,
    );
  }
}
