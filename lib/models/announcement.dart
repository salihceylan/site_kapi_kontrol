import 'package:flutter/foundation.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart'
    show crmInt, crmIntOrNull, crmText;

/// Platform Faz 3a (Duyuru ve Bildirim) modelleri (sözleşme: docs/PLATFORM_DUYURU.md).
///
/// Kurallar: alan yok / bozuk ise güvenli varsayılan; bilinmeyen sayım değeri enum'lara düşmez
/// (`unknown`); zaman damgaları evrensel an (UTC) olarak okunur ve ekranda İstanbul saatiyle
/// gösterilir (bkz. `istanbul_time.dart`); sunucu gövdesi `{ "announcement": {...} }` ile sarılı gelse de
/// düz gelse de okunur.

/// ISO 8601 zaman damgası -> UTC an. Saat dilimi bilgisi OLMAYAN metin UTC sayılır (cihaz saat dilimine
/// güvenilmez). Bozuk değerde null.
DateTime? announcementInstant(Object? raw) {
  if (raw == null) return null;
  var text = raw.toString().trim();
  if (text.isEmpty) return null;
  final hasZone = RegExp(r'(Z|[+-]\d{2}(?::?\d{2})?)$', caseSensitive: false).hasMatch(text);
  if (!hasZone) {
    text = '${text.replaceFirst(' ', 'T')}Z';
  }
  return DateTime.tryParse(text)?.toUtc();
}

bool _flag(Object? raw, {bool fallback = false}) => raw is bool ? raw : fallback;

String _text(Object? raw) => raw?.toString() ?? '';

List<int> _intList(Object? raw) {
  if (raw is! List) return const <int>[];
  final result = <int>[];
  for (final item in raw) {
    final value = crmIntOrNull(item);
    if (value != null) result.add(value);
  }
  return List<int>.unmodifiable(result);
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const <String>[];
  return List<String>.unmodifiable(
    raw.map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty),
  );
}

/// `{ "announcement": {...} }` sarmalını açar; yoksa gövdenin kendisi.
Map<String, dynamic> _unwrap(Map<String, dynamic> json) {
  final inner = json['announcement'];
  return inner is Map ? Map<String, dynamic>.from(inner) : json;
}

/// Duyurunun yaşam döngüsü durumu. Bilinmeyen değer [unknown]: hiçbir yazma eylemi sunulmaz.
enum AnnouncementStatus {
  draft('draft', 'Taslak'),
  scheduled('scheduled', 'Zamanlanmış'),
  published('published', 'Yayında'),
  withdrawn('withdrawn', 'Geri çekildi'),
  unknown('', 'Durum bilinmiyor');

  const AnnouncementStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Taslak ya da zamanlanmış: tüm alanlar düzenlenir, silinir, şimdi yayınlanır.
  bool get isEditable => this == draft || this == scheduled;

  static AnnouncementStatus fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final status in values) {
        if (status != unknown && status.apiValue == normalized) return status;
      }
    }
    return unknown;
  }
}

/// Önem: yalnız `urgent` acildir; eksik / bilinmeyen değer normaldir.
enum AnnouncementImportance {
  normal('normal', 'Normal'),
  urgent('urgent', 'Acil');

  const AnnouncementImportance(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static AnnouncementImportance fromApi(Object? value) {
    if (value is String && value.trim().toLowerCase() == 'urgent') {
      return AnnouncementImportance.urgent;
    }
    return AnnouncementImportance.normal;
  }
}

/// Hedef türü. Eksik / bilinmeyen değer `site` (en geniş, ancak yalnız GÖSTERİMDE; gönderimde seçili tür
/// kullanılır).
enum AnnouncementTargetType {
  site('site', 'Tüm site'),
  blocks('blocks', 'Bloklar'),
  apartments('apartments', 'Daireler');

  const AnnouncementTargetType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static AnnouncementTargetType fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final type in values) {
        if (type.apiValue == normalized) return type;
      }
    }
    return AnnouncementTargetType.site;
  }
}

/// Alıcı satırındaki e-posta durumu (`announcement_recipients.email_status`).
enum EmailDelivery {
  none('none', 'E-posta istenmedi'),
  pending('pending', 'E-posta sırada'),
  sent('sent', 'E-posta gönderildi'),
  failed('failed', 'E-posta gönderilemedi'),
  noAddress('no_address', 'E-postası yok'),
  skippedPref('skipped_pref', 'E-posta tercihi kapalı'),
  capped('capped', 'Günlük sınır aşıldı'),
  duplicate('duplicate', 'Aynı adres, tekrar gönderilmedi');

