import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

class SiteResidentsTreeSite {
  final int id;
  final String name;
  final String? city;
  final String? district;
  final int totalBlocks;
  final int totalApartments;
  final int totalResidents;
  final int emptyApartmentsCount;

  const SiteResidentsTreeSite({
    required this.id,
    required this.name,
    this.city,
    this.district,
    required this.totalBlocks,
    required this.totalApartments,
    required this.totalResidents,
    required this.emptyApartmentsCount,
  });

  factory SiteResidentsTreeSite.fromJson(Map<String, dynamic> json) {
    return SiteResidentsTreeSite(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      city: json['city'] as String?,
      district: json['district'] as String?,
      totalBlocks: json['total_blocks'] as int? ?? 0,
      totalApartments: json['total_apartments'] as int? ?? 0,
      totalResidents: json['total_residents'] as int? ?? 0,
      emptyApartmentsCount: json['empty_apartments_count'] as int? ?? 0,
    );
  }
}

class SiteResidentMember {
  final int userCode;
  final String fullName;
  final String? email;
  final String? phoneNumber;
  final String? loginName;
  final String role; // 'APARTMENT_ADMIN' or 'FAMILY_MEMBER'
  final String? joinedAt;

  /// Üyelik VE hesap birlikte aktif mi (sunucu: `is_active`).
  final bool isActive;

  /// Yalnız global hesap durumu (sunucu: `account_is_active`). Hesabı sistem yöneticisi
  /// pasife almışsa false: üyelik aktif edilse bile giriş ve kapı erişimi kapalı kalır.
  /// Eski sunucuda alan yoksa true sayılır.
  final bool accountIsActive;

  const SiteResidentMember({
    required this.userCode,
    required this.fullName,
    this.email,
    this.phoneNumber,
    this.loginName,
    required this.role,
    this.joinedAt,
    required this.isActive,
    this.accountIsActive = true,
  });

  factory SiteResidentMember.fromJson(Map<String, dynamic> json) {
    return SiteResidentMember(
      userCode: json['user_code'] as int? ?? 0,
      fullName: json['full_name'] as String? ?? '',
      email: json['email'] as String?,
      phoneNumber: json['phone_number'] as String?,
      loginName: json['login_name'] as String?,
      role: json['role'] as String? ?? 'FAMILY_MEMBER',
      joinedAt: json['joined_at'] as String?,
      isActive: json['is_active'] != false,
      accountIsActive: json['account_is_active'] != false,
    );
  }

  bool get isAdmin => role == 'APARTMENT_ADMIN';
  bool get isFamilyMember => role == 'FAMILY_MEMBER';

  String get roleLabel => isAdmin ? 'Daire Admini' : 'Aile Üyesi';

  Color getRoleBgColor(bool isDark) {
    if (isAdmin) {
      return (isDark ? AppColors.amber : const Color(0xFFD97706)).withValues(alpha: isDark ? 0.25 : 0.15);
    }
    return (isDark ? const Color(0xFF8B5CF6) : const Color(0xFF7C3AED)).withValues(alpha: isDark ? 0.25 : 0.12);
  }

  Color getRoleTextColor(bool isDark) {
    if (isAdmin) {
      return isDark ? AppColors.amberLight : const Color(0xFFB45309);
    }
    return isDark ? const Color(0xFFA78BFA) : const Color(0xFF6D28D9);
  }
}

class SiteResidentApartment {
  final int id;
  final int blockId;
  final String unitLabel;
  final int sortOrder;
  final String? residentPinCode;
  final int totalResidents;
  final List<SiteResidentMember> residents;

  const SiteResidentApartment({
    required this.id,
    required this.blockId,
    required this.unitLabel,
    required this.sortOrder,
    this.residentPinCode,
    required this.totalResidents,
    required this.residents,
  });

  factory SiteResidentApartment.fromJson(Map<String, dynamic> json) {
    return SiteResidentApartment(
      id: json['id'] as int? ?? 0,
      blockId: json['block_id'] as int? ?? 0,
      unitLabel: json['unit_label'] as String? ?? '',
      sortOrder: json['sort_order'] as int? ?? 0,
      residentPinCode: json['resident_pin_code'] as String?,
      totalResidents: json['total_residents'] as int? ?? 0,
      residents: (json['residents'] as List<dynamic>? ?? const [])
          .map((r) => SiteResidentMember.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  bool get isEmpty => residents.isEmpty;
}

class SiteResidentBlock {
  final int id;
  final String blockName;
  final int sortOrder;
  final int totalApartments;
  final int totalResidents;
  final List<SiteResidentApartment> apartments;

  const SiteResidentBlock({
    required this.id,
    required this.blockName,
    required this.sortOrder,
    required this.totalApartments,
    required this.totalResidents,
    required this.apartments,
  });

  factory SiteResidentBlock.fromJson(Map<String, dynamic> json) {
    return SiteResidentBlock(
      id: json['id'] as int? ?? 0,
      blockName: json['block_name'] as String? ?? '',
      sortOrder: json['sort_order'] as int? ?? 0,
      totalApartments: json['total_apartments'] as int? ?? 0,
      totalResidents: json['total_residents'] as int? ?? 0,
      apartments: (json['apartments'] as List<dynamic>? ?? const [])
          .map((a) => SiteResidentApartment.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SiteResidentsTreeData {
  final SiteResidentsTreeSite site;
  final List<SiteResidentBlock> blocks;

  const SiteResidentsTreeData({
    required this.site,
    required this.blocks,
  });

  factory SiteResidentsTreeData.fromJson(Map<String, dynamic> json) {
    return SiteResidentsTreeData(
      site: SiteResidentsTreeSite.fromJson(json['site'] as Map<String, dynamic>? ?? {}),
      blocks: (json['blocks'] as List<dynamic>? ?? const [])
          .map((b) => SiteResidentBlock.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }
}

