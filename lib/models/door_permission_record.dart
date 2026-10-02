import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';

// Sunucu (membership_service.getDoorPermissions) yanıtı: kapı {id, site_code, site_name,
// door_name, access_scope, block_id, block_name}; blok {id, block_name, total_residents,
// authorized_count, apartments}; daire {id, unit_label, residents, resident_count,
// authorized_count}; sakin {user_code, full_name, email, role, has_access, access_source,
// override: {id, is_allowed, notes, updated_at} | null}. Eski istemci anahtarları
// (site_id, can_open, member_role, override_*, door_number, allowed_residents_count)
// geriye dönük uyum için ikinci sırada okunur ("yeni ?? eski").
int? _asIntOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value == null) return null;
  return int.tryParse(value.toString());
}

class DoorPermissionInfo {
  final int id;
  final int siteId;
  final String doorName;
  final String accessScope;
  final int? blockId;
  final String? blockName;

  const DoorPermissionInfo({
    required this.id,
    required this.siteId,
    required this.doorName,
    required this.accessScope,
    this.blockId,
    this.blockName,
  });

  factory DoorPermissionInfo.fromJson(Map<String, dynamic> json) {
    return DoorPermissionInfo(
      id: _asIntOrNull(json['id']) ?? 0,
      // Sunucu 'site_code' gönderir (siteId bu modelde site kodu anlamında kullanılır).
      siteId: _asIntOrNull(json['site_code'] ?? json['site_id']) ?? 0,
      doorName: json['door_name'] as String? ?? '',
      accessScope: json['access_scope'] as String? ?? 'CUSTOM',
      blockId: _asIntOrNull(json['block_id']),
      blockName: json['block_name'] as String?,
    );
  }

  bool get isSiteCommon => accessScope == 'SITE_COMMON';
  bool get isBlockScope => accessScope == 'BLOCK';
  bool get isCustomScope => accessScope == 'CUSTOM';

  String get accessScopeLabel {
    switch (accessScope) {
      case 'SITE_COMMON':
        return 'Site Ortak Kapısı';
      case 'BLOCK':
        return blockName != null ? '$blockName Kapısı' : 'Blok Kapısı';
      case 'CUSTOM':
      default:
        return 'Özel / Ekstra Kapı';
    }
  }
}

class DoorResidentPermission {
  final int userCode;
  final String fullName;
  final String? email;
  final String? phone;
  final String memberRole;
  final bool canOpen;
  final String accessSource; // SITE_COMMON, BLOCK_DEFAULT, OVERRIDE_ALLOWED, OVERRIDE_DENIED, NO_ACCESS
  final bool? overrideAllowed;
  final String? overrideNotes;
  final String? overrideUpdatedAt;

  const DoorResidentPermission({
    required this.userCode,
    required this.fullName,
    this.email,
    this.phone,
    required this.memberRole,
    required this.canOpen,
    required this.accessSource,
    this.overrideAllowed,
    this.overrideNotes,
    this.overrideUpdatedAt,
  });

  factory DoorResidentPermission.fromJson(Map<String, dynamic> json) {
    final overrideRaw = json['override'];
    final override = overrideRaw is Map ? overrideRaw : null;
    final hasAccess = json['has_access'];
    return DoorResidentPermission(
      userCode: _asIntOrNull(json['user_code']) ?? 0,
      fullName: json['full_name'] as String? ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      // Sunucu 'role' gönderir (APARTMENT_ADMIN / FAMILY_MEMBER); eski anahtar 'member_role'.
      memberRole: (json['role'] ?? json['member_role']) as String? ?? 'FAMILY_MEMBER',
      // Sunucu 'has_access' gönderir; yoksa eski 'can_open' okunur.
      canOpen: hasAccess is bool ? hasAccess : json['can_open'] == true,
      accessSource: json['access_source'] as String? ?? 'NO_ACCESS',
      overrideAllowed: (override?['is_allowed'] ?? json['override_allowed']) as bool?,
      overrideNotes: (override?['notes'] ?? json['override_notes']) as String?,
      overrideUpdatedAt:
          (override?['updated_at'] ?? json['override_updated_at'])?.toString(),
    );
  }

  bool get isSiteCommon => accessSource == 'SITE_COMMON';
  bool get isBlockDefault => accessSource == 'BLOCK_DEFAULT';
  bool get isOverrideAllowed => accessSource == 'OVERRIDE_ALLOWED';
  bool get isOverrideDenied => accessSource == 'OVERRIDE_DENIED';
  bool get isNoAccess => accessSource == 'NO_ACCESS';

  String get roleLabel {
    switch (memberRole) {
      case 'APARTMENT_ADMIN':
      case 'ADMIN':
        return 'Daire Admini';
      case 'FAMILY_MEMBER':
      case 'MEMBER':
      default:
        return 'Aile Üyesi';
    }
  }