  const EmailDelivery(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static EmailDelivery fromApi(Object? value) {
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final status in values) {
        if (status.apiValue == normalized) return status;
      }
    }
    return EmailDelivery.none;
  }
}

/// Yönetici listesi satırı (`GET /manager/sites/:siteCode/announcements` -> `items[]`).
@immutable
class AnnouncementSummary {
  const AnnouncementSummary({
    required this.id,
    this.title = '',
    this.bodyPreview = '',
    this.importance = AnnouncementImportance.normal,
    this.status = AnnouncementStatus.unknown,
    this.targetType = AnnouncementTargetType.site,
    this.publishAt,
    this.publishedAt,
    this.editedAt,
    this.sendEmail = false,
    this.recipientCount = 0,
    this.readCount = 0,
    this.createdAt,
    this.createdByName,
  });

  final int id;
  final String title;
  final String bodyPreview;
  final AnnouncementImportance importance;
  final AnnouncementStatus status;
  final AnnouncementTargetType targetType;
  final DateTime? publishAt;
  final DateTime? publishedAt;
  final DateTime? editedAt;
  final bool sendEmail;
  final int recipientCount;
  final int readCount;
  final DateTime? createdAt;

  /// Kurul üyesine arayüzde gösterilmez ([AnnouncementSummary] sunucudan gelse bile).
  final String? createdByName;

  bool get isUrgent => importance == AnnouncementImportance.urgent;

  /// Okunma sayıları anlamlı mı (yalnız yayınlanmış ya da geri çekilmiş duyuruda alıcı vardır).
  bool get hasAudience =>
      status == AnnouncementStatus.published || status == AnnouncementStatus.withdrawn;

  factory AnnouncementSummary.fromJson(Map<String, dynamic> raw) {
    final json = _unwrap(raw);
    return AnnouncementSummary(
      id: crmInt(json['id']),
      title: _text(json['title']),
      bodyPreview: _text(json['body_preview']),
      importance: AnnouncementImportance.fromApi(json['importance']),
      status: AnnouncementStatus.fromApi(json['status']),
      targetType: AnnouncementTargetType.fromApi(_targetTypeOf(json)),
      publishAt: announcementInstant(json['publish_at']),
      publishedAt: announcementInstant(json['published_at']),
      editedAt: announcementInstant(json['edited_at']),
      sendEmail: _flag(json['send_email']),
      recipientCount: crmInt(json['recipient_count']),
      readCount: crmInt(json['read_count']),
      createdAt: announcementInstant(json['created_at']),
      createdByName: crmText(json['created_by_name']),
    );
  }

  /// Özet satırında `target_type`, ayrıntıda `target.type` gelir.
  static Object? _targetTypeOf(Map<String, dynamic> json) {
    final direct = json['target_type'];
    if (direct != null) return direct;
    final target = json['target'];
    return target is Map ? target['type'] : null;
  }
}

/// `GET .../announcements` sayfası (`limit/offset`).
@immutable
class AnnouncementPage {
  const AnnouncementPage({this.items = const <AnnouncementSummary>[], this.total = 0});

  final List<AnnouncementSummary> items;
  final int total;

  factory AnnouncementPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((e) => AnnouncementSummary.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : const <AnnouncementSummary>[];
    return AnnouncementPage(items: items, total: crmInt(json['total'], items.length));
  }
}

/// Duyurunun hedefi (`target`). [labels]: blok adları ya da daire etiketleri (sunucu doldurur).
@immutable
class AnnouncementTarget {
  const AnnouncementTarget({
    this.type = AnnouncementTargetType.site,
    this.blockIds = const <int>[],
    this.apartmentIds = const <int>[],
    this.labels = const <String>[],
  });

  final AnnouncementTargetType type;
  final List<int> blockIds;
  final List<int> apartmentIds;
  final List<String> labels;

  factory AnnouncementTarget.fromJson(Object? raw) {
    if (raw is! Map) return const AnnouncementTarget();
    return AnnouncementTarget(
      type: AnnouncementTargetType.fromApi(raw['type']),
      blockIds: _intList(raw['block_ids']),
      apartmentIds: _intList(raw['apartment_ids']),
      labels: _stringList(raw['labels']),
    );
  }

