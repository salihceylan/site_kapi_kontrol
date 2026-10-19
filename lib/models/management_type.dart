/// Sitenin yönetim türü (`sites.management_type`).
///
/// Platform modül sistemi: beş yönetim türünün hepsi seçilebilir (bkz. [selectable]).
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

  /// Seçilebilir mi? Tüm türler seçilebilir (2026-10-19): veri modeli ve modüller aynıdır; türe özgü terimler (ofis, mağaza,
  /// üye payı vb.) sonraki aşamadadır. Sunucu `selectable:false` bir türü hâlâ MANAGEMENT_TYPE_COMING_SOON ile reddeder.
  bool get selectable => true;

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
