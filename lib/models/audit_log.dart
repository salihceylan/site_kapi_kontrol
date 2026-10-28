import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/access_audit_label.dart' show accessAuditActionLabel;
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/models/contract_models.dart' show contractActionLabel;
import 'package:site_kapi_kontrol/models/decision_models.dart' show decisionBookActionLabel;
import 'package:site_kapi_kontrol/models/document_models.dart' show documentActionLabel;
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/history_item.dart';
import 'package:site_kapi_kontrol/models/plate_audit_label.dart' show plateActionLabel;
import 'package:site_kapi_kontrol/models/platform_rule.dart' show platformRuleActionLabel, platformRuleTargetLabel;
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
    'documents': 'Belgeler (Dosya Deposu)', // eski kayıtlar: Belgeler 084'te Dosya Deposu ile birleşti
    'card_payments': 'Kart Ödemesi (Aidat ve Finans)', // eski kayıtlar: Kart Ödemesi 083'te Aidat ve Finans'a katıldı
    'drive_storage': 'Dosya Deposu',
    'reservation': 'Rezervasyon ve Konsiyerj',
    'work_tracking': 'İş Takibi',
    'metering': 'Sayaç Okuma ve Faturalandırma',
    'online_payment': 'Online Tahsilat ve Banka Bağlantısı',
    'survey': 'Anket ve Oylama',
    'visitor_log': 'Ziyaretçi ve Kargo',
    'card_access': 'Kartlı Geçiş',
    'plate_recognition': 'Plaka Tanıma',
    'hgs_access': 'HGS Geçişi',
    'cctv_link': 'Kamera (CCTV) Bağlantısı',
    'decision_book': 'Karar Defteri',
    'contracts': 'Firma ve Sözleşme Takibi',
    'equipment': 'Ekipman ve Bakım',
    'budget': 'İşletme Projesi',
  };

  /// Rol kodlarının Türkçe adları: ek roller (`staff_role.*`), hesap / site rolleri (`user.*`, `site_manager.*`) ve
  /// katılım başvurusunda verilen daire rolü (`join_request.*`). Bilinmeyen kod olduğu gibi gösterilir.
  static const Map<String, String> _staffRoleNames = <String, String>{
    'BOARD_MEMBER': 'Yönetim Kurulu / Denetçi',
    'STAFF': 'Görevli',
    'SITE_OWNER': 'Site Sahibi',
    'SITE_ADMIN': 'Site Yöneticisi',
    'APARTMENT_ADMIN': 'Daire Yöneticisi',
    'FAMILY_MEMBER': 'Aile Üyesi',
    'super_user': 'Süper Kullanıcı',
    'site_manager': 'Site Yöneticisi',
    'apartment_owner': 'Daire Sakini',
    'individual': 'Bireysel Kullanıcı',
  };

  String? _roleName(Object? code) {
    final text = code?.toString();
    if (text == null || text.isEmpty) return null;
    return _staffRoleNames[text] ?? text;
  }

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
            decisionBookActionLabel(action) ??
            contractActionLabel(action, details) ??
            platformRuleActionLabel(action) ??
            plateActionLabel(action) ??
            accessAuditActionLabel(action) ??
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
        return _userTarget();
      case 'site':
        // Site adı denetim kaydına yazılmaz (site silinmiş olabilir); yalnız site kodu gösterilir.
        return _numbered('Site');
      case 'site_manager_invitation':
        // Davet edilenin e-postası / adı denetim kaydına yazılmaz; yalnız davet numarası gösterilir.
        return _numbered('Davet');
      case 'join_request':
        return _joinRequestTarget();
      case 'door':
        return _doorTarget();
      case 'device':
        // Cihaz UID'i denetim kaydına yazılmaz; yalnız cihaz numarası gösterilir.
        return _numbered('Cihaz');
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
      case 'board_decision':
        // Karar başlığı / metni denetim kaydına yazılmaz; kesinleşmişse karar numarası, değilse kayıt numarası.
        final label = details['number_label']?.toString();
        return label != null && label.isNotEmpty ? 'Karar $label' : _numbered('Karar');
      case 'contract_vendor':
        // Firma adı / iletişim bilgileri denetim kaydına yazılmaz; yalnız numara gösterilir.
        return _numbered('Firma');
      case 'contract':
        // Sözleşme başlığı / tutarı denetim kaydına yazılmaz; yalnız numara gösterilir.
        return _numbered('Sözleşme');
      case 'platform_rule':
        // Kurallar tablosu (G11): hedef kural anahtarıdır; ham anahtar yerine kuralın adı ve kapsamı gösterilir.
        return platformRuleTargetLabel(targetId, details);
      default:
        final id = targetId;
        return id == null || id.isEmpty ? null : id;
    }
  }

  /// Kullanıcı hedefi: "Kullanıcı 42" + rol adı (`details.role`). Rol değişiminde "eski → yeni", kapı özel izninde kapı numarası eklenir.
  /// Ad / e-posta denetim kaydına yazılmaz; yalnız kullanıcı kodu ve rol kodu gösterilir.
  String? _userTarget() {
    final id = targetId;
    final who = id == null || id.isEmpty ? null : 'Kullanıcı $id';
    String? role;
    if (action == 'user.role_changed') {
      final from = _roleName(details['old_role']);
      final to = _roleName(details['new_role']);
      if (from != null || to != null) role = '${from ?? '?'} → ${to ?? '?'}';
    } else {
      role = _roleName(details['role']);
    }
    final doorId = details['door_id']?.toString();
    final parts = <String>[
      ?who,
      ?role,
      if (doorId != null && doorId.isNotEmpty) 'Kapı #$doorId',
    ];
    return parts.isEmpty ? null : parts.join(' • ');
  }

  /// Katılım başvurusu hedefi: "Başvuru #9" + başvuran kullanıcı kodu + (onayda) verilen daire rolü. Ad / e-posta / ret gerekçesi yazılmaz.
  String? _joinRequestTarget() {
    final request = _numbered('Başvuru');
    final user = details['user_code']?.toString();
    final role = _roleName(details['assigned_role']);
    final parts = <String>[
      ?request,
      if (user != null && user.isNotEmpty) 'Kullanıcı $user',
      ?role,
    ];
    return parts.isEmpty ? null : parts.join(' • ');
  }

  /// Toplu kapı özel izni hedefi: "Kapı #12 • 24 kişi". Kişi adları yazılmaz; yalnız kapı numarası ve kişi sayısı gösterilir.
  String? _doorTarget() {
    final door = _numbered('Kapı');
    final count = details['count'];
    final parts = <String>[
      ?door,
      if (count is num) '${count.toInt()} kişi',
    ];
    return parts.isEmpty ? null : parts.join(' • ');
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