  /// Hedefteki öğe sayısı (blok ya da daire).
  int get count => switch (type) {
    AnnouncementTargetType.site => 0,
    AnnouncementTargetType.blocks => blockIds.length,
    AnnouncementTargetType.apartments => apartmentIds.length,
  };

  /// Kısa hedef özeti: "Tüm site", "A Blok, B Blok", "12 daire". Etiket yoksa sayıyla yetinir;
  /// [maxLabels]'tan fazlası "ve N daha" olarak kısaltılır.
  String summary({int maxLabels = 6}) {
    switch (type) {
      case AnnouncementTargetType.site:
        return 'Tüm site';
      case AnnouncementTargetType.blocks:
        return _describe('blok', maxLabels);
      case AnnouncementTargetType.apartments:
        return _describe('daire', maxLabels);
    }
  }

  String _describe(String noun, int maxLabels) {
    final total = count;
    if (labels.isEmpty || labels.length < total) {
      return total == 0 ? 'Seçili $noun yok' : '$total $noun';
    }
    if (labels.length <= maxLabels) return labels.join(', ');
    final rest = labels.length - maxLabels;
    return '${labels.take(maxLabels).join(', ')} ve $rest $noun daha';
  }
}

/// E-posta gönderim sayıları (`stats.email`).
@immutable
class AnnouncementEmailStats {
  const AnnouncementEmailStats({
    this.requested = false,
    this.sent = 0,
    this.failed = 0,
    this.noAddress = 0,
    this.skippedPref = 0,
    this.capped = 0,
    this.duplicate = 0,
    this.pending = 0,
  });

  /// Duyuruda "e-posta da gönder" seçilmiş mi?
  final bool requested;
  final int sent;
  final int failed;
  final int noAddress;
  final int skippedPref;
  final int capped;
  final int duplicate;
  final int pending;

  factory AnnouncementEmailStats.fromJson(Object? raw) {
    if (raw is! Map) return const AnnouncementEmailStats();
    final requested = raw['requested'];
    final sent = crmInt(raw['sent']);
    final failed = crmInt(raw['failed']);
    final noAddress = crmInt(raw['no_address']);
    final skippedPref = crmInt(raw['skipped_pref']);
    final capped = crmInt(raw['capped']);
    final duplicate = crmInt(raw['duplicate']);
    final pending = crmInt(raw['pending']);
    return AnnouncementEmailStats(
      // `requested` sayı (istenen e-posta adedi) ya da bayrak olarak gelebilir.
      requested: requested is bool
          ? requested
          : (requested is num ? requested > 0 : (sent + failed + pending) > 0),
      sent: sent,
      failed: failed,
      noAddress: noAddress,
      skippedPref: skippedPref,
      capped: capped,
      duplicate: duplicate,
      pending: pending,
    );
  }

  /// Sayısı sıfırdan büyük durumların okunur özeti: "32 gönderildi, 4 e-postası yok". Hiç yoksa null.
  String? get summary {
    final parts = <String>[
      if (sent > 0) '$sent gönderildi',
      if (pending > 0) '$pending sırada',
      if (failed > 0) '$failed gönderilemedi',
      if (noAddress > 0) '$noAddress kişinin e-postası yok',
      if (skippedPref > 0) '$skippedPref kişinin e-posta tercihi kapalı',
      if (capped > 0) '$capped günlük sınır nedeniyle gönderilmedi',
      if (duplicate > 0) '$duplicate aynı adres, tekrar gönderilmedi',
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }
}

/// Okunma ve e-posta istatistiği (`stats`).
@immutable
class AnnouncementStats {
  const AnnouncementStats({
    this.recipients = 0,
    this.read = 0,
    this.unread = 0,
    this.email = const AnnouncementEmailStats(),
  });

  final int recipients;
  final int read;
  final int unread;
  final AnnouncementEmailStats email;