  String get statusLabel {
    switch (accessSource) {
      case 'SITE_COMMON':
        return 'Ortak Kapı';
      case 'BLOCK_DEFAULT':
        return 'Blok Sakini';
      case 'OVERRIDE_ALLOWED':
        return 'Ek İzinli';
      case 'OVERRIDE_DENIED':
        return 'Engellendi';
      case 'NO_ACCESS':
      default:
        return 'Yetkisiz';
    }
  }

  Color getStatusColor(bool isDark) {
    switch (accessSource) {
      case 'SITE_COMMON':
      case 'BLOCK_DEFAULT':
        return isDark ? AppColors.emeraldLight : AppColors.emerald;
      case 'OVERRIDE_ALLOWED':
        return isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
      case 'OVERRIDE_DENIED':
        return isDark ? AppColors.roseLight : AppColors.rose;
      case 'NO_ACCESS':
      default:
        return isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    }
  }

  Color getStatusBgColor(bool isDark) {
    switch (accessSource) {
      case 'SITE_COMMON':
      case 'BLOCK_DEFAULT':
        return (isDark ? AppColors.emerald : AppColors.emeraldLight).withValues(alpha: isDark ? 0.2 : 0.15);
      case 'OVERRIDE_ALLOWED':
        return (isDark ? const Color(0xFF3B82F6) : const Color(0xFF93C5FD)).withValues(alpha: isDark ? 0.25 : 0.2);
      case 'OVERRIDE_DENIED':
        return (isDark ? AppColors.rose : AppColors.roseLight).withValues(alpha: isDark ? 0.25 : 0.15);
      case 'NO_ACCESS':
      default:
        return (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.08 : 0.05);
    }
  }
}

class DoorApartmentPermission {
  final int id;
  final String doorNumber;
  final int? floor;
  final List<DoorResidentPermission> residents;

  const DoorApartmentPermission({
    required this.id,
    required this.doorNumber,
    this.floor,
    required this.residents,
  });

  factory DoorApartmentPermission.fromJson(Map<String, dynamic> json) {
    return DoorApartmentPermission(
      id: _asIntOrNull(json['id']) ?? 0,
      // Sunucu 'unit_label' gönderir (ör. "Daire 12"); eski anahtar 'door_number'.
      doorNumber: (json['unit_label'] ?? json['door_number'])?.toString() ?? '',
      floor: _asIntOrNull(json['floor']),
      residents: (json['residents'] as List<dynamic>? ?? const [])
          .map((r) => DoorResidentPermission.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Başlıkta gösterilecek daire etiketi: sunucunun 'unit_label' değeri zaten "Daire 12"
  /// biçimindedir; yalnız sayı gelirse (eski anahtar) "Daire " öneki eklenir.
  String get label {
    final value = doorNumber.trim();
    if (value.isEmpty) return 'Daire';
    return value.toLowerCase().startsWith('daire') ? value : 'Daire $value';
  }
}

class DoorBlockPermission {
  final int id;
  final String blockName;
  final int totalApartments;
  final int totalResidents;
  final int allowedResidentsCount;
  final List<DoorApartmentPermission> apartments;

  const DoorBlockPermission({
    required this.id,
    required this.blockName,
    required this.totalApartments,
    required this.totalResidents,
    required this.allowedResidentsCount,
    required this.apartments,
  });

  factory DoorBlockPermission.fromJson(Map<String, dynamic> json) {
    final apartments = (json['apartments'] as List<dynamic>? ?? const [])
        .map((a) => DoorApartmentPermission.fromJson(a as Map<String, dynamic>))
        .toList();
    final residentCount = apartments.fold<int>(0, (sum, a) => sum + a.residents.length);
    final allowedCount = apartments.fold<int>(
      0,
      (sum, a) => sum + a.residents.where((r) => r.canOpen).length,
    );
    return DoorBlockPermission(
      id: _asIntOrNull(json['id']) ?? 0,
      blockName: json['block_name'] as String? ?? '',
      // Sunucu 'total_apartments' göndermez: yoksa gelen daire listesinden türetilir.
      totalApartments: _asIntOrNull(json['total_apartments']) ?? apartments.length,
      totalResidents: _asIntOrNull(json['total_residents']) ?? residentCount,
      // Sunucu 'authorized_count' gönderir; eski anahtar 'allowed_residents_count'.
      allowedResidentsCount: _asIntOrNull(
            json['authorized_count'] ?? json['allowed_residents_count'],
          ) ??
          allowedCount,
      apartments: apartments,
    );
  }
}

class DoorPermissionsData {
  final DoorPermissionInfo door;
  final List<DoorBlockPermission> blocks;

  const DoorPermissionsData({
    required this.door,
    required this.blocks,
  });

  factory DoorPermissionsData.fromJson(Map<String, dynamic> json) {
    return DoorPermissionsData(
      door: DoorPermissionInfo.fromJson(json['door'] as Map<String, dynamic>? ?? {}),
      blocks: (json['blocks'] as List<dynamic>? ?? const [])
          .map((b) => DoorBlockPermission.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }
}

