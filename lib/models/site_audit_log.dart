import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/audit_log.dart';

/// İşlem türü (kategori) süzgeci: sunucudaki `category` anahtarı + görünen ad. Anahtarlar
/// `server/src/modules/site_audit_log_catalog.js` ile AYNIDIR (sunucu bilinmeyen anahtara 400 verir).
@immutable
class SiteAuditCategory {
  const SiteAuditCategory(this.key, this.label);

  final String key;
  final String label;
}

/// Açılır listenin seçenekleri (sunucu kataloğuyla aynı sıra). "Tümü" listede YOKTUR (süzgeç yok = null).
const List<SiteAuditCategory> siteAuditCategories = <SiteAuditCategory>[
  SiteAuditCategory('modules', 'Modüller'),
  SiteAuditCategory('roles', 'Yetki ve roller'),
  SiteAuditCategory('access', 'Kapı ve geçiş'),
  SiteAuditCategory('people', 'Kişi ve daire kayıtları'),
  SiteAuditCategory('finance', 'Aidat ve finans'),
  SiteAuditCategory('announcements', 'Duyurular'),
  SiteAuditCategory('documents', 'Dosya deposu'),
  SiteAuditCategory('services', 'Site hizmetleri'),
  SiteAuditCategory('settings', 'Site ayarları'),
];

/// Kategori anahtarının görünen adı; bilinmiyorsa null.
String? siteAuditCategoryLabel(String? key) {
  for (final category in siteAuditCategories) {
    if (category.key == key) return category.label;
  }
  return null;
}

/// Site yöneticisinin "İşlem kayıtları" satırı (`GET /manager/sites/:siteCode/audit-log` -> `items[]`).
///
/// Kişisel veri asgaridir: kim (görünen ad + rol başlığı), ne zaman, ne yaptı. Sunucu kullanıcı kodu, site kodu, e-posta,
/// telefon ya da parola / belirteç göndermez; ayrıntı (`details`) yalnız izinli kısa değerlerdir. Süper kullanıcı
/// "Sistem yöneticisi", silinmiş hesap "Silinmiş Kullanıcı" olarak gelir.
@immutable
class SiteAuditEntry {
  const SiteAuditEntry({
    required this.id,
    required this.action,
    this.createdAt,
    this.actorName,
    this.actorRole,
    this.actorRoleLabel,
    this.serverActionLabel,
    this.category,
    this.categoryLabel,
    this.targetType,
    this.targetId,
    this.details = const <String, dynamic>{},
  });

  final int id;

  /// Makine adı (örn. `finance.run.posted`).
  final String action;
  final DateTime? createdAt;
  final String? actorName;
  final String? actorRole;
  final String? actorRoleLabel;

  /// Sunucunun Türkçe eylem başlığı (`action_label`); eski sunucuda null.
  final String? serverActionLabel;
  final String? category;
  final String? categoryLabel;
  final String? targetType;
  final String? targetId;
  final Map<String, dynamic> details;

  /// Süper kullanıcı ekranının etiket mantığını (hedef etiketi, eski eylem başlıkları) yeniden kullanmak için.
  AuditLogEntry get _asAuditEntry => AuditLogEntry(
        id: id,
        action: action,
        createdAt: createdAt,
        targetType: targetType,
        targetId: targetId,
        details: details,
      );

  /// "Ne yapıldı": sunucu başlığı; yoksa istemcideki eski tablo; o da bilmiyorsa "Diğer işlem" (ham kod gösterilmez).
  String get title {
    final label = serverActionLabel;
    if (label != null && label.trim().isNotEmpty) return label;
    return _asAuditEntry.actionLabel;
  }

  /// Hedefin okunur özeti (modül adı, "Karar 2026/5", "Kişi #31" ...); yoksa null.
  String? get targetLabel => _asAuditEntry.targetLabel;

  /// "Kim": görünen ad + (varsa ve addan farklıysa) rol başlığı. Ad yoksa "Sistem".
  String get actorLine {
    final name = (actorName ?? '').trim();
    final role = (actorRoleLabel ?? '').trim();
    if (name.isEmpty) return role.isEmpty ? 'Sistem' : role;
    return role.isEmpty || role == name ? name : '$name • $role';
  }

  factory SiteAuditEntry.fromJson(Map<String, dynamic> json) {
    int? asInt(Object? raw) {
      if (raw == null) return null;
      if (raw is num) return raw.toInt();
      return int.tryParse(raw.toString());
    }

    String? asString(Object? raw) {
      if (raw == null) return null;
      final text = raw.toString();
      return text.isEmpty ? null : text;
    }

    final rawDetails = json['details'];
    return SiteAuditEntry(
      id: asInt(json['id']) ?? 0,
      action: json['action']?.toString() ?? '',
      createdAt: json['created_at'] == null ? null : DateTime.tryParse(json['created_at'].toString()),
      actorName: asString(json['actor_name']),
      actorRole: asString(json['actor_role']),
      actorRoleLabel: asString(json['actor_role_label']),
      serverActionLabel: asString(json['action_label']),
      category: asString(json['category']),
      categoryLabel: asString(json['category_label']),
      targetType: asString(json['target_type']),
      targetId: asString(json['target_id']),
      details: rawDetails is Map ? Map<String, dynamic>.from(rawDetails) : const <String, dynamic>{},
    );
  }
}

/// Bir sayfa: `id DESC` sıralı satırlar ve sonraki sayfa için `before_id` (son sayfada null).
@immutable
class SiteAuditPage {
  const SiteAuditPage({this.items = const <SiteAuditEntry>[], this.nextBeforeId});

  final List<SiteAuditEntry> items;
  final int? nextBeforeId;

  bool get hasMore => nextBeforeId != null;

  factory SiteAuditPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final next = json['next_before_id'];
    return SiteAuditPage(
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) => SiteAuditEntry.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <SiteAuditEntry>[],
      nextBeforeId: next is num ? next.toInt() : (next == null ? null : int.tryParse(next.toString())),
    );
  }
}
