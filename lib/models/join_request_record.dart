class JoinRequestRecord {
  const JoinRequestRecord({
    required this.id,
    required this.siteCode,
    this.siteName,
    this.city,
    this.district,
    this.userCode,
    this.fullName,
    this.email,
    this.phoneNumber,
    this.blockId,
    this.blockName,
    required this.apartmentId,
    this.unitLabel,
    required this.status,
    this.notes,
    this.rejectionReason,
    this.createdAt,
    this.reviewedAt,
    this.reviewedByName,
  });

  final int id;
  final int siteCode;
  final String? siteName;
  final String? city;
  final String? district;
  final int? userCode;
  final String? fullName;
  final String? email;
  final String? phoneNumber;
  final int? blockId;
  final String? blockName;
  final int apartmentId;
  final String? unitLabel;
  final String status; // PENDING, APPROVED, REJECTED, CANCELLED
  final String? notes;
  final String? rejectionReason;

  /// Ayrıştırılamazsa null (uydurma 'şimdi' değeri KULLANILMAZ).
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final String? reviewedByName;

  bool get isPending => status == 'PENDING';
  bool get isApproved => status == 'APPROVED';
  bool get isRejected => status == 'REJECTED';

  factory JoinRequestRecord.fromJson(Map<String, dynamic> json) {
    return JoinRequestRecord(
      id: (json['id'] as num).toInt(),
      siteCode: (json['siteCode'] as num?)?.toInt() ??
          (json['site_code'] as num?)?.toInt() ??
          0,
      siteName: json['siteName'] as String? ?? json['site_name'] as String?,
      city: json['city'] as String?,
      district: json['district'] as String?,
      userCode: (json['userCode'] as num?)?.toInt() ??
          (json['user_code'] as num?)?.toInt(),
      fullName: json['fullName'] as String? ?? json['full_name'] as String?,
      email: json['email'] as String?,
      phoneNumber:
          json['phoneNumber'] as String? ?? json['phone_number'] as String?,
      blockId: (json['blockId'] as num?)?.toInt() ??
          (json['block_id'] as num?)?.toInt(),
      blockName: json['blockName'] as String? ?? json['block_name'] as String?,
      apartmentId: (json['apartmentId'] as num?)?.toInt() ??
          (json['apartment_id'] as num?)?.toInt() ??
          0,
      unitLabel: json['unitLabel'] as String? ?? json['unit_label'] as String?,
      status: (json['status'] as String? ?? 'PENDING').toUpperCase(),
      notes: json['notes'] as String?,
      rejectionReason: json['rejectionReason'] as String? ??
          json['rejection_reason'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ??
          json['created_at'] as String? ??
          ''),
      reviewedAt: DateTime.tryParse(json['reviewedAt'] as String? ??
          json['reviewed_at'] as String? ??
          ''),
      reviewedByName: json['reviewedByName'] as String? ??
          json['reviewed_by_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'siteCode': siteCode,
      'siteName': siteName,
      'city': city,
      'district': district,
      'userCode': userCode,
      'fullName': fullName,
      'email': email,
      'phoneNumber': phoneNumber,
      'blockId': blockId,
      'blockName': blockName,
      'apartmentId': apartmentId,
      'unitLabel': unitLabel,
      'status': status,
      'notes': notes,
      'rejectionReason': rejectionReason,
      'createdAt': createdAt?.toIso8601String(),
      'reviewedAt': reviewedAt?.toIso8601String(),
      'reviewedByName': reviewedByName,
    };
  }
}

