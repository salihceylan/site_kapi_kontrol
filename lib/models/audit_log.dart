import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/models/history_item.dart';

/// Denetim kaydı satırı (`GET /admin/audit-log` -> `items[]`). Kayıtlar yalnız eklenir.
@immutable
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.action,
    this.createdAt,
    this.actorUserCode,
    this.actorName,
    this.actorRole,
    this.siteCode,
    this.siteName,
    this.targetType,
    this.targetId,
    this.details = const <String, dynamic>{},
  });

  final int id;
  final DateTime? createdAt;
  final int? actorUserCode;
  final String? actorName;
  final String? actorRole;

  /// Makine adı (örn. `module.disabled`, `staff_role.assigned`).
  final String action;
  final int? siteCode;
  final String? siteName;
  final String? targetType;
  final String? targetId;
  final Map<String, dynamic> details;

  /// Bilinen modül kodlarının Türkçe adları (denetim satırında "ne" kısmı için).
  static const Map<String, String> _moduleNames = <String, String>{
    'door_control': 'Geçiş Kontrol (JetPass)',
    'people': 'Kişi ve Daire Kayıtları',
    'announcements': 'Duyuru ve Bildirim',
    'finance': 'Aidat ve Finans',
    'reservation': 'Rezervasyon ve Konsiyerj',
    'work_tracking': 'İş Takibi',
    'metering': 'Sayaç Okuma ve Faturalandırma',
    'online_payment': 'Online Tahsilat ve Banka Bağlantısı',
  };

  static const Map<String, String> _staffRoleNames = <String, String>{
    'BOARD_MEMBER': 'Yönetim Kurulu / Denetçi',
    'STAFF': 'Görevli',
  };

  /// "Ne yapıldı" kısa başlığı. Bilinmeyen eylemde "Diğer işlem" yazılır (ham kod gösterilmez; kayıt
  /// yine listelenir).
  String get actionLabel {
    switch (action) {
      case 'module.enabled':
        return 'Modül açıldı';
      case 'module.disabled':
        return 'Modül kapatıldı';
      case 'staff_role.assigned':
        return 'Ek rol atandı';
      case 'staff_role.removed':
        return 'Ek rol kaldırıldı';
      case 'module_request.created':
        return 'Talep oluşturuldu';
      case 'module_request.approved':
        return 'Talep onaylandı';
      case 'module_request.rejected':
        return 'Talep reddedildi';
      case 'module_request.cancelled':
        return 'Talep geri çekildi';
      default:
        return peopleActionLabel(action) ?? announcementActionLabel(action) ?? 'Diğer işlem';
    }
  }

  /// Hedefin okunur özeti (modül adı ya da rol/kişi); yoksa null.
  String? get targetLabel {
    switch (targetType) {
      case 'module':
        final code = targetId;
        if (code == null || code.isEmpty) return null;
        return _moduleNames[code] ?? code;
      case 'module_request':
        // Hedef talep numarasıdır; modül adı ayrıntıdan (`details.module_code`) okunur.
        final moduleCode = details['module_code']?.toString();
        final moduleName = (moduleCode == null || moduleCode.isEmpty)
            ? null
            : (_moduleNames[moduleCode] ?? moduleCode);
        final request = targetId == null || targetId!.isEmpty ? null : 'Talep #$targetId';
        if (moduleName != null && request != null) return '$moduleName • $request';
        return moduleName ?? request;
      case 'user':
        final role = details['role']?.toString();
        final roleName = role == null ? null : (_staffRoleNames[role] ?? role);
        final who = targetId == null || targetId!.isEmpty
            ? null
            : 'Kullanıcı $targetId';
        if (who != null && roleName != null) return '$who • $roleName';
        return who ?? roleName;
      case 'person':
        return _numbered('Kişi');
      case 'apartment':
        return _numbered('Daire');
      case 'vehicle':
        return _numbered('Araç');
      case 'announcement':
        // Başlık / gövde denetim kaydına yazılmaz; yalnız numara gösterilir.
        return _numbered('Duyuru');
      default:
        final id = targetId;
        return id == null || id.isEmpty ? null : id;
    }
  }

  String? _numbered(String noun) {
    final id = targetId;
    return id == null || id.isEmpty ? null : '$noun #$id';
  }

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    int? asIntOrNull(Object? raw) {
      if (raw == null) return null;
      if (raw is num) return raw.toInt();
      return int.tryParse(raw.toString());
    }

    String? asStringOrNull(Object? raw) {
      if (raw == null) return null;
      final text = raw.toString();
      return text.isEmpty ? null : text;
    }

    final rawDetails = json['details'];
    return AuditLogEntry(
      id: asIntOrNull(json['id']) ?? 0,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString())?.toLocal(),
      actorUserCode: asIntOrNull(json['actor_user_code']),
      actorName: asStringOrNull(json['actor_name']),
      actorRole: asStringOrNull(json['actor_role']),
      action: json['action']?.toString() ?? '',
      siteCode: asIntOrNull(json['site_code']),
      siteName: asStringOrNull(json['site_name']),
      targetType: asStringOrNull(json['target_type']),
      targetId: asStringOrNull(json['target_id']),
      details: rawDetails is Map
          ? Map<String, dynamic>.from(rawDetails)
          : const <String, dynamic>{},
    );
  }
}

/// Denetim kaydı sayfası: `id DESC` sıralı satırlar ve sonraki sayfa için `before_id`.
@immutable
class AuditLogPage {
  const AuditLogPage({
    this.items = const <AuditLogEntry>[],
    this.nextBeforeId,
  });

  final List<AuditLogEntry> items;

  /// Sonraki sayfa için `before_id`; son sayfada null.
  final int? nextBeforeId;

  bool get hasMore => nextBeforeId != null;

  factory AuditLogPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final next = json['next_before_id'];
    return AuditLogPage(
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) => AuditLogEntry.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <AuditLogEntry>[],
      nextBeforeId: next is num
          ? next.toInt()
          : (next == null ? null : int.tryParse(next.toString())),
    );
  }
}
