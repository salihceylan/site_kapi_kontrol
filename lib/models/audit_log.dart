import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/models/document_models.dart' show documentActionLabel;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/history_item.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';

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
    'door_control': 'Geçiş Kontrol (SmartKeyPass)',
    'people': 'Kişi ve Daire Kayıtları',
    'announcements': 'Duyuru ve Bildirim',
    'finance': 'Aidat ve Finans',
    'documents': 'Belgeler (Dosya Deposu)',
    'reservation': 'Rezervasyon ve Konsiyerj',
    'work_tracking': 'İş Takibi',
    'metering': 'Sayaç Okuma ve Faturalandırma',
    'online_payment': 'Online Tahsilat ve Banka Bağlantısı',
    'survey': 'Anket ve Oylama',
    'visitor_log': 'Ziyaretçi ve Kargo',
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
      case 'platform_config.updated':
        return 'Platform ayarları güncellendi';
      case 'account.deleted':
        return 'Hesap silindi';
      case 'account.data_exported':
        return 'Kişisel veri dışa aktarıldı';
      case 'account.key_rotation_failed':
        return 'Silinen hesabın cihaz anahtarı yenilenemedi';
      default:
        return peopleActionLabel(action) ??
            announcementActionLabel(action) ??
            documentActionLabel(action) ??
            siteApplicationActionLabel(action) ??
            financeActionLabel(action) ??
            visitorLogActionLabel(action) ??
            'Diğer işlem';
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
      case 'site_application':
        // Site adı / gerekçe / not denetim kaydına yazılmaz; yalnız başvuru numarası gösterilir.
        return _numbered('Başvuru');
      case 'document':
        // Başlık / dosya adı denetim kaydına yazılmaz; yalnız numara gösterilir.
        return _numbered('Belge');
      case 'finance':
        return _financeTarget();
      case 'platform_settings':
      case 'platform_setting':
        // Hedef ayar anahtarıdır (örn. `site_onboarding`); ham anahtar gösterilmez. Sunucu hedef türünü
        // tekil (`platform_setting`) yazar; çoğul yazım da kabul edilir.
        return targetId == 'site_onboarding' ? 'Site açılış modu' : 'Platform ayarı';
      case 'visitor_entry':
        // Ziyaretçi adı / firma / not denetim kaydına yazılmaz; yalnız numara gösterilir.
        return _numbered('Ziyaretçi kaydı');
      default:
        final id = targetId;
        return id == null || id.isEmpty ? null : id;
    }
  }

  /// Mali eylemin hedefi (Faz 4a): açıklama / neden metni ve kişi adı denetim kaydına yazılmaz; yalnız numara
  /// ya da dönem gösterilir. Hedef türü eylemin ön ekinden anlaşılır.
  String? _financeTarget() {
    final id = targetId;
    if (id == null || id.isEmpty) return null;
    final period = FinancePeriod.tryParse(id);
    if (action.startsWith('finance.period.') || (period != null && id.contains('-'))) {
      return period == null ? 'Dönem' : 'Dönem: ${period.label}';
    }
    if (action.startsWith('finance.definition.')) return 'Aidat tanımı #$id';
    if (action.startsWith('finance.run.')) return 'Borçlandırma #$id';
    if (action.startsWith('finance.charge.')) return 'Ek borç #$id';
    if (action.startsWith('finance.payment.')) return 'Tahsilat #$id';
    // Faz 4b: makbuz, tazminat, kasa / banka, gider, hatırlatma (yalnız numara; ad / not / tutar yazılmaz).
    if (action.startsWith('finance.receipt.')) return 'Makbuz #$id';
    if (action.startsWith('finance.latefee.')) return 'Tazminat çalıştırması #$id';
    if (action.startsWith('finance.account.')) return 'Hesap #$id';
    if (action.startsWith('finance.transfer.')) return 'Aktarım #$id';
    if (action.startsWith('finance.reconciliation.')) return 'Mutabakat #$id';
    if (action.startsWith('finance.expense.')) return 'Gider #$id';
    if (action.startsWith('finance.category.')) return 'Gider kategorisi #$id';
    if (action.startsWith('finance.supplier.')) return 'Tedarikçi #$id';
    if (action.startsWith('finance.reminder.')) return 'Hatırlatma #$id';
    if (action.startsWith('finance.settings.')) return 'Finans ayarları';
    if (action.startsWith('finance.legal_gate.')) return 'Hukuk onayı bayrağı';
    if (action.startsWith('finance.report.')) return 'Rapor';
    if (action.startsWith('finance.payments.')) return 'Tahsilat eşleme';
    return 'Mali kayıt #$id';
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

/// Ziyaretçi ve Kargo (`visitor_log`) denetim eylemlerinin Türkçe başlığı; bilinmeyen eylemde null (zincirdeki
/// sonraki üretici dener). Durum geçişi `details.status` içindedir; ad / firma / not denetim kaydına yazılmaz.
String? visitorLogActionLabel(String action) {
  switch (action) {
    case 'visitor_entry.created':
      return 'Ziyaretçi / kargo kaydı açıldı';
    case 'visitor_entry.updated':
      return 'Ziyaretçi / kargo kaydı güncellendi';
  }
  return null;
}
