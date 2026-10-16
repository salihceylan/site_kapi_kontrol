import 'package:flutter/foundation.dart';

/// Site başvurusu durumları (`site_applications.status`).
abstract final class SiteApplicationStatus {
  static const String pending = 'pending';
  static const String approved = 'approved';
  static const String rejected = 'rejected';
  static const String cancelled = 'cancelled';

  /// Sunucu `status` göndermediyse ya da tanınmayan değer: BEKLEYEN sayılmaz, hiçbir eylem sunulmaz.
  static const String unknown = 'unknown';
}

int _asInt(Object? raw, [int fallback = 0]) {
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? fallback;
}

int? _asIntOrNull(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw.toString());
}

String? _text(Object? raw) {
  if (raw == null) return null;
  final value = raw.toString().trim();
  return value.isEmpty ? null : value;
}

DateTime? _date(Object? raw) => raw == null ? null : DateTime.tryParse(raw.toString());

/// Başvurudaki bir blok (`blocks[]`: `{ name, apartment_count }`).
@immutable
class SiteApplicationBlock {
  const SiteApplicationBlock({required this.name, required this.apartmentCount});

  final String name;
  final int apartmentCount;

  /// Sunucu `normalizeSetupSiteInput` çıktısının JSON hâlini saklar: `apartmentCount` (camelCase) ya da
  /// `apartment_count` gelebilir; ikisi de okunur.
  factory SiteApplicationBlock.fromJson(Map<String, dynamic> json) {
    return SiteApplicationBlock(
      name: _text(json['name']) ?? '',
      apartmentCount: _asInt(json['apartment_count'] ?? json['apartmentCount']),
    );
  }
}

/// Başvurudaki bir kapı (`doors[]`: `{ name }`).
@immutable
class SiteApplicationDoor {
  const SiteApplicationDoor({required this.name});

  final String name;

  factory SiteApplicationDoor.fromJson(Map<String, dynamic> json) {
    return SiteApplicationDoor(name: _text(json['name']) ?? '');
  }
}

/// Süper kullanıcı yanıtındaki başvuran (`applicant`). İletişim bilgisi YALNIZ süper kullanıcıya gelir;
/// kişisel veri günlüğe yazılmaz.
@immutable
class SiteApplicant {
  const SiteApplicant({
    this.userCode,
    this.fullName,
    this.email,
    this.phone,
    this.role,
  });

  final int? userCode;
  final String? fullName;
  final String? email;
  final String? phone;
  final String? role;

  factory SiteApplicant.fromJson(Map<String, dynamic> json) {
    return SiteApplicant(
      userCode: _asIntOrNull(json['user_code']),
      fullName: _text(json['full_name']),
      email: _text(json['email']),
      phone: _text(json['phone']),
      role: _text(json['role']),
    );
  }

  /// Okunur ad; sunucu boş ad gönderirse (silinmiş hesap) "Bilinmeyen kullanıcı".
  String get displayName => fullName ?? 'Bilinmeyen kullanıcı';
}

/// Bir kişinin site olma (yönetici olma) başvurusu (Platform: site başvurusu).
///
/// Sunucu gövdesi: `{ id, status, site_name, city, district, address, management_type,
/// management_type_label, block_count, apartment_count, door_count, blocks, doors, device_uid, note,
/// plan_code, payment_status, decision_note, decided_at, site_code, created_at }`. Süper kullanıcı yanıtında
/// ek olarak `applicant`, `decision_source`, `decided_by_name`, `device_available` bulunur.
///
/// Savunmacı ayrıştırma: eksik sayaçlar listelerden türetilir; bilinmeyen alanlar yok sayılır.
@immutable
class SiteApplication {
  const SiteApplication({
    required this.id,
    this.status = SiteApplicationStatus.unknown,
    this.siteName = '',
    this.city,
    this.district,
    this.address,
    this.managementType,
    this.managementTypeLabel,
    this.blockCount = 0,
    this.apartmentCount = 0,
    this.doorCount = 0,
    this.blocks = const <SiteApplicationBlock>[],
    this.doors = const <SiteApplicationDoor>[],
    this.deviceUid,
    this.note,
    this.planCode,
    this.paymentStatus,
    this.decisionNote,
    this.decidedAt,
    this.siteCode,
    this.createdAt,
    this.applicant,
    this.decisionSource,
    this.decidedByName,
    this.deviceAvailable,
  });

  final int id;

  /// `pending`, `approved`, `rejected` ya da `cancelled`; eksik / tanınmayan değer ham tutulur ama
  /// bekleyen SAYILMAZ ([statusLabel] "Durum bilinmiyor").
  final String status;
  final String siteName;
  final String? city;
  final String? district;
  final String? address;
  final String? managementType;
  final String? managementTypeLabel;
  final int blockCount;
  final int apartmentCount;
  final int doorCount;
  final List<SiteApplicationBlock> blocks;
  final List<SiteApplicationDoor> doors;