  factory AnnouncementStats.fromJson(Object? raw) {
    if (raw is! Map) return const AnnouncementStats();
    final recipients = crmInt(raw['recipients']);
    final read = crmInt(raw['read']);
    return AnnouncementStats(
      recipients: recipients,
      read: read,
      unread: raw['unread'] == null
          ? (recipients - read).clamp(0, recipients).toInt()
          : crmInt(raw['unread']),
      email: AnnouncementEmailStats.fromJson(raw['email']),
    );
  }
}

/// Yönetici duyuru ayrıntısı (`GET/POST/PATCH .../announcements[/:id]`): özet alanlar + tam metin, hedef,
/// istatistik.
@immutable
class AnnouncementDetail extends AnnouncementSummary {
  const AnnouncementDetail({
    required super.id,
    super.title,
    super.bodyPreview,
    super.importance,
    super.status,
    super.targetType,
    super.publishAt,
    super.publishedAt,
    super.editedAt,
    super.sendEmail,
    super.recipientCount,
    super.readCount,
    super.createdAt,
    super.createdByName,
    this.body = '',
    this.target = const AnnouncementTarget(),
    this.stats = const AnnouncementStats(),
    this.editCount = 0,
  });

  final String body;
  final AnnouncementTarget target;
  final AnnouncementStats stats;

  /// Yayından sonra kaç kez düzenlendi (alan yoksa 0; [editedAt] doluysa en az bir kez).
  final int editCount;

  factory AnnouncementDetail.fromJson(Map<String, dynamic> raw) {
    final json = _unwrap(raw);
    final base = AnnouncementSummary.fromJson(json);
    final target = AnnouncementTarget.fromJson(json['target']);
    final stats = AnnouncementStats.fromJson(json['stats']);
    final body = _text(json['body']);
    return AnnouncementDetail(
      id: base.id,
      title: base.title,
      bodyPreview: base.bodyPreview.isEmpty ? body : base.bodyPreview,
      importance: base.importance,
      status: base.status,
      targetType: json['target'] is Map ? target.type : base.targetType,
      publishAt: base.publishAt,
      publishedAt: base.publishedAt,
      editedAt: base.editedAt,
      sendEmail: json['send_email'] == null ? stats.email.requested : base.sendEmail,
      recipientCount: json['recipient_count'] == null ? stats.recipients : base.recipientCount,
      readCount: json['read_count'] == null ? stats.read : base.readCount,
      createdAt: base.createdAt,
      createdByName: base.createdByName,
      body: body,
      target: target,
      stats: stats,
      editCount: crmInt(json['edit_count']),
    );
  }

  /// Listedeki satırı ayrıntıyla eşitler (liste yenilenene dek kart güncel görünür).
  AnnouncementSummary toSummary() => AnnouncementSummary(
    id: id,
    title: title,
    bodyPreview: body.length <= 160 ? body : body.substring(0, 160),
    importance: importance,
    status: status,
    targetType: target.type,
    publishAt: publishAt,
    publishedAt: publishedAt,
    editedAt: editedAt,
    sendEmail: sendEmail,
    recipientCount: recipientCount,
    readCount: readCount,
    createdAt: createdAt,
    createdByName: createdByName,
  );
}

/// Alıcılar sekmesindeki satır (`GET .../:id/recipients` -> `items[]`). Yalnız yazma yetkisi olana verilir.
@immutable
class AnnouncementRecipient {
  const AnnouncementRecipient({
    required this.personId,
    this.fullName = '',
    this.apartments = const <String>[],
    this.hasAccount = false,
    this.readAt,
    this.emailStatus = EmailDelivery.none,
  });

  final int personId;
  final String fullName;
  final List<String> apartments;
  final bool hasAccount;
  final DateTime? readAt;
  final EmailDelivery emailStatus;

  bool get isRead => readAt != null;

  factory AnnouncementRecipient.fromJson(Map<String, dynamic> json) {
    return AnnouncementRecipient(
      personId: crmInt(json['person_id']),
      fullName: _text(json['full_name']),
      apartments: _stringList(json['apartments']),
      hasAccount: _flag(json['has_account']),
      readAt: announcementInstant(json['read_at']),
      emailStatus: EmailDelivery.fromApi(json['email_status']),
    );
  }
}

/// `GET .../:id/recipients` sayfası (`limit/offset`).
@immutable
class AnnouncementRecipientPage {
  const AnnouncementRecipientPage({
    this.items = const <AnnouncementRecipient>[],
    this.total = 0,
  });

  final List<AnnouncementRecipient> items;
  final int total;

