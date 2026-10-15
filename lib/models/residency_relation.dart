/// Kişinin dairedeki ilişkisi (`apartment_residencies.relation`). Platform Faz 2a.
///
/// `resident` = ilişki belirtilmemiş (mevcut sakinler bununla aktarılır; malik/kiracı olduğunu yönetici
/// sonradan işaretler).
enum ResidencyRelation {
  owner('owner', 'Malik'),
  tenant('tenant', 'Kiracı'),
  familyMember('family_member', 'Aile Üyesi'),
  resident('resident', 'Sakin');

  const ResidencyRelation(this.apiValue, this.label);

  /// Sunucudaki değer.
  final String apiValue;

  /// Kullanıcıya gösterilen Türkçe ad.
  final String label;

  /// Bir dairede aynı anda en çok BİR güncel kişide olabilen ilişki (malik, kiracı). İkincisi için
  /// sunucu 409 `RELATION_TAKEN` döner.
  bool get isExclusive =>
      this == ResidencyRelation.owner || this == ResidencyRelation.tenant;

  /// Bilinmeyen değerde null.
  static ResidencyRelation? tryParse(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim().toLowerCase();
    for (final relation in values) {
      if (relation.apiValue == normalized) return relation;
    }
    return null;
  }

  /// Alan yoksa / bilinmiyorsa `resident` (ilişki belirtilmemiş).
  static ResidencyRelation fromApi(Object? value) =>
      tryParse(value) ?? ResidencyRelation.resident;
}

/// "Borç ve bildirimler kime gitsin" (`apartments.responsible_party`). Borç tarafını Faz 4 kullanır.
enum ResponsibleParty {
  owner('owner', 'Malik'),
  tenant('tenant', 'Kiracı'),
  both('both', 'İkisi');

  const ResponsibleParty(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Alan yoksa / bilinmiyorsa `both` (sunucu varsayılanı).
  static ResponsibleParty fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final party in values) {
        if (party.apiValue == normalized) return party;
      }
    }
    return ResponsibleParty.both;
  }
}
