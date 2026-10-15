/// Sitenin yönetim türü (`sites.management_type`).
///
/// Platform modül sistemi Faz 1: yalnız [apartmentSite] seçilebilir; diğer dördü "Yakında…" olarak
/// gösterilir ve sunucu tarafından `MANAGEMENT_TYPE_COMING_SOON` ile reddedilir.
enum ManagementType {
  apartmentSite('apartment_site', 'Apartman ve Site'),
  residence('residence', 'Rezidans'),
  businessCenter('business_center', 'İş Merkezi'),
  cooperative('cooperative', 'Kooperatif'),
  shoppingMall('shopping_mall', 'Alışveriş Merkezi');

  const ManagementType(this.apiValue, this.label);

  /// Sunucudaki değer (`management_type`).
  final String apiValue;

  /// Kullanıcıya gösterilen Türkçe ad (sunucudaki `management_type_label` ile aynı).
  final String label;

  /// Bu fazda seçilebilir mi? (Yalnız Apartman ve Site.)
  bool get selectable => this == ManagementType.apartmentSite;

  /// Sunucu değerinden tür. Alan yoksa, boşsa ya da bilinmiyorsa (eski sunucu / yeni tür)
  /// `apartment_site` (geriye dönük uyum: mevcut tüm siteler bu türdedir).
  static ManagementType fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim();
      for (final type in values) {
        if (type.apiValue == normalized) return type;
      }
    }
    return ManagementType.apartmentSite;
  }
}