  factory AnnouncementRecipientPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw
              .whereType<Map>()
              .map((e) => AnnouncementRecipient.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false)
        : const <AnnouncementRecipient>[];
    return AnnouncementRecipientPage(items: items, total: crmInt(json['total'], items.length));
  }
}

/// Yayın öncesi kitle önizlemesi (`POST .../preview-audience`).
@immutable
class AudiencePreview {
  const AudiencePreview({
    this.people = 0,
    this.apartments = 0,
    this.withAccount = 0,
    this.withEmail = 0,
    this.withoutEmail = 0,
  });

  final int people;
  final int apartments;
  final int withAccount;
  final int withEmail;
  final int withoutEmail;

  factory AudiencePreview.fromJson(Map<String, dynamic> json) {
    return AudiencePreview(
      people: crmInt(json['people']),
      apartments: crmInt(json['apartments']),
      withAccount: crmInt(json['with_account']),
      withEmail: crmInt(json['with_email']),
      withoutEmail: crmInt(json['without_email']),
    );
  }
}

/// Yazma isteklerinde hedef (`target` gövdesi).
@immutable
class AnnouncementTargetInput {
  const AnnouncementTargetInput({
    this.type = AnnouncementTargetType.site,
    this.blockIds = const <int>[],
    this.apartmentIds = const <int>[],
  });

  final AnnouncementTargetType type;
  final List<int> blockIds;
  final List<int> apartmentIds;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.apiValue,
    if (type == AnnouncementTargetType.blocks) 'block_ids': blockIds,
    if (type == AnnouncementTargetType.apartments) 'apartment_ids': apartmentIds,
  };
}

/// Sakin gelen kutusu satırı / ayrıntısı (`GET /app/announcements[/:id]`). Listede [body] boştur
/// ([bodyPreview] dolu), ayrıntıda tam metin [body]'dedir.
@immutable
class ResidentAnnouncement {
  const ResidentAnnouncement({
    required this.id,
    this.siteCode = 0,
    this.siteName = '',
    this.title = '',
    this.bodyPreview = '',
    this.body = '',
    this.importance = AnnouncementImportance.normal,
    this.publishedAt,
    this.editedAt,
    this.isRead = false,
  });

  final int id;
  final int siteCode;
  final String siteName;
  final String title;
  final String bodyPreview;
  final String body;
  final AnnouncementImportance importance;
  final DateTime? publishedAt;
  final DateTime? editedAt;
  final bool isRead;

  bool get isUrgent => importance == AnnouncementImportance.urgent;
  bool get isEdited => editedAt != null;

  /// Ayrıntı yüklenmeden önce kartta gösterilecek metin.
  String get previewOrBody => bodyPreview.isNotEmpty ? bodyPreview : body;

  ResidentAnnouncement copyWith({bool? isRead, String? body}) => ResidentAnnouncement(
    id: id,
    siteCode: siteCode,
    siteName: siteName,
    title: title,
    bodyPreview: bodyPreview,
    body: body ?? this.body,
    importance: importance,
    publishedAt: publishedAt,
    editedAt: editedAt,
    isRead: isRead ?? this.isRead,
  );

  factory ResidentAnnouncement.fromJson(Map<String, dynamic> raw) {
    final json = _unwrap(raw);
    return ResidentAnnouncement(
      id: crmInt(json['id']),
      siteCode: crmInt(json['site_code']),
      siteName: _text(json['site_name']),
      title: _text(json['title']),
      bodyPreview: _text(json['body_preview']),
      body: _text(json['body']),
      importance: AnnouncementImportance.fromApi(json['importance']),
      publishedAt: announcementInstant(json['published_at']),
      editedAt: announcementInstant(json['edited_at']),
      isRead: _flag(json['is_read']),
    );
  }
}

/// `GET /app/announcements` sayfası: `published_at DESC, id DESC`; sonraki sayfa `before_id`.
@immutable
class ResidentAnnouncementPage {
  const ResidentAnnouncementPage({
    this.items = const <ResidentAnnouncement>[],
    this.nextBeforeId,
  });

  final List<ResidentAnnouncement> items;
  final int? nextBeforeId;

  bool get hasMore => nextBeforeId != null;