  /// Başvuruda seçilen cihaz (isteğe bağlı).
  final String? deviceUid;
  final String? note;
  final String? planCode;
  final String? paymentStatus;
  final String? decisionNote;
  final DateTime? decidedAt;

  /// Onaylanınca kurulan sitenin kodu.
  final int? siteCode;
  final DateTime? createdAt;

  // --- Yalnız süper kullanıcı yanıtında ---
  final SiteApplicant? applicant;
  final String? decisionSource;
  final String? decidedByName;

  /// Onay anında cihaz hâlâ başvuranın mı? Alan yoksa null (bilinmiyor).
  final bool? deviceAvailable;

  bool get isPending => status == SiteApplicationStatus.pending;

  /// Süper kullanıcı ekranlarında başvuran adı: sunucu `applicant: null` gönderirse (başvuran hesabı silinmiş)
  /// "Silinmiş hesap". YALNIZ süper kullanıcı yanıtları için anlamlıdır (başvurana `applicant` hiç verilmez).
  String get applicantLabel => applicant == null ? 'Silinmiş hesap' : applicant!.displayName;

  bool get isApproved => status == SiteApplicationStatus.approved;
  bool get isRejected => status == SiteApplicationStatus.rejected;
  bool get isCancelled => status == SiteApplicationStatus.cancelled;
  bool get hasDevice => deviceUid != null;

  /// Durum sunucunun bildirdiği dört değerden biri mi? Değilse kart kısıtlı görünür ve eylem sunulmaz.
  bool get hasKnownStatus =>
      isPending || isApproved || isRejected || isCancelled;

  /// Okunur durum adı; bilinmeyen değerde "Durum bilinmiyor" (ham kod kullanıcıya gösterilmez; kayıt
  /// yine listelenir).
  String get statusLabel {
    switch (status) {
      case SiteApplicationStatus.pending:
        return 'Bekliyor';
      case SiteApplicationStatus.approved:
        return 'Onaylandı';
      case SiteApplicationStatus.rejected:
        return 'Reddedildi';
      case SiteApplicationStatus.cancelled:
        return 'İptal edildi';
      default:
        return 'Durum bilinmiyor';
    }
  }

  /// Site adı yoksa (bozuk kayıt) boş görünmez.
  String get siteNameLabel => siteName.trim().isEmpty ? 'Adsız site' : siteName.trim();

  /// "Şehir / İlçe" özeti; ikisi de yoksa null.
  String? get locationLabel {
    final parts = <String>[?city, ?district];
    return parts.isEmpty ? null : parts.join(' / ');
  }

  /// "2 blok • 40 daire • 1 kapı" özeti.
  String get structureLabel => '$blockCount blok • $apartmentCount daire • $doorCount kapı';

  factory SiteApplication.fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['blocks'];
    final blocks = rawBlocks is List
        ? rawBlocks
              .whereType<Map>()
              .map((e) => SiteApplicationBlock.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : const <SiteApplicationBlock>[];
    final rawDoors = json['doors'];
    final doors = rawDoors is List
        ? rawDoors
              .whereType<Map>()
              .map((e) => SiteApplicationDoor.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : const <SiteApplicationDoor>[];
    final rawApplicant = json['applicant'];
    final available = json['device_available'];
    return SiteApplication(
      id: _asInt(json['id']),
      status: _text(json['status']) ?? SiteApplicationStatus.unknown,
      siteName: json['site_name']?.toString() ?? '',
      city: _text(json['city']),
      district: _text(json['district']),
      address: _text(json['address']),
      managementType: _text(json['management_type']),
      managementTypeLabel: _text(json['management_type_label']),
      blockCount: _asIntOrNull(json['block_count']) ?? blocks.length,
      apartmentCount:
          _asIntOrNull(json['apartment_count']) ??
          blocks.fold<int>(0, (sum, b) => sum + b.apartmentCount),
      doorCount: _asIntOrNull(json['door_count']) ?? doors.length,
      blocks: blocks,
      doors: doors,
      deviceUid: _text(json['device_uid']),
      note: _text(json['note']),
      planCode: _text(json['plan_code']),
      paymentStatus: _text(json['payment_status']),
      decisionNote: _text(json['decision_note']),
      decidedAt: _date(json['decided_at']),
      siteCode: _asIntOrNull(json['site_code']),
      createdAt: _date(json['created_at']),
      applicant: rawApplicant is Map
          ? SiteApplicant.fromJson(Map<String, dynamic>.from(rawApplicant))
          : null,
      decisionSource: _text(json['decision_source']),
      decidedByName: _text(json['decided_by_name']),
      deviceAvailable: available is bool ? available : null,
    );
  }
}

/// `GET /admin/site-applications` sayfası: `limit/offset` ve süzgece uyan toplam.
@immutable
class SiteApplicationPage {
  const SiteApplicationPage({this.items = const <SiteApplication>[], this.total = 0});

