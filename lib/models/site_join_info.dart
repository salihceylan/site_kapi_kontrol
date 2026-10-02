class SiteJoinBlockInfo {
  const SiteJoinBlockInfo({
    required this.id,
    required this.blockName,
    this.blockIndex,
    this.apartmentCount = 0,
  });

  final int id;
  final String blockName;
  final int? blockIndex;
  final int apartmentCount;

  factory SiteJoinBlockInfo.fromJson(Map<String, dynamic> json) {
    return SiteJoinBlockInfo(
      id: (json['id'] as num).toInt(),
      blockName: json['block_name'] as String? ?? json['blockName'] as String? ?? '',
      blockIndex: (json['block_index'] as num?)?.toInt() ?? (json['blockIndex'] as num?)?.toInt() ?? (json['sort_order'] as num?)?.toInt(),
      apartmentCount: (json['apartment_count'] as num?)?.toInt() ?? (json['apartmentCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class SiteJoinApartmentInfo {
  const SiteJoinApartmentInfo({
    required this.id,
    this.blockId,
    required this.unitLabel,
    this.sortOrder,
  });

  final int id;
  final int? blockId;
  final String unitLabel;
  final int? sortOrder;

  factory SiteJoinApartmentInfo.fromJson(Map<String, dynamic> json) {
    return SiteJoinApartmentInfo(
      id: (json['id'] as num).toInt(),
      blockId: (json['block_id'] as num?)?.toInt() ?? (json['blockId'] as num?)?.toInt(),
      unitLabel: json['unit_label'] as String? ?? json['unitLabel'] as String? ?? '',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? (json['sortOrder'] as num?)?.toInt(),
    );
  }
}

class SiteJoinInfo {
  const SiteJoinInfo({
    required this.siteCode,
    required this.siteName,
    this.city,
    this.district,
    this.address,
    required this.token,
    this.blocks = const [],
    this.apartments = const [],
  });

  final int siteCode;
  final String siteName;
  final String? city;
  final String? district;
  final String? address;
  final String token;
  final List<SiteJoinBlockInfo> blocks;
  final List<SiteJoinApartmentInfo> apartments;

  factory SiteJoinInfo.fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['blocks'] as List<dynamic>? ?? const [];
    final rawApts = json['apartments'] as List<dynamic>? ?? const [];

    return SiteJoinInfo(
      siteCode: (json['site_code'] as num?)?.toInt() ?? (json['siteCode'] as num?)?.toInt() ?? 0,
      siteName: json['site_name'] as String? ?? json['siteName'] as String? ?? '',
      city: json['city'] as String?,
      district: json['district'] as String?,
      address: json['address'] as String?,
      token: json['token'] as String? ?? '',
      blocks: rawBlocks
          .map((b) => SiteJoinBlockInfo.fromJson(b as Map<String, dynamic>))
          .toList(),
      apartments: rawApts
          .map((a) => SiteJoinApartmentInfo.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}