  factory ResidentAnnouncementPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return ResidentAnnouncementPage(
      items: raw is List
          ? raw
                .whereType<Map>()
                .map((e) => ResidentAnnouncement.fromJson(Map<String, dynamic>.from(e)))
                .toList(growable: false)
          : const <ResidentAnnouncement>[],
      nextBeforeId: crmIntOrNull(json['next_before_id']),
    );
  }
}

/// `GET /app/notifications/summary`: okunmamış sayıları ve en son duyuru numarası.
@immutable
class NotificationSummary {
  const NotificationSummary({
    this.unreadAnnouncements = 0,
    this.unreadUrgent = 0,
    this.latestAnnouncementId,
    this.latestPublishedAt,
    this.serverTime,
  });

  final int unreadAnnouncements;
  final int unreadUrgent;

  /// En son YAYINLANAN duyurunun numarası (en büyük numara değil: zamanlanmış bir duyuru küçük numarayla
  /// sonradan yayınlanabilir).
  final int? latestAnnouncementId;

  /// En son yayınlanan duyurunun yayın zamanı (EKLEMELİ alan; eski sunucuda null). "Yeni duyuru" tespiti
  /// numara büyümesine değil bu zamanın ilerlemesine bağlanır.
  final DateTime? latestPublishedAt;
  final DateTime? serverTime;

  /// "En son duyuru" değişti mi karşılaştırması için imza (numara + yayın zamanı).
  String get latestSignature =>
      '${latestAnnouncementId ?? ''}|${latestPublishedAt?.millisecondsSinceEpoch ?? ''}';

  factory NotificationSummary.fromJson(Map<String, dynamic> json) {
    final unread = crmInt(json['unread_announcements']);
    final urgent = crmInt(json['unread_urgent']);
    return NotificationSummary(
      unreadAnnouncements: unread < 0 ? 0 : unread,
      // Acil sayısı toplamı aşamaz (tutarsız yanıta karşı).
      unreadUrgent: urgent < 0 ? 0 : (urgent > unread ? unread : urgent),
      latestAnnouncementId: crmIntOrNull(json['latest_announcement_id']),
      latestPublishedAt: announcementInstant(json['latest_published_at']),
      serverTime: announcementInstant(json['server_time']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationSummary &&
      other.unreadAnnouncements == unreadAnnouncements &&
      other.unreadUrgent == unreadUrgent &&
      other.latestAnnouncementId == latestAnnouncementId &&
      other.latestPublishedAt == latestPublishedAt;

  @override
  int get hashCode =>
      Object.hash(unreadAnnouncements, unreadUrgent, latestAnnouncementId, latestPublishedAt);
}

/// `GET/PUT /app/notification-preferences`. [pushAvailable] false: telefon bildirimi henüz yok.
@immutable
class NotificationPrefs {
  const NotificationPrefs({
    this.emailAnnouncements = true,
    this.pushAnnouncements = true,
    this.pushAvailable = false,
  });

  final bool emailAnnouncements;
  final bool pushAnnouncements;
  final bool pushAvailable;

  /// Alan yoksa e-posta tercihi [fallbackEmail] (PUT yanıtında istenen değer), o da yoksa açık.
  factory NotificationPrefs.fromJson(Map<String, dynamic> json, {bool? fallbackEmail}) {
    return NotificationPrefs(
      emailAnnouncements: _flag(json['email_announcements'], fallback: fallbackEmail ?? true),
      pushAnnouncements: _flag(json['push_announcements'], fallback: true),
      pushAvailable: _flag(json['push_available']),
    );
  }

  NotificationPrefs copyWith({bool? emailAnnouncements}) => NotificationPrefs(
    emailAnnouncements: emailAnnouncements ?? this.emailAnnouncements,
    pushAnnouncements: pushAnnouncements,
    pushAvailable: pushAvailable,
  );
}

/// Denetim kaydında duyuru eylemlerinin kısa Türkçe başlığı; bilinmeyen eylemde null.
String? announcementActionLabel(String action) {
  switch (action) {
    case 'announcement.created':
      return 'Duyuru oluşturuldu';
    case 'announcement.updated':
      return 'Duyuru düzenlendi';
    case 'announcement.scheduled':
      return 'Duyuru zamanlandı';
    case 'announcement.published':
      return 'Duyuru yayınlandı';
    case 'announcement.withdrawn':
      return 'Duyuru geri çekildi';
    case 'announcement.deleted':
      return 'Duyuru silindi';
    default:
      return null;
  }
}
