class SiteBlockRecord {
  const SiteBlockRecord({
    required this.id,
    required this.siteCode,
    required this.blockName,
    required this.sortOrder,
    required this.createdAt,
  });

  final int id;
  final int siteCode;
  final String blockName;
  final int sortOrder;
  final DateTime? createdAt;

  factory SiteBlockRecord.fromJson(Map<String, dynamic> json) {
    return SiteBlockRecord(
      id: json['id'] as int,
      siteCode: json['site_code'] as int,
      blockName: json['block_name'] as String? ?? '',
      sortOrder: json['sort_order'] as int? ?? 0,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'] as String),
    );
  }
}