  final List<SiteApplication> items;
  final int total;

  /// `items` listesi yoksa yanıt anlaşılamamıştır ([FormatException]): boş liste ("başvuru yok") sanılmaz.
  factory SiteApplicationPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List) throw const FormatException('items yok');
    final items = rawItems
        .whereType<Map>()
        .map((e) => SiteApplication.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    return SiteApplicationPage(items: items, total: _asIntOrNull(json['total']) ?? items.length);
  }
}

/// `GET /membership/site-applications/mine`: bekleyen başvuru (yoksa null) ve son başvurular (yeniden eskiye).
@immutable
class MySiteApplications {
  const MySiteApplications({
    this.pending,
    this.items = const <SiteApplication>[],
    this.requiresApplication,
  });

  final SiteApplication? pending;
  final List<SiteApplication> items;

  /// Sunucunun `requires_application` bildirimi: true = bu kullanıcı site eklemek için başvurmalı (örn. sahip
  /// bağı olmayan site yöneticisi); false = anlık "Site Ekle" açık; alan yoksa null (eski sunucu: rolden
  /// türetilen eski davranış).
  final bool? requiresApplication;

  /// Ekranda gösterilecek en güncel başvuru: bekleyen varsa o, yoksa listenin ilki.
  SiteApplication? get latest => pending ?? (items.isEmpty ? null : items.first);

  /// `pending` ve `items` alanlarının İKİSİ de yoksa yanıt anlaşılamamıştır ([FormatException]): "başvuru yok"
  /// sanılmaz. Yalnız `pending: null` + `items: []` meşru boş durumdur.
  factory MySiteApplications.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('pending') && !json.containsKey('items')) {
      throw const FormatException('pending/items yok');
    }
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((e) => SiteApplication.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : const <SiteApplication>[];
    final rawPending = json['pending'];
    var pending = rawPending is Map
        ? SiteApplication.fromJson(Map<String, dynamic>.from(rawPending))
        : null;
    // Savunma: `pending` alanı boş gelse de listede bekleyen bir kayıt varsa "başvuru yok" denmez.
    if (pending == null) {
      for (final item in items) {
        if (item.isPending) {
          pending = item;
          break;
        }
      }
    }
    final requires = json['requires_application'];
    return MySiteApplications(
      pending: pending,
      items: items,
      requiresApplication: requires is bool ? requires : null,
    );
  }
}

/// `POST /admin/site-applications/:id/approve` yanıtı: güncel başvuru, kurulan site ve cihazın bağlanıp
/// bağlanmadığı (`device_attached: false` ise site cihazsız kuruldu).
@immutable
class SiteApplicationDecision {
  const SiteApplicationDecision({
    required this.application,
    this.siteCode,
    this.siteName,
    this.deviceAttached,
  });

  final SiteApplication application;
  final int? siteCode;
  final String? siteName;

  /// Cihaz bağlandı mı? Alan yoksa null (bilinmiyor); false ise site cihazsız kuruldu.
  final bool? deviceAttached;

  factory SiteApplicationDecision.fromJson(Map<String, dynamic> json) {
    final rawApplication = json['application'];
    final rawSite = json['site'];
    final site = rawSite is Map ? Map<String, dynamic>.from(rawSite) : const <String, dynamic>{};
    final attached = json['device_attached'] ?? site['device_attached'];
    return SiteApplicationDecision(
      application: SiteApplication.fromJson(
        rawApplication is Map ? Map<String, dynamic>.from(rawApplication) : const <String, dynamic>{},
      ),
      siteCode: _asIntOrNull(site['site_code'] ?? site['id'] ?? site['code']),
      siteName: _text(site['name'] ?? site['site_name']),
      deviceAttached: attached is bool ? attached : null,
    );
  }
}

/// Denetim kaydında site başvurusu / platform ayarı eylemlerinin kısa Türkçe başlığı; bilinmeyen eylemde
/// null (çağıran "Diğer işlem" yazar: ham kod kullanıcıya gösterilmez, kayıt yine listelenir).
String? siteApplicationActionLabel(String action) {
  switch (action) {
    case 'site_application.created':
      return 'Site başvurusu yapıldı';
    case 'site_application.cancelled':
      return 'Site başvurusu iptal edildi';
    case 'site_application.approved':
      return 'Site başvurusu onaylandı';
    case 'site_application.rejected':
      return 'Site başvurusu reddedildi';
    case 'platform_settings.updated':
      return 'Platform ayarı güncellendi';
    default:
      return null;
  }
}
